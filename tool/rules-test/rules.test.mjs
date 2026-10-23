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
