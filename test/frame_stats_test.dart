import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/frame_stats.dart';

void main() {
  group('FrameStatsWindow', () {
    test('empty window has nothing to report', () {
      final w = FrameStatsWindow(budgetMs: 16.7);
      expect(w.takeSummary(), isNull);
    });

    test('counts janky frames and reports percentiles', () {
      final w = FrameStatsWindow(budgetMs: 16.7);
      // 8 smooth frames, 2 janky ones (one slow build, one slow raster).
      for (var i = 0; i < 8; i++) {
        w.add(buildMs: 4, rasterMs: 6);
      }
      w.add(buildMs: 30, rasterMs: 5);
      w.add(buildMs: 3, rasterMs: 40);

      final s = w.takeSummary()!;
      expect(s['frames'], 10);
      expect(s['janky'], 2);
      expect(s['jankPct'], 20.0);
      expect(s['worstBuildMs'], 30.0);
      expect(s['worstRasterMs'], 40.0);
      expect(s['p90BuildMs'], 4.0);
      expect(s['p90RasterMs'], 6.0);
    });

    test('taking the summary starts a new window', () {
      final w = FrameStatsWindow(budgetMs: 16.7)..add(buildMs: 1, rasterMs: 1);
      expect(w.takeSummary(), isNotNull);
      expect(w.takeSummary(), isNull);
    });

    test('a frame is janky when build OR raster exceeds the budget', () {
      final w = FrameStatsWindow(budgetMs: 16.7)
        ..add(buildMs: 16, rasterMs: 16)
        ..add(buildMs: 17, rasterMs: 1);
      expect(w.takeSummary()!['janky'], 1);
    });
  });
}
