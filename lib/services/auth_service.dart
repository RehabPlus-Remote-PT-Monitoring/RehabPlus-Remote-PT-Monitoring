import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import 'firestore_diagnostics.dart';

/// Shown to the user; [message] is safe to put in a SnackBar.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Firebase sign-in for the patient app.
///
/// Accounts are created by therapists from the web dashboard; each one has a
/// users/{uid} document whose `role` decides access. Only `patient` accounts
/// may use the mobile app.
///
/// Log events (tag 'AuthService'): "Sign-in started/succeeded", "Sign-in
/// failed" {code}, "Rejected non-patient login" {role}, "Password reset
/// sent/failed" {code}, "Signed out". The e-mail address is never logged.
class AuthService {
  AuthService._();
  static final AuthService I = AuthService._();

  // Getters, not fields: nothing touches Firebase until it is first used,
  // so tests can construct the app without Firebase.
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// The sign-in in progress, so a double tap on "Sign in" joins it instead
  /// of starting a second one (two parallel attempts would race on the role
  /// check and could sign the user out under the first).
  Future<void>? _signingIn;

  User? get currentUser => _auth.currentUser;

  /// The signed-in user's uid, or null.
  String? get currentUid => _auth.currentUser?.uid;

  /// Signs in and checks the account is a patient. Throws [AuthFailure]
  /// with a patient-friendly message on any problem; on failure the user is
  /// left signed out.
  Future<void> signIn(String email, String password) {
    final inFlight = _signingIn;
    if (inFlight != null) {
      _logger.info('AuthService', 'Sign-in already in progress; joining it');
      return inFlight;
    }
    final attempt = _signIn(email, password);
    _signingIn = attempt;
    return attempt.whenComplete(() {
      if (identical(_signingIn, attempt)) _signingIn = null;
    });
  }

  Future<void> _signIn(String email, String password) async {
    final stopwatch = Stopwatch()..start();
    _logger.info('AuthService', 'Sign-in started');

    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Sign-in failed', {
        'code': e.code,
        'ms': stopwatch.elapsedMilliseconds,
      }, e, st);
      throw AuthFailure(switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-email' => 'Invalid email or password.',
        'user-disabled' =>
          'This account has been disabled. Contact the clinic.',
        'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Sign-in failed. Please try again.',
      });
    } catch (e, st) {
      // Platform/channel errors that aren't FirebaseAuthExceptions.
      _logger.error('AuthService', 'Sign-in failed unexpectedly', {
        ...firebaseErrorData(e),
      }, e, st);
      throw const AuthFailure('Sign-in failed. Please try again.');
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // Shouldn't happen after a successful sign-in, but don't crash on `!`.
      _logger.error('AuthService', 'No user after successful sign-in');
      throw const AuthFailure('Sign-in failed. Please try again.');
    }

    final DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await _db.collection('users').doc(uid).get();
    } catch (e, st) {
      await _signOutQuietly();
      _logger.error('AuthService', 'Profile lookup failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      throw const AuthFailure('Could not load your account. Please try again.');
    }

    final data = profile.data() ?? const <String, dynamic>{};
    final role = data['role'] is String ? data['role'] as String : null;
    if (role != 'patient') {
      await _signOutQuietly();
      _logger.warn('AuthService', 'Rejected non-patient login', {
        'uid': uid,
        'role': role,
        'profileExists': profile.exists,
      });
      throw AuthFailure(
        role == null
            ? 'Your account is not set up yet. Contact the clinic.'
            : 'This app is for patients. Therapists use the web dashboard.',
      );
    }

    // Archiving a patient disables the Auth login, so this is normally
    // caught above as 'user-disabled'. `active: false` is checked as well in
    // case the dashboard only managed to update the users document.
    if (data['active'] == false) {
      await _signOutQuietly();
      _logger.warn('AuthService', 'Rejected inactive account', {'uid': uid});
      throw const AuthFailure(
        'This account has been disabled. Contact the clinic.',
      );
    }

    _logger.info('AuthService', 'Sign-in succeeded', {
      'uid': uid,
      'fromCache': profile.metadata.isFromCache,
      'ms': stopwatch.elapsedMilliseconds,
    });
  }

  /// Sends a password-reset e-mail. Errors are logged (code only) and
  /// re-thrown for the screen to explain.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _logger.info('AuthService', 'Password reset sent');
    } catch (e, st) {
      _logger.warn('AuthService', 'Password reset failed', {
        ...firebaseErrorData(e),
      }, e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    final uid = currentUid;
    try {
      await _auth.signOut();
      _logger.info('AuthService', 'Signed out', {'uid': uid});
    } catch (e, st) {
      _logger.error('AuthService', 'Sign-out failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      rethrow;
    }
  }

  /// Sign-out used while rejecting a login: its own failure must not hide
  /// the real reason, so it is only logged.
  Future<void> _signOutQuietly() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      _logger.warn('AuthService', 'Sign-out after rejected login failed',
          firebaseErrorData(e), e, st);
    }
  }
}
