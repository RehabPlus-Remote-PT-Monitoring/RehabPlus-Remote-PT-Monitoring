import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/firestore_fields.dart';
import '../screens/edit_profile_screen.dart' show ProfileData;
import 'firestore_diagnostics.dart';

/// Reads the signed-in patient's profile from users/{uid} and patients/{uid}.
///
/// Email, condition and therapist are managed by the clinic from the web
/// dashboard; the patient may edit their own name, phone and birth date.
///
/// Log events (tag 'ProfileService'): "Load profile done/failed" {uid, ms},
/// "Profile loaded" {fromCache, hasPhoto, repaired}, "Account doc load
/// failed" / "Photo load failed" {code}, "Contact info synced / sync
/// failed", "Photo synced / sync failed" {bytes}. Names, phone numbers,
/// birth dates and the picture itself are never logged.
class ProfileService {
  // A getter so constructing the service (e.g. in AppProvider's
  // constructor, or in tests) doesn't require Firebase.
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// Profile pictures are resized to fit this many pixels and stored as JPEG
  /// bytes in patients/{uid}/avatar/photo (Firestore, no Cloud Storage).
  static const double photoSize = 512;

  /// Upper limit, matching the Firestore rule (documents max out at 1 MiB).
  static const int maxPhotoBytes = 500 * 1024;

  /// Field limits from firestore.rules (validContactEdit).
  static const int maxNameLength = 100;
  static const int maxPhoneLength = 30;
  static const int maxDobLength = 30;

  DocumentReference<Map<String, dynamic>> _photoDoc(String uid) =>
      _db.collection('patients').doc(uid).collection('avatar').doc('photo');

  /// Loads the profile, or null when nobody is signed in.
  ///
  /// The three documents (users, patients, avatar) are independent, so they
  /// are fetched in parallel: one round trip instead of three. Only the
  /// patient document is essential; if the account document or the photo
  /// can't be read, the profile still loads with fallbacks. Throws when the
  /// patient document itself can't be read.
  Future<ProfileData?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final uid = user.uid;

    return _logger.timed('ProfileService', 'Load profile', () async {
      // Start all three reads before awaiting any. The account and photo
      // helpers never throw (they log and fall back), so if the patient
      // read fails no other future is left with an unhandled error.
      final accountRead = _loadAccount(uid);
      final photoRead = _loadPhoto(uid);
      final patientSnap = await _db.collection('patients').doc(uid).get();
      final account = await accountRead;
      final photo = await photoRead;

      final patient = FieldReader(patientSnap.data() ?? const {});
      final accountFields = FieldReader(account);

      final profile = ProfileData(
        name:
            patient.string('name') ?? accountFields.string('name') ?? '',
        email: accountFields.string('email') ?? user.email ?? '',
        phone: patient.string('phone') ?? '',
        dob: patient.string('dob') ?? '',
        condition: patient.string('condition') ?? '',
        therapist: patient.string('therapistName') ?? '',
        programStart: patient.dateTime('createdAt'),
        photo: photo,
      );

      _logger.info('ProfileService', 'Profile loaded', {
        'uid': uid,
        'patientDocExists': patientSnap.exists,
        'fromCache': patientSnap.metadata.isFromCache,
        'hasPhoto': photo != null,
        if (patient.repaired.isNotEmpty) 'repaired': patient.repaired,
      });
      return profile;
    }, data: {'uid': uid});
  }

  /// users/{uid} (fallback name and e-mail). Empty map if it can't be read:
  /// the patient document has everything that matters.
  Future<Map<String, dynamic>> _loadAccount(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return snap.data() ?? const {};
    } catch (e, st) {
      _logger.warn('ProfileService', 'Account doc load failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      return const {};
    }
  }

  /// The profile picture, or null (none set, or it couldn't be loaded; the
  /// default icon is shown either way).
  Future<Uint8List?> _loadPhoto(String uid) async {
    try {
      final snap = await _photoDoc(uid).get();
      final image = snap.data()?['image'];
      return image is Blob ? image.bytes : null;
    } catch (e, st) {
      _logger.warn('ProfileService', 'Photo load failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      return null;
    }
  }

  /// Saves the profile picture, or removes it when [photo] is null. Not
  /// awaited, like [saveContact], so it also works offline.
  ///
  /// Throws [StateError] when signed out and [ArgumentError] when [photo] is
  /// larger than [maxPhotoBytes] (the rules would reject it).
  void savePhoto(Uint8List? photo) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    if (photo != null && photo.length > maxPhotoBytes) {
      _logger.warn('ProfileService', 'Photo too large; not saved', {
        'bytes': photo.length,
        'max': maxPhotoBytes,
      });
      throw ArgumentError.value(photo.length, 'photo', 'Larger than the limit');
    }
    final doc = _photoDoc(uid);
    final write = photo == null
        ? doc.delete()
        : doc.set({
            'image': Blob(photo),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    logUnawaitedWrite(
      write,
      tag: 'ProfileService',
      operation: 'Photo',
      data: {'uid': uid, 'bytes': photo?.length ?? 0, 'removed': photo == null},
    );
  }

  /// Saves the patient-editable fields. Not awaited past the local write so it
  /// also works offline; Firestore uploads it when the phone reconnects.
  ///
  /// Throws [StateError] when signed out and [ArgumentError] when a value
  /// breaks the Firestore rule (name 1–100 characters, phone and date of
  /// birth up to 30): the screen validates the same limits, and failing here
  /// beats the server silently rolling the edit back later.
  void saveContact({
    required String name,
    required String phone,
    required String dob,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final invalid = [
      if (name.trim().isEmpty || name.length > maxNameLength) 'name',
      if (phone.length > maxPhoneLength) 'phone',
      if (dob.length > maxDobLength) 'dob',
    ];
    if (invalid.isNotEmpty) {
      // Field names only; the values are personal data.
      _logger.warn('ProfileService', 'Contact info invalid; not saved', {
        'fields': invalid,
      });
      throw ArgumentError('Invalid contact fields: ${invalid.join(', ')}');
    }

    logUnawaitedWrite(
      _db.collection('patients').doc(uid).update({
        'name': name,
        'phone': phone,
        'dob': dob,
      }),
      tag: 'ProfileService',
      operation: 'Contact info',
      data: {'uid': uid},
    );
  }
}
