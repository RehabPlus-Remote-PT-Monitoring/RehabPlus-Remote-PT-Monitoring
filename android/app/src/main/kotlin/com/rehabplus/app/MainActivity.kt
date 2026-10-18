package com.rehabplus.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): local_auth needs a
// FragmentActivity to show the system fingerprint/face prompt used by
// Settings > App lock.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessageChannel()
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
