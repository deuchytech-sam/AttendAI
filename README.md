# AttendAI University

AttendAI is a Flutter attendance app for university students, lecturers, and administrators. It combines course enrollment, lecturer-managed attendance sessions, face liveness checks, and Firebase-backed attendance records.

## What the app does

### Students

- View enrolled courses and schedules.
- Enroll a face and check in to an open course session with the liveness flow.
- Review personal attendance history and reports.
- Receive session notifications where Firebase Cloud Messaging and local notifications are configured.

### Lecturers

- View assigned courses and their student rosters.
- Open or close a course attendance session and see check-ins update live.
- Enroll a student's face or reset an enrollment when needed.
- View reports and load a semester summary for a selected course and date range.
- Export the displayed session attendance or semester summary as CSV or XLSX. Web uses a browser download; native platforms write a temporary file and invoke the platform share flow where supported.

### University administrators

- Review and approve pending student and lecturer accounts.
- Create and edit courses, schedules, enrollments, and lecturer assignments.
- Assign up to eight active lecturers to a course. Courses without a lecturer are identified for follow-up.

## Technology and architecture

| Area | Implementation |
| --- | --- |
| App | Flutter and Dart (SDK constraint in `pubspec.yaml`) |
| State | `flutter_bloc` BLoC pattern |
| Navigation | `go_router` |
| Backend | Firebase Authentication, Cloud Firestore, Cloud Functions, App Check, and Cloud Messaging |
| Face liveness | Local `flutter_face_liveness` package, with ML Kit and TensorFlow Lite components |
| File export | `package:web` for browser downloads; `path_provider` and `share_plus` for native file sharing |
| Structure | Feature-oriented Clean Architecture with data, domain, and presentation layers |

The active Flutter enrollment and check-in screens use the local liveness package. `functions/index.js` also contains FaceTec-backed callable endpoints; configuring those endpoints does not replace or configure the Flutter liveness UI.

## Repository layout

```text
lib/
├── app/                         # App widget, service wiring, theme
├── core/utils/                  # Platform-aware CSV/XLSX file downloads
├── features/
│   ├── auth/                    # Sign-in, registration, account approval state
│   ├── admin/                   # Account approval and course management
│   ├── biometrics/              # Liveness service and biometric repository
│   ├── notifications/           # FCM and local session notifications
│   └── university/              # Student, lecturer, attendance, and reports
├── firebase_options.dart        # FlutterFire configuration
└── main.dart                    # Firebase/App Check initialization

packages/flutter_face_liveness/  # Local face capture, liveness, and identity package
functions/                       # Callable and scheduled Firebase Functions
admin_tools/                     # Admin promotion and lecturer migration tools
firestore.rules                  # Firestore role and course access rules
```

## Requirements and platform configuration

- Flutter with a Dart SDK satisfying the `environment.sdk` constraint in `pubspec.yaml`.
- A Firebase project with Email/Password Authentication, Cloud Firestore, Cloud Functions, App Check, and Cloud Messaging enabled as needed.
- Node.js 22 for Firebase Functions.

The checked-in FlutterFire configuration currently contains Android and iOS options. Web, Windows, macOS, and Linux project folders exist, but those platforms are not configured in `lib/firebase_options.dart`. Run FlutterFire configuration for any additional platform before expecting the app to start there. Camera, ML Kit, TensorFlow Lite, App Check, notifications, and file-sharing support also vary by platform.

## Getting started

```bash
git clone https://github.com/deuchytech-sam/AttendAI.git
cd AttendAI
flutter pub get
flutter run
```

Configure Firebase for the target platform with the FlutterFire CLI and ensure its app identifiers match the Firebase project. Debug builds use Firebase App Check debug providers; register the generated debug token in the Firebase console. Release builds use Android Play Integrity and Apple DeviceCheck providers.

New users register with a university code and request a student or lecturer role. They must verify their email and be approved by a university administrator before reaching the role-specific app.

