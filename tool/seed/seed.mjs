// Seeds Firestore with a test patient and prescriptions.
//
// Usage (from tool/seed/):
//   npm install
//   node seed.mjs <path-to-service-account.json> <patient-email> [therapist-email]
//
// The patient (and optional therapist) must already exist in
// Firebase Console → Authentication → Users. Safe to re-run: documents are
// overwritten, sessions are left alone.
//
// NEVER commit the service-account JSON.

import { readFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

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

console.log(`Seeded patient ${patientEmail} (${patient.uid}) with ${Object.keys(prescriptions).length} prescriptions.`);
if (therapist) console.log(`Therapist ${therapistEmail} (${therapist.uid}) assigned.`);
