import 'package:flutter/material.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

import '../../biometrics/domain/services/face_liveness_service.dart';

/// Screen where a student enrolls their face using FlutterFaceLiveness widget.
///
/// It runs liveness challenges and registers the face template under [userId].
/// Pops with `true` when enrollment succeeds.
class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({
    super.key,
    required this.userId,
    required this.universityId,
    required this.livenessService,
  });

  final String userId;
  final String universityId;
  final FaceLivenessService livenessService;

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Check if face already registered
    _checkExistingRegistration();
  }

  Future<void> _checkExistingRegistration() async {
    final hasTemplate = await widget.livenessService.hasTemplate(faceId: widget.userId);
    if (hasTemplate && mounted) {
      setState(() {
        _error = 'Face already enrolled for this user. Please verify instead.';
      });
    }
  }

  void _onEnrollmentSuccess(LivenessResult result) async {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      if (result.isSuccess && result.faceId != null) {
        // Face successfully enrolled
        if (mounted) {
          _showSuccessDialog(result.faceId!);
        }
      } else {
        setState(() {
          _error = result.failureReason ?? 'Enrollment failed. Please try again.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Enrollment error: $e';
          _isProcessing = false;
        });
      }
    }
  }

  void _onEnrollmentFailed(String reason) {
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
            Text('Face Enrolled'),
          ],
        ),
        content: Text(
          'Your face has been saved (ID: $faceId). You can now use it to check in.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // close dialog
              Navigator.of(context).pop(true); // close screen with success
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.livenessService.createEnrollmentConfig();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Your Face'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          FlutterFaceLiveness(
            actions: defaultLivenessActions,
            config: config,
            onSuccess: _onEnrollmentSuccess,
            onFailed: _onEnrollmentFailed,
          ),
          if (_error != null)
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