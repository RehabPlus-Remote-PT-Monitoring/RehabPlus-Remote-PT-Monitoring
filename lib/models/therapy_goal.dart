// lib/models/therapy_goal.dart
//
// A rehab goal the therapist set on the clinic dashboard, stored at
// patients/{uid}/goals/{id} (schema in API_CONTRACT.md). The app only reads
// goals; the dashboard creates them and updates progress/status.

import 'firestore_fields.dart';

/// Where a goal stands. Unknown values from a newer dashboard fall back to
/// [active] so the goal is still shown.
enum GoalStatus {
  active,
  achieved,
  discontinued;

  static GoalStatus fromCode(String? code) => switch (code) {
        'achieved' => GoalStatus.achieved,
        'discontinued' => GoalStatus.discontinued,
        _ => GoalStatus.active,
      };

  /// Text shown on the goal's status chip.
  String get label => switch (this) {
        GoalStatus.active => 'In progress',
        GoalStatus.achieved => 'Achieved',
        GoalStatus.discontinued => 'Stopped',
      };
}

class TherapyGoal {
  /// Display limits; the dashboard allows a 150-character title. Anything
  /// longer is clipped only to stop a corrupt document flooding the screen.
  static const int maxTitleLength = 150;
  static const int maxDetailsLength = 2000;

  final String id;
  final String title;
  final String details;
  final GoalStatus status;

  /// 0–100. Always 100 for an achieved goal, whatever the document says.
  final int progress;
  final DateTime? targetDate;
  final DateTime? achievedAt;
  final DateTime? createdAt;
  final String therapistName;

  const TherapyGoal({
    required this.id,
    required this.title,
    required this.details,
    required this.status,
    required this.progress,
    this.targetDate,
    this.achievedAt,
    this.createdAt,
    this.therapistName = '',
  });

  /// Parses a goal document. A goal without a title is meaningless to the
  /// patient, so it fails (and is skipped by the caller); every other field
  /// has a safe fallback, listed in [Parsed.repaired] when it was used.
  static Parsed<TherapyGoal> parse(String id, Map<String, dynamic> d) =>
      Parsed.guard((r) {
        final title = r.string('title', maxLength: maxTitleLength) ?? '';
        if (title.trim().isEmpty) {
          throw const FormatException('goal has no title');
        }
        final status = GoalStatus.fromCode(r.string('status'));
        final progress = status == GoalStatus.achieved
            ? 100
            : (r.integer('progress', min: 0, max: 100) ?? 0);
        return TherapyGoal(
          id: id,
          title: title.trim(),
          details: r.string('details', maxLength: maxDetailsLength) ?? '',
          status: status,
          progress: progress,
          targetDate: r.dateTime('targetDate'),
          achievedAt: r.dateTime('achievedAt'),
          createdAt: r.dateTime('createdAt'),
          therapistName: r.string('therapistName', maxLength: 100) ?? '',
        );
      }, d);

  /// The goal's target date has passed and it is still being worked on.
  bool isOverdue(DateTime now) {
    final target = targetDate;
    if (status != GoalStatus.active || target == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return target.isBefore(today);
  }

  /// Order for the Goals screen: active goals first (nearest target date
  /// first, goals without a date after them), then achieved (most recent
  /// first), then discontinued ones.
  static int displayOrder(TherapyGoal a, TherapyGoal b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    if (byStatus != 0) return byStatus;

    if (a.status == GoalStatus.active) {
      final at = a.targetDate, bt = b.targetDate;
      if (at != null && bt != null) return at.compareTo(bt);
      if (at != null) return -1;
      if (bt != null) return 1;
    }
    if (a.status == GoalStatus.achieved) {
      final aa = a.achievedAt, ba = b.achievedAt;
      if (aa != null && ba != null) return ba.compareTo(aa);
    }
    final ac = a.createdAt, bc = b.createdAt;
    if (ac != null && bc != null) return bc.compareTo(ac);
    return a.title.compareTo(b.title);
  }
}
