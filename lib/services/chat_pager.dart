// lib/services/chat_pager.dart
//
// "Load older messages" for a conversation.
//
// The chat keeps a live Firestore listener on the newest
// ChatService.messageLimit messages (so replies appear at once). Anything
// older is fetched on demand, one page at a time, when the patient scrolls
// to the top, and shown below the live window in the reversed list.
//
// The page loader and the clock are injected, so the paging and merging
// are unit-tested without Firebase (test/chat_features_test.dart,
// test/ios_review_test.dart).

import 'package:flutter/foundation.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';

/// Loads up to `limit` messages sent at or before `before`, newest first.
///
/// "At or before" (Firestore `startAt`, not `startAfter`): another message
/// can share the boundary's exact `sentAt`, and `startAfter` would skip it
/// for good. The repeated boundary message is dropped when merging by id.
typedef OlderMessagesLoader =
    Future<List<ChatMessage>> Function(DateTime before, int limit);

/// Combines the [live] window with [older] pages: one entry per id, newest
/// first. The live copy of a message wins, because it carries the current
/// pending state (an older page may hold a stale copy).
///
/// Messages with the same `sentAt` are ordered by id, so they don't swap
/// places between rebuilds.
List<ChatMessage> mergeMessages(
  List<ChatMessage> live,
  Iterable<ChatMessage> older,
) {
  final byId = <String, ChatMessage>{
    for (final msg in older) msg.id: msg,
    for (final msg in live) msg.id: msg,
  };
  return byId.values.toList()..sort(_newestFirst);
}

