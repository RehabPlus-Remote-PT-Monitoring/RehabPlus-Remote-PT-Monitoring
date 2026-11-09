import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/ios/app_controls.dart';
import 'package:rehabplus/ios/ios_chrome.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
}

void main() {
  tearDown(() => debugUseIosChromeOverride = null);

  for (final brightness in Brightness.values) {
    group('Android path, ${brightness.name}', () {
      setUp(() => debugUseIosChromeOverride = false);

      testWidgets('AppSwitch is the Material Switch', (tester) async {
        await _pump(
          tester,
          AppSwitch(value: true, onChanged: (_) {}),
          brightness: brightness,
        );
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byType(CNSwitch), findsNothing);
      });

      testWidgets('AppSwitchTile builds exactly the material tile', (
        tester,
      ) async {
        await _pump(
          tester,
          AppSwitchTile(
            value: true,
            onChanged: (_) {},
            title: const Text('Sound'),
            material: () => SwitchListTile(
              value: true,
              onChanged: (_) {},
              title: const Text('Sound'),
            ),
          ),
          brightness: brightness,
        );
        expect(find.byType(SwitchListTile), findsOneWidget);
        expect(find.byType(CNSwitch), findsNothing);
      });

      testWidgets('AppSegmented builds exactly the material control', (
        tester,
      ) async {
        await _pump(
          tester,
          AppSegmented<int>(
            segments: const [(7, '7 days'), (30, '30 days')],
            selected: 7,
            onChanged: (_) {},
            material: () => SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
              ],
              selected: const {7},
              onSelectionChanged: (_) {},
            ),
          ),
          brightness: brightness,
        );
        expect(find.byType(SegmentedButton<int>), findsOneWidget);
        expect(find.byType(CNSegmentedControl), findsNothing);
      });

      testWidgets('AppButton builds exactly the material button', (
        tester,
      ) async {
        await _pump(
          tester,
          AppButton(
            label: 'Save',
            onPressed: () {},
            material: () =>
                FilledButton(onPressed: () {}, child: const Text('Save')),
          ),
          brightness: brightness,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(CNButton), findsNothing);
      });
    });

    group('iPhone path, ${brightness.name}', () {
      setUp(() => debugUseIosChromeOverride = true);

      testWidgets('AppSwitch is the native switch', (tester) async {
        await _pump(
          tester,
          AppSwitch(value: true, onChanged: (_) {}),
          brightness: brightness,
        );
        expect(find.byType(CNSwitch), findsOneWidget);
        // (On the Linux test host CNSwitch draws its own fallback switch
        // inside itself, so a Switch below CNSwitch is expected here.)
        expect(
          find.ancestor(
            of: find.byType(Switch),
            matching: find.byType(CNSwitch),
          ),
          findsOneWidget,
        );
      });

      testWidgets('disabled AppSwitch (onChanged null) builds', (tester) async {
        await _pump(
          tester,
          const AppSwitch(value: false, onChanged: null),
          brightness: brightness,
        );
        final cn = tester.widget<CNSwitch>(find.byType(CNSwitch));
        expect(cn.enabled, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('AppSwitchTile row tap toggles the value', (tester) async {
        bool? got;
        await _pump(
          tester,
          AppSwitchTile(
            value: false,
            onChanged: (v) => got = v,
            leading: const Icon(Icons.volume_up),
            title: const Text('Sound'),
            subtitle: const Text('Play a sound for each rep'),
            material: () => const SizedBox(),
          ),
          brightness: brightness,
        );
        expect(find.byType(CNSwitch), findsOneWidget);
        await tester.tap(find.text('Sound'));
        expect(got, isTrue);
      });

      testWidgets('AppSwitchTile wraps long text at 1.6x without overflow', (
        tester,
      ) async {
        await _pump(
          tester,
          AppSwitchTile(
            value: true,
            onChanged: (_) {},
            leading: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint or face recognition'),
            subtitle: const Text(
              'A quicker way in; the PIN still works when this is on',
            ),
            material: () => const SizedBox(),
          ),
          brightness: brightness,
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('AppSegmented maps the native index back to the value', (
        tester,
      ) async {
        int? got;
        await _pump(
          tester,
          AppSegmented<int>(
            segments: const [(7, '7 days'), (30, '30 days')],
            selected: 7,
            onChanged: (v) => got = v,
            material: () => const SizedBox(),
          ),
          brightness: brightness,
        );
        final cn = tester.widget<CNSegmentedControl>(
          find.byType(CNSegmentedControl),
        );
        expect(cn.labels, ['7 days', '30 days']);
        expect(cn.selectedIndex, 0);
        cn.onValueChanged(1);
        expect(got, 30);
      });

      testWidgets('AppButton is a glass button; disabled when no callback', (
        tester,
      ) async {
        await _pump(
          tester,
          AppButton(
            label: 'Save',
            onPressed: null,
            material: () => const SizedBox(),
          ),
          brightness: brightness,
        );
        final cn = tester.widget<CNButton>(find.byType(CNButton));
        expect(cn.label, 'Save');
        expect(cn.enabled, isFalse);
        expect(cn.config.style, CNButtonStyle.prominentGlass);
      });
    });
  }

  group('showAppConfirm', () {
    testWidgets('Android path returns what the material dialog returns', (
      tester,
    ) async {
      debugUseIosChromeOverride = false;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        await showAppConfirm(
          ctx,
          title: 'Sign out?',
          confirmLabel: 'Sign out',
          material: () async => true,
        ),
        isTrue,
      );
      expect(
        await showAppConfirm(
          ctx,
          title: 'Sign out?',
          confirmLabel: 'Sign out',
          material: () async => null,
        ),
        isFalse,
      );
    });
  });
}
