import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const [uid, universityId] = process.argv.slice(2);
if (!uid || !universityId || universityId.includes('/')) {
  console.error(
    'Usage: npm run promote-admin -- <firebase-auth-uid> <university-document-id>',
  );
  process.exit(2);
}

const projectId = process.env.GCLOUD_PROJECT || 'attendai-ec4cd';
initializeApp({ credential: applicationDefault(), projectId });

const auth = getAuth();
const firestore = getFirestore();
const [user, profile, university] = await Promise.all([
  auth.getUser(uid),
  firestore.collection('users').doc(uid).get(),
  firestore.collection('universities').doc(universityId).get(),
]);

if (!user.emailVerified) {
  throw new Error('The admin account must verify its email before promotion.');
}
if (!profile.exists || profile.data()?.universityId !== universityId) {
  throw new Error(
    'The user profile must exist and use this exact universityId first.',
  );
}
if (!university.exists) {
  throw new Error(
    `Create universities/${universityId} in Firestore before promotion.`,
  );
}

const existingClaims = user.customClaims ?? {};
await auth.setCustomUserClaims(uid, {
  ...existingClaims,
  universityAdmin: true,
  universityId,
});

const batch = firestore.batch();
batch.set(firestore.doc(`universities/${universityId}/members/${uid}`), {
  status: 'active',
  role: 'admin',
  approvedBy: uid,
  approvedAt: FieldValue.serverTimestamp(),
});
batch.update(profile.ref, { status: 'approved' });
await batch.commit();

console.log(`Promoted ${user.email ?? uid} as admin of ${universityId}.`);
console.log('Sign out and sign back in on the app to refresh the admin claim.');
