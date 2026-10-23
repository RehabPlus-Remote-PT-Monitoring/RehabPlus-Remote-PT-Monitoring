// Tests for ../../firestore.rules, run against the Firestore emulator:
//
//   cd tool/rules-test && npm install && npm test
//
// Needs Java and the Firebase CLI. Uses a demo project id, so it never touches
// the real rehabplus-80675 project.
//
// Cast: admin "adm", therapists "thA" and "thB", front desk "desk",
// patient "p1" (therapist thA), patient "p2" (therapist thB), and "stranger",
// a Firebase login with no users/ or patients/ document.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  deleteDoc,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rehabplus',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/adm'), { role: 'admin' });
    await setDoc(doc(db, 'users/thA'), { role: 'therapist' });
    await setDoc(doc(db, 'users/thB'), { role: 'therapist' });
    await setDoc(doc(db, 'users/desk'), { role: 'staff' });
    await setDoc(doc(db, 'users/p1'), { role: 'patient' });
    await setDoc(doc(db, 'users/p2'), { role: 'patient' });
    const patient = (therapistId) => ({
      name: 'Pat', email: 'p@x.com', therapistId, therapistName: 'Dr', archived: false,
      createdBy: 'adm', condition: 'Knee',
    });
    await setDoc(doc(db, 'patients/p1'), patient('thA'));
    await setDoc(doc(db, 'patients/p2'), patient('thB'));
    await setDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForStaff: 2, unreadForPatient: 0 });
    await setDoc(doc(db, 'patients/p1/threads/clinic'), { unreadForStaff: 0, unreadForPatient: 0 });
    await setDoc(doc(db, 'patients/p1/sessions/s1'), { exerciseId: 'x' });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

// Like Session.toFirestore() in the app, which always sends painNote (or null).
const session = () => ({
  exerciseId: 'knee_ext', startTime: Timestamp.now(), completedReps: 5, painLevel: 2,
  painNote: null, createdAt: serverTimestamp(),
});

const message = (senderId, senderRole) => ({
  text: 'hi', senderId, senderRole, sentAt: Timestamp.now(), createdAt: serverTimestamp(),
});

// The exact batch ChatService.send() commits in the app.
function patientSend(db, uid, thread, unread = increment(1)) {
  const t = doc(db, `patients/${uid}/threads/${thread}`);
  return writeBatch(db)
    .set(doc(db, `patients/${uid}/threads/${thread}/messages/m${Math.random()}`), message(uid, 'patient'))
    .set(t, { lastMessage: 'hi', lastMessageAt: Timestamp.now(), lastSenderRole: 'patient', unreadForStaff: unread }, { merge: true })
    .commit();
}

describe('1. a login with no patient profile can store nothing', () => {
  test('stranger cannot create sessions, messages, threads, avatar, devices, consent, prefs', async () => {
    const db = as('stranger');
    await assertFails(setDoc(doc(db, 'patients/stranger/sessions/s'), session()));
    await assertFails(patientSend(db, 'stranger', 'clinic'));
    await assertFails(setDoc(doc(db, 'patients/stranger/threads/clinic'), { unreadForPatient: 0 }));
    await assertFails(setDoc(doc(db, 'patients/stranger/avatar/photo'), { image: Bytes.fromUint8Array(new Uint8Array([1])), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, 'patients/stranger/devices/tok'), { token: 'tok', platform: 'android', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, 'patients/stranger/consents/v1'), {
      version: 'v1', acceptedTerms: true, acceptedPrivacyPolicy: true, healthDataConsent: true,
      cameraConsent: true, acceptedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db, 'patients/stranger/preferences/notifications'), {
      messages: true, exercises: true, updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db, 'patients/stranger'), { name: 'Me' }));
  });

  test('stranger cannot read anyone', async () => {
    const db = as('stranger');
    await assertFails(getDoc(doc(db, 'patients/p1')));
    await assertFails(getDoc(doc(db, 'patients/p1/sessions/s1')));
    await assertFails(getDoc(doc(db, 'users/p1')));
  });

  test('a real patient still can (what the app does)', async () => {
    const db = as('p1');
    await assertSucceeds(setDoc(doc(db, 'patients/p1/sessions/new'), session()));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/devices/tok'), { token: 'tok', platform: 'android', updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/avatar/photo'), { image: Bytes.fromUint8Array(new Uint8Array([1])), updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/preferences/notifications'), {
      messages: true, exercises: false, updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(db, 'patients/p1'), { phone: '0917' }));
  });

  test('device platform must be android or ios', async () => {
    const db = as('p1');
    await assertSucceeds(setDoc(doc(db, 'patients/p1/devices/t2'), { token: 't2', platform: 'ios', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, 'patients/p1/devices/t3'), { token: 't3', platform: { a: 'x' }, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, 'patients/p1/devices/t4'), { token: 't4', updatedAt: serverTimestamp() }));
  });
});

