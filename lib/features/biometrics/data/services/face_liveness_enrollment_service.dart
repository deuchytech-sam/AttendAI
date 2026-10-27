import 'dart:typed_data';
import 'dart:ui';

import 'package:face_liveness_verification/face_liveness_verification.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Service for enrolling student faces using the face_liveness_verification package.
///
/// This service integrates with the LivenessVerificationScreen UI flow
/// to perform on-device enrollment with liveness checks.
class FaceLivenessEnrollmentService {
  FaceLivenessEnrollmentService({
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

  /// Enrolls a new face with liveness verification.
  ///
  /// This method is typically called from the LivenessVerificationScreen
  /// after the user completes the liveness challenges.
  Future<EnrollmentResult> enrollStudent({
    required String faceId,
    required List<Face> faces,
    required Size imageSize,
    required Uint8List imageBytes,
  }) async {
    try {
      final result = await _service.enrollAndPersist(
        faceId: faceId,
        faces: faces,
        imageSize: imageSize,
        imageBytes: imageBytes,
        requireLiveness: true,
      );

      if (result.enrolledTemplate != null) {
        return EnrollmentResult(
          enrolled: true,
          message: 'Enrollment complete for $faceId',
        );
      } else if (result.failureReason != null) {
        return EnrollmentResult(
          enrolled: false,
          message: _failureReasonToMessage(result.failureReason!),
        );
      } else {
        return EnrollmentResult(
          enrolled: false,
          message: result.message,
        );
      }
    } catch (e) {
      return EnrollmentResult(
        enrolled: false,
        message: 'Enrollment failed: $e',
      );
    }
  }

  /// Gets the enrolled template for a face ID.
  Future<FaceTemplate?> getTemplate() async {
    return await _templateStore.load();
  }

  /// Verifies a face against an enrolled template.
  Future<VerificationResult> verify({
    required List<Face> faces,
    required Size imageSize,
    required Uint8List imageBytes,
  }) async {
    try {
      final template = await _templateStore.load();
      if (template == null) {
        return VerificationResult(
          isMatch: false,
          message: 'No enrolled template found',
        );
      }

      final result = await _service.verifyWithTemplate(
        template: template,
        faces: faces,
        imageSize: imageSize,
        imageBytes: imageBytes,
      );

      return VerificationResult(
        isMatch: result.isMatch,
        message: result.message,
        distance: result.distance,
        threshold: result.threshold,
      );
    } catch (e) {
      return VerificationResult(
        isMatch: false,
        message: 'Verification failed: $e',
      );
    }
  }

  String _failureReasonToMessage(FaceVerificationFailureReason reason) {
    switch (reason) {
      case FaceVerificationFailureReason.noFace:
        return 'No face detected. Please position your face in the frame.';
      case FaceVerificationFailureReason.multipleFaces:
        return 'Multiple faces detected. Please ensure only one person is in frame.';
      case FaceVerificationFailureReason.invalidPosition:
        return 'Invalid face position. Please center your face in the frame.';
      case FaceVerificationFailureReason.invalidHeadPose:
        return 'Invalid head pose. Please face the camera directly.';
      case FaceVerificationFailureReason.challengeTimeout:
        return 'Challenge timed out. Please try again.';
      case FaceVerificationFailureReason.challengeFailed:
        return 'Challenge failed. Please follow the instructions carefully.';
      case FaceVerificationFailureReason.sessionTimeout:
        return 'Session timed out. Please restart the enrollment.';
      case FaceVerificationFailureReason.faceTooSmall:
        return 'Face too small. Please move closer to the camera.';
      case FaceVerificationFailureReason.faceTooLarge:
        return 'Face too large. Please move back from the camera.';
      case FaceVerificationFailureReason.embeddingFailed:
        return 'Could not process face. Please try again with better lighting.';
      case FaceVerificationFailureReason.identityNotMatched:
        return 'Face does not match enrolled template.';
      case FaceVerificationFailureReason.processingError:
        return 'Processing error. Please try again.';
      case FaceVerificationFailureReason.cameraUnavailable:
        return 'Camera unavailable. Please check camera permissions.';
      case FaceVerificationFailureReason.permissionDenied:
        return 'Camera permission denied. Please grant camera access in settings.';
    }
  }
}

class EnrollmentResult {
  const EnrollmentResult({required this.enrolled, this.message});
  final bool enrolled;
  final String? message;
}

class VerificationResult {
  const VerificationResult({
    required this.isMatch,
    required this.message,
    this.distance,
    this.threshold,
  });
  final bool isMatch;
  final String message;
  final double? distance;
  final double? threshold;
}