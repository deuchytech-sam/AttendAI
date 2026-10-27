# FaceTec Flutter SDK Setup Guide

## Obtaining the SDK

The FaceTec Flutter SDK is not published on pub.dev. You must obtain it from FaceTec:

1. **Contact FaceTec** for access to their Flutter SDK distribution
2. **Download the SDK** from FaceTec's developer portal
3. **Place it locally** (e.g., `../facetec_flutter_sdk` relative to this project)

## Adding to Project

### Option 1: Path Dependency (Recommended for local development)

In `pubspec.yaml`, uncomment and update the path:

```yaml
dependencies:
  # ... other dependencies
  facetec_flutter:
    path: ../facetec_flutter_sdk
```

Run `flutter pub get` after updating.

### Option 2: Git Dependency (If FaceTec provides a private repo)

```yaml
dependencies:
  facetec_flutter:
    git:
      url: https://github.com/FaceTec/facetec-flutter-sdk.git
      ref: main
```

## Configuration Files

### Android

Add FaceTec native libraries to `android/app/src/main/jniLibs/` or configure in `build.gradle.kts`:

```kotlin
dependencies {
    implementation(files("libs/facetec.aar"))
}
```

### iOS

Add FaceTec framework to `ios/Frameworks/` and update `Podfile`:

```ruby
pod 'FaceTecSDK', :path => '../facetec_flutter_sdk/ios'
```

Run `cd ios && pod install` after adding.

## Firebase Functions Secrets

Set the FaceTec API key in Firebase Functions Secret Manager:

```bash
firebase functions:secrets:set FACETEC_API_KEY
```

Configure `FACETEC_API_BASE_URL` if your tenant uses a non-default endpoint:

```bash
firebase functions:config:set facetec.api_base_url="https://your-tenant.facetec.com/v1"
```

## Verifying Integration

After adding the SDK and running `flutter pub get`:

1. Run `flutter analyze` — should show no errors in FaceTec service files
2. Run `flutter build apk` / `flutter build ios` — should compile native code
3. Test enrollment and verification flows on physical devices

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Target of URI doesn't exist` | SDK not added to pubspec.yaml correctly |
| `Undefined name 'FaceTecSDK'` | API mismatch — check actual FaceTec Flutter SDK exports |
| Native build errors | Verify Android/iOS native libraries are linked correctly |
| "Session token invalid" | Check `FACETEC_API_BASE_URL` matches your tenant region |