int _newestFirst(ChatMessage a, ChatMessage b) {
  final byTime = b.sentAt.compareTo(a.sentAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

/// Holds the older pages of one conversation and loads the next on request.
///
/// Call [merge] with every live snapshot to get the list to show, and
/// [loadOlder] when the patient nears the top. Listeners are told when a load
/// starts and ends (to show or hide the spinner).
class ChatPager extends ChangeNotifier {
  ChatPager({
    required this.loadPage,
    required this.liveLimit,
    this.pageSize = 50,
    this.logTag = 'ChatPager',
    this.retryDelay = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OlderMessagesLoader loadPage;

  /// The live query's limit. A live snapshot shorter than this already holds
  /// the whole conversation, so there is nothing older to load.
  final int liveLimit;

  /// Messages per older page. A shorter page means the start was reached.
  final int pageSize;

  /// Log tag (the screen's), so paging shows up next to the chat's events.
  final String logTag;

  /// How long to wait after a failed load before scrolling may retry.
  ///
  /// The screen asks for a page on every scroll notification near the top
  /// (dozens per second during a fling). Without this pause, a load that
  /// fails at once (permission denied, no network) would be re-sent on
  /// every one of them.
  final Duration retryDelay;

  final DateTime Function() _clock;
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// Every message that reached the server, from older pages and from the
  /// live window. Keeping them is what keeps a message on screen when a new
  /// one pushes it out of the live window after older pages were loaded
  /// (otherwise a gap would open between the live window and the first
  /// older page). A message in the live window is refreshed by every
  /// snapshot; one further back is a one-shot read, so the patient's own
  /// edits and unsends are applied to it through [replace].
  ///
  /// Pending messages are not kept: one the server refused disappears from
  /// the live snapshot and must disappear from the screen too.
  final Map<String, ChatMessage> _known = {};

  /// Bumped whenever a loaded page adds to [_known], so [merge] knows when
  /// its cached result is stale.
  int _olderVersion = 0;

  /// [merge]'s last input and result. The list is rebuilt whenever the
  /// pager notifies (a load starting or ending) with the same live
  /// snapshot; reusing the result skips a re-sort of the whole history.
  List<ChatMessage>? _lastLive;
  int _lastOlderVersion = -1;
  List<ChatMessage> _shown = const [];

  bool _disposed = false;
  DateTime? _failedAt;

  /// A page is being fetched (show the spinner).
  bool get loading => _loading;
  bool _loading = false;

  /// The oldest message of the conversation is loaded: either an older page
  /// came back short, or the current live snapshot is shorter than its
  /// limit.
  ///
  /// The live half is re-judged on every snapshot rather than latched:
  /// Firestore often delivers a short snapshot from the phone's cache
  /// first and the full one from the server a moment later, and latching
  /// the first would stop paging for good.
  bool get reachedStart => _pagedToStart || _liveHoldsAll;
  bool _pagedToStart = false;
  bool _liveHoldsAll = false;

  /// At least one older page was loaded (so "Beginning of conversation"
  /// means something: the patient scrolled back to it).
  bool get loadedOlder => _loadedOlder;
  bool _loadedOlder = false;

  /// The last load failed (e.g. offline); scrolling up again retries.
  bool get lastLoadFailed => _failedAt != null;

  /// True when [loadOlder] would fetch now: not already loading, start not
  /// reached, a snapshot was merged, and no recent failure is cooling down.
  bool get canLoadMore {
    if (_disposed || _loading || reachedStart || _shown.isEmpty) return false;
    final failedAt = _failedAt;
    return failedAt == null || _clock().difference(failedAt) >= retryDelay;
  }

  /// The list to show for the [live] snapshot (newest first): the live
  /// window followed by every older message loaded so far.
  List<ChatMessage> merge(List<ChatMessage> live) {
    if (identical(live, _lastLive) && _olderVersion == _lastOlderVersion) {
      return _shown;
    }
    final holdsAll = live.length < liveLimit;
    if (holdsAll != _liveHoldsAll) {
      _logger.verbose(logTag, 'Live window coverage changed', {
        'live': live.length,
        'liveLimit': liveLimit,
        'holdsAll': holdsAll,
      });
    }
    _liveHoldsAll = holdsAll;
    for (final msg in live) {
      if (!msg.pending) _known[msg.id] = msg;
    }
    _shown = mergeMessages(live, _known.values);
    _lastLive = live;
    _lastOlderVersion = _olderVersion;
    return _shown;
  }

  /// Fetches the page before the oldest message shown. Does nothing while a
  /// load is running, once the start was reached, before the first
  /// snapshot, shortly after a failure, or after [dispose]. Never throws: a
  /// failure is logged and can be retried.
  Future<void> loadOlder() async {
    if (!canLoadMore) return;
    final before = _shown.last.sentAt;
    final retry = _failedAt != null;
    _loading = true;
    _failedAt = null;
    _notify();
    _logger.info(logTag, 'Loading older messages', {
      'shown': _shown.length,
      'pageSize': pageSize,
      'retry': retry,
    });
    try {
      final page = await loadPage(before, pageSize);
      if (_disposed) {
        _logger.verbose(logTag, 'Older page arrived after the chat closed', {
          'page': page.length,
        });
        return;
      }
      var added = 0;
      for (final msg in page) {
        if (msg.pending) continue;
        if (_known.containsKey(msg.id)) continue;
        _known[msg.id] = msg;
        added++;
      }
      if (added > 0) _olderVersion++;
      _loadedOlder = true;
      if (page.length < pageSize) {
        _pagedToStart = true;
      } else if (added == 0) {
        // A full page of messages we already have: more than a page share
        // one sentAt, and startAt would return the same page forever. Stop
        // rather than loop; logged so it is noticed.
        _pagedToStart = true;
        _logger.warn(logTag, 'Older page had nothing new; paging stopped', {
          'page': page.length,
        });
      }
      _logger.info(logTag, 'Older messages loaded', {
        'page': page.length,
        'added': added,
        'reachedStart': reachedStart,
      });
    } catch (e, st) {
      _failedAt = _clock();
      _logger.warn(
        logTag,
        'Loading older messages failed',
        {'retryDelayMs': retryDelay.inMilliseconds},
        e,
        st,
      );
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Shows [updated] in place of the message with the same id, when that
  /// message is one this pager keeps (so not for a pending one). Used for
  /// the patient's own edit or unsend: a message in the live window is also
  /// refreshed by the next snapshot, but one on an older page is not.
  void replace(ChatMessage updated) {
    if (_disposed || !_known.containsKey(updated.id)) return;
    _known[updated.id] = updated;
    _olderVersion++;
    _notify();
  }

  /// Listeners are skipped once disposed: a page can arrive after the chat
  /// was closed.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
