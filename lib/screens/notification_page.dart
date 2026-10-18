import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/diagnostic_logger.dart';
import '../models/app_notification.dart';
import '../models/chat.dart';
import '../services/notification_service.dart';
import 'messages_screen.dart';

/// Icon and colours per notification type.
class _Visual {
  final IconData icon;
  final Color bg;
  final Color fg;
  const _Visual(this.icon, this.bg, this.fg);
}

const _visuals = <String, _Visual>{
  'session_completed': _Visual(
    Icons.accessibility_new_rounded,
    Color(0xFFB3EBF2),
    Color(0xFF0097A7),
  ),
  'exercise_assigned': _Visual(
    Icons.assignment_outlined,
    Color(0xFFC8E6C9),
    Color(0xFF388E3C),
  ),
  'appointment': _Visual(
    Icons.calendar_month_outlined,
    Color(0xFFBBDEFB),
    Color(0xFF1976D2),
  ),
  'progress': _Visual(
    Icons.bar_chart_rounded,
    Color(0xFFE1BEE7),
    Color(0xFF7B1FA2),
  ),
  'milestone': _Visual(
    Icons.emoji_events_outlined,
    Color(0xFFFFF9C4),
    Color(0xFFFBC02D),
  ),
  'message': _Visual(
    Icons.chat_bubble_outline_rounded,
    Color(0xFFB2EBF2),
    Color(0xFF00838F),
  ),
  'reminder': _Visual(
    Icons.alarm_rounded,
    Color(0xFFFFE0B2),
    Color(0xFFF57C00),
  ),
};
const _defaultVisual = _Visual(
  Icons.notifications_none_rounded,
  Color(0xFFE0E0E0),
  Color(0xFF616161),
);

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  int _selectedFilterIndex = 0;

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  static const String _tag = 'Notifications';
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  final _service = NotificationService();

  /// Created once (not in build), so rebuilds don't re-subscribe Firestore.
  late final Stream<List<AppNotification>> _stream;

  /// Everything from the latest snapshot, then the filtered list and unread
  /// count derived from it. Computed once per snapshot or filter change in
  /// [_derive], not on every getter call (the list builder used to re-filter
  /// the whole list for every row it built).
  List<AppNotification> _notifications = const [];
  List<AppNotification> _filtered = const [];
  int _unreadCount = 0;

  /// While "mark all as read" runs, so a double tap sends one batch.
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
    // NotificationService logs the stream's start, first snapshot and
    // errors.
    _stream = _service.watch();
  }

  void _derive(List<AppNotification> all) {
    _notifications = all;
    _unreadCount = all.where((n) => !n.read).length;
    _filtered = switch (_selectedFilterIndex) {
      1 => all.where((n) => n.read).toList(),
      2 => all.where((n) => !n.read).toList(),
      _ => all,
    };
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    _logger.info(_tag, 'Mark all read', {'unread': _unreadCount});
    try {
      await _service.markAllRead();
    } catch (e, st) {
      // The unread query can fail offline; the badge just stays as it is.
      _logger.warn(_tag, 'Mark all read failed', null, e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update. Check your internet connection.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  String _time(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days == 0) return DateFormat.jm().format(t);
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat.EEEE().format(t);
    return DateFormat.MMMd().format(t);
  }

  void _open(AppNotification n) {
    // The type and state only; title/body can contain personal details.
    _logger.info(_tag, 'Notification opened', {'type': n.type, 'read': n.read});
    if (!n.read) _service.markRead(n.id);
    final thread = ChatThread.values
        .where((t) => t.name == n.data['thread'])
        .firstOrNull;
    if (n.type == 'message' && thread != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(thread: thread)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snap) {
        _derive(snap.data ?? const []);
        return _buildPage(loading: !snap.hasData && !snap.hasError);
      },
    );
  }

  Widget _buildPage({required bool loading}) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      body: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildFilterRow(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedFilterIndex == 0
                      ? 'All Notifications'
                      : _selectedFilterIndex == 1
                      ? 'Read'
                      : 'Unread',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${_filtered.length} items',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryTeal),
                  )
                : _filtered.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _notificationCard(_filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$_unreadCount new',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_unreadCount > 0)
                IconButton(
                  tooltip: 'Mark all as read',
                  onPressed: _markingAll ? null : _markAllRead,
                  icon: const Icon(Icons.done_all_rounded, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    const labels = ['All', 'Read', 'Unread'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: List.generate(3, (i) {
          final selected = _selectedFilterIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedFilterIndex == i) return;
                _logger.verbose(_tag, 'Filter changed', {'filter': labels[i]});
                setState(() => _selectedFilterIndex = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(colors: [primaryTeal, darkTeal])
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: primaryTeal.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? Colors.white : Colors.black45,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _notificationCard(AppNotification item) {
    final v = _visuals[item.type] ?? _defaultVisual;
    final isUnread = !item.read;
    return GestureDetector(
      onTap: () => _open(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isUnread
              ? Border.all(
                  color: primaryTeal.withValues(alpha: 0.25),
                  width: 1.2,
                )
              : Border.all(color: Colors.transparent),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: v.bg, shape: BoxShape.circle),
              child: Icon(v.icon, color: v.fg, size: 24),
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
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _time(item.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          item.body,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: primaryTeal,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primaryTeal.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              size: 40,
              color: primaryTeal,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _notifications.isEmpty
                ? 'No notifications yet'
                : 'No notifications here',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
