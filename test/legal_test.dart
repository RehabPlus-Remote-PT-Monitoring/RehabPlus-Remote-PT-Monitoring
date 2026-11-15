import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/legal/legal_info.dart';
import 'package:rehabplus/screens/consent_screen.dart';
import 'package:rehabplus/screens/legal_document_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('legal documents', () {
    for (final asset in [LegalInfo.termsAsset, LegalInfo.privacyAsset]) {
      test('$asset is bundled and every {{TOKEN}} is filled', () async {
        final filled = LegalInfo.fill(await rootBundle.loadString(asset));
        expect(filled, isNot(contains('{{')));
        expect(filled, contains(LegalInfo.clinicName));
        expect(filled, contains(LegalInfo.version));
      });
    }

    test('the privacy policy describes the movement replay', () async {
      final policy = LegalInfo.fill(
        await rootBundle.loadString(LegalInfo.privacyAsset),
      );
      // Still true with replays: no images or video are ever saved.
      expect(policy, contains('Video and images are never recorded'));
      expect(policy, contains('Movement replay'));
      expect(policy, contains('33 points'));
      expect(policy, contains('Save movement replays for my therapist'));
      final terms = await rootBundle.loadString(LegalInfo.termsAsset);
      expect(terms, contains('movement replay'));
    });

    test('version is the movement-replay revision (forces re-consent)', () {
      // Bumped when the replay was added to the documents; the dashboard's
      // LEGAL_CONSENT_VERSION must match.
      expect(LegalInfo.version, '2026-11-15');
    });

    test('fill is a single pass and leaves unknown tokens visible', () {
      // A token's value is inserted as plain text: braces around it are not
      // expanded again, and an unknown token stays so typos are noticed.
      expect(
        LegalInfo.fill('{{CLINIC_NAME}} {{NOT_A_TOKEN}} {{lowercase}}'),
        '${LegalInfo.clinicName} {{NOT_A_TOKEN}} {{lowercase}}',
      );
      expect(
        LegalInfo.fill('{{{{VERSION}}}}'),
        '{{${LegalInfo.version}}}',
      );
    });
  });

  testWidgets('LegalText renders headings, bullets and bold text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LegalText(
            '# Title\n\n## 1. Section\n\nFirst line\njoined line.\n\n'
            '- **Bold** item\n',
          ),
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('1. Section'), findsOneWidget);
    expect(find.text('First line joined line.'), findsOneWidget);
    expect(find.text('Bold item', findRichText: true), findsOneWidget);
  });

  testWidgets('Accept stays disabled until every box is ticked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400); // a typical phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ConsentScreen()));

    FilledButton accept() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Accept and continue'),
    );

    final labels = [
      'I have read and agree to the Terms',
      'I have read the Privacy Policy',
      'uses my camera',
    ];
    for (final label in labels) {
      expect(accept().onPressed, isNull, reason: 'before "$label"');
      final box = find.ancestor(
        of: find.textContaining(label),
        matching: find.byType(CheckboxListTile),
      );
      await tester.scrollUntilVisible(find.textContaining(label), 100);
      await tester.ensureVisible(box); // whole tile, clear of the buttons
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pump();
    }
    expect(accept().onPressed, isNotNull);
  });
}
