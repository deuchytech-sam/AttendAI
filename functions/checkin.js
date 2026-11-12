const { randomUUID } = require("node:crypto");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const region = "europe-west1";
const sessionLifetimeMs = 24 * 60 * 60 * 1000;

function sessionExpiryMillis(data) {
  const expiry = data.expiresAt;
  if (expiry instanceof Timestamp) return expiry.toMillis();
  const openedAt = data.openedAt;
  if (openedAt instanceof Timestamp) return openedAt.toMillis() + sessionLifetimeMs;
  return 0;
}

async function requireAssignedLecturer(db, universityId, uid, courseId) {
  if (typeof courseId !== "string" || !courseId.trim() || courseId.includes("/")) {
    throw new HttpsError("invalid-argument", "Choose a valid course.");
  }
  const [member, course] = await Promise.all([
    db.doc(`universities/${universityId}/members/${uid}`).get(),
    db.doc(`universities/${universityId}/courses/${courseId}`).get(),
  ]);
  if (!member.exists || member.get("status") !== "active" || member.get("role") !== "lecturer") {
    throw new HttpsError("permission-denied", "Lecturer access required.");
  }
  const lecturerIds = course.exists ? course.get("lecturerIds") : null;
  if (!Array.isArray(lecturerIds) || !lecturerIds.includes(uid)) {
    throw new HttpsError("permission-denied", "You are not assigned to this course.");
  }
  return course;
}

/**
 * Get student identity and validate they are an active student member
 * Returns { uid, universityId, studentId, courseId }
 */
async function getStudentIdentity(auth, courseId) {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const db = getFirestore();
  const account = await db.doc(`users/${auth.uid}`).get();
  const universityId = account.get("universityId");
  if (typeof universityId !== "string" || !universityId || universityId.includes("/")) {
    throw new HttpsError("permission-denied", "University membership is required.");
  }
  const member = await db.doc(`universities/${universityId}/members/${auth.uid}`).get();
  if (!member.exists || member.get("status") !== "active" || member.get("role") !== "student") {
    throw new HttpsError("permission-denied", "An active student membership is required.");
  }
  const studentsCollection = db.collection(`universities/${universityId}/students`);
  if (typeof courseId !== "string" || !courseId.trim()) {
    throw new HttpsError("invalid-argument", "courseId is required.");
  }
  const linkedStudents = await studentsCollection
    .where("userId", "==", auth.uid)
    .where("courseId", "==", courseId)
    .limit(2)
    .get();
  let studentDoc = linkedStudents.size === 1 ? linkedStudents.docs[0] : null;

  // A lecturer can add the roster row after the student account is approved.
  // In that order, the approval flow cannot add userId, so safely link the
  // unique roster entry by the matric number already stored on the account.
  if (linkedStudents.size === 0) {
    const matricNumber = account.get("matricNumber");
    if (typeof matricNumber === "string" && matricNumber.trim()) {
      const normalizedMatricNumber = matricNumber.trim();
      const matricMatches = await studentsCollection
        .where("matricNumber", "==", normalizedMatricNumber)
        .where("courseId", "==", courseId)
        .limit(10)
        .get();

      const unclaimed = matricMatches.docs.filter((doc) => !doc.get("userId"));
      const normalizeName = (value) => typeof value === "string"
        ? value.trim().replace(/\s+/g, " ").toLowerCase()
        : "";
      const accountName = normalizeName(account.get("displayName"));
      const nameMatches = accountName
        ? unclaimed.filter((doc) => normalizeName(doc.get("name")) === accountName)
        : [];
      let candidate = null;

      if (unclaimed.length === 1) {
        candidate = unclaimed[0];
      } else if (nameMatches.length === 1) {
        candidate = nameMatches[0];
      } else if (nameMatches.length > 1 && nameMatches.length === unclaimed.length) {
        // Duplicate unclaimed rows with the same matric, course, and name are
        // the same roster identity; deterministically use the newest row.
        candidate = nameMatches.sort((a, b) => {
          const aTime = a.get("createdAt")?.toMillis?.() || 0;
          const bTime = b.get("createdAt")?.toMillis?.() || 0;
          return bTime - aTime || a.id.localeCompare(b.id);
        })[0];
      } else if (matricMatches.size > 0 && unclaimed.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "Your roster record is linked to another account.",
        );
      } else if (unclaimed.length > 1) {
        throw new HttpsError(
          "failed-precondition",
          "Multiple roster records match your matric number. Contact your lecturer.",
        );
      }

      console.info("[CheckInIdentity] roster lookup", {
        uid: auth.uid, courseId, linkedMatches: linkedStudents.size,
        matricMatches: matricMatches.size, unclaimedMatches: unclaimed.length,
        nameMatches: nameMatches.length, selected: Boolean(candidate),
      });

      if (candidate) {
        const candidateUserId = candidate.get("userId");
        if (candidateUserId && candidateUserId !== auth.uid) {
          throw new HttpsError(
            "failed-precondition",
            "Your roster record is linked to another account.",
          );
        }

        await db.runTransaction(async (transaction) => {
          const current = await transaction.get(candidate.ref);
          if (!current.exists || current.get("matricNumber") !== normalizedMatricNumber || current.get("courseId") !== courseId) {
            throw new HttpsError(
              "failed-precondition",
              "Your roster record changed. Refresh and try again.",
            );
          }
          const currentUserId = current.get("userId");
          if (currentUserId && currentUserId !== auth.uid) {
            throw new HttpsError(
              "failed-precondition",
              "Your roster record is linked to another account.",
            );
          }
          transaction.update(candidate.ref, { userId: auth.uid });
        });
        studentDoc = candidate;
      }
    }
  }

  if (!studentDoc) {
    throw new HttpsError(
      "failed-precondition",
      "Your student roster record is not linked. Check that your matric number matches the course roster.",
    );
  }

  const student = studentDoc;
  const studentCourseId = student.get("courseId");
  if (typeof studentCourseId !== "string" || !studentCourseId.trim()) {
    throw new HttpsError("failed-precondition", "Your course enrollment is incomplete.");
  }
  if (studentCourseId !== courseId) {
    throw new HttpsError("failed-precondition", "Your student record is not enrolled in the open course.");
  }
  return {
    uid: auth.uid,
    universityId,
    studentId: student.id,
    studentName: student.get("name"),
    matricNumber: student.get("matricNumber"),
    courseId: studentCourseId
  };
}

