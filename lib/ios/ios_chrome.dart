// lib/ios/ios_chrome.dart
//
// The one switch for the iPhone-only look (branch iphone-testing).
//
// Everything in lib/ios/ asks [useIosChrome] before drawing anything
// different. It is simply "are we running on iOS", so the Android app keeps
// exactly the widgets, colours and page transitions it had before. Tests
// force it on with [debugUseIosChromeOverride] to check the iPhone path on
// the Linux test host.
//
// The native controls come from cupertino_native_better: real UIKit/SwiftUI
// views with Liquid Glass on iOS 26+, Cupertino look-alikes below that.

import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

/// Set in tests to force the iPhone look on (true) or off (false); null
/// means "follow the platform".
@visibleForTesting
bool? debugUseIosChromeOverride;

/// True when the iPhone look (Liquid Glass controls, iOS transitions,
/// solid brand colours) should be used.
bool get useIosChrome => debugUseIosChromeOverride ?? Platform.isIOS;

/// Page transitions for every `MaterialPageRoute` in the app.
///
/// iOS: the native slide with parallax, and the back swipe from the left
/// edge follows the finger. That is what makes moving between screens feel
/// connected rather than a cut. Android keeps the plain fade it had, which
/// was chosen because a slide on top of each page's own entrance animation
/// felt slow and busy there.
PageTransitionsTheme appPageTransitions({required bool ios}) {
  final PageTransitionsBuilder builder = ios
      ? const CupertinoPageTransitionsBuilder()
      : const FadeForwardsPageTransitionsBuilder();
  return PageTransitionsTheme(
    builders: {for (final platform in TargetPlatform.values) platform: builder},
  );
}

/// Navigator observers for the root navigator.
///
/// The glass controls are native views drawn under Flutter. Without this
/// observer their glow can show through dialogs and sheets pushed on top,
/// and the tab bar can sit above a sheet's text field.
List<NavigatorObserver> appNavigatorObservers({required bool ios}) =>
    ios ? [CNTabBarRouteObserver()] : const [];
