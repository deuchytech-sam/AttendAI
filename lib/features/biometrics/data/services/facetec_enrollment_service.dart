import 'package:cloud_functions/cloud_functions.dart';
import 'package:facetec_flutter/facetec_flutter.dart';

/// Runs a FaceTec enrollment using callable Functions as the trust boundary.
/// The app receives only a short-lived session token; FaceTec credentials and
/// claim validation stay on the server.
class FaceTecEnrollmentService {
  FaceTecEnrollmentService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<FaceTecEnrollmentResult> enrollStudent({
    required String universityId,
    required String studentId,
  }) async {
    final start = await _functions
        .httpsCallable('createFaceTecEnrollment')
        .call<Map<String, dynamic>>({
      'universityId': universityId,
      'studentId': studentId,
    });
    final session = _FaceTecSession.fromMap(start.data);

    final result = await FaceTecSDK.enroll(
      sessionToken: session.token,
    );

    if (result.status == FaceTecFaceScanStatus.success) {
      final complete = await _functions
          .httpsCallable('completeFaceTecEnrollment')
          .call<Map<String, dynamic>>({'sessionId': session.id});
      return FaceTecEnrollmentResult(
        enrolled: complete.data['enrolled'] == true,
        message: complete.data['enrolled'] == true
            ? null
            : 'Face enrollment could not be completed. Please try again.',
      );
    }
    if (result.status == FaceTecFaceScanStatus.userCanceled) {
      return const FaceTecEnrollmentResult(
        enrolled: false,
        message: 'Enrollment was cancelled.',
      );
    }
    if (result.status == FaceTecFaceScanStatus.timeout) {
      return const FaceTecEnrollmentResult(
        enrolled: false,
        message: 'Enrollment timed out. Please try again.',
      );
    }
    // Failure or error
    return FaceTecEnrollmentResult(
      enrolled: false,
      message: result.statusMessage ?? 'We could not enroll your face. Please try again.',
    );
  }
}

class FaceTecEnrollmentResult {
  const FaceTecEnrollmentResult({required this.enrolled, this.message});

  final bool enrolled;
  final String? message;
}

class _FaceTecSession {
  const _FaceTecSession({
    required this.id,
    required this.token,
  });

  final String id;
  final String token;

  factory _FaceTecSession.fromMap(Map<String, dynamic> data) {
    final id = data['sessionId'];
    final token = data['token'];
    if (id is! String || token is! String) {
      throw StateError(
        'The enrollment service returned an invalid session.',
      );
    }
    return _FaceTecSession(id: id, token: token);
  }
}