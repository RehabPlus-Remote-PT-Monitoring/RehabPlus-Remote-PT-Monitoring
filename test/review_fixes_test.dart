import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/ios/app_controls.dart';
import 'package:rehabplus/ios/brand_colors.dart';
import 'package:rehabplus/ios/ios_chrome.dart';
import 'package:rehabplus/widgets/profile_avatar.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => debugUseIosChromeOverride = null);

  group('light-mode accents are readable as text (WCAG AA 4.5:1)', () {
    // The pale tints the report/goals chips draw them on, and white cards.
    const backgrounds = [Colors.white, Color(0xFFE8F5E9), Color(0xFFFFF3E0)];

    testWidgets('coral, mint and amber', (tester) async {
      debugUseIosChromeOverride = true;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final accents = {
        'coral': AppAccents.coral(ctx, fallback: Colors.black),
        'mint': AppAccents.mint(ctx, fallback: Colors.black),
        'amber': AppAccents.amber(ctx, fallback: Colors.black),
      };
      for (final MapEntry(:key, :value) in accents.entries) {
        for (final bg in backgrounds) {
          expect(
            _contrast(value, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$key on $bg',
          );
        }
      }
    });
  });

  group('confirmWithFallback', () {
    test('native answer is used when there is one', () async {
      var materialCalls = 0;
      expect(
        await confirmWithFallback(
          native: () async => true,
          material: () async {
            materialCalls++;
            return false;
          },
        ),
        isTrue,
      );
      expect(materialCalls, 0);
    });

    test('no native answer (alert failed) shows the Material dialog', () async {
      expect(
        await confirmWithFallback(
          native: () async => null,
          material: () async => true,
        ),
        isTrue,
      );
    });

    test('native throwing also falls back', () async {
      expect(
        await confirmWithFallback(
          native: () async => throw StateError('no view'),
          material: () async => true,
        ),
        isTrue,
      );
    });
  });

  testWidgets('glass button label follows the in-app text size', (
    tester,
  ) async {
    debugUseIosChromeOverride = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: AppButton(
            label: 'Update account information',
            onPressed: () {},
            material: () => const SizedBox(),
          ),
        ),
      ),
    );
    final cn = tester.widget<CNButton>(find.byType(CNButton));
    expect(cn.config.labelFontSize, 17 * 1.5);
  });

  testWidgets('avatar glide also plays during the edge-swipe back', (
    tester,
  ) async {
    debugUseIosChromeOverride = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileAvatar(photo: null, size: 64, heroTag: 'profile-avatar'),
      ),
    );
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.transitionOnUserGestures, isTrue);
  });
}
