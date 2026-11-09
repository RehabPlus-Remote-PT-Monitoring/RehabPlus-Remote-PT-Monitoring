import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_palette.dart';
import 'package:rehabplus/widgets/profile_info_row.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, String value) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProfileInfoRow(
              icon: Icons.medical_services_outlined,
              label: 'Condition',
              value: value,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a long condition wraps onto more lines instead of clipping', (
    tester,
  ) async {
    await pumpRow(tester, 'MCL sprain (grade II), right knee, post-acute');
    expect(tester.takeException(), isNull);
    final value = find.text('MCL sprain (grade II), right knee, post-acute');
    final label = find.text('Condition');
    // Wrapped: the value is taller than the one-line label.
    expect(
      tester.getSize(value).height,
      greaterThan(tester.getSize(label).height * 1.5),
    );
  });

  testWidgets('a short value stays on one line', (tester) async {
    await pumpRow(tester, 'MCL');
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('MCL')).height,
      lessThan(tester.getSize(find.text('Condition')).height * 1.5),
    );
  });

  testWidgets('an empty value shows a dash', (tester) async {
    await pumpRow(tester, '');
    expect(find.text('—'), findsOneWidget);
  });
}
