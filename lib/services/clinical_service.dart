// lib/services/clinical_service.dart
//
// Reads the clinical safeguards data for the signed-in patient:
//   - patients/{uid}/clinical/profile   (clinician-validated profile)
//   - patients/{uid}/clearances         (physician clearance records)
//   - patients/{uid}/prescriptions      (active ones, for the completion gate)
// All three are written only by the clinic dashboard; the app only reads.
//
// Never throws to the UI. A failed read is logged and returned as an
// "unavailable" result, which the screens show as "Not available yet" and
// NEVER as cleared. PERMISSION_DENIED is expected until the new Firestore
// rules for clinical/ and clearances/ are deployed.
//
// The Firestore glue here is deliberately thin (no Firestore fake exists in
// this repo); the parsing is in static functions that are unit-tested.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/clearance_record.dart';
import '../models/clinical_profile.dart';
import '../models/prescription.dart';

/// The clinical profile read: [available] false = couldn't read it;
/// available with a null [profile] = the clinician hasn't set one yet.
class ClinicalProfileResult {
  const ClinicalProfileResult.loaded(this.profile) : available = true;
  const ClinicalProfileResult.unavailable() : profile = null, available = false;

  final bool available;
  final ClinicalProfile? profile;
}

/// Log events (tag 'ClinicalService'), never including clinical text:
///   "Load clinical profile|clearances|prescriptions done/failed" {uid, ms}
///   "Clinical profile|Clearances|Prescriptions unavailable" {code} - read
///   failed, the UI shows "unavailable"
///   "Clinical profile loaded" {exists, fromCache}
///   "Clearances loaded" {docs, kept, fromCache}
///   "Malformed clearance skipped" / "Malformed prescription skipped" {id, reason}
class ClinicalService {
  ClinicalService({FirebaseFirestore? db, FirebaseAuth? auth})
    : _dbOverride = db,
      _authOverride = auth;

  static const String _tag = 'ClinicalService';

  /// How many clearance records are read (newest first). Only the newest
  /// decides; a few more guard against a record with a bad signedAt.
  static const int clearanceLimit = 5;

