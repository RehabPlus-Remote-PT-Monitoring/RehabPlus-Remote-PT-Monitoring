import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../services/app_provider.dart';
import '../services/chat_pager.dart';
import '../services/chat_service.dart';
import '../services/chat_session_share.dart';
import '../services/chat_timeline.dart';
import '../services/progress_stats.dart' show CalendarDays;
import '../core/responsive.dart';
import '../ios/glass_tab_bar.dart';
import '../widgets/chat_composer_surface.dart';
import '../widgets/chat_session_share_sheet.dart';
import '../widgets/chat_timeline_widgets.dart';

const Color _primaryTeal = Color(0xFF23A8AA);
const String _tag = 'Messages';

/// Firestore rules limit a message to 1000 characters. Dart's String.length
/// counts UTF-16 units, which is never less than the rules' count, so a
/// message that passes this check always passes the rule.
const int _maxMessageLength = ChatMessage.maxTextLength;

/// Time label for a thread's last message: the time today, "Yesterday",
/// the weekday within a week, otherwise the date.
///
/// Days are counted as calendar days ([CalendarDays.between]), not as
/// 24-hour blocks: across a daylight-saving change "yesterday" is only 23
/// hours before midnight, and `Duration.inDays` used to call it 0 days,
/// so it showed a weekday instead of "Yesterday".
@visibleForTesting
String threadTimeLabel(DateTime t, DateTime now) {
  final daysAgo = CalendarDays.between(t, now);
  if (daysAgo == 0) return DateFormat.jm().format(t);
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return DateFormat.E().format(t);
  return DateFormat.MMMd().format(t);
}

/// Keeps only what a phone dialer understands (digits, and + at the start),
/// so a badly entered clinic number can't smuggle other characters into the
/// tel: link. Returns null if no digits are left.
String? _dialableNumber(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return trimmed.startsWith('+') ? '+$digits' : digits;
}

String _threadTitle(BuildContext context, ChatThread thread) {
  if (thread == ChatThread.clinic) return 'RehabPlus Clinic';
  final therapist = context.watch<AppProvider>().profile?.therapist ?? '';
  return therapist.isEmpty ? 'Your Therapist' : therapist;
}

String _threadSubtitle(ChatThread thread) => switch (thread) {
  ChatThread.therapist => 'Questions about your exercises or progress',
  ChatThread.clinic => 'Appointments, home visits and app support',
};

/// Background of the grey contact avatars: grey 300 in light mode (white
/// cards), the muted surface in dark mode so it doesn't glare.
Color _avatarBg(BuildContext context) => context.isDarkMode
    ? context.palette.surfaceMuted
    : Colors.grey.shade300;

IconData _threadIcon(ChatThread thread) =>
    thread == ChatThread.clinic ? Icons.groups : Icons.person_outline;

