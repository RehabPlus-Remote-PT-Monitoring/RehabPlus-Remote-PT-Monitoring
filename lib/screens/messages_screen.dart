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
import '../services/chat_actions.dart';
import '../services/chat_service.dart';
import '../services/progress_stats.dart' show CalendarDays;
import '../core/responsive.dart';
import '../core/tab_bar_clearance.dart';
import '../widgets/chat_action_widgets.dart';

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
  ChatThread.clinic => 'Appointments and app support',
};

/// Background of the grey contact avatars: grey 300 in light mode (white
/// cards), the muted surface in dark mode so it doesn't glare.
Color _avatarBg(BuildContext context) =>
    context.isDarkMode ? context.palette.surfaceMuted : Colors.grey.shade300;

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
      DiagnosticLogger.I.warn(
        _tag,
        'Thread summary unavailable',
        {'thread': widget.thread.name},
        e,
        st,
      );
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
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(thread: thread),
              ),
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

  /// The thread's pinned message (from the summary), or null.
  ChatPin? _pin;

  /// The bubble whose Reply / "⋯" buttons are showing (tap a bubble to show
  /// them, tap it again to hide them). Null: none.
  String? _selectedId;

  /// The message the next send replies to, or null.
  ChatMessage? _replyingTo;

  /// The patient's message the box is editing (send saves the edit), or null.
  ChatMessage? _editing;

  /// What was in the box when editing started; put back when the edit is
  /// saved or cancelled, so a half-typed message isn't lost.
  String _draftBeforeEdit = '';

  /// The list last shown (newest first), to tell which message is the newest
  /// and to see the current copy of the one being replied to.
  List<ChatMessage> _shown = const [];

  final _inputFocus = FocusNode();

  /// Starters for the clinic thread; they fill the box so the patient can
  /// add details before sending.
  static const _clinicPrompts = {
    'Book clinic visit':
        "I'd like to book a clinic visit. My preferred date and time: ",
    'Report a problem': "I'd like to report a problem with the app: ",
  };

  @override
  void initState() {
    super.initState();
    final thread = widget.thread.name;
    _logger.info(_tag, 'Chat opened', {'thread': thread});
    try {
      // ChatService logs the stream's start, first snapshot and errors.
      _messages = _chat.messages(widget.thread);
      // Clear the unread badge on open and whenever staff replies arrive.
      _unreadSub = _chat.summary(widget.thread).listen(
        (s) {
          // Drives the ticks; Firestore applies our own sends to the
          // summary locally too, so a new message starts as unseen.
          final pinChanged =
              s.pin?.messageId != _pin?.messageId || s.pin?.text != _pin?.text;
          if (mounted && (pinChanged || s.unreadForStaff != _unreadForStaff)) {
            setState(() {
              _unreadForStaff = s.unreadForStaff;
              _pin = s.pin;
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
              _logger.warn(_tag, 'Mark read failed', {'thread': thread}, e, st);
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
    _textController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (text.length > _maxMessageLength) {
      // Possible with many emoji (each counts as 2+ units): the server
      // would reject it, so say so instead of failing silently.
      _logger.warn(_tag, 'Message too long', {'length': text.length});
      _snack('That message is too long. Please shorten it.');
      return;
    }
    final editing = _editing;
    if (editing != null) {
      _saveEdit(editing, text);
      return;
    }
    final replyTo = _currentReplyTarget();
    if (_replyingTo != null && replyTo == null) {
      // Deleted by its author while the patient was typing; the dashboard
      // refuses a reply to an unsent message too.
      _logger.info(_tag, 'Reply target was deleted', {
        'thread': widget.thread.name,
      });
      setState(() => _replyingTo = null);
      _snack('The message you replied to was deleted.');
      return;
    }
    try {
      // Not awaited: Firestore's offline cache queues it. ChatService logs
      // "Message queued" with the length (never the text) and the sync
      // result. The text is cleared at once, so a double tap can't send it
      // twice.
      _chat.send(widget.thread, text, replyTo: replyTo);
    } catch (e, st) {
      _logger.error(
        _tag,
        'Sending failed',
        {'thread': widget.thread.name},
        e,
        st,
      );
      _snack('Could not send. Please sign in again.');
      return;
    }
    _textController.clear();
    if (_replyingTo != null) setState(() => _replyingTo = null);
  }

  /// The current copy of the message being replied to, or null when there
  /// is none or it has since been unsent.
  ChatMessage? _currentReplyTarget() {
    final target = _replyingTo;
    if (target == null) return null;
    final current =
        _shown.where((m) => m.id == target.id).firstOrNull ?? target;
    return current.unsent ? null : current;
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// The newest message shown (its edit or unsend changes the thread
  /// preview in the conversation list).
  bool _isNewest(ChatMessage msg) =>
      _shown.isNotEmpty && _shown.first.id == msg.id;

  /// Saves the edit of [msg] typed in the box.
  void _saveEdit(ChatMessage msg, String text) {
    try {
      _chat.editMessage(
        widget.thread,
        msg,
        text,
        newest: _isNewest(msg),
        pinned: _pin?.messageId == msg.id,
      );
    } catch (e, st) {
      _logger.error(_tag, 'Edit failed', {'thread': widget.thread.name}, e, st);
      _snack("Couldn't edit the message.");
      return;
    }
    _endEdit();
  }

  /// Leaves editing and puts back what was typed before it started.
  void _endEdit() {
    final draft = _draftBeforeEdit;
    _draftBeforeEdit = '';
    _textController
      ..text = draft
      ..selection = TextSelection.collapsed(offset: draft.length);
    setState(() => _editing = null);
  }

  /// Tap on a bubble: shows its Reply / "⋯" buttons, or hides them.
  void _toggleSelected(ChatMessage msg) {
    if (msg.unsent) return;
    setState(() => _selectedId = _selectedId == msg.id ? null : msg.id);
  }

  /// Long-press on a bubble shows its buttons too, with a buzz.
  Future<void> _onLongPress(ChatMessage msg) async {
    if (msg.unsent) return;
    setState(() => _selectedId = msg.id);
    try {
      await HapticFeedback.selectionClick();
    } catch (e, st) {
      _logger.warn(_tag, 'Select haptic failed', null, e, st);
    }
  }

  void _startReply(ChatMessage msg) {
    _logger.info(_tag, 'Reply started', {'thread': widget.thread.name});
    if (_editing != null) _endEdit();
    setState(() {
      _replyingTo = msg;
      _selectedId = null;
    });
    _inputFocus.requestFocus();
  }

  void _startEdit(ChatMessage msg) {
    _logger.info(_tag, 'Edit started', {'thread': widget.thread.name});
    // Editing a second message straight after the first keeps the original
    // draft, not the first message's text.
    if (_editing == null) _draftBeforeEdit = _textController.text;
    setState(() {
      _replyingTo = null;
      _editing = msg;
      _selectedId = null;
    });
    _textController
      ..text = msg.text
      ..selection = TextSelection.collapsed(offset: msg.text.length);
    _inputFocus.requestFocus();
  }

  /// An entry of a bubble's "⋯" menu.
  Future<void> _onAction(ChatMessage msg, ChatMessageAction action) async {
    setState(() => _selectedId = null);
    _logger.info(_tag, 'Message action', {
      'thread': widget.thread.name,
      'action': action.name,
    });
    try {
      switch (action) {
        case ChatMessageAction.copy:
          await _copy(msg);
        case ChatMessageAction.pin:
          _chat.pin(widget.thread, msg);
        case ChatMessageAction.unpin:
          _chat.unpin(widget.thread);
        case ChatMessageAction.edit:
          _startEdit(msg);
        case ChatMessageAction.unsend:
          await _unsend(msg);
      }
    } catch (e, st) {
      _logger.error(
        _tag,
        'Message action failed',
        {'thread': widget.thread.name, 'action': action.name},
        e,
        st,
      );
      if (mounted) _snack("Couldn't do that. Please try again.");
    }
  }

  /// Copies [msg]'s text (the "⋯" menu's Copy). The messenger is captured
  /// before the await so the SnackBar still works if the chat closes.
  Future<void> _copy(ChatMessage msg) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: msg.text));
    // Logs the length only, never the text.
    _logger.info(_tag, 'Message copied', {'length': msg.text.length});
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
      );
  }

  /// Asks first, then unsends [msg] for both sides.
  Future<void> _unsend(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsend message?'),
        content: const Text(
          'It will be removed for everyone in this chat. They will see '
          '"$kChatDeletedText" instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _chat.unsendMessage(
      widget.thread,
      msg,
      newest: _isNewest(msg),
      pinned: _pin?.messageId == msg.id,
    );
    setState(() {
      if (_replyingTo?.id == msg.id) _replyingTo = null;
    });
    if (_editing?.id == msg.id) _endEdit();
  }

  /// "You" for the patient's messages, the thread's name (therapist or
  /// clinic) for staff ones.
  String _senderLabel(BuildContext context, bool fromPatient) =>
      fromPatient ? 'You' : _threadTitle(context, widget.thread);

  /// Who wrote the message [msg] replies to ("You" or the thread's name),
  /// or null when [msg] is not a reply (or its quote is unusable).
  String? _quoteSender(BuildContext context, ChatMessage msg) {
    final quote = msg.replyTo;
    if (quote == null || quote['text'] is! String) return null;
    return _senderLabel(context, quote['senderRole'] == 'patient');
  }

  /// The pinned message under the app bar, or null when nothing is pinned
  /// or the pinned message (when loaded) has been unsent.
  Widget? _pinnedBanner(BuildContext context) {
    final pin = _pin;
    if (pin == null) return null;
    final pinned = _shown.where((m) => m.id == pin.messageId).firstOrNull;
    if (pinned != null && pinned.unsent) return null;
    return ChatPinnedBanner(
      senderLabel: _senderLabel(context, pin.fromPatient),
      // The loaded message is the freshest copy (e.g. just edited).
      text: pinned == null ? pin.text : chatSnippet(pinned.text),
      onUnpin: () {
        _logger.info(_tag, 'Unpin tapped', {'thread': widget.thread.name});
        try {
          _chat.unpin(widget.thread);
        } catch (e, st) {
          _logger.error(
            _tag,
            'Unpin failed',
            {'thread': widget.thread.name},
            e,
            st,
          );
          _snack("Couldn't do that. Please try again.");
        }
      },
    );
  }

  /// "Replying to …" / "Editing message" above the message box, or null.
  Widget? _composerContext(BuildContext context) {
    final editing = _editing;
    if (editing != null) {
      return ChatComposerContextBar(
        icon: Icons.edit_outlined,
        title: 'Editing message',
        text: editing.text,
        cancelTooltip: 'Cancel editing',
        onCancel: _endEdit,
      );
    }
    final replying = _replyingTo;
    if (replying != null) {
      return ChatComposerContextBar(
        icon: Icons.reply_rounded,
        title: 'Replying to ${_senderLabel(context, replying.fromPatient)}',
        text: replying.text,
        cancelTooltip: 'Cancel reply',
        onCancel: () => setState(() => _replyingTo = null),
      );
    }
    return null;
  }

  /// One quick-start chip under the clinic chat (e.g. "Book clinic visit").
  /// Tapping it fills the message box with [prompt]. The label shrinks with
  /// "…" rather than wrapping, so the chips always stay on one row.
  Widget _clinicPromptChip(String label, String prompt) {
    final palette = context.palette;
    final isProblem = label.contains('problem');
    return GestureDetector(
      onTap: () => _usePrompt(label, prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isProblem ? Icons.bug_report : Icons.calendar_today,
              size: 14,
              color: isProblem ? Colors.redAccent : _primaryTeal,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _usePrompt(String label, String prompt) {
    _logger.info(_tag, 'Prompt chip used', {'prompt': label});
    _textController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final palette = context.palette;
    // As a page: one readable column. In the split view the pane itself is
    // the column, so content uses all of it.
    final contentWidth = widget.embedded ? double.infinity : kReadableMaxWidth;
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
            ?_pinnedBanner(context),
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
                  final msgs = snap.data!;
                  if (msgs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          thread == ChatThread.clinic
                              ? 'Message the clinic to book a visit or get help with the app.'
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
                  _shown = msgs;
                  final seen = seenByStaff(msgs, _unreadForStaff);
                  return ListView.builder(
                    reverse: true, // newest at the bottom, auto-scrolls
                    padding: readablePadding(
                      context,
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      contentWidth,
                    ),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final msg = msgs[i];
                      // List is newest-first, so the message shown above is i + 1.
                      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                      final showTime =
                          older == null ||
                          msg.sentAt.difference(older.sentAt).inMinutes >= 10;
                      return _Bubble(
                        msg: msg,
                        icon: _threadIcon(thread),
                        showTime: showTime,
                        seen: seen.contains(msg.id),
                        quoteSender: _quoteSender(context, msg),
                        actions: msg.id == _selectedId
                            ? ChatMessageActionBar(
                                mine: msg.fromPatient,
                                actions: chatMenuActions(
                                  msg,
                                  pinnedMessageId: _pin?.messageId,
                                ),
                                onReply: chatCanReply(msg)
                                    ? () => _startReply(msg)
                                    : null,
                                onAction: (action) => _onAction(msg, action),
                              )
                            : null,
                        onTap: () => _toggleSelected(msg),
                        onLongPress: () => _onLongPress(msg),
                      );
                    },
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
                  // One row, side by side: each chip shrinks (text ends in
                  // "…") on very narrow screens instead of wrapping onto a
                  // second line.
                  child: Row(
                    children: [
                      for (final e in _clinicPrompts.entries) ...[
                        if (e.key != _clinicPrompts.keys.first)
                          const SizedBox(width: 8),
                        Flexible(child: _clinicPromptChip(e.key, e.value)),
                      ],
                    ],
                  ),
                ),
              ),

            if (_composerContext(context) case final bar?)
              ReadableWidth(maxWidth: contentWidth, child: bar),

            // Input bar
            ReadableWidth(
              maxWidth: contentWidth,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                color: palette.surfaceMuted,
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
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
                            focusNode: _inputFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: _maxMessageLength,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(color: palette.textPrimary),
                            decoration: InputDecoration(
                              hintText: _editing != null
                                  ? 'Edit message'
                                  : 'Message',
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
                      IconButton(
                        tooltip: _editing != null ? 'Save' : 'Send',
                        onPressed: _send,
                        icon: Icon(
                          _editing != null
                              ? Icons.check_rounded
                              : Icons.send_rounded,
                          color: _primaryTeal,
                        ),
                      ),
                    ],
                  ),
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

  /// Who wrote the message this one replies to; null: not a reply.
  final String? quoteSender;

  /// The Reply / "⋯" buttons, shown beside the bubble while it is selected.
  final Widget? actions;

  /// Tap on the bubble (shows or hides [actions]).
  final VoidCallback? onTap;

  /// Long-press on the bubble (shows [actions]).
  final VoidCallback? onLongPress;

  const _Bubble({
    required this.msg,
    required this.icon,
    required this.showTime,
    this.seen = false,
    this.quoteSender,
    this.actions,
    this.onTap,
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

  Widget _bubble(BuildContext context) {
    final mine = msg.fromPatient;
    final palette = context.palette;
    final onBubble = mine ? Colors.white : palette.textPrimary;
    final quote = msg.replyTo;
    final edited = msg.editedLabel;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: mine ? _primaryTeal : palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quoteSender != null && quote != null)
              ChatReplyQuote(
                senderLabel: quoteSender!,
                text: quote['text'] as String,
                onBubble: onBubble,
              ),
            Text(
              msg.text,
              style: TextStyle(
                color: onBubble,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (edited != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  edited,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: onBubble.withValues(alpha: 0.75),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = msg.fromPatient;
    final palette = context.palette;
    final actions = this.actions;
    return Column(
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              DateFormat("EEE 'at' h:mm a").format(msg.sentAt).toUpperCase(),
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
              // Reply and "⋯" sit on the side away from the screen edge:
              // left of the patient's bubbles, right of the other side's.
              if (mine && actions != null) ...[
                actions,
                const SizedBox(width: 4),
              ],
              Flexible(
                // An unsent message: only a placeholder, no bubble, menu
                // or ticks.
                child: msg.unsent
                    ? ChatUnsentPlaceholder(mine: mine)
                    : _bubble(context),
              ),
              if (!mine && actions != null) ...[
                const SizedBox(width: 4),
                actions,
              ],
              if (mine && !msg.unsent) ...[
                const SizedBox(width: 4),
                _receipt(palette),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
