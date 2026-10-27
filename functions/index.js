const { randomUUID } = require("node:crypto");

const { initializeApp } = require("firebase-admin/app");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { defineSecret, defineString } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();

// FaceTec configuration
const faceTecApiKey = defineSecret("FACETEC_API_KEY");
const faceTecApiBaseUrl = defineString("FACETEC_API_BASE_URL", {
  default: "https://api.facetec.com/v1",
});

const region = "europe-west1";
const challengeLifetimeMs = 110000;

async function requestFaceTecSessionToken({ type, userId, resource }) {
  const response = await fetch(`${faceTecApiBaseUrl.value()}/session/${type}/token`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-facetec-api-key": faceTecApiKey.value(),
    },
    body: JSON.stringify({
      user_id: userId,
      resource,
      assurance_type: "genuine_presence",
    }),
  });
  const body = await response.json();
  if (!response.ok || typeof body.session_token !== "string") {
    console.error("FaceTec session token request failed", response.status, body.error);
    throw new HttpsError("internal", "Unable to start identity verification.");
  }
  return body.session_token;
}

async function validateFaceTecSessionResult({ userId, sessionToken }) {
  const response = await fetch(`${faceTecApiBaseUrl.value()}/session/verify/validate`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-facetec-api-key": faceTecApiKey.value(),
    },
    body: JSON.stringify({
      user_id: userId,
      session_token: sessionToken,
      client: "attendai-firebase-functions",
    }),
  });
  const body = await response.json();
  if (!response.ok) {
    console.error("FaceTec validation failed", response.status, body.error);
    throw new HttpsError("failed-precondition", "Identity verification could not be validated.");
  }
  return body;
}

async function getStudentIdentity(auth) {
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
  const students = await db
    .collection(`universities/${universityId}/students`)
    .where("userId", "==", auth.uid)
    .limit(2)
    .get();
  if (students.size !== 1) {
    throw new HttpsError("failed-precondition", "Your student roster record is not linked.");
  }
  const student = students.docs[0];
  const courseId = student.get("courseId");
  if (typeof courseId !== "string") {
    throw new HttpsError("failed-precondition", "Your course enrollment is incomplete.");
  }
  return { uid: auth.uid, universityId, studentId: student.id, courseId };
}

async function getOpenSession(db, identity) {
  const sessions = await db
    .collection(`universities/${identity.universityId}/attendanceSessions`)
    .where("status", "==", "open")
    .where("courseId", "==", identity.courseId)
    .limit(2)
    .get();
  if (sessions.size !== 1) {
    throw new HttpsError("failed-precondition", "There is no open attendance session for your course.");
  }
  return sessions.docs[0];
}

// ============================================================
// ENROLLMENT FUNCTIONS
// ============================================================

exports.createFaceTecEnrollment = onCall(
  {
    region,
    enforceAppCheck: true,
    secrets: [faceTecApiKey],
  },
  async (request) => {
    const identity = await getStudentIdentity(request.auth);
    const db = getFirestore();
    const profileRef = db.doc(
      `universities/${identity.universityId}/biometricProfiles/${identity.studentId}`,
    );
    const profile = await profileRef.get();

    // If already enrolled, return existing FaceTec userId
    if (profile.exists && profile.get("status") === "enrolled" && typeof profile.get("facetecUserId") === "string") {
      const facetecUserId = profile.get("facetecUserId");
      const sessionToken = await requestFaceTecSessionToken({
        type: "enroll",
        userId: facetecUserId,
        resource: `attendai://enrollment/${identity.universityId}/${identity.studentId}`,
      });
      const challengeId = randomUUID();
      await db.doc(`universities/${identity.universityId}/facetecChallenges/${challengeId}`).set({
        uid: identity.uid,
        studentId: identity.studentId,
        facetecUserId,
        sessionToken,
        type: "enroll",
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + challengeLifetimeMs),
        used: false,
      });
      return { challengeId, sessionToken };
    }

    // Create new FaceTec user
    const facetecUserId = randomUUID();
    const sessionToken = await requestFaceTecSessionToken({
      type: "enroll",
      userId: facetecUserId,
      resource: `attendai://enrollment/${identity.universityId}/${identity.studentId}`,
    });
    const challengeId = randomUUID();
    await db.doc(`universities/${identity.universityId}/facetecChallenges/${challengeId}`).set({
      uid: identity.uid,
      studentId: identity.studentId,
      facetecUserId,
      sessionToken,
      type: "enroll",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + challengeLifetimeMs),
      used: false,
    });
    // Create or update biometric profile with pending status
    await profileRef.set({
      studentId: identity.studentId,
      uid: identity.uid,
      facetecUserId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { challengeId, sessionToken };
  },
);

