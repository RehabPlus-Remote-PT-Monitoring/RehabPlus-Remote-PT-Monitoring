import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';

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
class AuthService {
  AuthService._();
  static final AuthService I = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _logger.warn('AuthService', 'Sign-in failed', {'code': e.code});
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
    }

    final uid = _auth.currentUser!.uid;
    final DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await _db.collection('users').doc(uid).get();
    } on FirebaseException catch (e) {
      await _auth.signOut();
      _logger.error('AuthService', 'Profile lookup failed', {'code': e.code});
      throw const AuthFailure('Could not load your account. Please try again.');
    }

    final role = profile.data()?['role'];
    if (role != 'patient') {
      await _auth.signOut();
      _logger.warn('AuthService', 'Rejected non-patient login', {'role': role});
      throw AuthFailure(
        role == null
            ? 'Your account is not set up yet. Contact the clinic.'
            : 'This app is for patients. Therapists use the web dashboard.',
      );
    }
    _logger.info('AuthService', 'Signed in', {'uid': uid});
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();
}
