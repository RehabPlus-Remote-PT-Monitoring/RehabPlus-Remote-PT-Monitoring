// lib/widgets/report_key_numbers.dart
//
// The "key numbers" tiles of the progress report, styled like the summary
// tiles in Apple Health / Fitness: a small teal icon, a big number and a
// grey caption under it, on a plain card (no shadow, no gradient).
//
//   ReportKeyNumbers(tiles: [
//     ReportNumber(label: 'Sessions', value: '12', icon: CupertinoIcons.flame),
//     ...
//   ])
//
// The number of columns is chosen from the width the grid really gets
// (LayoutBuilder), not from the device type: the same phone-width column
// can appear on a tablet (left half of the two-column report) and a wide
// single column can appear on a phone in landscape.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';

/// One tile: what is measured, its value as shown, and an icon.
@immutable
class ReportNumber {
  const ReportNumber({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class ReportKeyNumbers extends StatelessWidget {
  const ReportKeyNumbers({super.key, required this.tiles});

  final List<ReportNumber> tiles;

  /// Gap between tiles, both ways.
  static const double gap = 10;

  /// Narrowest a tile may get before its big number has to shrink.
  static const double minTileWidth = 140;

  /// Columns for a grid [width] wide holding [tileCount] tiles.
  ///
  /// Three columns always fit a phone. Four are used only when every tile
  /// would still be at least [minTileWidth] wide AND the tiles fill whole
  /// rows: a half-empty last row looks like something failed to load.
  static int columnsFor(double width, int tileCount) {
    const wideColumns = 4;
    final wideTileWidth = (width - gap * (wideColumns - 1)) / wideColumns;
    final fitsWide = wideTileWidth >= minTileWidth;
    final fillsRows = tileCount % wideColumns == 0;
    if (fitsWide && fillsRows) return wideColumns;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth, tiles.length);

        // Rows of equal-height tiles. A Row per line (instead of a
        // GridView with a fixed aspect ratio) lets a tile grow when the
        // user's text size is large, rather than clipping the caption.
        final rows = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          final rowTiles = tiles.skip(start).take(columns).toList();
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(
                      // An empty slot keeps the last row's tiles the same
                      // width as the rows above.
                      child: i < rowTiles.length
                          ? _NumberTile(tile: rowTiles[i])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.tile});

  final ReportNumber tile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      // Read as "Sessions, 12" rather than "12" then "Sessions".
      label: '${tile.label}, ${tile.value}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(tile.icon, size: 18, color: AppPalette.teal),
            const SizedBox(height: 8),
            // Long values ("1h 20m") shrink to fit rather than wrap.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                tile.value,
                maxLines: 1,
                style: text.displaySmall?.copyWith(color: palette.textPrimary),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tile.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
