# AttendAI - Face Liveness Verification Flutter App

This project is a Flutter application that implements face liveness verification using the `face_liveness_verification` package. It provides a modern, production-ready solution for face detection, liveness checks, and identity verification.

## Features

- **Face Liveness Detection**: Challenge-based liveness checks (smile, blink, turn left/right, look up/down)
- **Face Enrollment**: Enroll new users with liveness verification
- **Face Verification**: Verify users against enrolled templates
- **Demo Mode**: Test liveness without enrollment/verification
- **Cross-platform**: Works on Android, iOS, and Windows

## Getting Started

### Prerequisites

- Flutter SDK (>=3.1.0 <4.0.0)
- Dart SDK (>=3.1.0)
- Android Studio / Xcode for mobile development
- Visual Studio 2022 with "Desktop development with C++" workload for Windows

### Dependencies

The app uses the following key packages:

- `face_liveness_verification: ^1.0.1` - Core liveness verification engine
- `camera: ^0.12.1` - Camera preview and image capture
- `google_mlkit_face_detection: ^0.15.1` - Face detection via Google ML Kit

### Installation

```bash
flutter pub get
```

### Platform Setup

#### Android
- Camera permission is already configured in `android/app/src/main/AndroidManifest.xml`
- Minimum SDK: 21 (Android 5.0)

#### iOS
- Camera usage description is configured in `ios/Runner/Info.plist`
- Minimum iOS: 12.0

#### Windows
- Requires Visual Studio 2022 with "Desktop development with C++" workload

## Running the App

```bash
# Run on Android
flutter run -d android

# Run on iOS (macOS only)
flutter run -d ios

# Run on Windows
flutter run -d windows

# Run on Web (limited camera support)
flutter run -d chrome
```

## Usage

The app provides four modes:

1. **FaceTec SDK Liveness (Original)** - Legacy FaceTec implementation (if configured)
2. **Face Liveness Verification** - Verify against an enrolled face template
3. **Enroll New Face** - Enroll a new user with liveness check
4. **Liveness Demo Only** - Test liveness challenges without enrollment/verification

## Architecture

```
lib/
├── main.dart                      # App entry point and navigation
├── liveness_verification_screen.dart  # Liveness verification UI and logic
```

## Configuration

### Liveness Settings

The liveness challenge configuration can be adjusted in `liveness_verification_screen.dart`:

```dart
FaceLivenessConfig(
  actions: [
    FaceLivenessAction.smile,
    FaceLivenessAction.blink,
    FaceLivenessAction.turnLeft,
    FaceLivenessAction.turnRight,
    FaceLivenessAction.lookUp,
    FaceLivenessAction.lookDown,
  ],
  challengeTimeout: Duration(seconds: 12),
  totalSessionTimeout: Duration(seconds: 45),
  randomizeActionOrder: true,
)
```

### Matching Threshold

The face matching threshold can be configured:

```dart
FaceMatchingConfig(
  metric: FaceSimilarityMetric.euclidean,
  threshold: 1.0,  // Lower = stricter matching
)
```

## Security & Privacy

- Face embeddings are treated as sensitive biometric data
- Templates are stored in-memory by default (use secure storage for production)
- No raw face images or embeddings are logged
- Camera access is only used during active verification sessions

## License

MIT License - See LICENSE file for details.