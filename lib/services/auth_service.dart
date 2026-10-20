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

  // ── Password reset by SMS ─────────────────────────────────────────────
  //
  // Firebase can only e-mail reset links, so the phone flow is:
  //   1. [sendResetCode] texts a 6-digit code (Firebase Phone Auth).
  //   2. [verifyResetCode] signs in with it. This only reaches the patient's
  //      account when the dashboard linked their number to the login
  //      (Admin SDK `phoneNumber`); otherwise Firebase would create a new,
  //      empty user, which is deleted again straight away.
  //   3. [setNewPassword] changes the password and signs out, so the patient
  //      then signs in normally with the new one.
  // [cancelPasswordReset] signs out if the patient leaves half-way.

  /// Texts a reset code to [phoneE164] (e.g. +639171234567). Completes with
  /// a [ResetCodeRequest]: normally the id to check the typed code against,
  /// or, when Android verified the number by itself, the ready credential.
  /// If Android reads the SMS later on its own, [onAutoVerified] gets the
  /// credential so the screen can skip typing. Throws [AuthFailure].
  Future<ResetCodeRequest> sendResetCode(
    String phoneE164, {
    int? resendToken,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    final result = Completer<ResetCodeRequest>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneE164,
        forceResendingToken: resendToken,
        timeout: const Duration(seconds: 60),
        codeSent: (verificationId, token) {
          _logger.info('AuthService', 'Reset code sent');
          if (!result.isCompleted) {
            result.complete(ResetCodeRequest(
              verificationId: verificationId,
              resendToken: token,
            ));
          }
        },
        verificationCompleted: (credential) {
          _logger.info('AuthService', 'Reset code verified automatically');
          if (!result.isCompleted) {
            result.complete(ResetCodeRequest(credential: credential));
          } else {
            onAutoVerified?.call(credential);
          }
        },
        verificationFailed: (e) {
          _logger.warn('AuthService', 'Reset code failed', {'code': e.code},
              e, e.stackTrace);
          if (!result.isCompleted) {
            result.completeError(AuthFailure(_resetCodeMessage(e.code)));
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Reset code failed', {'code': e.code}, e, st);
      throw AuthFailure(_resetCodeMessage(e.code));
    } catch (e, st) {
      _logger.error('AuthService', 'Reset code crashed',
          firebaseErrorData(e), e, st);
      throw const AuthFailure('Could not send the code. Please try again.');
    }
    return result.future;
  }

  static String _resetCodeMessage(String code) => switch (code) {
    'invalid-phone-number' => 'Enter a valid mobile number.',
    'too-many-requests' ||
    'quota-exceeded' => 'Too many attempts. Try again later.',
    'network-request-failed' => 'No internet connection.',
    'operation-not-allowed' || 'billing-not-enabled' =>
      'Reset by text message isn\'t available yet. Contact the clinic.',
    _ => 'Could not send the code. Please try again.',
  };

  /// The credential for the [smsCode] the patient typed.
  PhoneAuthCredential credentialFor(String verificationId, String smsCode) =>
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

  /// Signs in with the SMS [credential] and checks the number belongs to an
  /// active patient login. Throws [AuthFailure]; on failure nobody is left
  /// signed in.
  Future<void> verifyResetCode(PhoneAuthCredential credential) async {
    final UserCredential signedIn;
    try {
      signedIn = await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Reset code rejected', {'code': e.code},
          e, st);
      throw AuthFailure(switch (e.code) {
        'invalid-verification-code' => 'Wrong code. Check the text message.',
        'session-expired' ||
        'code-expired' => 'The code expired. Tap "Resend code".',
        'user-disabled' =>
          'This account has been disabled. Contact the clinic.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Could not check the code. Please try again.',
      });
    } catch (e, st) {
      _logger.error('AuthService', 'Reset code check crashed',
          firebaseErrorData(e), e, st);
      throw const AuthFailure('Could not check the code. Please try again.');
    }

    final user = signedIn.user;
    final hasPasswordLogin =
        user?.providerData.any((p) => p.providerId == 'password') ?? false;
    if (user == null || !hasPasswordLogin) {
      // The number isn't linked to any patient login: Firebase just made an
      // empty phone-only user. Remove it so it doesn't pile up.
      _logger.warn('AuthService', 'Reset number not linked to an account', {
        'newUser': signedIn.additionalUserInfo?.isNewUser,
      });
      try {
        if (signedIn.additionalUserInfo?.isNewUser ?? false) {
          await user?.delete();
        }
      } catch (e, st) {
        _logger.warn('AuthService', 'Deleting the stray phone user failed',
            firebaseErrorData(e), e, st);
      }
      await _signOutQuietly();
      throw const AuthFailure(
        'No account uses this number. Ask the clinic to add it, or reset '
        'with your email.',
      );
    }

    final Map<String, dynamic> data;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      data = doc.data() ?? const <String, dynamic>{};
    } catch (e, st) {
      await _signOutQuietly();
      _logger.error('AuthService', 'Profile lookup failed', {
        'uid': user.uid,
        ...firebaseErrorData(e),
      }, e, st);
      throw const AuthFailure('Could not load your account. Please try again.');
    }
    if (data['role'] != 'patient' || data['active'] == false) {
      await _signOutQuietly();
      _logger.warn('AuthService', 'Rejected password reset', {
        'uid': user.uid,
        'role': data['role'],
      });
      throw const AuthFailure(
        'This number can\'t reset a patient password. Contact the clinic.',
      );
    }
    _logger.info('AuthService', 'Reset code accepted', {'uid': user.uid});
  }

  /// Sets [newPassword] on the account signed in by [verifyResetCode], then
  /// signs out. Throws [AuthFailure] (still signed in, so the patient can
  /// try another password).
  Future<void> setNewPassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Your code expired. Please start again.');
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e, st) {
      _logger.warn('AuthService', 'Password change failed', {'code': e.code},
          e, st);
      throw AuthFailure(switch (e.code) {
        'weak-password' =>
          'Choose a stronger password (at least $minPasswordLength characters).',
        'requires-recent-login' => 'Your code expired. Please start again.',
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

  /// Leaves a half-finished SMS reset: signs out the account the code
  /// signed in. Never throws.
  Future<void> cancelPasswordReset() async {
    if (_auth.currentUser == null) return;
    _logger.info('AuthService', 'Password reset abandoned');
    await _signOutQuietly();
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

/// What [AuthService.sendResetCode] got back: a [verificationId] to check the
/// typed code against, or a [credential] when Android verified the number
/// by itself (no typing needed).
class ResetCodeRequest {
  const ResetCodeRequest({
    this.verificationId,
    this.resendToken,
    this.credential,
  });

  final String? verificationId;
  final int? resendToken;
  final PhoneAuthCredential? credential;
}

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