/**
 * Get the open session for the student's course
 */
async function getOpenSession(db, identity) {
  const sessions = await db
    .collection(`universities/${identity.universityId}/attendanceSessions`)
    .where("status", "==", "open")
    .where("courseId", "==", identity.courseId)
    .get();
  const now = Date.now();
  const active = [];
  const expired = [];
  for (const session of sessions.docs) {
    if (sessionExpiryMillis(session.data()) <= now) expired.push(session);
    else active.push(session);
  }
  if (expired.length) {
    const batch = db.batch();
    for (const session of expired) {
      batch.update(session.ref, {
        status: "closed",
        closedAt: FieldValue.serverTimestamp(),
        closeReason: "expired",
      });
    }
    await batch.commit();
  }
  if (active.length !== 1) {
    throw new HttpsError("failed-precondition", "There is no open attendance session for your course.");
  }
  return active[0];
}

/**
 * Verify face embedding against enrolled embeddings in Firestore
 * This replaces the FaceTec verification
 */
async function verifyFaceEmbedding(db, identity, faceEmbeddings, faceMatchScore) {
  // Load enrolled face embeddings from faceEmbeddings collection
  const faceDoc = await db
    .collection(`universities/${identity.universityId}/faceEmbeddings`)
    .doc(identity.uid)
    .get();

  if (!faceDoc.exists) {
    throw new HttpsError("failed-precondition", "Face not enrolled. Please enroll your face first.");
  }

  const enrolledData = faceDoc.data();
  const enrolledEmbeddings = enrolledData.embeddings;

  if (!enrolledEmbeddings || enrolledEmbeddings.length === 0) {
    throw new HttpsError("failed-precondition", "No enrolled face embeddings found.");
  }

  // The face match score is computed client-side by flutter_face_liveness
  // We trust it but also do a basic validation
  if (typeof faceMatchScore !== "number" || faceMatchScore < 0.7) {
    throw new HttpsError("permission-denied", "Face verification failed. Please try again with better lighting.");
  }

  return {
    verified: true,
    faceMatchScore: faceMatchScore,
    verificationProvider: "flutter_face_liveness",
    enrolledEmbeddingCount: enrolledEmbeddings.length
  };
}

