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
  bool _isPreparing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareExistingRegistration();
  }

  Future<void> _prepareExistingRegistration() async {
    try {
      if (await widget.dataSource.isFaceEnrollmentResetRequired(
        widget.userId,
      )) {
        await widget.livenessService.deleteTemplate(faceId: widget.userId);
        await widget.livenessService.clearSyncPending(widget.userId);
      }
      // Seed local storage before the liveness widget initializes its own
      // FaceIdentityService, so re-enrollment can replace this user's template.
      final existing = await widget.dataSource.loadFaceEmbeddings(
        widget.userId,
      );
      if (existing != null && existing.isNotEmpty) {
        await widget.livenessService.importFace(widget.userId, existing);
      } else {
        await widget.livenessService.refreshStoredFaces();
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[FaceEnrollment] Failed to prepare existing face data: $e\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _error = 'Could not load existing face data: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  void _onEnrollmentSuccess(LivenessResult result) async {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      if (result.isSuccess && result.faceId != null) {
        debugPrint(
          '[FaceEnrollment] Liveness success; faceId=${result.faceId}, '
          'captureBytes=${result.bestFrontalImageBytes?.length ?? 0}',
        );
        // FlutterFaceLiveness writes to its own FaceIdentityService instance.
        // Reload its persisted gallery before exporting from the app service.
        await widget.livenessService.refreshStoredFaces();
        final allFaces = widget.livenessService.exportAllFaces();
        final enrolledFaceId = result.faceId!;
        final embeddings = allFaces[enrolledFaceId];
        final embeddingLength = embeddings == null || embeddings.isEmpty
            ? 0
            : embeddings.first.length;
        debugPrint(
          '[FaceEnrollment] Gallery IDs=${allFaces.keys.toList()}, '
          'embeddingCount=${embeddings?.length ?? 0}, length=$embeddingLength, dtype=double',
        );

        if (embeddings == null || embeddings.isEmpty) {
          if (mounted) {
            setState(() {
              _error = 'Enrollment completed, but its local embedding could not be loaded. Your existing data was kept; please retry enrollment.';
              _isProcessing = false;
            });
          }
          return;
        }

        var syncPending = false;
        try {
          // Save to Firestore under the student's userId for cross-device sync
          await widget.dataSource.saveFaceEmbeddings(
            faceId: widget.userId,
            embeddings: embeddings,
            studentId: widget.userId,
          );
          final savedEmbeddings = await widget.dataSource.loadFaceEmbeddings(
            widget.userId,
          );
          if (savedEmbeddings == null ||
              savedEmbeddings.isEmpty ||
              savedEmbeddings.length != embeddings.length ||
              savedEmbeddings.any(
                (vector) => vector.length != embeddingLength,
              )) {
            throw StateError('Saved face embedding could not be read back.');
          }
          debugPrint(
            '[FaceEnrollment] Verified Firestore row=${widget.userId}, '
            'userId=${widget.userId}, embeddings=${savedEmbeddings.length}, '
            'length=${savedEmbeddings.first.length}, dtype=double',
          );
          await widget.livenessService.clearSyncPending(widget.userId);

          // Also import into FaceIdentityService under userId for local verification
          // This ensures verification can find the face using widget.userId
          if (enrolledFaceId != widget.userId) {
            await widget.livenessService.importFace(widget.userId, embeddings);
            debugPrint(
              '[FaceEnrollment] Imported embeddings under userId: ${widget.userId}',
            );
          }
        } catch (e, stackTrace) {
          debugPrint(
            '[FaceEnrollment] Error saving to Firestore: $e\n$stackTrace',
          );
          try {
            await widget.livenessService.markSyncPending(widget.userId);
          } catch (pendingError, pendingStackTrace) {
            debugPrint(
              '[FaceEnrollment] Could not persist pending-sync marker: '
              '$pendingError\n$pendingStackTrace',
            );
          }
          syncPending = true;
        }

        if (mounted) {
          _showSuccessDialog(enrolledFaceId, syncPending: syncPending);
        }
      } else {
        setState(() {
          _error =
              result.failureReason ?? 'Enrollment failed. Please try again.';
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[FaceEnrollment] Enrollment stage failed: $e\n$stackTrace');
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

  void _showSuccessDialog(String faceId, {required bool syncPending}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                syncPending ? 'Face Enrolled Locally' : 'Face Enrolled',
              ),
            ),
          ],
        ),
        content: Text(
          syncPending
              ? 'Your face is saved on this device (ID: $faceId). Cloud sync is pending; check-in will work on this device and sync will retry next time you open verification.'
              : 'Your face has been saved (ID: $faceId). You can now use it to check in on any device.',
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
          if (_isPreparing)
            const Center(child: CircularProgressIndicator())
          else
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
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await widget.livenessService
                                      .clearAllTemplates();
                                  if (mounted) {
                                    setState(() {
                                      _error = null;
                                    });
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'All face templates cleared (debug)',
                                        ),
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
