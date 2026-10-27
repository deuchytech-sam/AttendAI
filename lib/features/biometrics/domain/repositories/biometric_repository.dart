/// Provider boundary for enrollment and 1:1 identity verification.
///
/// Implement this only after choosing a vendor with suitable liveness,
/// privacy, age, device, and licensing support. A face detection result alone
/// must never be treated as proof of identity or attendance.
abstract interface class BiometricRepository {
  Future<EnrollmentResult> enrollStudent({
    required String universityId,
    required String studentId,
  });

  Future<VerificationResult> verifyStudent({
    required String universityId,
    required String studentId,
    required String sessionId,
  });

  Future<void> deleteEnrollment({
    required String universityId,
    required String studentId,
  });
}

class EnrollmentResult {
  const EnrollmentResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

class VerificationResult {
  const VerificationResult({
    required this.success,
    required this.verificationSessionId,
    this.errorMessage,
  });

  /// Opaque and short-lived provider result reference; never a face template.
  final bool success;
  final String? verificationSessionId;
  final String? errorMessage;
}