describe('patients only reach their own data', () => {
  test('p2 cannot read or write p1', async () => {
    const db = as('p2');
    await assertFails(getDoc(doc(db, 'patients/p1')));
    await assertFails(getDoc(doc(db, 'patients/p1/sessions/s1')));
    await assertFails(setDoc(doc(db, 'patients/p1/sessions/x'), session()));
    await assertFails(patientSend(db, 'p1', 'therapist'));
  });

  test('patient cannot reassign themselves or change their role', async () => {
    const db = as('p1');
    await assertFails(updateDoc(doc(db, 'patients/p1'), { therapistId: 'thB' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { archived: true }));
    await assertFails(setDoc(doc(db, 'users/p1'), { role: 'admin' }));
  });

  test('sessions and messages cannot be edited or deleted', async () => {
    const db = as('p1');
    await assertFails(updateDoc(doc(db, 'patients/p1/sessions/s1'), { completedReps: 99 }));
    await assertFails(deleteDoc(doc(db, 'patients/p1/sessions/s1')));
  });
});

describe('therapists only reach their own patients (IDOR)', () => {
  test('thB cannot read, edit or delete thA\'s patient', async () => {
    const db = as('thB');
    await assertFails(getDoc(doc(db, 'patients/p1')));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { condition: 'x' }));
    await assertFails(deleteDoc(doc(db, 'patients/p1')));
    await assertFails(getDoc(doc(db, 'patients/p1/sessions/s1')));
    await assertFails(setDoc(doc(db, 'patients/p1/prescriptions/rx'), { exerciseId: 'x' }));
    await assertFails(setDoc(doc(db, 'patients/p1/threads/therapist/messages/m'), message('thB', 'staff')));
  });

  test('thA can read and manage their own patient', async () => {
    const db = as('thA');
    await assertSucceeds(getDoc(doc(db, 'patients/p1')));
    await assertSucceeds(updateDoc(doc(db, 'patients/p1'), { condition: 'ACL' }));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/prescriptions/rx'), { exerciseId: 'x' }));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/threads/therapist/messages/m'), message('thA', 'staff')));
  });

  test('no therapist can delete a patient; only admins', async () => {
    await assertFails(deleteDoc(doc(as('thA'), 'patients/p1')));
    await assertSucceeds(deleteDoc(doc(as('adm'), 'patients/p1')));
  });

  test('front desk staff get nothing through the app', async () => {
    await assertFails(getDoc(doc(as('desk'), 'patients/p1')));
  });
});

describe('2. only admins change assignment, archiving and identity', () => {
  test('thA cannot hand p1 to another therapist, archive, or change identity', async () => {
    const db = as('thA');
    await assertFails(updateDoc(doc(db, 'patients/p1'), { therapistId: 'thB' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { therapistName: 'Someone' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { archived: true }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { email: 'new@x.com' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { createdBy: 'thA' }));
  });

  test('admin can reassign', async () => {
    await assertSucceeds(updateDoc(doc(as('adm'), 'patients/p1'), { therapistId: 'thB', therapistName: 'Dr B' }));
  });

  test('thA edits only the dashboard form fields, with its limits', async () => {
    const db = as('thA');
    await assertSucceeds(updateDoc(doc(db, 'patients/p1'), {
      name: 'Pat L', condition: 'ACL', medicalSummary: 'ok', therapyPlan: 'plan', phone: '0917', dob: '1990-01-01',
      updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { role: 'admin' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { junk: 'x' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { medicalSummary: 'x'.repeat(2001) }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { condition: { a: 1 } }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { name: '' }));
  });
});

describe('3. therapists stay out of the clinic thread', () => {
  test('therapist cannot post in, edit or delete the clinic thread', async () => {
    const db = as('thA');
    await assertFails(setDoc(doc(db, 'patients/p1/threads/clinic/messages/m'), message('thA', 'staff')));
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/clinic'), { unreadForPatient: 5 }));
    await assertFails(deleteDoc(doc(db, 'patients/p1/threads/clinic')));
  });

  test('therapist can still use their own thread but not delete it', async () => {
    const db = as('thA');
    await assertSucceeds(updateDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForStaff: 0 }));
    await assertFails(deleteDoc(doc(db, 'patients/p1/threads/therapist')));
  });

  test('admin can use the clinic thread', async () => {
    const db = as('adm');
    await assertSucceeds(setDoc(doc(db, 'patients/p1/threads/clinic/messages/m'), message('adm', 'staff')));
    await assertSucceeds(updateDoc(doc(db, 'patients/p1/threads/clinic'), { unreadForPatient: 1 }));
  });

  test('threads other than therapist/clinic are refused', async () => {
    await assertFails(setDoc(doc(as('adm'), 'patients/p1/threads/other'), { unreadForPatient: 0 }));
  });

  test('therapist cannot read the clinic thread or its messages; patient and admin can', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), 'patients/p1/threads/clinic/messages/c1'), message('p1', 'patient')));
    await assertFails(getDoc(doc(as('thA'), 'patients/p1/threads/clinic')));
    await assertFails(getDoc(doc(as('thA'), 'patients/p1/threads/clinic/messages/c1')));
    await assertSucceeds(getDoc(doc(as('thA'), 'patients/p1/threads/therapist')));
    await assertSucceeds(getDoc(doc(as('p1'), 'patients/p1/threads/clinic/messages/c1')));
    await assertSucceeds(getDoc(doc(as('adm'), 'patients/p1/threads/clinic/messages/c1')));
  });
});

