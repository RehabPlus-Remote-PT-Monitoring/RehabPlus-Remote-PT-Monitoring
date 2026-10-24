import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../services/app_provider.dart';
import '../services/chat_service.dart';
import '../core/responsive.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_split_view.dart';
import '../widgets/ios_page.dart';
import '../widgets/pressable.dart';

const String _tag = 'Messages';

/// Firestore rules limit a message to 1000 characters. Dart's String.length
/// counts UTF-16 units, which is never less than the rules' count, so a
/// message that passes this check always passes the rule.
const int _maxMessageLength = 1000;

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
    thread == ChatThread.clinic ? CupertinoIcons.person_3_fill : CupertinoIcons.person;

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

// --- CONVERSATION LIST (the Messages tab) ---
//
// Phone and narrow tablet: an iOS large-title list of the two threads;
// tapping one pushes the conversation. Wide (>= kTwoColumnBreakpoint, the
// page area beside the dashboard's sidebar): iPad Messages, with the list
// on the left and the selected conversation on the right of the same tab.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// The conversation shown in the right pane when the tab is wide. Kept
  /// on narrow widths too, so rotating back shows the same one.
  ChatThread _selected = ChatThread.values.first;

  /// Unsent text per thread. The conversation widget is rebuilt when the
  /// layout switches between split and pushed (rotating a tablet) or the
  /// selected thread changes; it reports every edit here and starts from
  /// this text, so a half-typed message survives that. Kept only while the
  /// tab is alive, never written anywhere.
  final Map<ChatThread, String> _drafts = {};

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  void _saveDraft(ChatThread thread, String text) => _drafts[thread] = text;

  /// Narrow layout: push the conversation as its own page.
  void _push(ChatThread thread, int unread) {
    DiagnosticLogger.I.info(_tag, 'Thread opened', {
      'thread': thread.name,
      'unread': unread,
      'layout': 'pushed',
    });
    setState(() => _selected = thread);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatPage(
          thread: thread,
          previousPageTitle: 'Messages',
          initialDraft: _drafts[thread],
          onDraftChanged: (text) => _saveDraft(thread, text),
        ),
      ),
    );
  }

  /// Wide layout: switch the right pane.
  void _select(ChatThread thread, int unread) {
    if (thread == _selected) return;
    DiagnosticLogger.I.info(_tag, 'Thread opened', {
      'thread': thread.name,
      'unread': unread,
      'layout': 'split',
    });
    setState(() => _selected = thread);
  }

  @override
  Widget build(BuildContext context) {
    if (!useChatSplitView(context)) {
      return _ThreadList(onOpen: _push);
    }
    return ChatSplitView(
      list: _ThreadList(selected: _selected, onOpen: _select),
      detail: _ChatPage(
        // A new key per thread gives the pane fresh message streams.
        key: ValueKey(_selected),
        thread: _selected,
        initialDraft: _drafts[_selected],
        onDraftChanged: (text) => _saveDraft(_selected, text),
      ),
    );
  }
}

/// The large-title list of threads. [selected] is highlighted (split view
/// only); [onOpen] gets the tapped thread and its unread count for logging.
class _ThreadList extends StatelessWidget {
  const _ThreadList({this.selected, required this.onOpen});

