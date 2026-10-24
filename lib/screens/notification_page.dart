import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/app_notification.dart';
import '../models/chat.dart';
import '../services/notification_service.dart';
import '../core/responsive.dart';
import '../widgets/info_content_unavailable.dart';
import '../widgets/ios_list.dart' show IosColors;
import '../widgets/ios_page.dart';
import '../widgets/ios_segmented_control.dart';
import '../widgets/pressable.dart';
import 'messages_screen.dart';

/// Icon and tint per notification type. The icon sits on a light wash of
/// its tint (works in light and dark mode alike).
class _Visual {
  final IconData icon;
  final Color tint;
  const _Visual(this.icon, this.tint);
}

const _visuals = <String, _Visual>{
  'session_completed': _Visual(CupertinoIcons.checkmark_seal, IosColors.teal),
  'exercise_assigned': _Visual(CupertinoIcons.doc_text, IosColors.green),
  'appointment': _Visual(CupertinoIcons.calendar, IosColors.blue),
  'progress': _Visual(CupertinoIcons.chart_bar, IosColors.purple),
  'milestone': _Visual(CupertinoIcons.rosette, IosColors.orange),
  'message': _Visual(CupertinoIcons.chat_bubble, IosColors.teal),
  'reminder': _Visual(CupertinoIcons.alarm, IosColors.orange),
};
const _defaultVisual = _Visual(CupertinoIcons.bell, IosColors.gray);

/// Home bell / Exercise bell > Notifications: everything the clinic and the
/// app sent, newest first, with an All / Read / Unread filter.
///
/// Opened from two places, so the back button is a bare chevron (no
/// previous-page name).
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key, this.notifications});

  /// For tests: a ready-made stream instead of [NotificationService.watch].
  final Stream<List<AppNotification>>? notifications;

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  int _selectedFilterIndex = 0;

  /// Filter index -> segment label, in display order.
  static const Map<int, String> _filterLabels = {
    0: 'All',
    1: 'Read',
    2: 'Unread',
  };

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
    _stream = widget.notifications ?? _service.watch();
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

  void _selectFilter(int index) {
    if (_selectedFilterIndex == index) return;
    _logger.verbose(_tag, 'Filter changed', {'filter': _filterLabels[index]});
    setState(() => _selectedFilterIndex = index);
  }

  Widget _buildPage({required bool loading}) {
    final palette = context.palette;
    return IosPage(
      title: 'Notifications',
      // Two parents (Home and Exercise bells): a bare chevron.
      previousPageTitle: null,
      trailing: _unreadCount > 0 ? _markAllButton() : null,
      slivers: [
        SliverPadding(
          padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 8, 16, 0)),
          sliver: SliverToBoxAdapter(
            child: IosSegmentedControl<int>(
              options: _filterLabels,
              value: _selectedFilterIndex,
              onChanged: _selectFilter,
            ),
          ),
        ),
        if (loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (_filtered.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmpty())
        else ...[
          SliverPadding(
            padding: readablePadding(context, const EdgeInsets.fromLTRB(20, 20, 20, 8)),
            sliver: SliverToBoxAdapter(child: _buildListHeader(palette)),
          ),
          SliverPadding(
            padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
            sliver: SliverList.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _notificationCard(_filtered[i], palette),
            ),
          ),
        ],
      ],
    );
  }

  /// "Mark all read" in the navigation bar, only while something is unread.
  Widget _markAllButton() {
    return Tooltip(
      message: 'Mark all as read',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: _markingAll ? null : _markAllRead,
        child: const Text(
          'Mark all read',
          style: TextStyle(fontSize: 17, color: AppPalette.teal),
        ),
      ),
    );
  }

  /// iOS section header above the list: what is shown, and how many are
  /// new (the old header's "N new" pill).
  Widget _buildListHeader(AppPalette palette) {
    final caption = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: palette.textMuted,
    );
    final heading = switch (_selectedFilterIndex) {
      1 => 'Read',
      2 => 'Unread',
      _ => 'All notifications',
    };
    final count = _filtered.length == 1 ? '1 item' : '${_filtered.length} items';
    return Row(
      children: [
        Expanded(child: Text(heading.toUpperCase(), style: caption)),
        if (_unreadCount > 0) ...[
          Text(
            '$_unreadCount new',
            style: caption?.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          Text(' · ', style: caption),
        ],
        Text(count, style: caption),
      ],
    );
  }

  Widget _notificationCard(AppNotification item, AppPalette palette) {
    final v = _visuals[item.type] ?? _defaultVisual;
    final isUnread = !item.read;
    final textTheme = Theme.of(context).textTheme;
    final time = _time(item.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => _open(item),
        // Read out the state in words, not only by the dot and weight.
        semanticLabel: '${isUnread ? 'Unread. ' : ''}${item.title}. $time',
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unread dot in its own slot (as in Mail), so read and
              // unread rows keep their icons lined up.
              SizedBox(
                width: 14,
                height: 40,
                child: isUnread
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppPalette.teal,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: v.tint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(v.icon, color: v.tint, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              time,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.body,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    if (_notifications.isEmpty) {
      return const InfoContentUnavailable(
        icon: CupertinoIcons.bell_slash,
        title: 'No notifications yet',
        body: 'Messages, reminders and new exercises will show up here.',
      );
    }
    // There are notifications, just none under this filter.
    return InfoContentUnavailable(
      icon: CupertinoIcons.tray,
      title: 'No notifications here',
      body: _selectedFilterIndex == 2
          ? 'You have read everything.'
          : 'Nothing has been read yet.',
    );
  }
}
