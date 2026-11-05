import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

import '../../biometrics/domain/services/face_liveness_service.dart';
import '../data/datasources/firestore_university_data_source.dart';

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
    required this.dataSource,
  });

  final String userId;
  final String universityId;
  final FaceLivenessService livenessService;
  final FirestoreUniversityDataSource dataSource;

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Check if face already registered (locally or in cloud)
    _checkExistingRegistration();
  }

  Future<void> _checkExistingRegistration() async {
    // Check local first
    final hasLocalTemplate = await widget.livenessService.hasTemplate(faceId: widget.userId);
    if (hasLocalTemplate && mounted) {
      setState(() {
        _error = 'Face already enrolled for this user. Please verify instead.';
      });
      return;
    }
    // Check cloud
    final hasCloudTemplate = await widget.dataSource.hasFaceEmbeddings(widget.userId);
    if (hasCloudTemplate && mounted) {
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
        // Face successfully enrolled locally, now save to cloud
        // Export face embeddings from local storage
        final embeddings = widget.livenessService.exportFace(widget.userId);
        if (embeddings == null || embeddings.isEmpty) {
          if (mounted) {
            setState(() {
              _error = 'No face embeddings generated. Please try again.';
              _isProcessing = false;
            });
          }
          return;
        }

        try {
          // Save to Firestore - MUST succeed for cross-device verification to work
          await widget.dataSource.saveFaceEmbeddings(
            faceId: widget.userId,
            embeddings: embeddings,
            studentId: widget.userId,
          );
          debugPrint('[FaceEnrollment] Saved ${embeddings.length} embeddings to Firestore for faceId: ${widget.userId}');
        } catch (e) {
          debugPrint('[FaceEnrollment] Error saving to Firestore: $e');
          if (mounted) {
            setState(() {
              _error = 'Face enrolled locally but failed to sync to cloud: $e. Please try again or contact support.';
              _isProcessing = false;
            });
          }
          return;
        }

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
            Expanded(child: Text('Face Enrolled')),
          ],
        ),
        content: Text(
          'Your face has been saved (ID: $faceId). You can now use it to check in on any device.',
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
    final config = widget.livenessService.createEnrollmentConfig(
      faceId: widget.userId,
    );

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
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _error = null;
                                });
                              },
                              child: const Text('Dismiss'),
                            ),
                          ),
                          if (kDebugMode) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await widget.livenessService.clearAllTemplates();
                                  if (mounted) {
                                    setState(() {
                                      _error = null;
                                    });
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('All face templates cleared (debug)'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                ),
                                child: const Text('Reset Enrollment'),
                              ),
                            ),
                          ],
                        ],
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