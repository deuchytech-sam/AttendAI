import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const projectId = 'demo-attendai-course-assignment';
const rules = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: process.env.FIRESTORE_EMULATOR_HOST?.split(':')[0] ?? '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':')[1] ?? 8080),
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const members = [
      ['admin-1', { status: 'active', role: 'admin' }],
      ['claim-only-admin', { status: 'active', role: 'admin' }],
      ['lecturer-1', { status: 'active', role: 'lecturer' }],
      ['lecturer-2', { status: 'active', role: 'lecturer' }],
      ['lecturer-stale-profile', { status: 'active', role: 'lecturer' }],
      ['inactive-lecturer', { status: 'inactive', role: 'lecturer' }],
      ['student-1', { status: 'active', role: 'student', courseIds: ['course-1'] }],
    ];
    for (const [uid, data] of members) {
      await setDoc(doc(db, 'universities/uni-1/members', uid), data);
    }
    await setDoc(doc(db, 'users/admin-1'), {
      uid: 'admin-1',
      universityId: 'uni-1',
      status: 'approved',
      requestedRole: 'admin',
    });
    await setDoc(doc(db, 'users/lecturer-1'), {
      uid: 'lecturer-1',
      universityId: 'uni-1',
      status: 'approved',
      requestedRole: 'lecturer',
    });
    await setDoc(doc(db, 'users/lecturer-stale-profile'), {
      uid: 'lecturer-stale-profile',
      universityId: 'old-university-id',
      status: 'pending',
      requestedRole: 'lecturer',
      displayName: 'Lecturer With Legacy Profile',
    });
    await setDoc(doc(db, 'users/pending-student'), {
      uid: 'pending-student',
      universityId: 'uni-1',
      status: 'pending',
      requestedRole: 'student',
    });
    await setDoc(doc(db, 'universities/uni-1/courses/course-1'), {
      id: 'course-1',
      name: 'Biology',
      lecturer: 'Legacy display name',
      lecturerIds: ['lecturer-1'],
      schedule: 'Monday',
      createdBy: 'admin-1',
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'universities/uni-1/courses/course-2'), {
      id: 'course-2',
      name: 'Chemistry',
      lecturer: '',
      lecturerIds: ['lecturer-2'],
      schedule: 'Tuesday',
      createdBy: 'admin-1',
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'universities/uni-1/attendanceSessions/session-1'), {
      id: 'session-1',
      courseId: 'course-1',
      status: 'open',
      openedBy: 'lecturer-1',
      openedAt: new Date(),
    });
    for (let index = 2; index <= 12; index += 1) {
      const sessionId = `session-${index}`;
      await setDoc(
        doc(db, `universities/uni-1/attendanceSessions/${sessionId}`),
        {
          id: sessionId,
          courseId: 'course-1',
          status: 'closed',
          openedBy: 'lecturer-1',
          openedAt: new Date(),
        },
      );
      await setDoc(
        doc(db, `universities/uni-1/attendanceRecords/legacy-${index}`),
        { sessionId, studentId: 'roster-1', studentUid: 'student-1' },
      );
    }
    await setDoc(doc(db, 'universities/uni-1/students/roster-1'), {
      id: 'roster-1',
      name: 'Student One',
      matricNumber: 'M1',
      courseId: 'course-1',
      userId: 'student-1',
    });
    await setDoc(doc(db, 'universities/uni-1/attendanceRecords/record-1'), {
      courseId: 'course-1',
      sessionId: 'session-1',
      studentId: 'roster-1',
      studentUid: 'student-1',
    });
    await setDoc(doc(db, 'universities/uni-1/attendanceRecords/legacy-record'), {
      sessionId: 'session-1',
      studentId: 'roster-1',
      studentUid: 'student-1',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const courseRef = (uid) =>
  doc(testEnv.authenticatedContext(uid).firestore(), 'universities/uni-1/courses/course-1');
const sessionRef = (uid) =>
  doc(testEnv.authenticatedContext(uid).firestore(), 'universities/uni-1/attendanceSessions/session-1');
const recordRef = (uid, recordId = 'record-1') =>
  doc(testEnv.authenticatedContext(uid).firestore(), `universities/uni-1/attendanceRecords/${recordId}`);

describe('course lecturer assignments', () => {
  it('allows users to read their own profile and admins to read university profiles', async () => {
    const adminDb = testEnv.authenticatedContext('admin-1').firestore();
    await assertSucceeds(getDoc(doc(adminDb, 'users/admin-1')));
    await assertSucceeds(getDoc(doc(adminDb, 'users/lecturer-1')));
    await assertSucceeds(
      getDoc(doc(adminDb, 'users/lecturer-stale-profile')),
    );
    await assertFails(
      getDoc(
        doc(
          testEnv.authenticatedContext('student-1').firestore(),
          'users/lecturer-1',
        ),
      ),
    );
    const pending = await assertSucceeds(
      getDocs(
        query(
          collection(adminDb, 'users'),
          where('universityId', '==', 'uni-1'),
          where('status', '==', 'pending'),
        ),
      ),
    );
    assert.deepEqual(pending.docs.map((user) => user.id), ['pending-student']);
  });

  it('allows a member to update only their own FCM token fields', async () => {
    const member = doc(
      testEnv.authenticatedContext('admin-1').firestore(),
      'universities/uni-1/members/admin-1',
    );
    await assertSucceeds(
      updateDoc(member, {
        fcmToken: 'test-token',
        tokenUpdatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(member, {
        fcmToken: 'another-token',
        role: 'lecturer',
        tokenUpdatedAt: serverTimestamp(),
      }),
    );
  });

  it('allows admins to list eligible lecturer memberships', async () => {
    const db = testEnv.authenticatedContext('admin-1').firestore();
    const lecturers = await assertSucceeds(
      getDocs(
        query(
          collection(db, 'universities/uni-1/members'),
          where('status', '==', 'active'),
          where('role', '==', 'lecturer'),
        ),
      ),
    );
    assert.deepEqual(
      lecturers.docs.map((member) => member.id).sort(),
      ['lecturer-1', 'lecturer-2', 'lecturer-stale-profile'],
    );
  });

  it('allows admins to query registered approved lecturer profiles by university', async () => {
    const db = testEnv.authenticatedContext('admin-1').firestore();
    const profiles = await assertSucceeds(
      getDocs(
        query(
          collection(db, 'users'),
          where('universityId', '==', 'uni-1'),
          where('status', '==', 'approved'),
          where('requestedRole', '==', 'lecturer'),
        ),
      ),
    );
    assert.deepEqual(profiles.docs.map((profile) => profile.id), ['lecturer-1']);
  });

  it('allows an admin claim to read active member profiles without reading the admin profile', async () => {
    const db = testEnv.authenticatedContext('claim-only-admin', {
      universityAdmin: true,
      universityId: 'uni-1',
    }).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'users/lecturer-stale-profile')),
    );
  });

  it('allows an admin to assign active lecturers', async () => {
    await assertSucceeds(
      updateDoc(courseRef('admin-1'), { lecturerIds: ['lecturer-1', 'lecturer-2'] }),
    );
    const snapshot = await assertSucceeds(getDoc(courseRef('lecturer-1')));
    assert.deepEqual(snapshot.data().lecturerIds, ['lecturer-1', 'lecturer-2']);
    await assertSucceeds(
      updateDoc(courseRef('admin-1'), {
        lecturerIds: ['lecturer-stale-profile'],
      }),
    );
  });

  it('rejects assignments to inactive or non-lecturer members', async () => {
    await assertFails(
      updateDoc(courseRef('admin-1'), { lecturerIds: ['inactive-lecturer'] }),
    );
    await assertFails(
      updateDoc(courseRef('admin-1'), { lecturerIds: ['student-1'] }),
    );
  });

  it('does not allow a lecturer to edit lecturerIds', async () => {
    await assertFails(
      updateDoc(courseRef('lecturer-1'), { lecturerIds: ['lecturer-1'] }),
    );
  });

  it('allows an admin to create a course with lecturer assignments', async () => {
    const ref = doc(
      testEnv.authenticatedContext('admin-1').firestore(),
      'universities/uni-1/courses/course-3',
    );
    await assertSucceeds(
      setDoc(ref, {
        id: 'course-3',
        name: 'Chemistry',
        lecturer: '',
        lecturerIds: ['lecturer-1'],
        schedule: 'Tuesday',
        createdBy: 'admin-1',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('allows the admin course-save transaction to read assigned lecturers and write the course', async () => {
    const db = testEnv.authenticatedContext('admin-1').firestore();
    const course = doc(db, 'universities/uni-1/courses/transaction-course');
    const lecturer = doc(
      db,
      'universities/uni-1/members/lecturer-1',
    );
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        const [currentCourse, member] = await Promise.all([
          transaction.get(course),
          transaction.get(lecturer),
        ]);
        assert.equal(currentCourse.exists(), false);
        assert.equal(member.data().status, 'active');
        assert.equal(member.data().role, 'lecturer');
        transaction.set(course, {
          id: 'transaction-course',
          name: 'Physics',
          lecturer: '',
          lecturerIds: ['lecturer-1'],
          schedule: 'Wednesday',
          createdBy: 'admin-1',
          createdAt: serverTimestamp(),
        });
      }),
    );

    const existingCourse = doc(
      db,
      'universities/uni-1/courses/course-1',
    );
    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        await transaction.get(existingCourse);
        await transaction.get(lecturer);
        transaction.update(existingCourse, {
          name: 'Biology Updated',
          schedule: 'Thursday',
          lecturerIds: ['lecturer-1'],
        });
      }),
    );
  });

  it('returns only assigned courses in a lecturer dashboard query', async () => {
    for (const [uid, expectedCourseId] of [
      ['lecturer-1', 'course-1'],
      ['lecturer-2', 'course-2'],
    ]) {
      const db = testEnv.authenticatedContext(uid).firestore();
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collection(db, 'universities/uni-1/courses'),
            where('lecturerIds', 'array-contains', uid),
          ),
        ),
      );
      assert.deepEqual(snapshot.docs.map((course) => course.id), [expectedCourseId]);
    }
  });

  it('prevents lecturers from creating courses or roster entries', async () => {
    const db = testEnv.authenticatedContext('lecturer-1').firestore();
    await assertFails(
      setDoc(doc(db, 'universities/uni-1/courses/lecturer-course'), {
        id: 'lecturer-course',
        name: 'Unauthorized',
        lecturer: 'Legacy name',
        schedule: '',
        createdBy: 'lecturer-1',
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, 'universities/uni-1/students/lecturer-roster'), {
        id: 'lecturer-roster',
        name: 'Unauthorized Student',
        matricNumber: 'X1',
        courseId: 'course-1',
        createdBy: 'lecturer-1',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('allows only assigned lecturers to read and update course attendance sessions', async () => {
    await assertSucceeds(getDoc(sessionRef('lecturer-1')));
    await assertFails(getDoc(sessionRef('lecturer-2')));
    await assertSucceeds(
      updateDoc(sessionRef('lecturer-1'), {
        status: 'closed',
        closedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(sessionRef('lecturer-2'), {
        status: 'closed',
        closedAt: serverTimestamp(),
      }),
    );
  });

  it('allows only assigned lecturers to read current and legacy attendance records', async () => {
    await assertSucceeds(getDoc(recordRef('lecturer-1')));
    await assertSucceeds(getDoc(recordRef('lecturer-1', 'legacy-record')));
    await assertFails(getDoc(recordRef('lecturer-2')));
    await assertFails(getDoc(recordRef('lecturer-2', 'legacy-record')));
  });

  it('allows attendance history queries only for assigned course sessions', async () => {
    const assignedDb = testEnv.authenticatedContext('lecturer-1').firestore();
    const unassignedDb = testEnv.authenticatedContext('lecturer-2').firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(assignedDb, 'universities/uni-1/attendanceRecords'),
          where('sessionId', '==', 'session-1'),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          collection(unassignedDb, 'universities/uni-1/attendanceRecords'),
          where('sessionId', '==', 'session-1'),
        ),
      ),
    );
  });

  it('allows lecturers to load legacy attendance records one assigned session at a time', async () => {
    const db = testEnv.authenticatedContext('lecturer-1').firestore();
    const records = collection(db, 'universities/uni-1/attendanceRecords');
    for (let index = 1; index <= 12; index += 1) {
      const result = await assertSucceeds(
        getDocs(query(records, where('sessionId', '==', `session-${index}`))),
      );
      assert.equal(result.empty, false);
    }
  });

  it('allows students to query their own attendance history', async () => {
    const db = testEnv.authenticatedContext('student-1').firestore();
    const records = await assertSucceeds(
      getDocs(
        query(
          collection(db, 'universities/uni-1/attendanceRecords'),
          where('studentUid', '==', 'student-1'),
        ),
      ),
    );
    assert.equal(records.size, 13);
  });

  it('allows class roster queries only to lecturers assigned to that course', async () => {
    const assignedDb = testEnv.authenticatedContext('lecturer-1').firestore();
    const unassignedDb = testEnv.authenticatedContext('lecturer-2').firestore();
    const rosterQuery = (db) =>
      query(
        collection(db, 'universities/uni-1/students'),
        where('courseId', 'in', ['course-1']),
      );
    const roster = await assertSucceeds(getDocs(rosterQuery(assignedDb)));
    assert.deepEqual(roster.docs.map((student) => student.id), ['roster-1']);
    await assertFails(getDocs(rosterQuery(unassignedDb)));
  });

  it('keeps students limited to their own enrolled course documents', async () => {
    await assertSucceeds(getDoc(courseRef('student-1')));
    await assertFails(
      getDoc(
        doc(
          testEnv.authenticatedContext('student-1').firestore(),
          'universities/uni-1/courses/course-2',
        ),
      ),
    );
    await assertFails(getDoc(courseRef('lecturer-2')));
  });
});