exports.completeFaceTecEnrollment = onCall(
  {
    region,
    enforceAppCheck: true,
    secrets: [faceTecApiKey],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
    const challengeId = request.data?.challengeId;
    if (typeof challengeId !== "string" || challengeId.length > 100) {
      throw new HttpsError("invalid-argument", "A valid challenge is required.");
    }

    const identity = await getStudentIdentity(request.auth);
    const db = getFirestore();
    const challengeRef = db.doc(
      `universities/${identity.universityId}/facetecChallenges/${challengeId}`,
    );
    const challenge = await challengeRef.get();
    if (!challenge.exists || challenge.get("uid") !== request.auth.uid) {
      throw new HttpsError("not-found", "Enrollment challenge not found.");
    }
    if (challenge.get("type") !== "enroll") {
      throw new HttpsError("failed-precondition", "Invalid challenge type.");
    }
    const expiresAt = challenge.get("expiresAt");
    if (challenge.get("used") === true || !(expiresAt instanceof Timestamp) || expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("failed-precondition", "Enrollment challenge has expired. Try again.");
    }

    if (challenge.get("studentId") !== identity.studentId) {
      throw new HttpsError("permission-denied", "Enrollment challenge is not valid for this student.");
    }

    const validation = await validateFaceTecSessionResult({
      userId: challenge.get("facetecUserId"),
      sessionToken: challenge.get("sessionToken"),
    });
    if (validation.passed !== true) {
      await challengeRef.update({ used: true, failedAt: FieldValue.serverTimestamp() });
      throw new HttpsError("permission-denied", "FaceTec could not enroll your face.");
    }

    const profileRef = db.doc(
      `universities/${identity.universityId}/biometricProfiles/${identity.studentId}`,
    );
    await db.runTransaction(async (transaction) => {
      const [freshChallenge, freshProfile] = await Promise.all([
        transaction.get(challengeRef),
        transaction.get(profileRef),
      ]);
      if (!freshChallenge.exists || freshChallenge.get("used") === true) {
        throw new HttpsError("failed-precondition", "Enrollment challenge was already used.");
      }
      if (!freshProfile.exists || freshProfile.get("facetecUserId") !== challenge.get("facetecUserId")) {
        throw new HttpsError("failed-precondition", "Biometric profile mismatch.");
      }
      transaction.update(challengeRef, { used: true, completedAt: FieldValue.serverTimestamp() });
      transaction.update(profileRef, {
        status: "enrolled",
        enrolledAt: FieldValue.serverTimestamp(),
        assuranceType: validation.assurance_type ?? "unknown",
      });
    });
    return { enrolled: true };
  },
);

// ============================================================
// ATTENDANCE VERIFICATION FUNCTIONS
// ============================================================

