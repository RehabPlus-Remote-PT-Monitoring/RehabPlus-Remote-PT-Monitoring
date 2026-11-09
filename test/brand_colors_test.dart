import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_palette.dart';
import 'package:rehabplus/ios/brand_colors.dart';
import 'package:rehabplus/ios/ios_chrome.dart';
import 'package:rehabplus/widgets/profile_avatar.dart';

/// Pumps a MaterialApp with [brightness] and returns a context inside it.
Future<BuildContext> _contextFor(
  WidgetTester tester,
  Brightness brightness,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  tearDown(() => debugUseIosChromeOverride = null);

  const a = Color(0xFF0D6E71);
  const b = Color(0xFF1A8587);
  const c = Color(0xFF23A8AA);
  const oldOrange = Color(0xFFFF6B35);

  group('Android (iPhone look off): nothing changes', () {
    setUp(() => debugUseIosChromeOverride = false);

    test('brandGradient is the same gradient the call site had', () {
      expect(
        brandGradient(
          [a, b, c],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        const LinearGradient(
          colors: [a, b, c],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    });

    testWidgets('accents return the colour the call site used before', (
      tester,
    ) async {
      final context = await _contextFor(tester, Brightness.light);
      expect(AppAccents.coral(context, fallback: oldOrange), oldOrange);
      expect(AppAccents.mint(context, fallback: a), a);
      expect(AppAccents.amber(context, fallback: b), b);
    });
  });

  group('iPhone look on', () {
    setUp(() => debugUseIosChromeOverride = true);

    test('brandGradient is solid mid teal (no visible gradient)', () {
      final gradient = brandGradient([a, b, c]) as LinearGradient;
      expect(gradient.colors.toSet(), {AppPalette.midTeal});
    });

    testWidgets('accents use the light values in light mode', (tester) async {
      final context = await _contextFor(tester, Brightness.light);
      expect(
        AppAccents.coral(context, fallback: oldOrange),
        const Color(0xFFB8401A),
      );
      expect(AppAccents.mint(context, fallback: a), const Color(0xFF137A55));
      expect(AppAccents.amber(context, fallback: a), const Color(0xFFA15C00));
    });

    testWidgets('accents use the dark values in dark mode', (tester) async {
      final context = await _contextFor(tester, Brightness.dark);
      expect(
        AppAccents.coral(context, fallback: oldOrange),
        const Color(0xFFFF9479),
      );
      expect(AppAccents.mint(context, fallback: a), const Color(0xFF5FD3A8));
      expect(AppAccents.amber(context, fallback: a), const Color(0xFFFFC14D));
    });
  });

  group('ProfileAvatar hero (iPhone only)', () {
    Future<void> pumpAvatar(WidgetTester tester, {String? heroTag}) =>
        tester.pumpWidget(
          MaterialApp(
            home: ProfileAvatar(photo: null, size: 64, heroTag: heroTag),
          ),
        );

    testWidgets('iPhone: a tagged avatar flies between pages', (tester) async {
      debugUseIosChromeOverride = true;
      await pumpAvatar(tester, heroTag: 'profile-avatar');
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == 'profile-avatar'),
        findsOneWidget,
      );
    });

    testWidgets('iPhone: no tag, no hero', (tester) async {
      debugUseIosChromeOverride = true;
      await pumpAvatar(tester);
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('Android: unchanged, no hero even with a tag', (tester) async {
      debugUseIosChromeOverride = false;
      await pumpAvatar(tester, heroTag: 'profile-avatar');
      expect(find.byType(Hero), findsNothing);
    });
  });
}