  final ChatThread? selected;
  final void Function(ChatThread thread, int unread) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final threads = ChatThread.values;
    // The dashboard's tab bar may float over the bottom of the page.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final rows = <Widget>[];
    for (var i = 0; i < threads.length; i++) {
      if (i > 0) {
        // Inset past the avatar, like iOS Messages.
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: _ThreadRow.textStart),
            child: Container(height: 0.5, color: palette.divider),
          ),
        );
      }
      rows.add(
        _ThreadRow(
          thread: threads[i],
          selected: threads[i] == selected,
          onOpen: onOpen,
        ),
      );
    }

    return IosPage(
      title: 'Messages',
      trailing: IconButton(
        tooltip: 'Call the clinic',
        visualDensity: VisualDensity.compact,
        onPressed: () => callClinic(context),
        icon: const Icon(CupertinoIcons.phone, color: AppPalette.teal),
      ),
      slivers: [
        SliverPadding(
          padding: readablePadding(
            context,
            EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
          ),
          sliver: SliverToBoxAdapter(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: palette.surface,
                child: Column(children: rows),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatefulWidget {
  const _ThreadRow({
    required this.thread,
    required this.selected,
    required this.onOpen,
  });

  final ChatThread thread;
  final bool selected;
  final void Function(ChatThread thread, int unread) onOpen;

  /// Where the name starts (left padding + unread dot + avatar + gap);
  /// separators start here too.
  static const double textStart = 8 + 14 + 48 + 12;

  @override
  State<_ThreadRow> createState() => _ThreadRowState();
}

class _ThreadRowState extends State<_ThreadRow> {
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

  /// "9:41 AM" today, then "Yesterday", the weekday within a week, else
  /// the date, as in the iOS Messages list.
  String _time(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return DateFormat.jm().format(t);
    if (today.difference(day).inDays == 1) return 'Yesterday';
    if (today.difference(day).inDays < 7) return DateFormat.EEEE().format(t);
    return DateFormat.yMd().format(t);
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return StreamBuilder<ChatThreadSummary>(
      stream: _summary,
      builder: (context, snap) {
        final s = snap.data ?? ChatThreadSummary.empty;
        final unread = s.unreadForPatient;
        final hasUnread = unread > 0;
        final title = _threadTitle(context, thread);
        final preview = s.lastMessage ?? _threadSubtitle(thread);
        final time = s.lastMessageAt == null ? null : _time(s.lastMessageAt!);

        // Read as one sentence by screen readers, unread count included
        // (the dot alone would only say it by colour).
        final label = [
          title,
          if (hasUnread) '$unread unread',
          preview,
          ?time,
        ].join(', ');

        return Pressable(
          // List rows only dim on touch, like UIKit cell highlights.
          pressedScale: 1,
          semanticLabel: label,
          onTap: () => widget.onOpen(thread, unread),
          child: ExcludeSemantics(
            child: Container(
              color: widget.selected
                  ? AppPalette.teal.withValues(alpha: 0.16)
                  : Colors.transparent,
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: Row(
                children: [
                  // Unread dot in its own column, so names stay aligned.
                  SizedBox(
                    width: 14,
                    child: hasUnread
                        ? Center(
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: AppPalette.teal,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _avatarBg(context),
                    child: Icon(
                      _threadIcon(thread),
                      color: palette.textMuted,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                time,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              size: 14,
                              color: palette.textFaint,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: hasUnread
                                ? palette.textPrimary
                                : palette.textSecondary,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- CHAT DETAIL SCREEN ---
//
// Pushed by the notification list, push notification taps and Settings
// ("Contact the clinic"). The Messages tab pushes the same page itself
// (with a "Messages" back label and draft keeping), or shows it as the
// right pane of the split view.
class ChatDetailScreen extends StatelessWidget {
  final ChatThread thread;

  const ChatDetailScreen({super.key, required this.thread});

  @override
  Widget build(BuildContext context) {
    // Callers come from several screens, so the back button doesn't name
    // one it can't be sure of.
    return _ChatPage(thread: thread, previousPageTitle: 'Back');
  }
}

/// A conversation with its navigation bar: contact name centred, call
/// button on the right, and a back button when pushed. Used as a pushed
/// page and as the split view's right pane (no back button there, since
/// nothing was pushed).
class _ChatPage extends StatelessWidget {
  const _ChatPage({
    super.key,
    required this.thread,
    this.previousPageTitle,
    this.initialDraft,
    this.onDraftChanged,
  });

  final ChatThread thread;

  /// Label of the back button; null for the split-view pane.
  final String? previousPageTitle;

  final String? initialDraft;
  final ValueChanged<String>? onDraftChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isPane = previousPageTitle == null;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: CupertinoNavigationBar(
        automaticallyImplyLeading: !isPane,
        previousPageTitle: previousPageTitle,
        middle: Text(
          _threadTitle(context, thread),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Call the clinic',
          visualDensity: VisualDensity.compact,
          icon: const Icon(CupertinoIcons.phone, color: AppPalette.teal),
          onPressed: () => callClinic(context),
        ),
        backgroundColor: palette.background,
        border: Border(bottom: BorderSide(color: palette.divider, width: 0.5)),
        // Material routes don't run Cupertino's flying-title animation.
        transitionBetweenRoutes: false,
      ),
      body: _ChatConversation(
        thread: thread,
        initialDraft: initialDraft,
        onDraftChanged: onDraftChanged,
      ),
    );
  }
}

/// The messages, the clinic's quick replies and the composer, without any
/// page chrome, so it can sit in a pushed page or a split-view pane.
class _ChatConversation extends StatefulWidget {
  const _ChatConversation({
    required this.thread,
    this.initialDraft,
    this.onDraftChanged,
  });

  final ChatThread thread;

  /// Text to start the box with (a draft kept across layout changes).
  final String? initialDraft;

  /// Told about every change of the box's text, so the owner can keep it.
  final ValueChanged<String>? onDraftChanged;

  @override
  State<_ChatConversation> createState() => _ChatConversationState();
}

class _ChatConversationState extends State<_ChatConversation> {
  final _chat = ChatService();
  late final TextEditingController _textController;
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// Created once in initState, so rebuilds (keyboard, typing) don't
  /// re-subscribe to Firestore.
  late final Stream<List<ChatMessage>> _messages;
  StreamSubscription<ChatThreadSummary>? _unreadSub;

  /// The thread's `unreadForStaff` counter, for read receipts (two ticks once
  /// staff have seen a message). Null until the summary first loads.
  int? _unreadForStaff;

  /// Starters for the clinic thread; they fill the box so the patient can
  /// add details before sending.
  static const _clinicPrompts = [
    ChatQuickReply(
      label: 'Book clinic visit',
      text: "I'd like to book a clinic visit. My preferred date and time: ",
      icon: CupertinoIcons.calendar,
    ),
    ChatQuickReply(
      label: 'Request home visit',
      text: "I'd like to request a home visit. My address and preferred date: ",
      icon: CupertinoIcons.house,
    ),
    ChatQuickReply(
      label: 'Report a problem',
      text: "I'd like to report a problem with the app: ",
      icon: CupertinoIcons.ant,
      iconColor: Colors.redAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialDraft ?? '');
    _textController.addListener(_reportDraft);
    final thread = widget.thread.name;
    _logger.info(_tag, 'Chat opened', {'thread': thread});
    try {
      // ChatService logs the stream's start, first snapshot and errors.
      _messages = _chat.messages(widget.thread);
      // Clear the unread badge on open and whenever staff replies arrive.
      _unreadSub = _chat
          .summary(widget.thread)
          .listen(
            (s) {
              // Drives the ticks; Firestore applies our own sends to the
              // summary locally too, so a new message starts as unseen.
              if (mounted && s.unreadForStaff != _unreadForStaff) {
                setState(() => _unreadForStaff = s.unreadForStaff);
              }
              if (s.unreadForPatient > 0) {
                _logger.verbose(_tag, 'Marking thread read', {
                  'thread': thread,
                  'unread': s.unreadForPatient,
                });
                _chat.markRead(widget.thread);
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
    _textController.removeListener(_reportDraft);
    _textController.dispose();
    super.dispose();
  }

  void _reportDraft() => widget.onDraftChanged?.call(_textController.text);

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (text.length > _maxMessageLength) {
      // Possible with many emoji (each counts as 2+ units): the server
      // would reject it, so say so instead of failing silently.
      _logger.warn(_tag, 'Message too long', {'length': text.length});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That message is too long. Please shorten it.'),
        ),
      );
      return;
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
      return;
    }
    // The bubble appearing is the confirmation; the tap of haptics makes
    // it feel sent, like iMessage's "whoosh".
    HapticFeedback.lightImpact();
    _textController.clear();
  }

  void _usePrompt(ChatQuickReply reply) {
    _logger.info(_tag, 'Prompt chip used', {'prompt': reply.label});
    _textController
      ..text = reply.text
      ..selection = TextSelection.collapsed(offset: reply.text.length);
  }

  /// A centred grey note in the message area (empty or failed states).
  Widget _note(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
      ),
    );
  }

  /// The list is newest first, so a message's older neighbour is i + 1.
  /// A grey time label starts a new group after a 10-minute gap.
  static bool _startsGroup(List<ChatMessage> msgs, int i) {
    if (i + 1 >= msgs.length) return true;
    return msgs[i].sentAt.difference(msgs[i + 1].sentAt).inMinutes >= 10;
  }

  /// The newest bubble of a run from one sender gets the tail: the next
  /// (newer, i - 1) message is from the other side or starts a new group.
  static bool _isLastInGroup(List<ChatMessage> msgs, int i) {
    if (i == 0) return true;
    final newer = msgs[i - 1];
    return newer.fromPatient != msgs[i].fromPatient || _startsGroup(msgs, i - 1);
  }

  Widget _buildMessages() {
    final thread = widget.thread;
    return StreamBuilder<List<ChatMessage>>(
      stream: _messages,
      builder: (context, snap) {
        if (snap.hasError) return _note("Couldn't load messages.");
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final msgs = snap.data!;
        if (msgs.isEmpty) {
          return _note(
            thread == ChatThread.clinic
                ? 'Message the clinic to book a visit, request a home visit, or get help with the app.'
                : 'Send your therapist a message about your exercises or how you feel.',
          );
        }
        final seen = seenByStaff(msgs, _unreadForStaff);
        return ListView.builder(
          reverse: true, // newest at the bottom, auto-scrolls
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: readablePadding(
            context,
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final msg = msgs[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_startsGroup(msgs, i)) ChatTimeLabel(sentAt: msg.sentAt),
                ChatBubble(
                  message: msg,
                  isLastInGroup: _isLastInGroup(msgs, i),
                  seen: seen.contains(msg.id),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildMessages()),
        if (widget.thread == ChatThread.clinic)
          ChatQuickReplies(replies: _clinicPrompts, onSelected: _usePrompt),
        ChatComposer(
          controller: _textController,
          onSend: _send,
          maxLength: _maxMessageLength,
        ),
      ],
    );
  }
}
