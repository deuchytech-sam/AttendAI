import '../../domain/repositories/biometric_repository.dart';
import '../services/facetec_enrollment_service.dart';
import '../services/facetec_attendance_service.dart';

/// FaceTec implementation of the [BiometricRepository] interface.
class FaceTecBiometricRepository implements BiometricRepository {
  FaceTecBiometricRepository({
    required this._enrollmentService,
    required this._attendanceService,
  });

  final FaceTecEnrollmentService _enrollmentService;
  final FaceTecAttendanceService _attendanceService;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String universityId,
    required String studentId,
  }) async {
    try {
      final result = await _enrollmentService.enrollStudent(
        universityId: universityId,
        studentId: studentId,
      );
      return EnrollmentResult(
        success: result.enrolled,
        errorMessage: result.message,
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
      final result = await _attendanceService.verifyOpenSession();
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
    // This would require a Cloud Function to delete the FaceTec user and biometric profile
    // For now, we'll throw an error indicating it's not implemented
    throw UnimplementedError('Delete enrollment not yet implemented');
  }
}