// Seeds Firestore with a test patient and prescriptions.
//
// Usage (from tool/seed/):
//   npm install
//   node seed.mjs <path-to-service-account.json> <patient-email> [therapist-email]
//
// Optional: CLINIC_PHONE="+63 2 1234 5678" node seed.mjs ...  sets the number
// the app's call button dials (settings/clinic).
//
// The patient (and optional therapist) must already exist in
// Firebase Console → Authentication → Users. Safe to re-run: documents are
// overwritten, sessions are left alone, and the welcome message is only
// posted once.
//
// NEVER commit the service-account JSON.

import { readFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';

const [keyPath, patientEmail, therapistEmail] = process.argv.slice(2);
if (!keyPath || !patientEmail) {
  console.error('Usage: node seed.mjs <service-account.json> <patient-email> [therapist-email]');
  process.exit(1);
}

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) });
const auth = getAuth();
const db = getFirestore();

const patient = await auth.getUserByEmail(patientEmail);
const therapist = therapistEmail ? await auth.getUserByEmail(therapistEmail) : null;

if (therapist) {
  await db.doc(`users/${therapist.uid}`).set({
    role: 'therapist',
    name: therapist.displayName ?? therapistEmail,
    email: therapistEmail,
  });
}

await db.doc(`users/${patient.uid}`).set({
  role: 'patient',
  name: patient.displayName ?? 'Test Patient',
  email: patientEmail,
});

await db.doc(`patients/${patient.uid}`).set({
  name: patient.displayName ?? 'Test Patient',
  condition: 'MCL sprain, post-acute',
  therapistId: therapist?.uid ?? null,
  // Denormalised so the patient app can show it (patients can't read
  // other users' profiles).
  therapistName: therapist ? (therapist.displayName ?? therapistEmail) : '',
  phone: '',
  dob: '',
  medicalSummary: 'Seeded test patient.',
  therapyPlan: 'Home program: knee extension, bicep curl, side raise.',
  createdAt: FieldValue.serverTimestamp(),
});

// exerciseType must match an ExerciseType enum name in
// lib/models/exercise_model.dart. schedule.days uses 1 = Mon … 7 = Sun.
const prescriptions = {
  knee_extension: {
    exerciseType: 'kneeExtension',
    targetReps: 10,
    frequencyPerWeek: 5,
    schedule: { days: [1, 2, 3, 4, 5], startHour: 6, endHour: 20 },
    notes: 'Hold the straight knee for a moment at the top.',
  },
  bicep_curl: {
    exerciseType: 'bicepCurl',
    targetReps: 12,
    frequencyPerWeek: 3,
    schedule: { days: [1, 3, 5] },
    notes: 'Keep your elbow tucked to your side.',
  },
  side_raise: {
    exerciseType: 'sideRaise',
    targetReps: 8,
    frequencyPerWeek: 3,
    notes: 'Stop at shoulder height.',
  },
};

const col = db.collection(`patients/${patient.uid}/prescriptions`);
for (const [id, p] of Object.entries(prescriptions)) {
  await col.doc(id).set({
    ...p,
    active: true,
    assignedBy: therapist?.uid ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

// "New exercise assigned" notifications. Fixed ids so re-running the seed
// doesn't duplicate them.
const NAMES = { kneeExtension: 'Knee Extension', bicepCurl: 'Bicep Curl', sideRaise: 'Side Raise' };
for (const [id, pr] of Object.entries(prescriptions)) {
  await db.doc(`patients/${patient.uid}/notifications/assigned_${id}`).set({
    type: 'exercise_assigned',
    title: 'New Exercise Assigned',
    body: `Your therapist assigned ${NAMES[pr.exerciseType] ?? pr.exerciseType}: ${pr.targetReps} reps, ${pr.frequencyPerWeek}x a week.`,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

// Clinic contact details for the app's call button.
const clinic = { name: 'Rehab Plus Physiotherapy' };
if (process.env.CLINIC_PHONE) clinic.phone = process.env.CLINIC_PHONE;
await db.doc('settings/clinic').set(clinic, { merge: true });

// A welcome message from the therapist so the Messages screen isn't empty.
const thread = db.doc(`patients/${patient.uid}/threads/therapist`);
if (!(await thread.get()).exists) {
  const text = 'Hi! Your home exercise program is ready in the app. ' +
    'Message me here if anything hurts or you have questions.';
  const now = Timestamp.now();
  await thread.collection('messages').add({
    text,
    senderId: therapist?.uid ?? 'clinic',
    senderRole: 'staff',
    sentAt: now,
    createdAt: FieldValue.serverTimestamp(),
  });
  await thread.set({
    lastMessage: text,
    lastMessageAt: now,
    lastSenderRole: 'staff',
    unreadForPatient: 1,
    unreadForStaff: 0,
  });
}

console.log(`Seeded patient ${patientEmail} (${patient.uid}) with ${Object.keys(prescriptions).length} prescriptions.`);
if (therapist) console.log(`Therapist ${therapistEmail} (${therapist.uid}) assigned.`);
console.log(clinic.phone ? `Clinic phone set to ${clinic.phone}.` : 'Clinic phone not set (pass CLINIC_PHONE=... to set it).');
