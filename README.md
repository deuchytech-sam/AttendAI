# AttendAI University

Flutter attendance app for university lecturers and students. The client uses Clean Architecture with `flutter_bloc`; Firebase Authentication stores accounts and Cloud Firestore stores university data.

## Sign-in and approval

1. In Firebase Console for `attendai-ec4cd`, enable **Authentication → Sign-in method → Email/Password**.
2. A person registers with a university ID and requests a student or lecturer role. Their Auth account and `/users/{uid}` profile are created; the profile remains `pending` until email verification and university approval.
3. A university administrator approves the account in Firestore by creating `/universities/{universityId}/members/{uid}` with `status: "active"`, the administrator-assigned `role` (`student` or `lecturer`), and `courseIds` for students. Use the UID from Authentication. Membership writes are denied to app clients, so an administrator must do this in Firebase Console or a trusted admin tool.
4. For student attendance views, link the student's roster document under `/universities/{universityId}/students/{studentId}` by setting its `userId` to the student's Firebase UID. Lecturer enrollment currently creates the roster record; an admin must link an existing student account.

The requested role on registration is informational. Access is granted only from an active Firestore membership and verified email. Do not let a user approve their own membership.

## Admin dashboard

The app includes an admin dashboard for pending account approvals. The first university admin must be designated by a trusted Firebase project operator; nobody can grant themselves admin access in the app.

1. Create the university document and fix the admin user's `/users/{uid}.universityId` to that document ID. The admin account must verify its email.
2. Install Node.js and Google Cloud CLI. In a terminal, sign in with a Google account that has Firebase Authentication Admin and Firestore access to this project:

   ```sh
   gcloud auth application-default login --project attendai-ec4cd
   cd admin_tools
   npm install
   npm run promote-admin -- YOUR_AUTH_UID YOUR_UNIVERSITY_DOCUMENT_ID
   ```

3. Sign out and back into the app. The user will enter the admin dashboard. Use the account's Firebase Authentication UID, not its email or matriculation number.

The setup utility uses the Firebase Admin SDK and application-default credentials; run it only from a trusted operator's machine. It adds a university-scoped custom claim and an active admin membership. Firestore rules use that active `admin` membership to allow the admin to review pending profiles and atomically approve the requested student/lecturer role. Student approvals can include course IDs.

## Firebase setup

The default Firebase project is `attendai-ec4cd`; Firestore is in `europe-west1`. Android and iOS use `com.attendai.samtechcomputers`. FlutterFire options are in `lib/firebase_options.dart`, and Android's native configuration is `android/app/google-services.json`.

Firestore rules are in `firestore.rules`. Client writes are limited to pending account registration, lecturer-created courses/roster entries, and lecturer-managed attendance sessions. Verified attendance records and biometric profiles cannot be written by the client.

## FaceTec attendance verification

The Flutter client uses `facetec_flutter` to verify a student's presence during an open attendance session. It never receives a FaceTec API secret or writes an attendance record directly. Android requires API 26 or newer; iOS requires iOS 15 or newer. FaceTec scans must be tested on a physical device.

The client calls two HTTPS callable Functions in `europe-west1`:

| Callable | Input | Required response / effect |
| --- | --- | --- |
| `createFaceTecAttendanceVerification` | none; use `request.auth.uid` | Check active membership, find that student's roster record and open course session, require an enrolled biometric profile, create a short-lived FaceTec **verify** session token, store an unexpired server-side challenge, and return `{ challengeId, sessionToken }`. |
| `completeFaceTecAttendanceVerification` | `{ challengeId }` | Load the challenge for `request.auth.uid`, validate its stored FaceTec session token with FaceTec, check that the session is still open, then atomically write one attendance record and return `{ recorded: true }`. |

Use FaceTec's **enroll** flow for a separate, consented enrollment before a student can check in. Store only a FaceTec user/profile reference and enrollment status in `/biometricProfiles/{studentId}`; do not store a face image, template, token, or API credential in Firestore.

Keep the FaceTec API key in Firebase Functions Secret Manager. The server must derive the university, student, course, and session from the authenticated user and Firestore; it must never trust those values from callable input. Reject expired/reused challenges and duplicate attendance records. Device ML Kit detection is only suitable for framing guidance, not identity verification.

The callable implementation is in [`functions/index.js`](functions/index.js). Before deploying it, enable App Check for the Android and iOS Firebase apps, create the FaceTec secret, then install and deploy the function dependencies:

```sh
firebase functions:secrets:set FACETEC_API_KEY
cd functions
npm install
cd ..
firebase deploy --only functions
```

Set `FACETEC_API_BASE_URL` to the URL assigned to the FaceTec tenant if it differs from the default. The server implementation expects a trusted enrollment flow to create `/biometricProfiles/{studentId}` with `status: "enrolled"` and a FaceTec UUID in `facetecUserId`; enrollment should use the same server-created-token and server-validation pattern.

## Commands

```sh
flutter pub get
flutter run
```

Regenerate Firebase app configuration if Firebase project/app settings change:

```sh
dart pub global activate flutterfire_cli
flutterfire configure --project=attendai-ec4cd
```
