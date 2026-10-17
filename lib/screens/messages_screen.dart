import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat.dart';
import '../services/app_provider.dart';
import '../services/chat_service.dart';

const Color _primaryTeal = Color(0xFF23A8AA);

String _threadTitle(BuildContext context, ChatThread thread) {
  if (thread == ChatThread.clinic) return 'RehabPlus Clinic';
  final therapist = context.watch<AppProvider>().profile?.therapist ?? '';
  return therapist.isEmpty ? 'Your Therapist' : therapist;
}

String _threadSubtitle(ChatThread thread) => switch (thread) {
  ChatThread.therapist => 'Questions about your exercises or progress',
  ChatThread.clinic => 'Appointments, home visits and app support',
};

IconData _threadIcon(ChatThread thread) =>
    thread == ChatThread.clinic ? Icons.groups : Icons.person_outline;

/// Opens the phone dialer with the clinic number (settings/clinic.phone).
Future<void> callClinic(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  String? phone;
  try {
    phone = await ChatService().clinicPhone();
  } catch (_) {
    phone = null;
  }
  if (phone == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('The clinic phone number is not set up yet.'),
      ),
    );
    return;
  }
  final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
  if (!launched) {
    messenger.showSnackBar(
      SnackBar(content: Text('Call the clinic at $phone')),
    );
  }
}

// --- CONVERSATION LIST ---
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
  late final Stream<ChatThreadSummary> _summary = ChatService().summary(
    widget.thread,
  );

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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatDetailScreen(thread: thread)),
          ),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade300,
            child: Icon(
              _threadIcon(thread),
              color: Colors.grey.shade600,
              size: 30,
            ),
          ),
          title: Text(
            _threadTitle(context, thread),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            s.lastMessage ?? _threadSubtitle(thread),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: unread > 0 ? Colors.black87 : Colors.black54,
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
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
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
  late final Stream<List<ChatMessage>> _messages = _chat.messages(
    widget.thread,
  );
  StreamSubscription<ChatThreadSummary>? _unreadSub;

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
    // Clear the unread badge on open and whenever staff replies arrive.
    _unreadSub = _chat.summary(widget.thread).listen((s) {
      if (s.unreadForPatient > 0) _chat.markRead(widget.thread);
    });
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
    _chat.send(widget.thread, text);
    _textController.clear();
  }

  void _usePrompt(String prompt) {
    _textController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade300,
              child: Icon(
                _threadIcon(thread),
                color: Colors.grey.shade600,
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
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _threadSubtitle(thread),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3F7779), Color(0xFF8CE1E4)],
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
                  return ListView.builder(
                    reverse: true, // newest at the bottom, auto-scrolls
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
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
                      );
                    },
                  );
                },
              ),
            ),

            if (thread == ChatThread.clinic)
              Container(
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
                      onTap: () => _usePrompt(e.value),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
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
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Input bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              color: Colors.grey.shade200,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
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

  const _Bubble({
    required this.msg,
    required this.icon,
    required this.showTime,
  });

  @override
  Widget build(BuildContext context) {
    final mine = msg.fromPatient;
    return Column(
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              DateFormat("EEE 'at' h:mm a").format(msg.sentAt).toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
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
                  backgroundColor: Colors.grey.shade300,
                  child: Icon(icon, color: Colors.grey.shade600, size: 18),
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
                    color: mine ? _primaryTeal : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: mine ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(
                  msg.pending ? Icons.schedule : Icons.done,
                  size: 12,
                  color: Colors.black45,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