  final FirebaseFirestore? _dbOverride;
  final FirebaseAuth? _authOverride;
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  // Lazy, so constructing the service never touches Firebase (tests).
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// The signed-in uid, or null (signed out, or Firebase not set up).
  String? _uid() {
    try {
      return _auth.currentUser?.uid;
    } catch (e, st) {
      _logger.warn(_tag, 'No auth available', null, e, st);
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>> _patient(String uid) =>
      _db.collection('patients').doc(uid);

  /// The clinical profile. Unavailable when signed out or unreadable.
  Future<ClinicalProfileResult> loadProfile() async {
    final uid = _uid();
    if (uid == null) return const ClinicalProfileResult.unavailable();
    try {
      final snap = await _logger.timed(
        _tag,
        'Load clinical profile',
        () => _patient(uid).collection('clinical').doc('profile').get(),
        data: {'uid': uid},
      );
      final result = parseProfileDoc(snap.data(), logger: _logger);
      _logger.info(_tag, 'Clinical profile loaded', {
        'exists': snap.exists,
        'fromCache': snap.metadata.isFromCache,
      });
      return result;
    } catch (e, st) {
      _logUnavailable('Clinical profile', e, st);
      return const ClinicalProfileResult.unavailable();
    }
  }

  /// Clearance records, newest signedAt first. Null when unavailable.
  Future<List<ClearanceRecord>?> loadClearances() async {
    final uid = _uid();
    if (uid == null) return null;
    try {
      final snap = await _logger.timed(
        _tag,
        'Load clearances',
        () => _patient(uid)
            .collection('clearances')
            .orderBy('signedAt', descending: true)
            .limit(clearanceLimit)
            .get(),
        data: {'uid': uid},
      );
      final records = parseClearanceDocs(
        snap.docs.map((d) => MapEntry(d.id, d.data())),
        logger: _logger,
      );
      _logger.info(_tag, 'Clearances loaded', {
        'docs': snap.size,
        'kept': records.length,
        'fromCache': snap.metadata.isFromCache,
      });
      return records;
    } catch (e, st) {
      _logUnavailable('Clearances', e, st);
      return null;
    }
  }

  /// Active prescriptions as models, INCLUDING exercise types this app
  /// doesn't know (the dashboard's gate counts them too, so the patient's
  /// missing list must as well). Null when unavailable.
  Future<List<Prescription>?> loadActivePrescriptions() async {
    final uid = _uid();
    if (uid == null) return null;
    try {
      final snap = await _logger.timed(
        _tag,
        'Load prescriptions',
        () => _patient(
          uid,
        ).collection('prescriptions').where('active', isEqualTo: true).get(),
        data: {'uid': uid},
      );
      return parsePrescriptionDocs(
        snap.docs.map((d) => MapEntry(d.id, d.data())),
        logger: _logger,
      );
    } catch (e, st) {
      _logUnavailable('Prescriptions', e, st);
      return null;
    }
  }

  void _logUnavailable(String what, Object error, StackTrace stackTrace) {
    final code = error is FirebaseException ? error.code : null;
    _logger.warn(
      _tag,
      '$what unavailable',
      {
        'code': code,
        // Expected until the clinical/clearances rules are deployed.
        'rulesNotDeployedYet': code == 'permission-denied',
      },
      error,
      stackTrace,
    );
  }

  // ── Pure parsing (unit-tested) ──────────────────────────────────────

  /// Turns the profile document's data into a result. Null data means the
  /// document doesn't exist yet (no profile set).
  static ClinicalProfileResult parseProfileDoc(
    Map<String, dynamic>? data, {
    DiagnosticLogger? logger,
  }) {
    if (data == null) return const ClinicalProfileResult.loaded(null);
    final parsed = ClinicalProfile.parse(data);
    if (!parsed.isOk) {
      // Every field is optional, so this only happens on an unexpected
      // shape. Treat it as unreadable, not as "no restrictions".
      logger?.warn(_tag, 'Malformed clinical profile', {
        'reason': parsed.error,
      });
      return const ClinicalProfileResult.unavailable();
    }
    if (parsed.repaired.isNotEmpty) {
      logger?.info(_tag, 'Clinical profile repaired', {
        'fields': parsed.repaired,
      });
    }
    return ClinicalProfileResult.loaded(parsed.value);
  }

  /// Parses clearance documents (id -> data), skipping and logging bad
  /// ones, newest signedAt first.
  static List<ClearanceRecord> parseClearanceDocs(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs, {
    DiagnosticLogger? logger,
  }) {
    final records = <ClearanceRecord>[];
    for (final doc in docs) {
      final parsed = ClearanceRecord.parse(doc.key, doc.value);
      if (!parsed.isOk) {
        logger?.warn(_tag, 'Malformed clearance skipped', {
          'id': doc.key,
          'reason': parsed.error,
        });
        continue;
      }
      if (parsed.repaired.isNotEmpty) {
        logger?.info(_tag, 'Clearance repaired', {
          'id': doc.key,
          'fields': parsed.repaired,
        });
      }
      records.add(parsed.value!);
    }
    records.sort((a, b) => b.signedAt.compareTo(a.signedAt));
    return records;
  }

  /// Parses prescription documents (id -> data), skipping and logging bad
  /// ones.
  static List<Prescription> parsePrescriptionDocs(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs, {
    DiagnosticLogger? logger,
  }) {
    final prescriptions = <Prescription>[];
    for (final doc in docs) {
      final parsed = Prescription.parse(doc.key, doc.value);
      if (!parsed.isOk) {
        logger?.warn(_tag, 'Malformed prescription skipped', {
          'id': doc.key,
          'reason': parsed.error,
        });
        continue;
      }
      prescriptions.add(parsed.value!);
    }
    return prescriptions;
  }
}
