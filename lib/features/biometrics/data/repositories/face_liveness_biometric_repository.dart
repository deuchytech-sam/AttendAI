import '../../domain/repositories/biometric_repository.dart';
import '../../domain/services/face_liveness_service.dart' hide EnrollmentResult, VerificationResult;

/// Repository for face liveness biometric operations using flutter_face_liveness.
class FaceLivenessBiometricRepository implements BiometricRepository {
  FaceLivenessBiometricRepository({
    required this.livenessService,
  });

  final FaceLivenessService livenessService;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String universityId,
    required String studentId,
  }) async {
    // The actual enrollment is handled by FlutterFaceLiveness widget
    // with FaceIdMode.registrationOnly. This method checks if already enrolled.
    final hasTemplate = await livenessService.hasTemplate(faceId: studentId);
    if (hasTemplate) {
      return EnrollmentResult(
        success: false,
        errorMessage: 'Face already enrolled for this student',
      );
    }
    // Enrollment will be done via the widget, return ready status
    return const EnrollmentResult(success: true);
  }

  @override
  Future<VerificationResult> verifyStudent({
    required String universityId,
    required String studentId,
    required String sessionId,
  }) async {
    // The actual verification is handled by FlutterFaceLiveness widget
    // with FaceIdMode.verificationOnly. This method checks if enrolled.
    final hasTemplate = await livenessService.hasTemplate(faceId: studentId);
    if (!hasTemplate) {
      return VerificationResult(
        success: false,
        verificationSessionId: sessionId,
        errorMessage: 'No enrolled template found for student $studentId',
      );
    }
    // Verification will be done via the widget, return ready status
    return VerificationResult(
      success: true,
      verificationSessionId: sessionId,
    );
  }

  @override
  Future<void> deleteEnrollment({
    required String universityId,
    required String studentId,
  }) async {
    await livenessService.deleteTemplate(faceId: studentId);
  }

  /// Checks if a face template exists for the given user ID.
  Future<bool> hasTemplate({required String faceId}) async {
    return livenessService.hasTemplate(faceId: faceId);
  }
}