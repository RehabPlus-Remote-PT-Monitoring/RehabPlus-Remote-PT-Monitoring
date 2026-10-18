import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../screens/edit_profile_screen.dart' show ProfileData;

/// Reads the signed-in patient's profile from users/{uid} and patients/{uid}.
///
/// Email, condition and therapist are managed by the clinic from the web
/// dashboard; the patient may edit their own name, phone and birth date.
class ProfileService {
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// Profile pictures are resized to fit this many pixels and stored as JPEG
  /// bytes in patients/{uid}/avatar/photo (Firestore, no Cloud Storage).
  static const double photoSize = 512;

  /// Upper limit, matching the Firestore rule (documents max out at 1 MiB).
  static const int maxPhotoBytes = 500 * 1024;

  DocumentReference<Map<String, dynamic>> _photoDoc(String uid) =>
      _db.collection('patients').doc(uid).collection('avatar').doc('photo');

  Future<ProfileData?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final results = await Future.wait([
      _db.collection('users').doc(user.uid).get(),
      _db.collection('patients').doc(user.uid).get(),
    ]);
    final account = results[0].data() ?? const {};
    final patient = results[1].data() ?? const {};
    final photo = await _loadPhoto(user.uid);

    return ProfileData(
      name: (patient['name'] ?? account['name'] ?? '') as String,
      email: (account['email'] ?? user.email ?? '') as String,
      phone: (patient['phone'] ?? '') as String,
      dob: (patient['dob'] ?? '') as String,
      condition: (patient['condition'] ?? '') as String,
      therapist: (patient['therapistName'] ?? '') as String,
      programStart: (patient['createdAt'] as Timestamp?)?.toDate(),
      photo: photo,
    );
  }

  /// The profile picture, or null (none set, or it couldn't be loaded; the
  /// default icon is shown either way).
  Future<Uint8List?> _loadPhoto(String uid) async {
    try {
      final snap = await _photoDoc(uid).get();
      return (snap.data()?['image'] as Blob?)?.bytes;
    } on FirebaseException catch (e) {
      _logger.warn('ProfileService', 'Photo load failed', {'code': e.code});
      return null;
    }
  }

  /// Saves the profile picture, or removes it when [photo] is null. Not
  /// awaited, like [saveContact], so it also works offline.
  void savePhoto(Uint8List? photo) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    final doc = _photoDoc(uid);
    final write = photo == null
        ? doc.delete()
        : doc.set({
            'image': Blob(photo),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    unawaited(
      write.then(
        (_) => _logger.info('ProfileService', 'Photo synced', {
          'bytes': photo?.length ?? 0,
        }),
        onError: (Object e, StackTrace _) => _logger.error(
          'ProfileService',
          'Photo sync failed',
          {'error': e.toString()},
        ),
      ),
    );
  }

  /// Saves the patient-editable fields. Not awaited past the local write so it
  /// also works offline; Firestore uploads it when the phone reconnects.
  void saveContact({
    required String name,
    required String phone,
    required String dob,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    unawaited(
      _db
          .collection('patients')
          .doc(uid)
          .update({'name': name, 'phone': phone, 'dob': dob})
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
