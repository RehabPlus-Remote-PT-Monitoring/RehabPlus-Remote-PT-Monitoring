import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../core/app_keys.dart';
import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../screens/messages_screen.dart';

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
class PushService {
  PushService._();
  static final PushService I = PushService._();

  final _logger = DiagnosticLogger.I;
  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _token;
  bool _listening = false;

  /// Call once at startup, after Firebase.initializeApp.
  void listen() {
    if (_listening) return;
    _listening = true;

    FirebaseMessaging.onMessage.listen(_showInApp);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    // App launched by tapping a notification while it was closed: kept until
    // the startup splash hands over (see [openLaunchMessage]); opening it
    // earlier would put the chat under the splash's replacement route.
    _launchMessage = _fm.getInitialMessage();
  }

  Future<RemoteMessage?>? _launchMessage;

  /// Opens the notification that launched the app, if any. Called by the
  /// splash once the first real screen is showing.
  Future<void> openLaunchMessage() async {
    final m = await _launchMessage;
    _launchMessage = null;
    if (m != null) _open(m);
  }

  /// Asks for permission (Android 13+) and saves this device's token for the
  /// signed-in patient. Call after sign-in and at startup when signed in.
  Future<void> registerForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final settings = await _fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _logger.info('PushService', 'Notification permission denied');
        return;
      }
      // ignore: deprecated_member_use
      final token = await _fm.getToken();
      if (token != null) await _save(uid, token);

      await _tokenRefreshSub?.cancel();
      // ignore: deprecated_member_use
      _tokenRefreshSub = _fm.onTokenRefresh.listen((t) async {
        final current = FirebaseAuth.instance.currentUser?.uid;
        if (current == null) return;
        if (_token != null && _token != t) await _delete(current, _token!);
        await _save(current, t);
      });
    } catch (e) {
      // No Play Services, no network, etc. Messaging still works in-app.
      _logger.warn('PushService', 'Registration failed', {
        'error': e.toString(),
      });
    }
  }

  /// Stops pushes to this device. Call before signing out (needs auth to
  /// delete the token doc).
  Future<void> unregister() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    _token = null;
    try {
      if (uid != null && token != null) await _delete(uid, token);
      // ignore: deprecated_member_use
      await _fm.deleteToken();
    } catch (e) {
      _logger.warn('PushService', 'Unregister failed', {'error': e.toString()});
    }
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid, String token) =>
      FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .collection('devices')
          .doc(token);

  Future<void> _save(String uid, String token) async {
    _token = token;
    await _doc(uid, token).set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logger.info('PushService', 'Device token saved');
  }

  Future<void> _delete(String uid, String token) => _doc(uid, token).delete();

  ChatThread? _threadOf(RemoteMessage m) {
    if (m.data['type'] != 'chat') return null;
    return ChatThread.values
        .where((t) => t.name == m.data['thread'])
        .firstOrNull;
  }

  void _open(RemoteMessage m) {
    final thread = _threadOf(m);
    if (thread == null || FirebaseAuth.instance.currentUser == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ChatDetailScreen(thread: thread)),
    );
  }

  void _showInApp(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    final thread = _threadOf(m);
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
