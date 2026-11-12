import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { planCourseLecturerMigration } from './course_lecturer_matching.mjs';

const apply = process.argv.includes('--apply');
const dryRun = process.argv.includes('--dry-run');
if (apply && dryRun) throw new Error('Choose either --dry-run or --apply.');
const universityArg = process.argv.find((arg) => arg.startsWith('--university='));
const selectedUniversityId = universityArg?.split('=', 2)[1];
const projectId = process.env.GCLOUD_PROJECT || 'attendai-ec4cd';

initializeApp({ credential: applicationDefault(), projectId });
const firestore = getFirestore();

const universities = selectedUniversityId
  ? [await firestore.collection('universities').doc(selectedUniversityId).get()]
  : (await firestore.collection('universities').get()).docs;
const report = [];

for (const university of universities) {
  if (!university.exists) {
    report.push({ universityId: selectedUniversityId, status: 'university-not-found' });
    continue;
  }
  const universityId = university.id;
  const [courseSnapshot, lecturerMembers] = await Promise.all([
    firestore.collection(`universities/${universityId}/courses`).get(),
    firestore
      .collection(`universities/${universityId}/members`)
      .where('status', '==', 'active')
      .where('role', '==', 'lecturer')
      .get(),
  ]);

  const lecturers = [];
  for (const member of lecturerMembers.docs) {
    const profile = await firestore.collection('users').doc(member.id).get();
    const displayName = profile.data()?.displayName;
    if (profile.exists && typeof displayName === 'string' && displayName.trim()) {
      lecturers.push({ uid: member.id, displayName });
    }
  }

  for (const course of courseSnapshot.docs) {
    const data = course.data();
    const plan = planCourseLecturerMigration(data, lecturers);
    const entry = {
      universityId,
      courseId: course.id,
      courseName: data.name ?? '',
      legacyLecturer: data.lecturer ?? '',
      ...plan,
    };
    if (plan.status === 'matched' && (!apply || dryRun)) {
      entry.status = 'would-assign';
    }
    if (plan.status === 'matched' && apply) {
      const applied = await firestore.runTransaction(async (transaction) => {
        const current = await transaction.get(course.ref);
        const currentIds = current.data()?.lecturerIds;
        if (
          (Array.isArray(currentIds) && currentIds.length > 0) ||
          (currentIds != null &&
            !Array.isArray(currentIds) &&
            String(currentIds).trim().length > 0)
        ) return false;
        transaction.update(course.ref, { lecturerIds: plan.lecturerIds });
        return true;
      });
      entry.status = applied ? 'assigned' : 'already-assigned';
    }
    report.push(entry);
  }
}

console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry-run', report }, null, 2));
