import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';
import 'firestore_diagnostics.dart';

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
///
/// Log events (tag 'ConsentService'): "Consent check" {uid, version,
/// accepted, source: phone|server|cache}, "Consent check failed" {code},
/// "Consent recorded" {version, alreadyOnServer, ms}, "Saving consent
/// failed" {code}.
class ConsentService {
  ConsentService._();
  static final ConsentService I = ConsentService._();

  final _logger = DiagnosticLogger.I;

  /// The acceptance being saved, so a double tap on "Accept" doesn't send
  /// two creates (the second would be rejected as an update by the rules
  /// and shown to the patient as a failure).
  Future<void>? _accepting;

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

    final prefs = await _prefsOrNull();
    if (_cachedVersion(prefs, uid) == LegalInfo.version) {
      _logConsentCheck(uid, accepted: true, source: 'phone');
      return true;
    }
    try {
      final snap = await _doc(uid).get();
      if (snap.exists) await _remember(prefs, uid);
      _logConsentCheck(
        uid,
        accepted: snap.exists,
        source: snap.metadata.isFromCache ? 'cache' : 'server',
      );
      return snap.exists;
    } catch (e, st) {
      // Can't check (e.g. offline on a new phone): ask again rather than let
      // someone in without a record of their consent.
      _logger.warn('ConsentService', 'Consent check failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      return false;
    }
  }

  void _logConsentCheck(
    String uid, {
    required bool accepted,
    required String source,
  }) => _logger.info('ConsentService', 'Consent check', {
    'uid': uid,
    'version': LegalInfo.version,
    'accepted': accepted,
    'source': source,
  });

  /// Records that the patient accepted the Terms, the Privacy Policy, the
  /// processing of their health information and the use of the camera.
  /// Throws [ConsentFailure] with a message for the patient.
  Future<void> accept() {
    final inFlight = _accepting;
    if (inFlight != null) return inFlight;
    final run = _accept();
    _accepting = run;
    return run.whenComplete(() {
      if (identical(_accepting, run)) _accepting = null;
    });
  }

  Future<void> _accept() async {
    final uid = _uid;
    if (uid == null) throw const ConsentFailure('Please sign in again.');
    final stopwatch = Stopwatch()..start();
    var alreadyOnServer = false;
    try {
      final doc = _doc(uid);
      // Already recorded (e.g. on another phone): the record can't be
      // overwritten, so just remember it here.
      alreadyOnServer = (await doc.get()).exists;
      if (!alreadyOnServer) {
        // Awaited, with a timeout: the patient must not get in without a
        // consent record that actually reached the clinic.
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
    } on FirebaseException catch (e, st) {
      _logger.error('ConsentService', 'Saving consent failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      throw const ConsentFailure(
        'Could not save your acceptance. Please try again.',
      );
    } catch (e, st) {
      _logger.error('ConsentService', 'Saving consent failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      throw const ConsentFailure(
        'Could not save your acceptance. Check your internet connection and try again.',
      );
    }
    await _remember(await _prefsOrNull(), uid);
    _logger.info('ConsentService', 'Consent recorded', {
      'uid': uid,
      'version': LegalInfo.version,
      'alreadyOnServer': alreadyOnServer,
      'ms': stopwatch.elapsedMilliseconds,
    });
  }

  // The phone-side cache is only a shortcut: if SharedPreferences fails,
  // fall back to asking Firestore instead of failing the consent flow.

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e, st) {
      _logger.warn('ConsentService', 'Phone storage unavailable', null, e, st);
      return null;
    }
  }

  String? _cachedVersion(SharedPreferences? prefs, String uid) {
    final value = prefs?.get(_cacheKey(uid));
    return value is String ? value : null;
  }

  Future<void> _remember(SharedPreferences? prefs, String uid) async {
    try {
      await prefs?.setString(_cacheKey(uid), LegalInfo.version);
    } catch (e, st) {
      _logger.warn('ConsentService', 'Caching consent failed', null, e, st);
    }
  }
}
