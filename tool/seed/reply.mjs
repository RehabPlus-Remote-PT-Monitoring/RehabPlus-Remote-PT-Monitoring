// Sends a staff reply to a patient and pushes a notification to their phone.
//
// Use it to demo messaging before the Laravel dashboard can reply, and as the
// reference for what the dashboard must do (see API_CONTRACT.md, "Push
// notifications").
//
// Usage (from tool/seed/):
//   node reply.mjs <service-account.json> <patient-email> <therapist|clinic> "<message>"
//
// NEVER commit the service-account JSON.

import { readFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

const [keyPath, patientEmail, threadId, text] = process.argv.slice(2);
if (!keyPath || !patientEmail || !['therapist', 'clinic'].includes(threadId) || !text) {
  console.error('Usage: node reply.mjs <service-account.json> <patient-email> <therapist|clinic> "<message>"');
  process.exit(1);
}

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) });
const db = getFirestore();
const patient = await getAuth().getUserByEmail(patientEmail);
const patientDoc = db.doc(`patients/${patient.uid}`);

// 1. Write the message and update the thread summary in one batch.
const thread = patientDoc.collection('threads').doc(threadId);
const now = Timestamp.now();
const p = (await patientDoc.get()).data() ?? {};
const batch = db.batch();
batch.create(thread.collection('messages').doc(), {
  text,
  senderId: threadId === 'therapist' ? (p.therapistId ?? 'clinic') : 'clinic',
  senderRole: 'staff',
  sentAt: now,
  createdAt: FieldValue.serverTimestamp(),
});
batch.set(thread, {
  lastMessage: text,
  lastMessageAt: now,
  lastSenderRole: 'staff',
  unreadForPatient: FieldValue.increment(1),
}, { merge: true });
await batch.commit();
console.log(`Message written to ${patientEmail}'s ${threadId} thread.`);

// 2. List it on the app's Notifications page (even if no phone gets the push).
const title = threadId === 'therapist'
  ? (p.therapistName || 'Your therapist')
  : 'RehabPlus Clinic';
const body = text.length > 120 ? `${text.slice(0, 117)}...` : text;
await patientDoc.collection('notifications').add({
  type: 'message',
  title: `Message from ${title}`,
  body,
  data: { thread: threadId },
  read: false,
  createdAt: FieldValue.serverTimestamp(),
});

// 3. Push to every registered device.
const devices = await patientDoc.collection('devices').get();
const tokens = devices.docs.map((d) => d.id);
if (tokens.length === 0) {
  console.log('No devices registered (patient never signed in on a phone, or denied notifications). No push sent.');
  process.exit(0);
}

const res = await getMessaging().sendEachForMulticast({
  tokens,
  notification: { title, body },
  data: { type: 'chat', thread: threadId },
  android: { priority: 'high', notification: { channelId: 'chat_messages' } },
});
console.log(`Push sent: ${res.successCount} delivered, ${res.failureCount} failed.`);

// 4. Remove tokens FCM says are dead (app uninstalled, data cleared, ...).
const DEAD = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);
for (const [i, r] of res.responses.entries()) {
  if (r.success) continue;
  if (DEAD.has(r.error?.code)) {
    await patientDoc.collection('devices').doc(tokens[i]).delete();
    console.log('  removed stale device token');
  } else {
    console.log(`  failure: ${r.error?.code} ${r.error?.message}`);
  }
}