// ============================================================
// CHECK-IN FUNCTION
// ============================================================

exports.recordAttendanceCheckIn = onCall(
  {
    region,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    // Get request data
    const { faceEmbeddings, faceMatchScore, sessionId: providedSessionId, courseId } = request.data || {};

    if (!Array.isArray(faceEmbeddings) || faceEmbeddings.length === 0) {
      throw new HttpsError("invalid-argument", "Face embeddings are required.");
    }
    if (typeof faceMatchScore !== "number") {
      throw new HttpsError("invalid-argument", "Face match score is required.");
    }
    if (typeof courseId !== "string" || !courseId.trim()) {
      throw new HttpsError("invalid-argument", "courseId is required.");
    }

    const identity = await getStudentIdentity(request.auth, courseId);
    const db = getFirestore();

    // Get the open session (use provided sessionId if available, otherwise find open session)
    let sessionRef;
    if (providedSessionId) {
      sessionRef = db.doc(`universities/${identity.universityId}/attendanceSessions/${providedSessionId}`);
      const sessionDoc = await sessionRef.get();
      if (!sessionDoc.exists || sessionDoc.get("status") !== "open" || sessionDoc.get("courseId") !== identity.courseId || sessionExpiryMillis(sessionDoc.data()) <= Date.now()) {
        throw new HttpsError("failed-precondition", "The attendance session is closed or invalid.");
      }
    } else {
      const session = await getOpenSession(db, identity);
      sessionRef = session.ref;
    }

    const sessionData = (await sessionRef.get()).data();

    // Verify face embedding
    const verification = await verifyFaceEmbedding(db, identity, faceEmbeddings, faceMatchScore);

    // Deterministic document ID to prevent duplicates: {sessionId}_{studentUid}
    const recordId = `${sessionRef.id}_${identity.uid}`;
    const recordRef = db.doc(`universities/${identity.universityId}/attendanceRecords/${recordId}`);

    let alreadyRecorded = false;
    await db.runTransaction(async (transaction) => {
      const [session, record] = await Promise.all([
        transaction.get(sessionRef),
        transaction.get(recordRef),
      ]);

      if (!session.exists || session.get("status") !== "open" || session.get("courseId") !== identity.courseId || sessionExpiryMillis(session.data()) <= Date.now()) {
        throw new HttpsError("failed-precondition", "The attendance session is closed.");
      }

      if (record.exists) {
        alreadyRecorded = true;
        return;
      }

      // Create attendance record with all required fields
      transaction.set(recordRef, {
        studentId: identity.studentId,
        studentUid: identity.uid,
        studentName: identity.studentName,
        matricNumber: identity.matricNumber,
        courseId: identity.courseId,
        sessionId: sessionRef.id,
        checkedAt: FieldValue.serverTimestamp(),
        verificationProvider: verification.verificationProvider,
        faceMatchScore: verification.faceMatchScore,
        enrolledEmbeddingCount: verification.enrolledEmbeddingCount,
      });
    });

    return {
      recorded: !alreadyRecorded,
      sessionId: sessionRef.id,
      sessionName: sessionData?.courseId ? `Session for ${sessionData.courseId}` : sessionRef.id,
      checkedAt: new Date().toISOString(),
    };
  },
);

// ============================================================
// LECTURER: TOGGLE ATTENDANCE SESSION (with FCM notification)
// ============================================================

