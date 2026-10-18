// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/main.dart';
import 'package:rehabplus/screens/splash_screen.dart';
import 'package:rehabplus/services/app_provider.dart';

void main() {
  testWidgets('Signed-out app shows the login page', (WidgetTester tester) async {
    final provider = AppProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const RehabPlusApp(),
      ),
    );
    await tester.pumpAndSettle(); // let the intro animations finish
    expect(find.text('Sign in to continue your recovery'), findsOneWidget);
  });

  testWidgets('Splash still leaves when the first screen fails to load', (
    WidgetTester tester,
  ) async {
    // Fail only after the splash is listening (a Future.error created up
    // front would complete before the widget subscribes, which the test
    // framework reports as an unhandled error).
    final next = Completer<Widget>();
    await tester.pumpWidget(MaterialApp(home: SplashScreen(next: next.future)));
    next.completeError(StateError('simulated startup failure'));
    await tester.pumpAndSettle(); // whole splash timeline + crossfade
    // Falls back to the login page instead of staying on the logo.
    expect(find.text('Sign in to continue your recovery'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });
}
