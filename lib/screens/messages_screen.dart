import 'dart:async';

import 'package:flutter/material.dart';
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

const Color _primaryTeal = Color(0xFF23A8AA);
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

// --- CONVERSATION LIST ---
// Stateful only so "Screen opened" is logged once, not on every rebuild.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  @override
  Widget build(BuildContext context) {
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
        padding: readablePadding(context),
        itemCount: ChatThread.values.length,
        separatorBuilder: (_, _) =>
            const Divider(indent: 72, height: 1, thickness: 0.5),
        itemBuilder: (context, i) => _ThreadTile(thread: ChatThread.values[i]),
      ),
    );
  }
}

class _ThreadTile extends StatefulWidget {
  final ChatThread thread;
  const _ThreadTile({required this.thread});

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

  String _time(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return DateFormat.jm().format(t);
    if (today.difference(day).inDays == 1) return 'Yesterday';
    if (today.difference(day).inDays < 7) return DateFormat.E().format(t);
    return DateFormat.MMMd().format(t);
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          onTap: () {
            DiagnosticLogger.I.info(_tag, 'Thread opened', {
              'thread': thread.name,
              'unread': unread,
            });
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
                  _time(s.lastMessageAt!),
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

  const ChatDetailScreen({super.key, required this.thread});

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
    _textController.dispose();
    super.dispose();
  }

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
    _textController.clear();
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 1,
        leading: IconButton(
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
                  final msgs = snap.data!;
                  if (msgs.isEmpty) {
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
                  final seen = seenByStaff(msgs, _unreadForStaff);
                  return ListView.builder(
                    reverse: true, // newest at the bottom, auto-scrolls
                    padding: readablePadding(
                      context,
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      );
                    },
                  );
                },
              ),
            ),

            if (thread == ChatThread.clinic)
              ReadableWidth(
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

            // Input bar
            ReadableWidth(
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
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
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
                      IconButton(
                        tooltip: 'Send',
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded, color: _primaryTeal),
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

  const _Bubble({
    required this.msg,
    required this.icon,
    required this.showTime,
    this.seen = false,
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
              Flexible(
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
              if (mine) ...[const SizedBox(width: 4), _receipt(palette)],
            ],
          ),
        ),
      ],
    );
  }
}