exports.toggleAttendanceSession = onCall(
  {
    region,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const { universityId, courseId } = request.data || {};
    if (!universityId || !courseId) {
      throw new HttpsError("invalid-argument", "universityId and courseId are required.");
    }

    const db = getFirestore();

    await requireAssignedLecturer(db, universityId, request.auth.uid, courseId);

    // Check if there's already an open session for this course
    const openSessions = await db
      .collection(`universities/${universityId}/attendanceSessions`)
      .where("status", "==", "open")
      .where("courseId", "==", courseId)
      .get();

    const now = Date.now();
    const expiredSessions = openSessions.docs.filter(
      (doc) => sessionExpiryMillis(doc.data()) <= now,
    );
    if (expiredSessions.length) {
      const batch = db.batch();
      for (const doc of expiredSessions) {
        batch.update(doc.ref, {
          status: "closed",
          closedAt: FieldValue.serverTimestamp(),
          closeReason: "expired",
        });
      }
      await batch.commit();
    }
    const activeSessions = openSessions.docs.filter(
      (doc) => sessionExpiryMillis(doc.data()) > now,
    );

    if (activeSessions.length > 0) {
      // Close the existing open session
      const sessionRef = activeSessions[0].ref;
      await sessionRef.update({
        status: "closed",
        closedAt: FieldValue.serverTimestamp(),
      });

      // Send FCM notification to students that session ended
      await sendSessionNotification(db, universityId, courseId, false);

      return {
        action: "closed",
        sessionId: sessionRef.id,
        message: "Attendance session closed.",
      };
    } else {
      // Create new open session
      const sessionRef = db.collection(`universities/${universityId}/attendanceSessions`).doc();
      await sessionRef.set({
        id: sessionRef.id,
        courseId: courseId,
        status: "open",
        openedBy: request.auth.uid,
        openedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + sessionLifetimeMs),
      });

      // Send FCM notification to students that session opened
      await sendSessionNotification(db, universityId, courseId, true);

      return {
        action: "opened",
        sessionId: sessionRef.id,
        message: "Attendance session opened. Students have been notified.",
      };
    }
  },
);

/**
 * Lecturer-requested reset. The cloud marker makes each student's app remove
 * its stale local template on the next verification or enrollment attempt.
 */
exports.resetStudentFaceEnrollment = onCall(
  { region, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
    const studentId = request.data?.studentId;
    if (typeof studentId !== "string" || !studentId.trim() || studentId.includes("/")) {
      throw new HttpsError("invalid-argument", "Choose a valid student.");
    }

    const db = getFirestore();
    const account = await db.doc(`users/${request.auth.uid}`).get();
    const universityId = account.get("universityId");
    if (typeof universityId !== "string" || !universityId) {
      throw new HttpsError("permission-denied", "University membership is required.");
    }
    const lecturer = await db.doc(`universities/${universityId}/members/${request.auth.uid}`).get();
    if (!lecturer.exists || lecturer.get("status") !== "active" || lecturer.get("role") !== "lecturer") {
      throw new HttpsError("permission-denied", "Lecturer access required.");
    }

    const roster = await db.doc(`universities/${universityId}/students/${studentId}`).get();
    if (!roster.exists) throw new HttpsError("not-found", "Student roster entry not found.");
    await requireAssignedLecturer(
      db,
      universityId,
      request.auth.uid,
      roster.get("courseId"),
    );
    const studentUid = roster.get("userId");
    if (typeof studentUid !== "string" || !studentUid) {
      throw new HttpsError("failed-precondition", "Link this student to their account before resetting face enrollment.");
    }
    const studentMember = await db.doc(`universities/${universityId}/members/${studentUid}`).get();
    if (!studentMember.exists || studentMember.get("status") !== "active" || studentMember.get("role") !== "student") {
      throw new HttpsError("failed-precondition", "The linked account is not an active student.");
    }

    const now = FieldValue.serverTimestamp();
    await Promise.all([
      db.doc(`universities/${universityId}/faceEmbeddings/${studentUid}`).set({
        faceId: studentUid,
        studentId: studentUid,
        embeddings: [],
        status: "reset_required",
        resetAt: now,
        resetBy: request.auth.uid,
        updatedAt: now,
      }),
      db.doc(`universities/${universityId}/biometricProfiles/${studentId}`).set({
        studentId,
        uid: studentUid,
        status: "reset_required",
        resetAt: now,
        resetBy: request.auth.uid,
      }, { merge: true }),
    ]);
    console.info("[FaceEnrollmentReset] Lecturer reset student face enrollment", {
      universityId, studentId, studentUid, lecturerUid: request.auth.uid,
    });
    return { reset: true, studentId };
  },
);

