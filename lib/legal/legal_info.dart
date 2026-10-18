// Clinic details and versions used by the Terms and Conditions and the
// Privacy Policy (assets/legal/*.md). The documents contain {{TOKENS}} that
// [LegalInfo.fill] replaces with the values below.
//
// To publish a material change to either document: edit the .md file, then
// bump [LegalInfo.version] and [LegalInfo.effectiveDate]. Every patient is then
// asked to accept the new version the next time they open the app.

class LegalInfo {
  LegalInfo._();

  /// Version of the Terms + Privacy Policy pair. Also the id of the consent
  /// record (patients/{uid}/consents/{version}).
  static const String version = '2026-10-18';
  static const String effectiveDate = 'October 18, 2026';

  static const String clinicName = 'Rehab Plus Physiotherapy';

  // TODO(clinic): fill in before the app is given to patients.
  static const String clinicAddress = '[clinic address]';
  static const String dpoName = '[Data Protection Officer name]';
  static const String dpoEmail = '[DPO email address]';
  static const String venue = '[city where the clinic is located]';
  static const String retentionPeriod =
      '[number] years after your last session';

  static const String termsAsset = 'assets/legal/terms_and_conditions.md';
  static const String privacyAsset = 'assets/legal/privacy_policy.md';

  static const Map<String, String> _tokens = {
    'VERSION': version,
    'EFFECTIVE_DATE': effectiveDate,
    'CLINIC_NAME': clinicName,
    'CLINIC_ADDRESS': clinicAddress,
    'DPO_NAME': dpoName,
    'DPO_EMAIL': dpoEmail,
    'VENUE': venue,
    'RETENTION_PERIOD': retentionPeriod,
  };

  /// Replaces every {{TOKEN}} in a legal document with its value.
  static String fill(String text) => text.replaceAllMapped(
    RegExp(r'\{\{([A-Z_]+)\}\}'),
    (m) => _tokens[m[1]] ?? m[0]!,
  );
}
