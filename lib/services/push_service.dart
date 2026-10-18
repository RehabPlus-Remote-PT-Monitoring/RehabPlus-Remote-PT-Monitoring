import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../core/app_keys.dart';
import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../screens/messages_screen.dart';
import 'firestore_diagnostics.dart';

/// Push notifications (Firebase Cloud Messaging).
///
/// The device token is stored at patients/{uid}/devices/{token}; whoever
/// writes a staff reply (Laravel dashboard, or tool/seed/reply.mjs) sends the
/// push to those tokens. Payload `data`: {type: 'chat', thread: 'therapist' |
/// 'clinic'}.
///
/// While the app is in the background or closed, Android shows the
/// notification itself; tapping it opens the conversation. While the app is
/// open, a SnackBar is shown instead.
///
/// Uses FCM registration tokens (getToken/onTokenRefresh/deleteToken).
/// firebase_messaging 17 deprecates these in favour of Installation-ID
/// "direct send", but the server SDKs we send with (firebase-admin, and
/// Laravel via the FCM v1 API) address devices by token, so tokens stay.
///
/// Concurrency: registration awaits a permission prompt and two network
/// calls, so the patient can sign out (or another patient sign in) half-way.
/// Every [unregister] starts a new "registration generation"; a
/// registration or token-refresh from an older generation, or for a uid
/// that is no longer signed in, stops before writing anything.
///
/// Log events (tag 'PushService'). The token itself is never logged, only
/// `tokenHash` (a short hash, enough to tell whether a refresh changed it):
///   "Listening for messages"; "Registration started|done|abandoned|failed"
///   {uid, permission, generation}; "Device token saved|save failed"
///   {uid, tokenHash}; "Token refreshed" {tokenHash}; "Unregistered"
///   "Foreground message" {type, thread, hasNotification}; "Opening chat
///   from notification" {thread}; "Launch message" {present}
class PushService {
  PushService._();
  static final PushService I = PushService._();

  /// The rules only accept device doc ids (= tokens) shorter than this.
  static const int maxTokenLength = 1023;

  final _logger = DiagnosticLogger.I;
  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _token;
  bool _listening = false;

  /// Bumped by [unregister]; see the class comment.
  int _generation = 0;

  /// The registration in progress, so overlapping calls (startup + consent
  /// screen) share one run instead of racing to save the token twice.
  Future<void>? _registering;

  /// Call once at startup, after Firebase.initializeApp. Later calls are
  /// ignored. These subscriptions live as long as the app (this is a
  /// singleton), so they are intentionally never cancelled.
  void listen() {
    if (_listening) return;
    _listening = true;

    FirebaseMessaging.onMessage.listen(
      _showInApp,
      onError: (Object e, StackTrace st) => _logger.warn(
        'PushService',
        'onMessage stream error',
        firebaseErrorData(e),
        e,
        st,
      ),
    );
    FirebaseMessaging.onMessageOpenedApp.listen(
      _open,
      onError: (Object e, StackTrace st) => _logger.warn(
        'PushService',
        'onMessageOpenedApp stream error',
        firebaseErrorData(e),
        e,
        st,
      ),
    );
    // App launched by tapping a notification while it was closed: kept until
    // the startup splash hands over (see [openLaunchMessage]); opening it
    // earlier would put the chat under the splash's replacement route.
    _launchMessage = _fm.getInitialMessage().then<RemoteMessage?>(
      (m) => m,
      onError: (Object e, StackTrace st) {
        _logger.warn('PushService', 'getInitialMessage failed',
            firebaseErrorData(e), e, st);
        return null;
      },
    );
    _logger.info('PushService', 'Listening for messages');
  }

  Future<RemoteMessage?>? _launchMessage;

  /// Opens the notification that launched the app, if any. Called by the
  /// splash once the first real screen is showing.
  Future<void> openLaunchMessage() async {
    final m = await _launchMessage;
    _launchMessage = null;
    _logger.info('PushService', 'Launch message', {'present': m != null});
    if (m != null) _open(m);
  }

  /// Asks for permission (Android 13+) and saves this device's token for the
  /// signed-in patient. Call after sign-in and at startup when signed in.
  /// Never throws: push is optional (no Play Services, offline, denied).
  Future<void> registerForCurrentUser() {
    final inFlight = _registering;
    if (inFlight != null) return inFlight;
    final run = _register();
    _registering = run;
    return run.whenComplete(() {
      if (identical(_registering, run)) _registering = null;
    });
  }

  Future<void> _register() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final generation = _generation;
    bool stale() =>
        generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != uid;
    final stopwatch = Stopwatch()..start();
    _logger.info('PushService', 'Registration started', {
      'uid': uid,
      'generation': generation,
    });

    try {
      final settings = await _fm.requestPermission();
      final permission = settings.authorizationStatus.name;
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _logger.info('PushService', 'Notification permission denied');
        return;
      }
      if (stale()) return _abandon(uid, 'after permission');

