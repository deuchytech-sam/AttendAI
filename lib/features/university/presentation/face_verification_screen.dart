import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

import '../../biometrics/domain/services/face_liveness_service.dart';
import 'face_enrollment_screen.dart';
import 'university_bloc.dart';
import 'university_event.dart';

/// Screen for face liveness verification during check-in using FlutterFaceLiveness widget.
///
/// This screen uses the FlutterFaceLiveness widget which handles camera,
/// liveness challenges, and face verification against enrolled templates.
/// On success, it records attendance.
class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({
    super.key,
    required this.userId,
    required this.universityId,
    required this.livenessService,
  });

  final String userId;
  final String universityId;
  final FaceLivenessService livenessService;

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  bool _isProcessing = false;
  String? _error;
  bool _needsEnrollment = false;

  @override
  void initState() {
    super.initState();
    // Check if face is already enrolled
    _checkEnrollment();
  }

  Future<void> _checkEnrollment() async {
    final hasTemplate = await widget.livenessService.hasTemplate(faceId: widget.userId);
    if (!hasTemplate && mounted) {
      setState(() {
        _needsEnrollment = true;
        _error = 'You have not enrolled your face yet. Enroll once, then you can check in.';
      });
    }
  }

  void _onVerificationSuccess(LivenessResult result) async {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      if (result.isSuccess && result.faceId != null) {
        // Face successfully verified
        if (mounted) {
          _showSuccessDialog(result.faceId!);
        }
      } else {
        setState(() {
          _error = result.failureReason ?? 'Verification failed. Please try again.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Verification error: $e';
          _isProcessing = false;
        });
      }
    }
  }

  void _onVerificationFailed(String reason) {
    if (!mounted) return;
    setState(() {
      _error = reason;
      _isProcessing = false;
    });
  }

  void _showSuccessDialog(String faceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Verification Successful'),
          ],
        ),
        content: Text(
          'Face verified successfully! (ID: $faceId)',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog
              _recordAttendance(); // Record attendance
            },
            child: const Text('Check In'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordAttendance() async {
    if (!mounted) return;
    context.read<UniversityBloc>().add(const StudentCheckInRequested());
    Navigator.of(context).pop(true);
  }

  Future<void> _openEnrollment() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FaceEnrollmentScreen(
          userId: widget.userId,
          universityId: widget.universityId,
          livenessService: widget.livenessService,
        ),
      ),
    );

    if (enrolled == true && mounted) {
      setState(() {
        _needsEnrollment = false;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needsEnrollment) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Verification')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'You have not enrolled your face yet.',
                  textAlign: TextAlign.center,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _openEnrollment,
                  icon: const Icon(Icons.face),
                  label: const Text('Enroll your face'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final config = widget.livenessService.createVerificationConfig();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          FlutterFaceLiveness(
            actions: defaultLivenessActions,
            config: config,
            onSuccess: _onVerificationSuccess,
            onFailed: _onVerificationFailed,
          ),
          if (_error != null && !_needsEnrollment)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                          });
                        },
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}