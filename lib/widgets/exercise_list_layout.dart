// lib/widgets/exercise_list_layout.dart
//
// Layout pieces for the Exercise tab's card list: the iOS-style section
// header ("YOUR PLAN ... 3 exercises") and the one-or-two-column card rows.
// Kept apart from ExercisePage so the phone/tablet switch can be tested
// without Firebase.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';

/// Gap between cards, vertically and between the two columns.
const double kExerciseCardGap = 12;

/// Small grey uppercase title with a count on the right, like the section
/// headers above iOS grouped lists.
class ExerciseSectionHeader extends StatelessWidget {
  const ExerciseSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: context.palette.textMuted,
    );
    final countLabel = count == 1 ? '1 exercise' : '$count exercises';
    return Padding(
      // Indented like iOS section headers, which line up with the text
      // inside the cards rather than with the card edge.
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Semantics(
        header: true,
        label: '$title, $countLabel',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(child: Text(title.toUpperCase(), style: style)),
            const SizedBox(width: 8),
            Text(countLabel, style: style),
          ],
        ),
      ),
    );
  }
}

/// Lays [cards] out for a SliverList: one per row on a phone, two per row
/// when [twoColumns] (a tablet, see isTwoColumn). Each returned widget is
/// one row, with the vertical gap included, so the list stays lazy.
///
/// Rows are top-aligned: two cards side by side may differ in height (one
/// title wraps, the other doesn't), like cards on an iPad dashboard.
List<Widget> exerciseCardRows(
  List<Widget> cards, {
  required bool twoColumns,
}) {
  final perRow = twoColumns ? 2 : 1;
  final rows = <Widget>[];
  for (var start = 0; start < cards.length; start += perRow) {
    final isLastRow = start + perRow >= cards.length;
    final Widget row;
    if (perRow == 1) {
      row = cards[start];
    } else {
      final right = start + 1 < cards.length ? cards[start + 1] : null;
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cards[start]),
          const SizedBox(width: kColumnGap),
          // An odd last card keeps half the width rather than stretching
          // across both columns, so every card has the same width.
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      );
    }
    rows.add(
      Padding(
        padding: EdgeInsets.only(bottom: isLastRow ? 0 : kExerciseCardGap),
        child: row,
      ),
    );
  }
  return rows;
}