exports.createFaceTecAttendanceVerification = onCall(
  {
    region,
    enforceAppCheck: true,
    secrets: [faceTecApiKey],
  },
  async (request) => {
    const identity = await getStudentIdentity(request.auth);
    const db = getFirestore();
    const profile = await db.doc(
      `universities/${identity.universityId}/biometricProfiles/${identity.studentId}`,
    ).get();
    const facetecUserId = profile.get("facetecUserId");
    if (profile.get("status") !== "enrolled" || typeof facetecUserId !== "string") {
      throw new HttpsError(
        "failed-precondition",
        "Complete face enrollment before checking in.",
      );
    }

    const session = await getOpenSession(db, identity);
    const sessionToken = await requestFaceTecSessionToken({
      type: "verify",
      userId: facetecUserId,
      resource: `attendai://attendance/${identity.universityId}/${session.id}`,
    });
    const challengeId = randomUUID();
    await db.doc(`universities/${identity.universityId}/facetecChallenges/${challengeId}`).set({
      uid: identity.uid,
      studentId: identity.studentId,
      sessionId: session.id,
      courseId: identity.courseId,
      facetecUserId,
      sessionToken,
      type: "verify",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + challengeLifetimeMs),
      used: false,
    });

    return {
      challengeId,
      sessionToken,
    };
  },
);

exports.completeFaceTecAttendanceVerification = onCall(
  {
    region,
    enforceAppCheck: true,
    secrets: [faceTecApiKey],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
    const challengeId = request.data?.challengeId;
    if (typeof challengeId !== "string" || challengeId.length > 100) {
      throw new HttpsError("invalid-argument", "A valid challenge is required.");
    }

    const identity = await getStudentIdentity(request.auth);
    const db = getFirestore();
    const challengeRef = db.doc(
      `universities/${identity.universityId}/facetecChallenges/${challengeId}`,
    );
    const challenge = await challengeRef.get();
    if (!challenge.exists || challenge.get("uid") !== request.auth.uid) {
      throw new HttpsError("not-found", "Verification challenge not found.");
    }
    if (challenge.get("type") !== "verify") {
      throw new HttpsError("failed-precondition", "Invalid challenge type.");
    }
    const expiresAt = challenge.get("expiresAt");
    if (challenge.get("used") === true || !(expiresAt instanceof Timestamp) || expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("failed-precondition", "Verification challenge has expired. Try again.");
    }

    if (
      challenge.get("studentId") !== identity.studentId ||
      challenge.get("courseId") !== identity.courseId
    ) {
      throw new HttpsError("permission-denied", "Verification challenge is not valid for this student.");
    }
    const sessionRef = db.doc(
      `universities/${identity.universityId}/attendanceSessions/${challenge.get("sessionId")}`,
    );
    const validation = await validateFaceTecSessionResult({
      userId: challenge.get("facetecUserId"),
      sessionToken: challenge.get("sessionToken"),
    });
    if (validation.passed !== true) {
      await challengeRef.update({ used: true, failedAt: FieldValue.serverTimestamp() });
      throw new HttpsError("permission-denied", "FaceTec could not verify your identity.");
    }

    const recordRef = db.doc(
      `universities/${identity.universityId}/attendanceRecords/${sessionRef.id}_${identity.studentId}`,
    );
    let alreadyRecorded = false;
    await db.runTransaction(async (transaction) => {
      const [session, record, freshChallenge] = await Promise.all([
        transaction.get(sessionRef),
        transaction.get(recordRef),
        transaction.get(challengeRef),
      ]);
      if (!session.exists || session.get("status") !== "open" || session.get("courseId") !== identity.courseId) {
        throw new HttpsError("failed-precondition", "The attendance session is closed.");
      }
      if (!freshChallenge.exists || freshChallenge.get("used") === true) {
        throw new HttpsError("failed-precondition", "Verification challenge was already used.");
      }
      transaction.update(challengeRef, { used: true, completedAt: FieldValue.serverTimestamp() });
      if (record.exists) {
        alreadyRecorded = true;
        return;
      }
      transaction.set(recordRef, {
        studentId: identity.studentId,
        studentUid: identity.uid,
        sessionId: sessionRef.id,
        checkedAt: FieldValue.serverTimestamp(),
        verificationProvider: "facetec",
        verificationAssurance: validation.assurance_type ?? "unknown",
      });
    });
    return { recorded: !alreadyRecorded };
  },
);