      // ignore: deprecated_member_use
      final token = await _fm.getToken();
      if (stale()) return _abandon(uid, 'after getToken');
      if (token == null) {
        _logger.warn('PushService', 'No FCM token available', {'uid': uid});
        return;
      }
      await _save(uid, token);
      // Signed out during the save: unregister() already saw `_token` and
      // queued the doc's deletion, so just don't start listening.
      if (stale()) return _abandon(uid, 'after save');

      await _tokenRefreshSub?.cancel();
      // ignore: deprecated_member_use
      _tokenRefreshSub = _fm.onTokenRefresh.listen(
        (t) => _onTokenRefresh(t, generation),
        onError: (Object e, StackTrace st) => _logger.warn(
          'PushService',
          'onTokenRefresh stream error',
          firebaseErrorData(e),
          e,
          st,
        ),
      );
      _logger.info('PushService', 'Registration done', {
        'uid': uid,
        'permission': permission,
        'ms': stopwatch.elapsedMilliseconds,
      });
    } catch (e, st) {
      // No Play Services, no network, etc. Messaging still works in-app.
      _logger.warn('PushService', 'Registration failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
    }
  }

  void _abandon(String uid, String stage) => _logger.info(
    'PushService',
    'Registration abandoned: user changed',
    {'uid': uid, 'stage': stage},
  );

  /// FCM rotated this device's token: replace the stored one. Ignored when
  /// it arrives after sign-out (older [generation]) or with nobody signed in.
  Future<void> _onTokenRefresh(String token, int generation) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || generation != _generation) {
      _logger.info('PushService', 'Token refresh ignored: signed out');
      return;
    }
    _logger.info('PushService', 'Token refreshed', {
      'tokenHash': _hash(token),
    });
    try {
      final old = _token;
      if (old != null && old != token) await _delete(uid, old);
      await _save(uid, token);
    } catch (e, st) {
      _logger.warn('PushService', 'Token refresh save failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
    }
  }

  /// Stops pushes to this device. Call before signing out (needs auth to
  /// delete the token doc). Never throws.
  Future<void> unregister() async {
    // First, so any registration still in flight stops before writing.
    _generation++;
    _registering = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    _token = null;
    try {
      if (uid != null && token != null) await _delete(uid, token);
      // ignore: deprecated_member_use
      await _fm.deleteToken();
      _logger.info('PushService', 'Unregistered', {
        'uid': uid,
        'hadToken': token != null,
      });
    } catch (e, st) {
      _logger.warn('PushService', 'Unregister failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
    }
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid, String token) =>
      FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .collection('devices')
          .doc(token);

  /// Awaited (unlike most writes): registration happens in the background
  /// anyway, and knowing it reached the server is what makes pushes work.
  Future<void> _save(String uid, String token) async {
    if (token.isEmpty || token.length > maxTokenLength || token.contains('/')) {
      // Would be rejected by the rules (or be an invalid doc id).
      _logger.warn('PushService', 'Unusable FCM token; not saved', {
        'length': token.length,
      });
      return;
    }
    _token = token;
    try {
      await _doc(uid, token).set({
        'token': token,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _logger.info('PushService', 'Device token saved', {
        'uid': uid,
        'tokenHash': _hash(token),
      });
    } catch (e, st) {
      _logger.warn('PushService', 'Device token save failed', {
        'uid': uid,
        ...firebaseErrorData(e),
      }, e, st);
      rethrow;
    }
  }

  Future<void> _delete(String uid, String token) => _doc(uid, token).delete();

  /// A short, non-reversible label for a token, so log lines about the same
  /// token can be matched up without the token itself being written down.
  static String _hash(String token) =>
      (token.hashCode & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  ChatThread? _threadOf(RemoteMessage m) {
    if (m.data['type'] != 'chat') return null;
    return ChatThread.tryParse(m.data['thread']);
  }

  void _open(RemoteMessage m) {
    final thread = _threadOf(m);
    if (thread == null || FirebaseAuth.instance.currentUser == null) {
      _logger.info('PushService', 'Notification tap not routed', {
        'type': m.data['type'],
        'signedIn': FirebaseAuth.instance.currentUser != null,
      });
      return;
    }
    _logger.info('PushService', 'Opening chat from notification', {
      'thread': thread.name,
    });
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ChatDetailScreen(thread: thread)),
    );
  }

  void _showInApp(RemoteMessage m) {
    final n = m.notification;
    final thread = _threadOf(m);
    // Payload routing fields only; the title/body are message content.
    _logger.info('PushService', 'Foreground message', {
      'type': m.data['type'],
      'thread': thread?.name,
      'hasNotification': n != null,
    });
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          [n.title, n.body].whereType<String>().join(': '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: thread == null
            ? null
            : SnackBarAction(label: 'View', onPressed: () => _open(m)),
      ),
    );
  }
}
