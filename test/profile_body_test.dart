// Gender, weight and height on the patient profile: display text, defensive
// reading of the stored numbers, and the edit form's checks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/firestore_fields.dart';
import 'package:rehabplus/screens/edit_profile_screen.dart';
import 'package:rehabplus/services/profile_service.dart';

ProfileData _profile({String gender = '', double? weightKg, double? heightCm}) =>
    ProfileData(
      name: 'Alex Test',
      email: 'alex@example.com',
      phone: '555-0100',
      dob: '',
      condition: 'Knee',
      gender: gender,
      weightKg: weightKg,
      heightCm: heightCm,
    );

void main() {
  group('ProfileData body text', () {
    test('unset values show as empty', () {
      final p = _profile();
      expect(p.gender, '');
      expect(p.weightText, '');
      expect(p.heightText, '');
    });

    test('whole numbers drop the decimal, fractions keep it', () {
      expect(_profile(weightKg: 65).weightText, '65 kg');
      expect(_profile(weightKg: 65.5).weightText, '65.5 kg');
      expect(_profile(heightCm: 170).heightText, '170 cm');
      expect(_profile(heightCm: 172.25).heightText, '172.25 cm');
    });

    test('numberText has no trailing zeros', () {
      expect(ProfileData.numberText(null), '');
      expect(ProfileData.numberText(80), '80');
      expect(ProfileData.numberText(80.0), '80');
    });
  });

  group('FieldReader.number', () {
    test('absent or null gives null and is not reported as repaired', () {
      final r = FieldReader({'weightKg': null});
      expect(r.number('weightKg', min: 1, max: 500), isNull);
      expect(r.number('heightCm'), isNull);
      expect(r.repaired, isEmpty);
    });

    test('an integer or a double is read as a double', () {
      final r = FieldReader({'weightKg': 70, 'heightCm': 168.5});
      expect(r.number('weightKg'), 70.0);
      expect(r.number('heightCm'), 168.5);
      expect(r.repaired, isEmpty);
    });

    test('a value out of range is clamped and reported', () {
      final r = FieldReader({'weightKg': 900, 'heightCm': 5});
      expect(r.number('weightKg', min: 1, max: 500), 500);
      expect(r.number('heightCm', min: 30, max: 300), 30);
      expect(r.repaired, ['weightKg', 'heightCm']);
    });

    test('a value that is not a number is dropped and reported', () {
      final r = FieldReader({'weightKg': '70 kg'});
      expect(r.number('weightKg'), isNull);
      expect(r.repaired, ['weightKg']);
    });

    test('NaN is dropped and reported', () {
      final r = FieldReader({'heightCm': double.nan});
      expect(r.number('heightCm'), isNull);
      expect(r.repaired, ['heightCm']);
    });
  });

  group('ProfileService limits', () {
    test('the gender choices are the four the rules accept', () {
      expect(ProfileService.genderOptions, [
        'Female',
        'Male',
        'Other',
        'Prefer not to say',
      ]);
    });

    test('measurement limits match firestore.rules', () {
      expect(ProfileService.minWeightKg, 1);
      expect(ProfileService.maxWeightKg, 500);
      expect(ProfileService.minHeightCm, 30);
      expect(ProfileService.maxHeightCm, 300);
    });
  });

  group('EditProfileScreen body fields', () {
    Future<void> pump(WidgetTester tester, ProfileData initial) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(initial: initial)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the form shows the stored weight and height', (tester) async {
      await pump(tester, _profile(weightKg: 65.5, heightCm: 170));

      expect(find.widgetWithText(TextFormField, '65.5'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '170'), findsOneWidget);
    });

    testWidgets('a weight outside the rule is rejected with its unit', (
      tester,
    ) async {
      await pump(tester, _profile());

      await tester.enterText(find.byType(TextFormField).at(5), '900');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(find.text('Enter a weight from 1 to 500 kg'), findsOneWidget);
    });

    testWidgets('a height that is not a number is rejected', (tester) async {
      await pump(tester, _profile());

      await tester.enterText(find.byType(TextFormField).at(6), 'tall');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(find.text('Enter a height from 30 to 300 cm'), findsOneWidget);
    });

    testWidgets('a decimal comma is accepted for weight', (tester) async {
      await pump(tester, _profile());

      await tester.enterText(find.byType(TextFormField).at(5), '65,5');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(find.textContaining('Enter a weight'), findsNothing);
    });

    testWidgets('tapping Gender opens the choices', (tester) async {
      await pump(tester, _profile());

      final gender = find.widgetWithText(TextFormField, 'Gender');
      await tester.ensureVisible(gender);
      await tester.tap(gender);
      await tester.pumpAndSettle();

      for (final option in ProfileService.genderOptions) {
        expect(find.text(option), findsOneWidget);
      }
    });

    testWidgets('choosing a gender closes the list', (tester) async {
      await pump(tester, _profile());

      final gender = find.widgetWithText(TextFormField, 'Gender');
      await tester.ensureVisible(gender);
      await tester.tap(gender);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male'));
      await tester.pumpAndSettle();

      expect(find.text('Prefer not to say'), findsNothing);
    });
  });
}
