package com.rehabplus.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity): local_auth needs a
// FragmentActivity to show the system fingerprint/face prompt used by
// Settings > App lock.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessageChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerCastChannel(flutterEngine)
    }

    // "Cast screen" button on the exercise screen
    // (lib/services/cast_service.dart). The patient stands 2-3 m from the
    // phone, too far to read the rep counter, so the button opens Android's
    // screen-cast settings to mirror the phone to a TV or laptop.
    //
    // There is no public API to start a cast directly, so we open the
    // settings page and the patient picks the TV there. Phone brands name
    // and hide this page differently, so we try the official action first,
    // then the older Wi-Fi Display page some brands still ship. We try
    // startActivity and catch "not found" rather than resolveActivity(),
    // because Android 11+ package visibility can hide the Settings app from
    // resolveActivity() even when the page exists.
    //
    // Returns the action that opened, or null if none did (the Dart side
    // then shows written instructions instead).
    private fun registerCastChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAST_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openCastSettings" -> result.success(openCastSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun openCastSettings(): String? {
        val actions = listOf(
            Settings.ACTION_CAST_SETTINGS,
            // Hidden pre-Lollipop name; some brands still route it.
            "android.settings.WIFI_DISPLAY_SETTINGS",
        )
        for (action in actions) {
            try {
                startActivity(Intent(action))
                return action
            } catch (e: ActivityNotFoundException) {
                Log.w(TAG, "Cast settings page not available: $action")
            } catch (e: SecurityException) {
                Log.w(TAG, "Cast settings page not allowed: $action", e)
            }
        }
        return null
    }

    private companion object {
        const val CAST_CHANNEL = "com.rehabplus.app/cast"
        const val TAG = "RehabPlusCast"
    }

    // High importance so chat notifications pop up on screen. Without it FCM
    // falls back to a default-importance "Miscellaneous" channel that only
    // shows quietly in the shade. The id must match
    // default_notification_channel_id in AndroidManifest.xml and the
    // android.notification.channelId the server sends.
    private fun createMessageChannel() {
        val channel = NotificationChannel(
            "chat_messages",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Replies from your therapist and the clinic"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
