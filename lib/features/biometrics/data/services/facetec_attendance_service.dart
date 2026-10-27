import 'package:cloud_functions/cloud_functions.dart';
import 'package:facetec_flutter/facetec_flutter.dart';

import '../../domain/services/biometric_attendance_service.dart';

/// Runs a FaceTec attendance verification using callable Functions as the
/// trust boundary. The app receives only a short-lived session token; FaceTec
/// credentials and claim validation stay on the server.
class FaceTecAttendanceService implements BiometricAttendanceService {
  FaceTecAttendanceService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  @override
  Future<BiometricAttendanceResult> verifyOpenSession() async {
    final start = await _functions
        .httpsCallable('createFaceTecAttendanceVerification')
        .call<Map<String, dynamic>>();
    final session = _FaceTecSession.fromMap(start.data);

    final result = await FaceTecSDK.verify(
      sessionToken: session.token,
    );

    if (result.status == FaceTecFaceScanStatus.success) {
      final complete = await _functions
          .httpsCallable('completeFaceTecAttendanceVerification')
          .call<Map<String, dynamic>>({'sessionId': session.id});
      return BiometricAttendanceResult(
        recorded: complete.data['recorded'] == true,
        message: complete.data['recorded'] == true
            ? null
            : 'Attendance is already recorded for this session.',
      );
    }
    if (result.status == FaceTecFaceScanStatus.userCanceled) {
      return const BiometricAttendanceResult(
        recorded: false,
        message: 'Verification was cancelled.',
      );
    }
    if (result.status == FaceTecFaceScanStatus.timeout) {
      return const BiometricAttendanceResult(
        recorded: false,
        message: 'Verification timed out. Please try again.',
      );
    }
    // Failure or error
    return BiometricAttendanceResult(
      recorded: false,
      message: result.statusMessage ?? 'We could not verify your identity. Please try again.',
    );
  }
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
        'The verification service returned an invalid session.',
      );
    }
    return _FaceTecSession(id: id, token: token);
  }
}