describe('4. patients can only add one to the staff unread count', () => {
  test('the app\'s send batch works on existing and new threads', async () => {
    const db = as('p1');
    await assertSucceeds(patientSend(db, 'p1', 'therapist'));
    await assertSucceeds(patientSend(db, 'p1', 'therapist'));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = await getDoc(doc(ctx.firestore(), 'patients/p1/threads/therapist'));
      if (d.data().unreadForStaff !== 4) throw new Error(`expected 4, got ${d.data().unreadForStaff}`);
    });
    await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'patients/p1/threads/clinic')));
    await assertSucceeds(patientSend(db, 'p1', 'clinic'));
  });

  test('markRead (unreadForPatient = 0) works, also on a new thread', async () => {
    const db = as('p1');
    await assertSucceeds(setDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForPatient: 0 }, { merge: true }));
    await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'patients/p1/threads/clinic')));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/threads/clinic'), { unreadForPatient: 0 }, { merge: true }));
  });

  test('setting it to any other number is refused', async () => {
    const db = as('p1');
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForStaff: 0 }));
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForStaff: 9999 }));
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForStaff: increment(5) }));
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { unreadForPatient: 3 }));
  });

  test('lastMessageAt must be a timestamp; patient cannot post as staff', async () => {
    const db = as('p1');
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { lastMessageAt: 'yesterday' }));
    await assertFails(updateDoc(doc(db, 'patients/p1/threads/therapist'), { lastSenderRole: 'staff' }));
    await assertFails(setDoc(doc(db, 'patients/p1/threads/therapist/messages/m'), message('p1', 'staff')));
  });
});

describe('5. goals: patients read their own, nobody writes through the app', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'patients/p1/goals/g1'), {
        title: 'Walk 1 km', status: 'active', progress: 40,
      });
    });
  });

  test('the patient and their therapist can read p1\'s goals', async () => {
    await assertSucceeds(getDoc(doc(as('p1'), 'patients/p1/goals/g1')));
    await assertSucceeds(getDoc(doc(as('thA'), 'patients/p1/goals/g1')));
    await assertSucceeds(getDoc(doc(as('adm'), 'patients/p1/goals/g1')));
  });

  test('other patients, other therapists, front desk and strangers cannot', async () => {
    for (const uid of ['p2', 'thB', 'desk', 'stranger']) {
      await assertFails(getDoc(doc(as(uid), 'patients/p1/goals/g1')));
    }
  });

  test('nobody can create, edit or delete a goal from the app', async () => {
    for (const uid of ['p1', 'thA', 'adm']) {
      await assertFails(setDoc(doc(as(uid), 'patients/p1/goals/g2'), { title: 'x' }));
      await assertFails(updateDoc(doc(as(uid), 'patients/p1/goals/g1'), { progress: 100 }));
      await assertFails(deleteDoc(doc(as(uid), 'patients/p1/goals/g1')));
    }
  });

  test('assessments and notes stay clinic-only', async () => {
    await assertFails(getDoc(doc(as('p1'), 'patients/p1/assessments/a1')));
    await assertFails(getDoc(doc(as('p1'), 'patients/p1/notes/n1')));
  });
});

describe('6. push preferences: the clinic-reminder switch', () => {
  const prefs = (extra) => ({ messages: true, exercises: true, updatedAt: serverTimestamp(), ...extra });

  test('the app can save reminders on/off, and older app versions without it still work', async () => {
    const db = as('p1');
    await assertSucceeds(setDoc(doc(db, 'patients/p1/preferences/notifications'), prefs({ reminders: false })));
    await assertSucceeds(setDoc(doc(db, 'patients/p1/preferences/notifications'), prefs({})));
  });

  test('reminders must be a bool, and no other new fields are accepted', async () => {
    const db = as('p1');
    await assertFails(setDoc(doc(db, 'patients/p1/preferences/notifications'), prefs({ reminders: 'no' })));
    await assertFails(setDoc(doc(db, 'patients/p1/preferences/notifications'), prefs({ marketing: true })));
  });
});

