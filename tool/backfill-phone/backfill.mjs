// Copies each patient's `phone` (patients/{uid}) onto their Auth login as
// `phoneNumber`, so the app's "Forgot password" texts a code to it.
//
// Usage (from tool/backfill-phone/):
//   npm install
//   node backfill.mjs <path-to-service-account.json>          dry run (default)
//   node backfill.mjs <path-to-service-account.json> --apply  writes the changes
//
// The dry run reads everything and prints what --apply would do; it writes
// nothing. Archived patients are skipped. A number used by two patients is
// skipped for both, since Firebase Auth allows one login per number.
//
// NEVER commit the service-account JSON.

import { readFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const keyPath = args.find((a) => !a.startsWith('--'));
const apply = args.includes('--apply');
if (!keyPath) {
  console.error('Usage: node backfill.mjs <service-account.json> [--apply]');
  process.exit(1);
}

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) });
const auth = getAuth();
const db = getFirestore();

// Same rules as toE164 in lib/services/auth_service.dart.
function toE164(input) {
  const cleaned = input.replace(/[\s\-().]/g, '');
  if (/^\+\d{8,15}$/.test(cleaned)) return cleaned;
  if (/^09\d{9}$/.test(cleaned)) return `+63${cleaned.slice(1)}`;
  if (/^639\d{9}$/.test(cleaned)) return `+${cleaned}`;
  if (/^9\d{9}$/.test(cleaned)) return `+63${cleaned}`;
  return null;
}

const snapshot = await db.collection('patients').get();

const candidates = [];
const skipped = [];
for (const doc of snapshot.docs) {
  const data = doc.data();
  const label = data.email ?? doc.id;
  if (data.archived === true) {
    skipped.push({ label, reason: 'archived' });
    continue;
  }
  const raw = typeof data.phone === 'string' ? data.phone.trim() : '';
  if (raw === '') {
    skipped.push({ label, reason: 'no phone in patients doc' });
    continue;
  }
  const phone = toE164(raw);
  if (phone === null) {
    skipped.push({ label, reason: `phone not recognised: "${raw}"` });
    continue;
  }
  candidates.push({ uid: doc.id, label, phone });
}

// Numbers used by more than one patient can't go on two logins.
const byPhone = new Map();
for (const c of candidates) {
  byPhone.set(c.phone, [...(byPhone.get(c.phone) ?? []), c]);
}
const duplicated = [...byPhone.values()].filter((list) => list.length > 1).flat();
const duplicatedUids = new Set(duplicated.map((c) => c.uid));
for (const c of duplicated) {
  skipped.push({ label: c.label, reason: `number ${c.phone} is shared by several patients` });
}

const planned = [];
for (const c of candidates.filter((c) => !duplicatedUids.has(c.uid))) {
  let user;
  try {
    user = await auth.getUser(c.uid);
  } catch {
    skipped.push({ label: c.label, reason: 'no Auth login with this uid' });
    continue;
  }
  if (user.phoneNumber === c.phone) {
    skipped.push({ label: c.label, reason: 'already set' });
    continue;
  }
  if (user.phoneNumber) {
    skipped.push({ label: c.label, reason: `Auth already has ${user.phoneNumber}; not changed` });
    continue;
  }
  planned.push(c);
}

console.log(`Patients read: ${snapshot.size}`);
console.log(`To set: ${planned.length}`);
for (const c of planned) console.log(`  ${c.label} -> ${c.phone}`);
console.log(`Skipped: ${skipped.length}`);
for (const s of skipped) console.log(`  ${s.label}: ${s.reason}`);

if (!apply) {
  console.log('\nDry run only. Re-run with --apply to write these numbers.');
  process.exit(0);
}

let done = 0;
for (const c of planned) {
  try {
    await auth.updateUser(c.uid, { phoneNumber: c.phone });
    done += 1;
  } catch (e) {
    console.error(`Failed for ${c.label}: ${e.code ?? e.message}`);
  }
}
console.log(`\nWrote ${done} of ${planned.length}.`);
