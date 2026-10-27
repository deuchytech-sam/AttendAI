import 'package:face_liveness_verification/face_liveness_verification.dart';

import '../../domain/repositories/biometric_repository.dart';
import '../services/face_liveness_attendance_service.dart' as attendance_service;

/// Local implementation of the [BiometricRepository] interface using
/// face_liveness_verification package for on-device liveness and matching.
class FaceLivenessBiometricRepository implements BiometricRepository {
  FaceLivenessBiometricRepository({
    required this._attendanceService,
    FaceTemplateStore? templateStore,
  }) : _templateStore = templateStore ?? InMemoryFaceTemplateStore();

  final attendance_service.FaceLivenessAttendanceService _attendanceService;
  final FaceTemplateStore _templateStore;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String universityId,
    required String studentId,
  }) async {
    try {
      // The face_liveness_verification package handles enrollment directly
      // The actual enrollment happens in the UI flow (LivenessVerificationScreen)
      // This service method is called after the UI flow completes
      // For now, we'll return success - the actual enrollment is handled by the UI
      return const EnrollmentResult(
        success: true,
        errorMessage: null,
      );
    } catch (e) {
      return EnrollmentResult(
        success: false,
        errorMessage: 'Enrollment failed: $e',
      );
    }
  }

  @override
  Future<VerificationResult> verifyStudent({
    required String universityId,
    required String studentId,
    required String sessionId,
  }) async {
    try {
      final result = await _attendanceService.verifyStudent();

      return VerificationResult(
        success: result.recorded,
        verificationSessionId: result.recorded ? sessionId : null,
        errorMessage: result.message,
      );
    } catch (e) {
      return VerificationResult(
        success: false,
        verificationSessionId: null,
        errorMessage: 'Verification failed: $e',
      );
    }
  }

  @override
  Future<void> deleteEnrollment({
    required String universityId,
    required String studentId,
  }) async {
    await _templateStore.delete();
  }

  /// Get the template store for UI integration
  FaceTemplateStore get templateStore => _templateStore;
}