// lib/models/clearance_record.dart
//
// A physician clearance record, stored at patients/{uid}/clearances/{id}.
// Append-only and written only by the clinic dashboard after a physician's
// final assessment; the newest `signedAt` wins (API_CONTRACT.md, "Clinical
// safeguards").
//
// This is the ONLY source of "cleared" in the app. Finishing the exercise
// program never clears a patient by itself (see lib/services/care_gate.dart).

import 'firestore_fields.dart';

/// The physician's decision.
enum ClearanceDecision {
  /// Cleared after the final assessment.
  cleared('cleared'),

  /// Not cleared: continue or revise the program.
  notCleared('not_cleared');

  const ClearanceDecision(this.code);

  /// The code stored in Firestore.
  final String code;

  static ClearanceDecision? fromCode(Object? code) {
    for (final decision in values) {
      if (decision.code == code) return decision;
    }
    return null;
  }
}

class ClearanceRecord {
  static const int maxNameLength = 100;
  static const int maxLicenseLength = 40;
  static const int maxFindingsLength = 2000;
  static const int maxRecommendationsLength = 1000;

  const ClearanceRecord({
    required this.id,
    required this.decision,
    required this.signedAt,
    this.physicianName = '',
    this.physicianLicense = '',
    this.assessedAt,
    this.findings = '',
    this.recommendations = '',
    this.signedByName,
  });

  final String id;
  final ClearanceDecision decision;

  /// Server time the record was saved; orders the records (newest wins).
  final DateTime signedAt;

  /// Assessing physician.
  final String physicianName;

  /// PRC license number.
  final String physicianLicense;

  /// Date of the final assessment.
  final DateTime? assessedAt;
  final String findings;
  final String recommendations;

  /// Dashboard account that recorded it.
  final String? signedByName;

  bool get isCleared => decision == ClearanceDecision.cleared;

  /// Parses one record. Never throws.
  ///
  /// Required (the record is skipped otherwise): a known `decision`, since
  /// guessing one could show "cleared" by mistake, and `signedAt`, without
  /// which "newest wins" can't be decided. Everything else defaults.
  static Parsed<ClearanceRecord> parse(String id, Map<String, dynamic> data) =>
      Parsed.guard((reader) => _fromReader(id, reader), data);

  static ClearanceRecord _fromReader(String id, FieldReader r) {
    final decision = ClearanceDecision.fromCode(r.data['decision']);
    if (decision == null) {
      throw const FormatException(
        'Missing or invalid required field "decision"',
      );
    }
    return ClearanceRecord(
      id: id,
      decision: decision,
      signedAt: r.requireDateTime('signedAt'),
      physicianName:
          r.string('physicianName', maxLength: maxNameLength)?.trim() ?? '',
      physicianLicense:
          r.string('physicianLicense', maxLength: maxLicenseLength)?.trim() ??
          '',
      assessedAt: r.dateTime('assessedAt'),
      findings:
          r.string('findings', maxLength: maxFindingsLength)?.trim() ?? '',
      recommendations:
          r
              .string('recommendations', maxLength: maxRecommendationsLength)
              ?.trim() ??
          '',
      signedByName: r.string('signedByName', maxLength: maxNameLength),
    );
  }

  /// The newest record by [signedAt], or null when there are none. Doesn't
  /// rely on the query order, so a cached or unordered list is still right.
  static ClearanceRecord? newest(Iterable<ClearanceRecord> records) {
    ClearanceRecord? newest;
    for (final record in records) {
      if (newest == null || record.signedAt.isAfter(newest.signedAt)) {
        newest = record;
      }
    }
    return newest;
  }
}
