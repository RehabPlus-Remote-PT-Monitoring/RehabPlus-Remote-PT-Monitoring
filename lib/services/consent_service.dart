import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';

/// Thrown by [ConsentService.accept]; [message] is safe to show the patient.
class ConsentFailure implements Exception {
  final String message;
  const ConsentFailure(this.message);
  @override
  String toString() => message;
}

/// The patient's acceptance of the Terms and Conditions and Privacy Policy.
///
/// Each acceptance is an append-only record at
/// patients/{uid}/consents/{LegalInfo.version} (the Firestore rules forbid
/// editing or deleting it), so the clinic can show who accepted which version
/// and when. The accepted version is also cached on the phone so a patient who
/// already accepted isn't blocked when they're offline.
class ConsentService {
  ConsentService._();
  static final ConsentService I = ConsentService._();

  final _logger = DiagnosticLogger.I;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => FirebaseFirestore
      .instance
      .collection('patients')
      .doc(uid)
      .collection('consents')
      .doc(LegalInfo.version);

  String _cacheKey(String uid) => 'consent_version_$uid';

  /// Whether the signed-in patient has accepted the current version.
  Future<bool> hasAcceptedCurrent() async {
    final uid = _uid;
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_cacheKey(uid)) == LegalInfo.version) return true;
    try {
      final snap = await _doc(uid).get();
      if (snap.exists) await prefs.setString(_cacheKey(uid), LegalInfo.version);
      return snap.exists;
    } on FirebaseException catch (e) {
      // Can't check (e.g. offline on a new phone): ask again rather than let
      // someone in without a record of their consent.
      _logger.warn('ConsentService', 'Consent check failed', {'code': e.code});
      return false;
    }
  }

  /// Records that the patient accepted the Terms, the Privacy Policy, the
  /// processing of their health information and the use of the camera.
  Future<void> accept() async {
    final uid = _uid;
    if (uid == null) throw const ConsentFailure('Please sign in again.');
    try {
      final doc = _doc(uid);
      // Already recorded (e.g. on another phone): the record can't be
      // overwritten, so just remember it here.
      if (!(await doc.get()).exists) {
        await doc
            .set({
              'version': LegalInfo.version,
              'acceptedTerms': true,
              'acceptedPrivacyPolicy': true,
              'healthDataConsent': true,
              'cameraConsent': true,
              'acceptedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 15));
      }
    } on FirebaseException catch (e) {
      _logger.error('ConsentService', 'Saving consent failed', {
        'code': e.code,
      });
      throw const ConsentFailure(
        'Could not save your acceptance. Please try again.',
      );
    } catch (e) {
      _logger.error('ConsentService', 'Saving consent failed', {
        'error': e.toString(),
      });
      throw const ConsentFailure(
        'Could not save your acceptance. Check your internet connection and try again.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(uid), LegalInfo.version);
    _logger.info('ConsentService', 'Consent recorded', {
      'version': LegalInfo.version,
    });
  }
}