/// Opens the phone dialer with the clinic number (settings/clinic.phone).
///
/// The messenger is captured before any await, so the SnackBars still work
/// if the calling screen is closed meanwhile.
Future<void> callClinic(BuildContext context) async {
  final logger = DiagnosticLogger.I;
  final messenger = ScaffoldMessenger.of(context);
  logger.info(_tag, 'Call clinic tapped');
  String? phone;
  try {
    final configured = await ChatService().clinicPhone();
    phone = configured == null ? null : _dialableNumber(configured);
  } catch (e, st) {
    logger.warn(_tag, 'Could not read the clinic phone number', null, e, st);
    phone = null;
  }
  if (phone == null) {
    logger.warn(_tag, 'Clinic phone number not configured');
    messenger.showSnackBar(
      const SnackBar(
        content: Text('The clinic phone number is not set up yet.'),
      ),
    );
    return;
  }
  bool launched;
  try {
    // tel: only opens the dialer; the patient still has to press call.
    launched = await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (e, st) {
    logger.warn(_tag, 'Opening the dialer failed', null, e, st);
    launched = false;
  }
  logger.info(_tag, 'Dialer result', {'launched': launched});
  if (!launched) {
    messenger.showSnackBar(
      SnackBar(content: Text('Call the clinic at $phone')),
    );
  }
}

// --- TABLET SPLIT VIEW ---

/// Width of the thread list beside the open conversation: room for the
/// avatar, the name and a two-line preview, leaving the rest to the chat.
const double kMessagesListWidth = 340;

/// True when [width] (the space the Messages tab really has, i.e. right of
/// the dashboard sidebar) fits the thread list and a conversation side by
/// side. Narrower screens (phones, portrait tablets) keep pushing the chat
/// as its own page.
bool showsMessagesSplit(double width) => width >= kTwoColumnBreakpoint;

/// Lays out the Messages tab: just the thread list when narrow, the list on
/// the left and the [selected] conversation on the right when wide.
///
/// Kept free of Firebase (the screens are passed in as builders) so the
/// layout decision can be widget-tested.
class MessagesLayout extends StatelessWidget {
  const MessagesLayout({
    super.key,
    required this.selected,
    required this.listBuilder,
    required this.detailBuilder,
  });

  /// The conversation shown in the right pane in the split view, or null
  /// for none yet (the pane then asks the patient to pick one).
  final ChatThread? selected;

  /// Builds the thread list. `split` is true when it sits beside the
  /// conversation, so a tap should switch the right pane instead of
  /// pushing a page.
  final Widget Function(BuildContext context, bool split) listBuilder;

  /// Builds the conversation for the right pane.
  final Widget Function(BuildContext context, ChatThread thread) detailBuilder;

  /// Gives [child] a MediaQuery as wide as its pane, so readablePadding and
  /// ReadableWidth inside it centre content in the pane, not in the screen.
  Widget _pane(MediaQueryData media, double width, Widget child) {
    return MediaQuery(
      data: media.copyWith(size: Size(width, media.size.height)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || !showsMessagesSplit(width)) {
          return listBuilder(context, false);
        }
        final media = MediaQuery.of(context);
        const dividerWidth = 1.0;
        final detailWidth = math.max(
          0.0,
          width - kMessagesListWidth - dividerWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: kMessagesListWidth,
              child: _pane(
                media,
                kMessagesListWidth,
                Builder(builder: (context) => listBuilder(context, true)),
              ),
            ),
            VerticalDivider(
              width: dividerWidth,
              thickness: dividerWidth,
              color: context.palette.divider,
            ),
            Expanded(
              child: _pane(
                media,
                detailWidth,
                // Keyed by thread: switching threads disposes the old chat
                // (cancelling its Firestore listeners) and subscribes anew.
                selected == null
                    ? const _NoConversationSelected()
                    : KeyedSubtree(
                        key: ValueKey(selected),
                        child: Builder(
                          builder: (context) =>
                              detailBuilder(context, selected!),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Right pane of the split view before any thread is chosen.
class _NoConversationSelected extends StatelessWidget {
  const _NoConversationSelected();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: palette.textFaint),
              const SizedBox(height: 12),
              Text(
                'Select a conversation',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose your therapist or the clinic on the left.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- CONVERSATION LIST ---
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// The conversation open in the right pane of the tablet split view;
  /// phones ignore it. It starts empty on purpose: opening a conversation
  /// marks it read (the therapist then sees "seen"), so that should only
  /// happen when the patient actually taps a thread, not just because they
  /// opened the Messages tab.
  ChatThread? _selected;

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  void _select(ChatThread thread) {
    if (thread == _selected) return;
    setState(() => _selected = thread);
  }

  @override
  Widget build(BuildContext context) {
    return MessagesLayout(
      selected: _selected,
      listBuilder: _buildList,
      detailBuilder: (context, thread) =>
          ChatDetailScreen(thread: thread, embedded: true),
    );
  }

  /// The thread list. In the split view a tap selects the thread for the
  /// right pane; otherwise it pushes the conversation (phones).
  Widget _buildList(BuildContext context, bool split) {
    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Call the clinic',
            onPressed: () => callClinic(context),
            icon: const Icon(Icons.call_outlined, color: Colors.white),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView.separated(
        // iPhone: room at the bottom for the floating glass tab bar.
        padding: withTabBarClearance(context, readablePadding(context)),
        itemCount: ChatThread.values.length,
        separatorBuilder: (_, _) =>
            const Divider(indent: 72, height: 1, thickness: 0.5),
        itemBuilder: (context, i) {
          final thread = ChatThread.values[i];
          return _ThreadTile(
            thread: thread,
            selected: split && thread == _selected,
            onOpen: split ? _select : null,
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatefulWidget {
  final ChatThread thread;

  /// Highlights the tile whose conversation is open beside the list.
  final bool selected;

  /// Called instead of pushing the conversation (the tablet split view).
  final ValueChanged<ChatThread>? onOpen;

  const _ThreadTile({required this.thread, this.selected = false, this.onOpen});

  @override
  State<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<_ThreadTile> {
  /// Created once (not in build), so rebuilds don't re-subscribe Firestore.
  late final Stream<ChatThreadSummary> _summary = _openSummary();

  Stream<ChatThreadSummary> _openSummary() {
    try {
      // ChatService logs the stream's start, first snapshot and errors.
      return ChatService().summary(widget.thread);
    } catch (e, st) {
      // Thrown synchronously when nobody is signed in (e.g. mid sign-out).
      DiagnosticLogger.I.warn(_tag, 'Thread summary unavailable', {
        'thread': widget.thread.name,
      }, e, st);
      return Stream.value(ChatThreadSummary.empty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final palette = context.palette;
    return StreamBuilder<ChatThreadSummary>(
      stream: _summary,
      builder: (context, snap) {
        final s = snap.data ?? ChatThreadSummary.empty;
        final unread = s.unreadForPatient;
        return ListTile(
          selected: widget.selected,
          selectedTileColor: palette.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          onTap: () {
            DiagnosticLogger.I.info(_tag, 'Thread opened', {
              'thread': thread.name,
              'unread': unread,
            });
            final onOpen = widget.onOpen;
            if (onOpen != null) {
              onOpen(thread);
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatDetailScreen(thread: thread)),
            );
          },
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: _avatarBg(context),
            child: Icon(
              _threadIcon(thread),
              color: palette.textMuted,
              size: 30,
            ),
          ),
          title: Text(
            _threadTitle(context, thread),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: palette.textPrimary,
            ),
          ),
          subtitle: Text(
            s.lastMessage ?? _threadSubtitle(thread),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: unread > 0 ? palette.textPrimary : palette.textSecondary,
              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (s.lastMessageAt != null)
                Text(
                  threadTimeLabel(s.lastMessageAt!, DateTime.now()),
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              const SizedBox(height: 6),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// --- CHAT DETAIL SCREEN ---
class ChatDetailScreen extends StatefulWidget {
  final ChatThread thread;

  /// Shown in the right pane of the tablet split view rather than as its
  /// own page: no back button, and the messages and composer fill the pane
  /// (it is already narrow enough to read).
  final bool embedded;

  const ChatDetailScreen({
    super.key,
    required this.thread,
    this.embedded = false,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _chat = ChatService();
  final _textController = TextEditingController();
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// Created once in initState, so rebuilds (keyboard, typing) don't
  /// re-subscribe to Firestore.
  late final Stream<List<ChatMessage>> _messages;
  StreamSubscription<ChatThreadSummary>? _unreadSub;

  /// The thread's `unreadForStaff` counter, for read receipts (two ticks once
  /// staff have seen a message). Null until the summary first loads.
  int? _unreadForStaff;

  /// Older pages loaded below the live window when the patient scrolls up.
  late final ChatPager _pager;

  /// `unreadForPatient` from the first summary, i.e. before opening the
  /// chat reset it to 0: how many staff replies are new on this visit.
  int? _unreadAtOpen;

  /// The message the "New messages" divider sits above (null: none). Worked
  /// out once, from the first messages shown after [_unreadAtOpen] is known,
  /// and then kept for this visit: replies arriving while the chat is open
  /// are read as they come, so they must not move it.
  String? _newMessagesDividerId;
  bool _dividerPlaced = false;

  /// Start loading the next older page this close (in pixels) to the top.
  static const double _loadOlderThreshold = 400;

  /// Starters for the clinic thread; they fill the box so the patient can
  /// add details before sending.
  static const _clinicPrompts = {
    'Book clinic visit':
        "I'd like to book a clinic visit. My preferred date and time: ",
    'Request home visit':
        "I'd like to request a home visit. My address and preferred date: ",
    'Report a problem': "I'd like to report a problem with the app: ",
  };

  @override
  void initState() {
    super.initState();
    final thread = widget.thread.name;
    _logger.info(_tag, 'Chat opened', {'thread': thread});
    _pager = ChatPager(
      // Errors are caught and logged by the pager (the spinner then turns
      // into a "try again" note).
      loadPage: (before, limit) =>
          _chat.olderMessages(widget.thread, before: before, limit: limit),
      liveLimit: ChatService.messageLimit,
      logTag: _tag,
    );
    try {
      // ChatService logs the stream's start, first snapshot and errors.
      _messages = _chat.messages(widget.thread);
      // Clear the unread badge on open and whenever staff replies arrive.
      _unreadSub = _chat
          .summary(widget.thread)
          .listen(
            (s) {
              // The first summary is the count before markRead below resets
              // it; later ones are already 0 or replies read as they come.
              final firstSummary = _unreadAtOpen == null;
              // Drives the ticks; Firestore applies our own sends to the
              // summary locally too, so a new message starts as unseen.
              if (mounted &&
                  (firstSummary || s.unreadForStaff != _unreadForStaff)) {
                setState(() {
                  _unreadForStaff = s.unreadForStaff;
                  _unreadAtOpen ??= s.unreadForPatient;
                });
              }
              if (s.unreadForPatient > 0) {
                _logger.verbose(_tag, 'Marking thread read', {
                  'thread': thread,
                  'unread': s.unreadForPatient,
                });
                try {
                  _chat.markRead(widget.thread);
                } catch (e, st) {
                  // Throws synchronously when signed out (a cached snapshot
                  // can still arrive mid sign-out). Inside a stream callback
                  // that would be an uncaught error; the badge simply stays.
                  _logger.warn(
                    _tag,
                    'Mark read failed',
                    {'thread': thread},
                    e,
                    st,
                  );
                }
              }
            },
            // Without this a listener error would be an uncaught error.
            onError: (Object e, StackTrace st) => _logger.warn(
              _tag,
              'Unread listener failed',
              {'thread': thread},
              e,
              st,
            ),
          );
    } catch (e, st) {
      // Thrown synchronously when nobody is signed in.
      _logger.error(_tag, 'Chat unavailable', {'thread': thread}, e, st);
      _messages = Stream.error(e, st); // shows "Couldn't load messages."
    }
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    _pager.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_deliver(text)) _textController.clear();
  }

  /// Sends [text] (already trimmed, not empty) the one way every message
  /// goes, typed or a shared session, so the thread preview and unread
  /// counter are updated identically. Returns false (after telling the
  /// patient) if it wasn't sent.
  bool _deliver(String text) {
    if (text.length > _maxMessageLength) {
      // Possible with many emoji (each counts as 2+ units): the server
      // would reject it, so say so instead of failing silently.
      _logger.warn(_tag, 'Message too long', {'length': text.length});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That message is too long. Please shorten it.'),
        ),
      );
      return false;
    }
    try {
      // Not awaited: Firestore's offline cache queues it. ChatService logs
      // "Message queued" with the length (never the text) and the sync
      // result. The text is cleared at once, so a double tap can't send it
      // twice.
      _chat.send(widget.thread, text);
    } catch (e, st) {
      _logger.error(_tag, 'Sending failed', {'thread': widget.thread.name}, e, st);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send. Please sign in again.'),
        ),
      );
      return false;
    }
    return true;
  }

  /// Long-press on a bubble: copies its text. The messenger is captured
  /// before the await so the SnackBar still works if the chat closes.
  Future<void> _copy(ChatMessage msg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: msg.text));
    } catch (e, st) {
      _logger.warn(_tag, 'Copy failed', {'thread': widget.thread.name}, e, st);
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't copy the message.")),
      );
      return;
    }
    // Logs the length only, never the text.
    _logger.info(_tag, 'Message copied', {'length': msg.text.length});
    try {
      await HapticFeedback.selectionClick();
    } catch (e, st) {
      // Only the buzz is lost; the copy worked.
      _logger.warn(_tag, 'Copy haptic failed', null, e, st);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  /// Opens the recent-sessions sheet and sends the chosen session's summary
  /// as an ordinary text message (no new message fields).
  Future<void> _shareSession() async {
    final history = context.read<AppProvider>().sessionHistory;
    _logger.info(_tag, 'Share session opened', {'available': history.length});
    final picked = await showChatSessionShareSheet(context, history);
    if (picked == null || !mounted) return;
    final text = sessionShareText(picked);
    if (_deliver(text)) {
      _logger.info(_tag, 'Session shared', {
        'thread': widget.thread.name,
        'exercise': picked.exerciseId,
        'length': text.length,
      });
    }
  }

  /// Near the top of the reversed list (its end), fetch the next older page.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _loadOlderThreshold &&
        _pager.canLoadMore) {
      // Never throws: the pager logs a failure and shows it in the footer.
      unawaited(_pager.loadOlder());
    }
    return false;
  }

  void _usePrompt(String label, String prompt) {
    _logger.info(_tag, 'Prompt chip used', {'prompt': label});
    _textController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
  }

  /// The conversation, newest at the bottom ([msgs] is newest first): day
  /// separators, the "New messages" divider, the bubbles, and at the top a
  /// footer for older pages.
  Widget _buildMessageList(
    BuildContext context,
    List<ChatMessage> msgs,
    double contentWidth,
  ) {
    final thread = widget.thread;
    final seen = seenByStaff(msgs, _unreadForStaff);
    final unreadAtOpen = _unreadAtOpen;
    if (!_dividerPlaced && unreadAtOpen != null) {
      // Placed once; see [_newMessagesDividerId].
      _newMessagesDividerId = newMessagesDividerId(msgs, unreadAtOpen);
      _dividerPlaced = true;
    }
    final now = DateTime.now();
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        reverse: true, // newest at the bottom, auto-scrolls
        // Dragging the conversation puts the keyboard away (both platforms).
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: readablePadding(
          context,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          contentWidth,
        ),
        // One extra item at the end (the top of the screen) for the footer.
        itemCount: msgs.length + 1,
        itemBuilder: (context, i) {
          if (i == msgs.length) {
            return ChatHistoryFooter(
              loading: _pager.loading,
              // Only after scrolling back: a short chat needs no marker.
              reachedStart: _pager.reachedStart && _pager.loadedOlder,
              failed: _pager.lastLoadFailed,
            );
          }
          final msg = msgs[i];
          // List is newest-first, so the message shown above is i + 1.
          final older = i + 1 < msgs.length ? msgs[i + 1] : null;
          final newDay = startsNewDay(msg.sentAt, older?.sentAt);
          // A new day always shows its first time; within a day, a time
          // after every 10-minute pause.
          final showTime =
              newDay || msg.sentAt.difference(older!.sentAt).inMinutes >= 10;
          return Column(
            children: [
              if (newDay) ChatDaySeparator(label: chatDayLabel(msg.sentAt, now)),
              if (msg.id == _newMessagesDividerId)
                const ChatNewMessagesDivider(),
              _Bubble(
                msg: msg,
                icon: _threadIcon(thread),
                showTime: showTime,
                seen: seen.contains(msg.id),
                onLongPress: () => _copy(msg),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final palette = context.palette;
    // As a page: one readable column. In the split view the pane itself is
    // the column, so content uses all of it.
    final contentWidth = widget.embedded
        ? double.infinity
        : kReadableMaxWidth;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back_ios, color: palette.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _avatarBg(context),
              child: Icon(
                _threadIcon(thread),
                color: palette.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _threadTitle(context, thread),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _threadSubtitle(thread),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call the clinic',
            icon: const Icon(Icons.call_outlined, color: _primaryTeal),
            onPressed: () => callClinic(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Dark mode: a deep teal fade instead of the bright aqua, so the
            // surface-coloured bubbles and white captions still stand out.
            colors: context.isDarkMode
                ? [palette.background, const Color(0xFF16393A)]
                : const [Color(0xFF3F7779), Color(0xFF8CE1E4)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messages,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: Text(
                        "Couldn't load messages.",
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  final live = snap.data!;
                  if (live.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          thread == ChatThread.clinic
                              ? 'Message the clinic to book a visit, request a home visit, or get help with the app.'
                              : 'Send your therapist a message about your exercises or how you feel.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  // Rebuilt when an older page starts or finishes loading.
                  return ListenableBuilder(
                    listenable: _pager,
                    builder: (context, _) => _buildMessageList(
                      context,
                      _pager.merge(live),
                      contentWidth,
                    ),
                  );
                },
              ),
            ),

            if (thread == ChatThread.clinic)
              ReadableWidth(
                maxWidth: contentWidth,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _clinicPrompts.entries.map((e) {
                      return GestureDetector(
                        onTap: () => _usePrompt(e.key, e.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.key.contains('problem')
                                    ? Icons.bug_report
                                    : e.key.contains('home')
                                    ? Icons.home_outlined
                                    : Icons.calendar_today,
                                size: 14,
                                color: e.key.contains('problem')
                                    ? Colors.redAccent
                                    : _primaryTeal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Input bar (Liquid Glass on iPhone, the flat bar on Android).
            ReadableWidth(
              maxWidth: contentWidth,
              child: ChatComposerSurface(
                child: Row(
                  children: [
                    // Sessions are what the therapist reviews; the clinic
                    // desk has no use for them.
                    if (thread == ChatThread.therapist)
                      IconButton(
                        tooltip: 'Share a session',
                        onPressed: _shareSession,
                        icon: const Icon(
                          Icons.insights_outlined,
                          color: _primaryTeal,
                        ),
                      ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: palette.divider),
                        ),
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: _maxMessageLength,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: palette.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: palette.textFaint,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Dimmed and disabled while the box is empty or only
                    // spaces (rebuilt as the patient types).
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, _) {
                        final canSend = value.text.trim().isNotEmpty;
                        return IconButton(
                          tooltip: 'Send',
                          onPressed: canSend ? _send : null,
                          icon: Icon(
                            Icons.send_rounded,
                            color: canSend ? _primaryTeal : palette.textFaint,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final IconData icon;
  final bool showTime;

  /// Staff have opened the conversation since this (patient) message.
  final bool seen;

  /// Long-press on the bubble (copies the text).
  final VoidCallback? onLongPress;

  const _Bubble({
    required this.msg,
    required this.icon,
    required this.showTime,
    this.seen = false,
    this.onLongPress,
  });

  /// Like other messaging apps: a clock while it's still uploading, one tick
  /// once it reached the server, two ticks once staff have seen it.
  Widget _receipt(AppPalette palette) {
    final (IconData glyph, String label) = msg.pending
        ? (Icons.schedule, 'Sending')
        : seen
        ? (Icons.done_all, 'Seen')
        : (Icons.done, 'Sent');
    return Semantics(
      label: label,
      child: Icon(
        glyph,
        size: 14,
        color: seen ? _primaryTeal : palette.textMuted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = msg.fromPatient;
    final palette = context.palette;
    return Column(
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              // Time only: the day is on the separator above.
              DateFormat.jm().format(msg.sentAt).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: palette.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _avatarBg(context),
                  child: Icon(icon, color: palette.textMuted, size: 18),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? _primaryTeal : palette.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: mine ? Colors.white : palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              if (mine) ...[const SizedBox(width: 4), _receipt(palette)],
            ],
          ),
        ),
      ],
    );
  }
}