describe('7. sessions: every field the dashboard shows is type- and size-checked', () => {
  // The exact shape ExerciseSession.toFirestore() writes after a camera session.
  const appSession = (extra = {}) => ({
    exerciseId: 'kneeExtension', exerciseName: 'Knee Extension', prescriptionId: 'rx1',
    startTime: Timestamp.now(), endTime: Timestamp.now(), completedReps: 9, completedSets: 1,
    targetReps: 10, targetSets: 1, repComplianceScores: [1, 1, 0, 1], overallCompliance: 0.75,
    notes: '1 rep(s) rejected for poor form or range', rejectedReps: 1, painLevel: 3,
    painNote: null, outsideSchedule: false, endedEarly: true, createdAt: serverTimestamp(), ...extra,
  });
  const add = (extra) => setDoc(doc(as('p1'), `patients/p1/sessions/n${Math.random()}`), appSession(extra));

  test('what the app writes is accepted, including unassigned practice and an empty session', async () => {
    await assertSucceeds(add({}));
    await assertSucceeds(add({ prescriptionId: null, notes: null, endTime: null, repComplianceScores: [], overallCompliance: 0 }));
    await assertSucceeds(add({ overallCompliance: 1 })); // whole number, still a valid score
    await assertSucceeds(setDoc(doc(as('p1'), 'patients/p1/sessions/min'), session())); // older, minimal shape
  });

  test('a map or list where text is expected is refused (it broke the dashboard page)', async () => {
    await assertFails(add({ exerciseName: { a: 'b' } }));
    await assertFails(add({ prescriptionId: ['x'] }));
    await assertFails(add({ notes: { a: 1 } }));
    await assertFails(add({ exerciseId: '' }));
  });

  test('oversized text is refused', async () => {
    await assertFails(add({ exerciseName: 'x'.repeat(101) }));
    await assertFails(add({ notes: 'x'.repeat(2001) }));
    await assertFails(add({ exerciseId: 'x'.repeat(101) }));
  });

  test('counts must be whole numbers from 0 to 10000', async () => {
    await assertFails(add({ completedReps: 2000000000 }));
    await assertFails(add({ targetReps: -1 }));
    await assertFails(add({ rejectedReps: { x: 1 } }));
    await assertFails(add({ completedSets: 1.5 }));
    await assertSucceeds(add({ completedReps: 10000 }));
  });

  test('scores, flags and times must have the right type and range', async () => {
    await assertFails(add({ overallCompliance: 5 }));
    await assertFails(add({ overallCompliance: 'high' }));
    await assertFails(add({ repComplianceScores: 'all good' }));
    await assertFails(add({ endedEarly: 'yes' }));
    await assertFails(add({ outsideSchedule: 1 }));
    await assertFails(add({ endTime: 'later' }));
  });

  test('a start time more than an hour in the future is refused; past ones (offline) are fine', async () => {
    const at = (ms) => Timestamp.fromMillis(Date.now() + ms);
    await assertFails(add({ startTime: Timestamp.fromDate(new Date('2099-01-01')) }));
    await assertSucceeds(add({ startTime: at(30 * 60 * 1000), endTime: at(40 * 60 * 1000) })); // phone clock 30 min fast
    await assertSucceeds(add({ startTime: at(-3 * 24 * 3600 * 1000) })); // queued offline for days
  });

  test('an end time far in the future or before the start is refused', async () => {
    const at = (ms) => Timestamp.fromMillis(Date.now() + ms);
    await assertFails(add({ endTime: Timestamp.fromDate(new Date('2099-01-01')) }));
    await assertFails(add({ startTime: at(-60 * 1000), endTime: at(-10 * 60 * 1000) }));
  });
});

describe('8. chat times from the phone cannot be far in the future', () => {
  const future = Timestamp.fromDate(new Date('2099-01-01'));

  test('a message dated 2099 is refused', async () => {
    await assertFails(setDoc(doc(as('p1'), 'patients/p1/threads/therapist/messages/late'),
      { ...message('p1', 'patient'), sentAt: future }));
  });

  test('pinning the thread to the top with a 2099 lastMessageAt is refused', async () => {
    await assertFails(updateDoc(doc(as('p1'), 'patients/p1/threads/therapist'), { lastMessageAt: future }));
  });

  test('the normal send batch and a slightly fast phone clock still work', async () => {
    await assertSucceeds(patientSend(as('p1'), 'p1', 'therapist'));
    await assertSucceeds(setDoc(doc(as('p1'), 'patients/p1/threads/therapist/messages/fast'),
      { ...message('p1', 'patient'), sentAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000) }));
  });
});
