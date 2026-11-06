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
/// sent/failed" {code}, "Reset code sent/failed" {code}, "Reset code
/// accepted/rejected", "Password changed", "Signed out". E-mail addresses,
/// phone numbers, codes and passwords are never logged.
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

  // ── Password reset with a temporary password ──────────────────────────
  //
  // The clinic sets a temporary password on the dashboard and gives it to
  // the patient in person. [resetWithTemporaryPassword] signs in with it,
  // sets the patient's own password, and signs out, so the patient then
  // signs in normally with the new one.

  /// Replaces the temporary password with [newPassword]. Throws [AuthFailure]
  /// for a wrong email or temporary password (nothing changes), or for a new
  /// password Firebase refuses (the patient is signed out again).
  Future<void> resetWithTemporaryPassword({
    required String email,
    required String temporaryPassword,
    required String newPassword,
  }) async {
    await signIn(email, temporaryPassword);
    try {
      await setNewPassword(newPassword);
    } catch (_) {
      await _signOutQuietly();
      rethrow;
    }
  }

  /// Sets [newPassword] on the signed-in account, then signs out. Throws
  /// [AuthFailure] (still signed in, so the patient can try another password).
  Future<void> setNewPassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Please try again.');
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Password change failed', {'code': e.code},
          e, st);
      throw AuthFailure(switch (e.code) {
        'weak-password' =>
          'Choose a stronger password (at least $minPasswordLength characters).',
        'requires-recent-login' => 'Please try again.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Could not change the password. Please try again.',
      });
    } catch (e, st) {
      _logger.error('AuthService', 'Password change crashed',
          firebaseErrorData(e), e, st);
      throw const AuthFailure(
        'Could not change the password. Please try again.',
      );
    }
    _logger.info('AuthService', 'Password changed', {'uid': user.uid});
    await _signOutQuietly();
  }

  /// Changes the password of the signed-in patient. Firebase wants a recent
  /// sign-in for this, so [currentPassword] is checked again first. The
  /// patient stays signed in. Throws [AuthFailure] with a message for the
  /// form.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthFailure('Sign in again to change your password.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Current password check failed',
          {'code': e.code}, e, st);
      throw AuthFailure(switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'invalid-login-credentials' => 'Your current password is wrong.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        'user-disabled' => 'This account has been disabled. Contact the clinic.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Could not check your password. Please try again.',
      });
    } catch (e, st) {
      _logger.error('AuthService', 'Current password check crashed',
          firebaseErrorData(e), e, st);
      throw const AuthFailure('Could not check your password. Please try again.');
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Password change failed', {'code': e.code},
          e, st);
      throw AuthFailure(switch (e.code) {
        'weak-password' =>
          'Choose a stronger password (at least $minPasswordLength characters).',
        'requires-recent-login' =>
          'Please enter your current password again.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Could not change the password. Please try again.',
      });
    } catch (e, st) {
      _logger.error('AuthService', 'Password change crashed',
          firebaseErrorData(e), e, st);
      throw const AuthFailure(
        'Could not change the password. Please try again.',
      );
    }
    _logger.info('AuthService', 'Password changed in app', {'uid': user.uid});
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

/// Firebase's minimum password length.
const int minPasswordLength = 6;


/// Turns what a patient types into the +country-code form Firebase
/// needs, or null when it can't be a mobile number. Numbers without a
/// country code are taken as Philippine (09171234567 -> +639171234567).
String? toE164(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^\+\d{8,15}$').hasMatch(cleaned)) return cleaned;
  if (RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
    return '+63${cleaned.substring(1)}';
  }
  if (RegExp(r'^639\d{9}$').hasMatch(cleaned)) return '+$cleaned';
  if (RegExp(r'^9\d{9}$').hasMatch(cleaned)) return '+63$cleaned';
  return null;
}
