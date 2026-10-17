import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../screens/edit_profile_screen.dart' show ProfileData;

/// Reads the signed-in patient's profile from users/{uid} and patients/{uid}.
///
/// Name, email, condition and therapist are managed by the clinic from the
/// web dashboard; the patient may only edit their own phone and birth date.
class ProfileService {
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  Future<ProfileData?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final results = await Future.wait([
      _db.collection('users').doc(user.uid).get(),
      _db.collection('patients').doc(user.uid).get(),
    ]);
    final account = results[0].data() ?? const {};
    final patient = results[1].data() ?? const {};

    return ProfileData(
      name: (account['name'] ?? patient['name'] ?? '') as String,
      email: (account['email'] ?? user.email ?? '') as String,
      phone: (patient['phone'] ?? '') as String,
      dob: (patient['dob'] ?? '') as String,
      condition: (patient['condition'] ?? '') as String,
      therapist: (patient['therapistName'] ?? '') as String,
      programStart: (patient['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Saves the patient-editable fields. Not awaited past the local write so it
  /// also works offline; Firestore uploads it when the phone reconnects.
  void saveContact({required String phone, required String dob}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    unawaited(
      _db
          .collection('patients')
          .doc(uid)
          .update({'phone': phone, 'dob': dob})
          .then(
            (_) => _logger.info('ProfileService', 'Contact info synced'),
            onError: (Object e, StackTrace _) => _logger.error(
              'ProfileService',
              'Contact info sync failed',
              {'error': e.toString()},
            ),
          ),
    );
  }
}