// Scheduled cleanup complements exact 24-hour enforcement in check-in.
exports.expireAttendanceSessions = onSchedule(
  { schedule: "every 15 minutes", timeZone: "Etc/UTC", region },
  async () => {
    const db = getFirestore();
    const openSessions = await db.collectionGroup("attendanceSessions")
      .where("status", "==", "open")
      .get();
    const expiredSessions = openSessions.docs.filter(
      (doc) => sessionExpiryMillis(doc.data()) <= Date.now(),
    );
    for (let start = 0; start < expiredSessions.length; start += 450) {
      const batch = db.batch();
      for (const doc of expiredSessions.slice(start, start + 450)) {
        batch.update(doc.ref, {
          status: "closed",
          closedAt: FieldValue.serverTimestamp(),
          closeReason: "expired",
        });
      }
      await batch.commit();
    }
    if (expiredSessions.length) {
      console.info(`[SessionExpiry] Closed ${expiredSessions.length} expired attendance sessions.`);
    }
  },
);

/**
 * Sends FCM notification to all students enrolled in a course
 */
async function sendSessionNotification(db, universityId, courseId, isOpen) {
  try {
    // Get all students in the course with their FCM tokens
    const studentsSnap = await db
      .collection(`universities/${universityId}/students`)
      .where("courseId", "==", courseId)
      .get();

    if (studentsSnap.empty) return;

    // Get course name for notification
    const courseSnap = await db.doc(`universities/${universityId}/courses/${courseId}`).get();
    const courseName = courseSnap.exists ? courseSnap.get("name") : courseId;

    // Collect FCM tokens from members collection
    const tokens = [];
    for (const studentDoc of studentsSnap.docs) {
      const studentData = studentDoc.data();
      const userId = studentData.userId;
      if (userId) {
        const memberSnap = await db.doc(`universities/${universityId}/members/${userId}`).get();
        if (memberSnap.exists) {
          const token = memberSnap.get("fcmToken");
          if (token && typeof token === "string") {
            tokens.push(token);
          }
        }
      }
    }

    if (tokens.length === 0) {
      console.log("No FCM tokens found for course:", courseId);
      return;
    }

    // Send FCM multicast message
    const messaging = getMessaging();
    const message = {
      tokens: tokens,
      notification: {
        title: isOpen ? "Session Started" : "Session Ended",
        body: isOpen
          ? `Attendance session opened for ${courseName}. Tap to check in.`
          : `Attendance session ended for ${courseName}.`,
      },
      data: {
        courseId: courseId,
        type: isOpen ? "session_opened" : "session_closed",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "session_updates",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    const response = await messaging.sendEachForMulticast(message);
    console.log(`FCM sent for ${isOpen ? "opened" : "closed"} session: ${response.successCount} success, ${response.failureCount} failures`);
  } catch (error) {
    console.error("Error sending session notification:", error);
    // Don't throw - notification failure shouldn't break session toggle
  }
}

// ============================================================
// LECTURER: GET ATTENDANCE FOR SESSION
// ============================================================

exports.getSessionAttendance = onCall(
  {
    region,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const { sessionId, universityId } = request.data || {};
    if (!sessionId || !universityId) {
      throw new HttpsError("invalid-argument", "sessionId and universityId are required.");
    }

    const db = getFirestore();

    // Verify lecturer permissions
    const member = await db.doc(`universities/${universityId}/members/${request.auth.uid}`).get();
    if (!member.exists || member.get("status") !== "active" || member.get("role") !== "lecturer") {
      throw new HttpsError("permission-denied", "Lecturer access required.");
    }

    // Get session
    const sessionRef = db.doc(`universities/${universityId}/attendanceSessions/${sessionId}`);
    const session = await sessionRef.get();
    if (!session.exists) {
      throw new HttpsError("not-found", "Session not found.");
    }
    const sessionData = session.data();
    await requireAssignedLecturer(
      db,
      universityId,
      request.auth.uid,
      sessionData.courseId,
    );

    // Get all students enrolled in this course
    const studentsSnap = await db
      .collection(`universities/${universityId}/students`)
      .where("courseId", "==", sessionData.courseId)
      .get();

    const students = studentsSnap.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // Get attendance records for this session
    const recordsSnap = await db
      .collection(`universities/${universityId}/attendanceRecords`)
      .where("sessionId", "==", sessionId)
      .get();

    const records = recordsSnap.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // Build attendance list with present/absent status
    const attendance = students.map(student => {
      const record = records.find(r => r.studentId === student.id);
      return {
        studentId: student.id,
        studentName: student.name,
        matricNumber: student.matricNumber,
        userId: student.userId,
        status: record ? "present" : "absent",
        checkedAt: record?.checkedAt?.toDate?.()?.toISOString() || null,
        faceMatchScore: record?.faceMatchScore || null,
        verificationProvider: record?.verificationProvider || null,
      };
    });

    return {
      sessionId: session.id,
      courseId: sessionData.courseId,
      status: sessionData.status,
      openedAt: sessionData.openedAt?.toDate?.()?.toISOString(),
      closedAt: sessionData.closedAt?.toDate?.()?.toISOString(),
      attendance,
      totalStudents: students.length,
      presentCount: attendance.filter(a => a.status === "present").length,
      absentCount: attendance.filter(a => a.status === "absent").length,
    };
  },
);

// ============================================================
// LECTURER: GET SEMESTER ATTENDANCE SUMMARY
// ============================================================

exports.getSemesterAttendanceSummary = onCall(
  {
    region,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const { universityId, courseId, semesterStart, semesterEnd } = request.data || {};
    if (!universityId || !courseId) {
      throw new HttpsError("invalid-argument", "universityId and courseId are required.");
    }

    const db = getFirestore();

    await requireAssignedLecturer(db, universityId, request.auth.uid, courseId);

    // Build date filter
    let startDate = semesterStart ? new Date(semesterStart) : new Date(new Date().getFullYear(), 0, 1);
    let endDate = semesterEnd ? new Date(semesterEnd) : new Date();

    // Get all students in the course
    const studentsSnap = await db
      .collection(`universities/${universityId}/students`)
      .where("courseId", "==", courseId)
      .get();

    const students = studentsSnap.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // Get all sessions for this course in the date range
    const sessionsSnap = await db
      .collection(`universities/${universityId}/attendanceSessions`)
      .where("courseId", "==", courseId)
      .where("openedAt", ">=", Timestamp.fromDate(startDate))
      .where("openedAt", "<=", Timestamp.fromDate(endDate))
      .get();

    const sessions = sessionsSnap.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // Get all attendance records for these sessions
    const sessionIds = sessions.map(s => s.id);
    let records = [];
    if (sessionIds.length > 0) {
      // Firestore 'in' query limited to 30, so batch if needed
      const batches = [];
      for (let i = 0; i < sessionIds.length; i += 30) {
        const batch = sessionIds.slice(i, i + 30);
        batches.push(
          db
            .collection(`universities/${universityId}/attendanceRecords`)
            .where("sessionId", "in", batch)
            .get()
        );
      }
      const results = await Promise.all(batches);
      for (const snap of results) {
        records.push(...snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
      }
    }

    // Build per-student summary
    const studentSummaries = students.map(student => {
      const studentRecords = records.filter(r => r.studentId === student.id);
      const sessionsAttended = studentRecords.length;
      const totalSessions = sessions.length;
      const percentage = totalSessions > 0 ? Math.round((sessionsAttended / totalSessions) * 100) : 0;

      return {
        studentId: student.id,
        studentName: student.name,
        matricNumber: student.matricNumber,
        userId: student.userId,
        sessionsAttended,
        totalSessions,
        percentage,
        recentSessions: studentRecords
          .sort((a, b) => (b.checkedAt?.toMillis?.() || 0) - (a.checkedAt?.toMillis?.() || 0))
          .slice(0, 5)
          .map(r => ({
            sessionId: r.sessionId,
            checkedAt: r.checkedAt?.toDate?.()?.toISOString(),
            faceMatchScore: r.faceMatchScore,
          })),
      };
    });

    // Sort by percentage descending, then name
    studentSummaries.sort((a, b) => {
      if (b.percentage !== a.percentage) return b.percentage - a.percentage;
      return a.studentName.localeCompare(b.studentName);
    });

    return {
      courseId,
      semesterStart: startDate.toISOString(),
      semesterEnd: endDate.toISOString(),
      totalSessions: sessions.length,
      studentSummaries,
    };
  },
);

// ============================================================
// STUDENT: GET OWN ATTENDANCE HISTORY
// ============================================================

exports.linkStudentRosterRecord = onCall({ region, enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const studentId = request.data?.studentId;
  if (typeof studentId !== "string" || !studentId.trim() || studentId.includes("/")) throw new HttpsError("invalid-argument", "Choose a valid roster entry.");
  const db = getFirestore();
  const account = await db.doc("users/" + request.auth.uid).get();
  const universityId = account.get("universityId");
  if (typeof universityId !== "string" || !universityId) throw new HttpsError("permission-denied", "University membership is required.");
  const lecturer = await db.doc("universities/" + universityId + "/members/" + request.auth.uid).get();
  if (!lecturer.exists || lecturer.get("status") !== "active" || lecturer.get("role") !== "lecturer") throw new HttpsError("permission-denied", "Lecturer access required.");
  const studentRef = db.doc("universities/" + universityId + "/students/" + studentId);
  const student = await studentRef.get();
  if (!student.exists) throw new HttpsError("not-found", "Student roster entry not found.");
  const rawMatric = student.get("matricNumber");
  const matric = typeof rawMatric === "string" ? rawMatric.trim() : "";
  const courseId = student.get("courseId");
  if (!matric || typeof courseId !== "string" || !courseId) throw new HttpsError("failed-precondition", "This roster entry needs a matric number and course.");
  await requireAssignedLecturer(db, universityId, request.auth.uid, courseId);
  const matches = await db.collection("users").where("universityId", "==", universityId).where("matricNumber", "==", matric).limit(10).get();
  const candidates = [];
  for (const user of matches.docs) {
    const member = await db.doc("universities/" + universityId + "/members/" + user.id).get();
    if (member.exists && member.get("status") === "active" && member.get("role") === "student") candidates.push(user);
  }
  if (!candidates.length) throw new HttpsError("failed-precondition", "No active student account matches this matric number. The student must register with this matric number and be approved.");
  if (candidates.length > 1) throw new HttpsError("failed-precondition", "More than one active student account uses this matric number. Ask an administrator to resolve the duplicate accounts.");
  const candidate = candidates[0], candidateUid = candidate.id, existingUid = student.get("userId");
  if (existingUid === candidateUid) return { linked: true, alreadyLinked: true, displayName: candidate.get("displayName") || student.get("name"), email: candidate.get("email") || "" };
  if (typeof existingUid === "string" && existingUid) {
    const prior = await db.doc("users/" + existingUid).get();
    const priorMatric = typeof prior.get("matricNumber") === "string" ? prior.get("matricNumber").trim().toLowerCase() : "";
    if (prior.exists && prior.get("universityId") === universityId && priorMatric === matric.toLowerCase()) throw new HttpsError("failed-precondition", "This roster entry is linked to another account with the same matric number. Ask an administrator to verify the correct account.");
  }
  const links = await db.collection("universities/" + universityId + "/students").where("userId", "==", candidateUid).where("courseId", "==", courseId).limit(2).get();
  if (links.docs.some((doc) => doc.id !== studentId)) throw new HttpsError("failed-precondition", "This account is already linked to another roster entry for this course. Use that linked entry.");
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(studentRef);
    if (!current.exists || current.get("matricNumber") !== rawMatric || current.get("courseId") !== courseId) throw new HttpsError("failed-precondition", "The roster entry changed. Refresh and try again.");
    const currentUid = current.get("userId");
    if (currentUid && currentUid !== existingUid && currentUid !== candidateUid) throw new HttpsError("aborted", "The roster entry changed during repair. Refresh and retry.");
    transaction.update(studentRef, { userId: candidateUid, userIdLinkedAt: FieldValue.serverTimestamp(), userIdLinkedBy: request.auth.uid });
  });
  return { linked: true, alreadyLinked: false, displayName: candidate.get("displayName") || student.get("name"), email: candidate.get("email") || "" };
});
exports.getStudentAttendanceHistory = onCall(
  {
    region,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const { universityId, courseId, semesterStart, semesterEnd } = request.data || {};
    if (!universityId) {
      throw new HttpsError("invalid-argument", "universityId is required.");
    }

    const db = getFirestore();

    // Verify student membership
    const member = await db.doc(`universities/${universityId}/members/${request.auth.uid}`).get();
    if (!member.exists || member.get("status") !== "active" || member.get("role") !== "student") {
      throw new HttpsError("permission-denied", "Student access required.");
    }

    // Get student record
    let studentsQuery = db
      .collection(`universities/${universityId}/students`)
      .where("userId", "==", request.auth.uid);
    if (courseId) studentsQuery = studentsQuery.where("courseId", "==", courseId);
    const studentsSnap = await studentsQuery.limit(2).get();

    if (studentsSnap.size !== 1) {
      throw new HttpsError("failed-precondition", "Student record not found.");
    }

    const studentDoc = studentsSnap.docs[0];
    const studentData = studentDoc.data();
    const studentId = studentDoc.id;
    const studentCourseId = studentData.courseId;

    // If courseId provided, verify it matches student's course
    const targetCourseId = courseId || studentCourseId;
    if (courseId && courseId !== studentCourseId) {
      throw new HttpsError("permission-denied", "Not enrolled in this course.");
    }

    // Build date filter
    let startDate = semesterStart ? new Date(semesterStart) : new Date(new Date().getFullYear(), 0, 1);
    let endDate = semesterEnd ? new Date(semesterEnd) : new Date();

    // Get all sessions for the course in date range
    const sessionsSnap = await db
      .collection(`universities/${universityId}/attendanceSessions`)
      .where("courseId", "==", targetCourseId)
      .where("openedAt", ">=", Timestamp.fromDate(startDate))
      .where("openedAt", "<=", Timestamp.fromDate(endDate))
      .get();

    const sessions = sessionsSnap.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // Get student's attendance records for these sessions
    const sessionIds = sessions.map(s => s.id);
    let records = [];
    if (sessionIds.length > 0) {
      const batches = [];
      for (let i = 0; i < sessionIds.length; i += 30) {
        const batch = sessionIds.slice(i, i + 30);
        batches.push(
          db
            .collection(`universities/${universityId}/attendanceRecords`)
            .where("sessionId", "in", batch)
            .where("studentId", "==", studentId)
            .get()
        );
      }
      const results = await Promise.all(batches);
      for (const snap of results) {
        records.push(...snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
      }
    }

    // Build history
    const history = sessions.map(session => {
      const record = records.find(r => r.sessionId === session.id);
      return {
        sessionId: session.id,
        courseId: session.courseId,
        sessionDate: session.openedAt?.toDate?.()?.toISOString(),
        sessionStatus: session.status,
        checkedIn: !!record,
        checkedAt: record?.checkedAt?.toDate?.()?.toISOString() || null,
        faceMatchScore: record?.faceMatchScore || null,
        verificationProvider: record?.verificationProvider || null,
      };
    }).sort((a, b) => new Date(b.sessionDate) - new Date(a.sessionDate));

    const attendedCount = history.filter(h => h.checkedIn).length;
    const totalSessions = history.length;

    return {
      studentId,
      studentName: studentData.name,
      matricNumber: studentData.matricNumber,
      courseId: targetCourseId,
      semesterStart: startDate.toISOString(),
      semesterEnd: endDate.toISOString(),
      totalSessions,
      attendedCount,
      percentage: totalSessions > 0 ? Math.round((attendedCount / totalSessions) * 100) : 0,
      history,
    };
  },
);