### Deploy Firestore rules and Functions

From the repository root:

```bash
cd functions
npm install
cd ..
firebase deploy --only firestore:rules,functions
```

Callable Functions use the `europe-west1` region and enforce App Check. They manage attendance sessions and records, lecturer course assignment checks, semester summaries, student attendance history, roster linking, and face-enrollment resets. A scheduled function expires stale attendance sessions.

`functions/index.js` also exports FaceTec token and verification callables. If those server-side flows are used, configure the `FACETEC_API_KEY` secret and, if needed, the `FACETEC_API_BASE_URL` Functions parameter before deployment.

### Promote the first university administrator

The admin promotion tool requires Application Default Credentials. The user must already have a verified Firebase Auth account, a matching `users/{uid}` profile with the university ID, and an existing university document.

```bash
cd admin_tools
npm install
npm run promote-admin -- <firebase-auth-uid> <university-document-id>
```

The admin should sign out and back in after promotion so the app receives the updated custom claims.

### Migrate legacy course lecturer assignments

The migration matches legacy free-text lecturer names to active lecturer accounts. It skips courses that already have a non-empty `lecturerIds` field and reports unmatched or ambiguous names without guessing.

```bash
cd admin_tools
npm install

# Preview and review the report first
npm run migrate:course-lecturers -- --dry-run

# Apply the reviewed migration
npm run migrate:course-lecturers -- --apply
```

Set `GCLOUD_PROJECT` when targeting a Firebase project other than `attendai-ec4cd`. You can limit the migration with `--university=<university-document-id>`. Run the migration before deploying Firestore rules that depend on `lecturerIds`.

Student roster rows and university membership course IDs are separate records. A student taking multiple courses can have one roster row per course, while the current approval/linking flow links a matric number to one roster row.

## App workflows

### Attendance

1. An administrator creates a course and assigns active lecturers.
2. Students enroll in the course and complete email verification and account approval.
3. A lecturer opens a session for an assigned course.
4. An enrolled student completes the face liveness check to check in.
5. The lecturer monitors the live session, reviews reports, or loads a semester summary.

Attendance check-in is handled by Cloud Functions, which validate the student's university membership, course enrollment, and open session. Lecturers can manage only courses assigned to them.

### Lecturer exports

Open **Lecturer → Live Session** or **Lecturer → Semester Summary**, select a course, and use **Export CSV** or **Export XLSX**. CSV exports include a UTF-8 BOM for spreadsheet compatibility. On web the browser downloads the file; on native platforms the app opens the system share flow for the generated temporary file.

### Face enrollment and data

The liveness flow uses the local `flutter_face_liveness` package. The app persists face embeddings through the university data source and loads them for enrollment and check-in flows. Do not treat the liveness UI as a substitute for Firebase authorization: callable functions and Firestore rules enforce membership and course access.

## Development and checks

```bash
# Install Flutter dependencies
flutter pub get

# Static analysis
flutter analyze

# Dart tests
flutter test

# Admin migration tests
cd admin_tools
npm run test:migration

# Firestore Rules and migration tests using the emulator
npm run test:rules
```

Flutter build commands:

```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
flutter build web --release
```

The web build command requires web Firebase options and compatible platform implementations to be configured first. Windows, macOS, and Linux builds likewise require Firebase and plugin setup for the target platform.

## Security notes

- Accounts are scoped by university ID and require email verification and administrator approval.
- Firestore rules validate role membership and lecturer assignments for protected data.
- Attendance and identity-sensitive operations use authenticated, App Check-enforced callable functions.
- Face embeddings are stored and synchronized by the app; avoid logging, exporting, or sharing biometric data outside the intended enrollment and attendance flows.
- Never commit service-account credentials, production secrets, or Firebase Admin SDK keys.

## License and support

This project is proprietary software. All rights reserved. For issues and feature requests, open a [GitHub Issue](https://github.com/deuchytech-sam/AttendAI/issues).
