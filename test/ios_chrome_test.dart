import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/ios/ios_chrome.dart';

void main() {
  tearDown(() => debugUseIosChromeOverride = null);

  group('useIosChrome', () {
    test('follows the platform (false on the Linux test host)', () {
      expect(useIosChrome, isFalse);
    });

    test('can be forced on and back off in tests', () {
      debugUseIosChromeOverride = true;
      expect(useIosChrome, isTrue);
      debugUseIosChromeOverride = null;
      expect(useIosChrome, isFalse);
    });
  });

  group('appPageTransitions', () {
    test('iOS: swipe-back Cupertino slide on every platform key', () {
      final theme = appPageTransitions(ios: true);
      for (final platform in TargetPlatform.values) {
        expect(
          theme.builders[platform],
          isA<CupertinoPageTransitionsBuilder>(),
          reason: platform.name,
        );
      }
    });

    test('Android build: unchanged fade on every platform key', () {
      final theme = appPageTransitions(ios: false);
      for (final platform in TargetPlatform.values) {
        expect(
          theme.builders[platform],
          isA<FadeForwardsPageTransitionsBuilder>(),
          reason: platform.name,
        );
      }
    });
  });

  group('appNavigatorObservers', () {
    test('iOS registers exactly one glass route observer', () {
      final observers = appNavigatorObservers(ios: true);
      expect(observers, hasLength(1));
      expect(observers.single, isA<CNTabBarRouteObserver>());
    });

    test('Android registers none', () {
      expect(appNavigatorObservers(ios: false), isEmpty);
    });
  });
}
