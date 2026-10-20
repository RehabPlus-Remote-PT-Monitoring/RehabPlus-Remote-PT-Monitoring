import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/diagnostic_logger.dart';

/// Optional app lock: a 4-digit PIN (with fingerprint/face as a shortcut)
/// asked before the dashboard, both when the app is opened and when the
/// patient comes back after [relockAfter] in the background.
///
/// It is a second layer on top of the Firebase sign-in, which stays signed
/// in across restarts: anyone holding the unlocked phone would otherwise see
/// the patient's health data straight away.
///
/// Design decisions:
/// - Phone-only. The PIN never leaves the phone and is not stored in
///   Firestore; only a salted, stretched SHA-256 hash is kept, in
///   flutter_secure_storage (Android Keystore-encrypted).
/// - Forgetting the PIN is never a dead end: "Sign in with password" signs
///   out, which also removes the lock. The same happens automatically after
///   [maxAttempts] wrong PINs in a row (the count survives restarts, so
///   killing the app doesn't reset it).
/// - The PIN is kept per patient (storage keys end in the Firebase uid) and
///   survives signing out: when the same patient signs in again on this
///   phone, their PIN and fingerprint choice come back. Another patient who
///   signs in on the phone never sees or inherits it. Sign-out only forgets
///   it in memory ([forget]); "Forgot PIN" and too many wrong PINs delete
///   it ([disable]) before signing out, so the patient can choose a new one.
/// - If the secure storage can't be read, the lock is treated as off and
///   the failure is logged (error). flutter_secure_storage already wipes
///   unreadable data on its own, so this matches what it would do anyway,
///   and the patient is never locked out of their own app.
///
/// The service only keeps the state; the lock screens and the code that
/// shows them on resume live in lib/screens/app_lock_screen.dart.
///
/// Log events (tag 'AppLock'), never containing the PIN:
/// "Loaded" {enabled, biometrics, failedAttempts}, "PIN set", "PIN removed",
/// "Locked" {reason, awayS}, "Unlocked" {method}, "Wrong PIN"
/// {failedAttempts}, "Too many wrong PINs", "Biometric result" {result},
/// "Storage read failed"/"Storage write failed" (with the exception).
class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService({
    AppLockStore? store,
    BiometricAuth? biometrics,
    DateTime Function()? clock,
    String? Function()? currentUid,
  }) : _store = store ?? SecureAppLockStore(),
       _biometrics = biometrics ?? LocalBiometricAuth(),
       _clock = clock ?? DateTime.now,
       _currentUid = currentUid ?? _firebaseUid;

  /// The app-wide instance.
  static final AppLockService I = AppLockService();

  static const String _tag = 'AppLock';

  /// Number of digits in the PIN.
  static const int pinLength = 4;

  /// Wrong PINs in a row before the patient must sign in with the password.
  static const int maxAttempts = 5;

  /// Time in the background after which the PIN is asked again.
  static const Duration relockAfter = Duration(minutes: 1);

  // Keys in secure storage; the patient's uid is appended (see [_key]).
  static const String _kPin = 'lock_pin';
  static const String _kBiometrics = 'lock_biometrics';
  static const String _kFailed = 'lock_failed_attempts';
  static const List<String> _allKeys = [_kPin, _kBiometrics, _kFailed];

  final AppLockStore _store;
  final BiometricAuth _biometrics;
  final DateTime Function() _clock;
  final String? Function() _currentUid;
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  static String? _firebaseUid() => FirebaseAuth.instance.currentUser?.uid;

  bool _isSignedIn() => _currentUid() != null;

  /// The storage key for [base] for the signed-in patient, or null when
  /// nobody is signed in.
  String? _key(String base) {
    final uid = _currentUid();
    return uid == null ? null : '${base}_$uid';
  }

  /// The stored PIN hash record (see [PinHasher]); null = lock is off.
  String? _pinRecord;
  bool _biometricsEnabled = false;
  int _failedAttempts = 0;
  bool _locked = false;

  /// Whether a lock screen is on screen right now (so a second one is never
  /// pushed on top of the first).
  int _lockViewsShowing = 0;

  /// Set once the first real screen is on screen; before that (splash,
  /// startup lock) coming back from the background must not push a lock.
  bool _armed = false;
  bool _observing = false;

  /// When the app last went to the background; null while in front.
  DateTime? _backgroundedAt;

  bool get isEnabled => _pinRecord != null;
  bool get biometricsEnabled => isEnabled && _biometricsEnabled;
  int get failedAttempts => _failedAttempts;
  int get attemptsLeft => max(0, maxAttempts - _failedAttempts);

  /// True while the PIN must be entered before the app can be used.
  bool get isLocked => _locked;

  /// True when the app is locked but no lock screen shows it yet: the
  /// screen layer must push one (see AppLockRouter). Never before [arm]:
  /// at startup main.dart shows its own lock screen in place of the
  /// dashboard, and a second one pushed over the splash would break the
  /// splash's hand-over (seen on the phone).
  bool get needsLockScreen => _armed && _locked && _lockViewsShowing == 0;

  /// Reads the signed-in patient's saved lock from the phone (lock off when
  /// nobody is signed in). Call at startup once Firebase is ready and again
  /// after each sign-in. Never throws.
  Future<void> load() async {
    _locked = false;
    try {
      if (!_isSignedIn()) {
        _pinRecord = null;
        _biometricsEnabled = false;
        _failedAttempts = 0;
      } else {
        await _migrateLegacyKeys();
        _pinRecord = await _store.read(_key(_kPin)!);
        _biometricsEnabled = await _store.read(_key(_kBiometrics)!) == 'true';
        _failedAttempts =
            int.tryParse(await _store.read(_key(_kFailed)!) ?? '') ?? 0;
      }
      if (_pinRecord != null && !PinHasher.isValidRecord(_pinRecord!)) {
        // Unreadable record (e.g. a future format): turn the lock off
        // rather than lock the patient out with a PIN nothing can check.
        _logger.warn(_tag, 'Stored PIN record invalid; lock turned off');
        _pinRecord = null;
      }
    } catch (e, st) {
      _logger.error(_tag, 'Storage read failed; lock treated as off', null,
          e, st);
      _pinRecord = null;
      _biometricsEnabled = false;
      _failedAttempts = 0;
    }
    _logger.info(_tag, 'Loaded', {
      'enabled': isEnabled,
      'biometrics': biometricsEnabled,
      'failedAttempts': _failedAttempts,
    });
    notifyListeners();
  }

  /// Older versions kept one PIN for the phone under the bare keys; it
  /// belongs to whoever is signed in now, so move it under their uid.
  Future<void> _migrateLegacyKeys() async {
    final legacyPin = await _store.read(_kPin);
    if (legacyPin == null) return;
    if (await _store.read(_key(_kPin)!) == null) {
      for (final base in _allKeys) {
        final value = await _store.read(base);
        if (value != null) await _store.write(_key(base)!, value);
      }
      _logger.info(_tag, 'Moved PIN to per-patient storage');
    }
    for (final base in _allKeys) {
      await _store.delete(base);
    }
  }

  /// Forgets the lock in memory only, keeping it saved on the phone so it
  /// comes back when the same patient signs in again. Used by sign-out.
  void forget() {
    _pinRecord = null;
    _biometricsEnabled = false;
    _failedAttempts = 0;
    _locked = false;
    _logger.info(_tag, 'Forgotten until next sign-in');
    notifyListeners();
  }

  /// Whether [pin] has the right shape (exactly [pinLength] digits).
  static bool isValidPin(String pin) =>
      pin.length == pinLength && RegExp(r'^\d+$').hasMatch(pin);

  /// Why [pin] is too easy to guess (all one digit, or a straight run such
  /// as 1234 / 9876), or null when it's fine. Shown while choosing a PIN.
  static String? weakPinReason(String pin) {
    if (!isValidPin(pin)) return 'Use $pinLength digits.';
    final digits = pin.split('').map(int.parse).toList();

    /// True when every digit is the previous one plus [step].
    bool goesUpBy(int step) {
      for (var i = 1; i < digits.length; i++) {
        if (digits[i] - digits[i - 1] != step) return false;
      }
      return true;
    }

    final allSameDigit = goesUpBy(0); // 0000, 7777
    final countsUp = goesUpBy(1); // 1234, 6789
    final countsDown = goesUpBy(-1); // 4321, 9876
    if (allSameDigit || countsUp || countsDown) {
      return 'That PIN is too easy to guess. Try another.';
    }
    return null;
  }

  /// Whether to offer setting up the lock right after [uid] signs in: only
  /// when it's off and this patient hasn't chosen "Not now" on this phone.
  /// Never throws (a storage failure just means "offer it").
  Future<bool> shouldOfferSetup(String uid) async {
    if (isEnabled) return false;
    try {
      return await _store.read(_offerDismissedKey(uid)) != 'true';
    } catch (e, st) {
      _logger.warn(_tag, 'Reading the setup-offer choice failed', null, e, st);
      return true;
    }
  }

  /// Remembers "Not now" for [uid] on this phone, so the offer isn't shown
  /// at every sign-in. Kept on sign-out on purpose (unlike the PIN itself).
  Future<void> dismissSetupOffer(String uid) async {
    _logger.info(_tag, 'Setup offer dismissed');
    await _writeQuietly(_offerDismissedKey(uid), 'true');
  }

  static String _offerDismissedKey(String uid) => 'lock_offer_dismissed_$uid';

  /// Turns the lock on, or changes the PIN. Throws [ArgumentError] for a
  /// malformed PIN, [StateError] when nobody is signed in, and rethrows a
  /// storage failure so the caller can tell the patient it wasn't saved.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('The PIN must be $pinLength digits');
    }
    if (!_isSignedIn()) throw StateError('No patient signed in');
    final record = PinHasher.create(pin);
    await _write(_key(_kPin), record);
    await _write(_key(_kFailed), '0');
    _pinRecord = record;
    _failedAttempts = 0;
    _logger.info(_tag, 'PIN set');
    notifyListeners();
  }

  /// Turns the lock off and deletes the signed-in patient's PIN and
  /// fingerprint choice from the phone. Used by Settings and by "Forgot
  /// PIN" (not by a normal sign-out, see [forget]). Never throws: a failed
  /// delete is logged. [uid] deletes that patient's lock instead, for
  /// right after they were signed out.
  Future<void> disable({String reason = 'settings', String? uid}) async {
    uid ??= _currentUid();
    final wasEnabled = isEnabled;
    _pinRecord = null;
    _biometricsEnabled = false;
    _failedAttempts = 0;
    _locked = false;
    for (final base in _allKeys) {
      if (uid == null) break;
      final key = '${base}_$uid';
      try {
        await _store.delete(key);
      } catch (e, st) {
        _logger.error(_tag, 'Storage write failed', {'key': key}, e, st);
      }
    }
    if (wasEnabled) _logger.info(_tag, 'PIN removed', {'reason': reason});
    notifyListeners();
  }

  /// Checks [pin]. A correct PIN unlocks the app and resets the wrong-PIN
  /// count. A wrong one is counted (and saved); at [maxAttempts] the result
  /// is [PinCheck.tooManyAttempts] and the caller must sign the patient out.
  Future<PinCheck> verifyPin(String pin) async {
    final record = _pinRecord;
    if (record == null) return PinCheck.correct; // lock is off
    if (_failedAttempts >= maxAttempts) return PinCheck.tooManyAttempts;

    if (PinHasher.verify(pin, record)) {
      await _resetFailedAttempts();
      _unlock('pin');
      return PinCheck.correct;
    }

    _failedAttempts++;
    await _writeQuietly(_key(_kFailed), '$_failedAttempts');
    _logger.warn(_tag, 'Wrong PIN', {'failedAttempts': _failedAttempts});
    notifyListeners();
    if (_failedAttempts >= maxAttempts) {
      _logger.warn(_tag, 'Too many wrong PINs');
      return PinCheck.tooManyAttempts;
    }
    return PinCheck.wrong;
  }

  /// Whether this phone has fingerprint/face unlock set up. Never throws.
  Future<bool> biometricsAvailable() async {
    try {
      return await _biometrics.isAvailable();
    } catch (e, st) {
      _logger.warn(_tag, 'Biometric check failed', null, e, st);
      return false;
    }
  }

  /// Asks for the fingerprint/face. On success, unlocks the app (when
  /// [unlockOnSuccess]) and resets the wrong-PIN count.
  Future<BiometricResult> authenticateWithBiometrics({
    required String reason,
    bool unlockOnSuccess = true,
  }) async {
    final BiometricResult result;
    try {
      result = await _biometrics.authenticate(reason);
    } catch (e, st) {
      _logger.error(_tag, 'Biometric prompt crashed', null, e, st);
      return BiometricResult.error;
    }
    _logger.info(_tag, 'Biometric result', {'result': result.name});
    if (result == BiometricResult.success) {
      await _resetFailedAttempts();
      if (unlockOnSuccess) _unlock('biometric');
    }
    return result;
  }

  /// Turns the fingerprint shortcut on or off (Settings checks the finger
  /// first). Rethrows a storage failure.
  Future<void> setBiometricsEnabled(bool on) async {
    await _write(_key(_kBiometrics), on ? 'true' : 'false');
    _biometricsEnabled = on;
    _logger.info(_tag, 'Biometrics ${on ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  /// Locks the app now if the lock is on and someone is signed in. Returns
  /// whether it is locked.
  bool lockIfEnabled(String reason) {
    if (!isEnabled || !_isSignedIn()) return false;
    if (!_locked) {
      _locked = true;
      _logger.info(_tag, 'Locked', {'reason': reason});
      notifyListeners();
    }
    return true;
  }

  /// Starts watching the app going to and coming back from the background.
  /// Call once the first real screen is showing (after the splash).
  void arm() {
    _armed = true;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  /// Lock screens call these so only one is shown at a time.
  void lockViewShown() => _lockViewsShowing++;
  void lockViewHidden() => _lockViewsShowing = max(0, _lockViewsShowing - 1);

  /// Whether being away from [since] until [now] requires the PIN again.
  @visibleForTesting
  static bool awayLongEnough(DateTime since, DateTime now) =>
      !now.difference(since).isNegative &&
      now.difference(since) >= relockAfter;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Keep the first time: hidden then paused is one trip away.
        _backgroundedAt ??= _clock();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (!_armed || since == null) return;
        final now = _clock();
        if (awayLongEnough(since, now)) {
          if (lockIfEnabled('resume')) {
            _logger.info(_tag, 'Away long enough to relock', {
              'awayS': now.difference(since).inSeconds,
            });
          }
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Inactive = a system dialog (e.g. the fingerprint prompt) on top;
        // the app is still in front, so it doesn't count as away.
        break;
    }
  }

  void _unlock(String method) {
    if (!_locked) return;
    _locked = false;
    _logger.info(_tag, 'Unlocked', {'method': method});
    notifyListeners();
  }

  Future<void> _resetFailedAttempts() async {
    if (_failedAttempts == 0) return;
    _failedAttempts = 0;
    await _writeQuietly(_key(_kFailed), '0');
  }

  Future<void> _write(String? key, String value) async {
    if (key == null) throw StateError('No patient signed in');
    try {
      await _store.write(key, value);
    } catch (e, st) {
      _logger.error(_tag, 'Storage write failed', {'key': key}, e, st);
      rethrow;
    }
  }

  /// For values whose loss is harmless for this run (the attempt counter).
  Future<void> _writeQuietly(String? key, String value) async {
    if (key == null) return;
    try {
      await _store.write(key, value);
    } catch (e, st) {
      // The in-memory value still applies for this run.
      _logger.warn(_tag, 'Storage write failed', {'key': key}, e, st);
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Result of [AppLockService.verifyPin].
enum PinCheck { correct, wrong, tooManyAttempts }

/// Result of a fingerprint/face prompt.
enum BiometricResult {
  success,

  /// The finger/face wasn't recognised.
  failed,

  /// The patient closed the prompt (or the system did).
  cancelled,

  /// No fingerprint/face set up on this phone, or no sensor.
  unavailable,

  /// Too many tries; the phone blocks the sensor for a while.
  lockedOut,
  error,
}

/// Salted, stretched PIN hashes, stored as `v1$<iterations>$<salt>$<hash>`
/// (salt and hash base64). A 4-digit PIN has only 10,000 values, so the
/// hash alone can't stop a determined attacker who has the stored file; the
/// real protection is that the file is encrypted by the Android Keystore
/// and readable only by this app. The stretching just makes a leaked copy
/// slower to try.
class PinHasher {
  static const int iterations = 20000;

  static String create(String pin, {Random? random}) {
    final rng = random ?? Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final hash = _hash(pin, salt, iterations);
    return 'v1\$$iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  static bool isValidRecord(String record) => _parse(record) != null;

  static bool verify(String pin, String record) {
    final parsed = _parse(record);
    if (parsed == null) return false;
    final actual = _hash(pin, parsed.salt, parsed.iterations);
    return _constantTimeEquals(actual, parsed.hash);
  }

  static List<int> _hash(String pin, List<int> salt, int rounds) {
    var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
    for (var i = 1; i < rounds; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return digest;
  }

  static ({int iterations, List<int> salt, List<int> hash})? _parse(
    String record,
  ) {
    final parts = record.split(r'$');
    if (parts.length != 4 || parts[0] != 'v1') return null;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1 || rounds > 1000000) return null;
    try {
      return (
        iterations: rounds,
        salt: base64Decode(parts[2]),
        hash: base64Decode(parts[3]),
      );
    } on FormatException {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Where the lock keeps its values; replaced by an in-memory map in tests.
abstract class AppLockStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed storage (flutter_secure_storage).
class SecureAppLockStore implements AppLockStore {
  SecureAppLockStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Fingerprint/face unlock; replaced by a fake in tests.
abstract class BiometricAuth {
  Future<bool> isAvailable();
  Future<BiometricResult> authenticate(String reason);
}

/// The phone's fingerprint/face unlock (local_auth). Biometric only: the
/// app's own PIN is the fallback, not the phone's screen-lock PIN.
class LocalBiometricAuth implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (!await _auth.canCheckBiometrics) return false;
    return (await _auth.getAvailableBiometrics()).isNotEmpty;
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress => BiometricResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricResult.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => BiometricResult.lockedOut,
        _ => BiometricResult.error,
      };
    }
  }
}
