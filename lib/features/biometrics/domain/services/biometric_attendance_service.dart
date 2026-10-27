/// Interface for biometric attendance verification services.
///
/// Implementations (iProov, FaceTec, etc.) handle the provider-specific
/// liveness/identity verification flow and return a result indicating
/// whether attendance was recorded.
abstract interface class BiometricAttendanceService {
  /// Runs a verification for an open attendance session.
  ///
  /// Returns a result with [recorded] true if the student's identity was
  /// verified and attendance was recorded, false otherwise.
  Future<BiometricAttendanceResult> verifyOpenSession();
}

class BiometricAttendanceResult {
  const BiometricAttendanceResult({required this.recorded, this.message});

  final bool recorded;
  final String? message;
}