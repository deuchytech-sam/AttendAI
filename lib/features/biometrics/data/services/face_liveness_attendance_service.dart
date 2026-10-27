import 'dart:typed_data';
import 'dart:ui';

import 'package:face_liveness_verification/face_liveness_verification.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/services/biometric_attendance_service.dart';

/// Attendance verification service using face_liveness_verification package.
///
/// This service runs on-device liveness and matching verification against
/// enrolled templates stored in the FaceTemplateStore.
class FaceLivenessAttendanceService implements BiometricAttendanceService {
  FaceLivenessAttendanceService({
    FaceLivenessMatchService? service,
    FaceTemplateStore? templateStore,
  })  : _service = service ?? FaceLivenessMatchService(
          livenessConfig: const FaceLivenessConfig(
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
          ),
          matchingConfig: const FaceMatchingConfig(
            metric: FaceSimilarityMetric.euclidean,
            threshold: 1.0,
          ),
          templateStore: InMemoryFaceTemplateStore(),
        ),
        _templateStore = templateStore ?? InMemoryFaceTemplateStore();

  final FaceLivenessMatchService _service;
  final FaceTemplateStore _templateStore;

  /// Preloads the model to reduce first-frame latency.
  Future<void> warmUp() async {
    await _service.warmUp();
  }

  /// Resets the internal liveness challenge state.
  void reset() {
    _service.reset();
  }

  @override
  Future<BiometricAttendanceResult> verifyOpenSession() async {
    try {
      // This is a placeholder - actual verification requires the faceId
      // and camera frames. The real flow goes through LivenessVerificationScreen
      // which calls the service directly.
      return const BiometricAttendanceResult(
        recorded: false,
        message: 'Verification requires active camera session',
      );
    } catch (e) {
      return BiometricAttendanceResult(
        recorded: false,
        message: 'Verification failed: $e',
      );
    }
  }

  /// Verifies a specific face ID against enrolled template.
  ///
  /// This is the main entry point for attendance verification.
  Future<BiometricAttendanceResult> verifyStudent() async {
    try {
      final template = await _templateStore.load();
      if (template == null) {
        return const BiometricAttendanceResult(
          recorded: false,
          message: 'No enrolled template found',
        );
      }

      // The actual verification happens in the UI flow (LivenessVerificationScreen)
      // which collects frames and calls verifyWithTemplate.
      // This method returns a result that the UI can use to trigger the flow.
      return const BiometricAttendanceResult(
        recorded: false,
        message: 'Ready to verify - start camera session',
      );
    } catch (e) {
      return BiometricAttendanceResult(
        recorded: false,
        message: 'Verification failed: $e',
      );
    }
  }

  /// Gets the enrolled template for a face ID.
  Future<FaceTemplate?> getTemplate() async {
    return await _templateStore.load();
  }

  /// Verifies a face against an enrolled template using live camera frames.
  ///
  /// This should be called from the LivenessVerificationScreen after
  /// collecting the required frames and liveness challenges.
  Future<BiometricAttendanceResult> verifyWithFrames({
    required List<Face> faces,
    required Size imageSize,
    required Uint8List imageBytes,
  }) async {
    try {
      final template = await _templateStore.load();
      if (template == null) {
        return const BiometricAttendanceResult(
          recorded: false,
          message: 'No enrolled template found',
        );
      }

      final result = await _service.verifyWithTemplate(
        template: template,
        faces: faces,
        imageSize: imageSize,
        imageBytes: imageBytes,
      );

      return BiometricAttendanceResult(
        recorded: result.isMatch,
        message: result.message,
      );
    } catch (e) {
      return BiometricAttendanceResult(
        recorded: false,
        message: 'Verification failed: $e',
      );
    }
  }
}