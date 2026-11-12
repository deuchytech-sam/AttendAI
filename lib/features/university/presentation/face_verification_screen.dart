import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../biometrics/domain/services/face_liveness_service.dart';
import '../data/datasources/firestore_university_data_source.dart';
import 'face_enrollment_screen.dart';
import 'university_bloc.dart';

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
    required this.dataSource,
  });

  final String userId;
  final String universityId;
  final FaceLivenessService livenessService;
  final FirestoreUniversityDataSource dataSource;

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  bool _isProcessing = false;
  String? _error;
  bool _needsEnrollment = false;
  bool _isLoadingFaceData = false;
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    // Check if face is already enrolled (locally or in cloud)
    _checkEnrollment();
  }

  Future<void> _checkEnrollment() async {
    setState(() {
      _isLoadingFaceData = true;
      _showRetry = false;
    });

    try {
      // A lecturer reset is stored in Firestore. Honor it before consulting
      // this device's local gallery so stale templates cannot keep being used.
      if (await widget.dataSource.isFaceEnrollmentResetRequired(
        widget.userId,
      )) {
        await widget.livenessService.deleteTemplate(faceId: widget.userId);
        await widget.livenessService.clearSyncPending(widget.userId);
        debugPrint(
          '[FaceVerification] Cleared locally cached template after lecturer reset for ${widget.userId}',
        );
      }
      await widget.livenessService.refreshStoredFaces();
      // Check local first
      final hasLocalTemplate = await widget.livenessService.hasTemplate(
        faceId: widget.userId,
      );

      if (hasLocalTemplate) {
        if (await widget.livenessService.isSyncPending(widget.userId)) {
          await _retryPendingFaceSync();
        }
        // Face data exists locally, ready for verification
        if (mounted) {
          setState(() {
            _isLoadingFaceData = false;
          });
        }
        return;
      }

      // Check cloud
      final hasCloudTemplate = await widget.dataSource.hasFaceEmbeddings(
        widget.userId,
      );

      if (!hasCloudTemplate) {
        // No face data anywhere - needs enrollment
        if (mounted) {
          setState(() {
            _needsEnrollment = true;
            _error = 'You have not enrolled your face yet. Enroll once, then you can check in.';
            _isLoadingFaceData = false;
          });
        }
        return;
      }

      // Face data exists in cloud but not locally - import it
      if (mounted) {
        setState(() {
          _error = 'Loading your face data from cloud...';
        });
      }

      final embeddings = await widget.dataSource.loadFaceEmbeddings(
        widget.userId,
      );

      if (embeddings != null && embeddings.isNotEmpty) {
        // Import to local FaceIdentityService
        await widget.livenessService.importFace(widget.userId, embeddings);
        await widget.livenessService.clearSyncPending(widget.userId);
        debugPrint(
          '[FaceVerification] Imported ${embeddings.length} embeddings from Firestore for faceId: ${widget.userId}',
        );

        if (mounted) {
          setState(() {
            _isLoadingFaceData = false;
            _error = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _needsEnrollment = true;
            _error =
                'Face data found but could not be loaded. Please re-enroll.';
            _isLoadingFaceData = false;
          });
        }
      }
    } on FirebaseException catch (e) {
      debugPrint(
        '[FaceVerification] Firebase error loading face data: ${e.code} - ${e.message}',
      );
      if (mounted) {
        if (e.code == 'permission-denied') {
          setState(() {
            _error = 'Couldn\'t load your face data. Check your connection or contact support.';
            _isLoadingFaceData = false;
            _showRetry = true;
          });
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          setState(() {
            _error =
                'Network error. Please check your connection and try again.';
            _isLoadingFaceData = false;
            _showRetry = true;
          });
        } else {
          setState(() {
            _error =
                'Failed to load face data: ${e.message}. Please try again.';
            _isLoadingFaceData = false;
            _showRetry = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[FaceVerification] Error loading face data: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load face data: $e. Please try again.';
          _isLoadingFaceData = false;
          _showRetry = true;
        });
      }
    }
  }

  Future<void> _retryPendingFaceSync() async {
    final embeddings = widget.livenessService.exportFace(widget.userId);
    if (embeddings == null || embeddings.isEmpty) return;
    try {
      await widget.dataSource.saveFaceEmbeddings(
        faceId: widget.userId,
        embeddings: embeddings,
        studentId: widget.userId,
      );
      final saved = await widget.dataSource.loadFaceEmbeddings(widget.userId);
      if (saved == null ||
          saved.isEmpty ||
          saved.length != embeddings.length ||
          saved.any((vector) => vector.length != embeddings.first.length)) {
        throw StateError('Synced face embedding could not be read back.');
      }
      await widget.livenessService.clearSyncPending(widget.userId);
      debugPrint(
        '[FaceVerification] Pending face sync completed; '
        'userId=${widget.userId}, vectors=${saved.length}, '
        'lengths=${saved.map((vector) => vector.length).toList()}',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[FaceVerification] Pending face sync failed: $e\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _error = 'Your face is available on this device. Cloud sync is still pending; it will retry next time.';
        });
      }
    }
  }

  void _onVerificationSuccess(LivenessResult result) async {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      if (result.isSuccess) {
        // Face successfully verified - export embeddings using the student's userId
        // (face was enrolled with userId as faceId, not result.faceId)
        final faceId = widget.userId;
        final faceMatchScore = result.faceMatchScore ?? 0.0;
        final faceEmbeddings = widget.livenessService.exportFace(faceId);

        if (faceEmbeddings == null || faceEmbeddings.isEmpty) {
          if (mounted) {
            setState(() {
              _error = 'Could not export face data. Please try again.';
              _isProcessing = false;
            });
          }
          return;
        }

        if (mounted) {
          _showSuccessDialog(faceId, faceEmbeddings, faceMatchScore);
        }
      } else {
        // Verification failed - could be face not recognized
        setState(() {
          _error = result.failureReason ?? 'Face not recognized. Please try again with good lighting and face clearly visible.';
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
    // Check if failure is due to face not matching
    String errorMessage = reason;
    if (reason.toLowerCase().contains('not found') ||
        reason.toLowerCase().contains('not recognized') ||
        reason.toLowerCase().contains('no match') ||
        reason.toLowerCase().contains('similarity')) {
      errorMessage = 'Face not recognized. Please try again with good lighting and face clearly visible.';
    }
    setState(() {
      _error = errorMessage;
      _isProcessing = false;
    });
  }

  void _showSuccessDialog(
    String faceId,
    List<List<double>> faceEmbeddings,
    double faceMatchScore,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('Verification Successful')),
          ],
        ),
        content: Text(
          'Face verified successfully! (ID: $faceId)\nMatch: ${(faceMatchScore * 100).toStringAsFixed(1)}%',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog
              _recordAttendance(
                faceEmbeddings,
                faceMatchScore,
              ); // Record attendance
            },
            child: const Text('Check In'),
          ),
        ],
      ),
    );
  }

  String _friendlyPreconditionMessage(String? serverMessage) {
    final message = serverMessage?.toLowerCase() ?? '';
    if (message.contains('student roster record is not linked')) {
      return 'Your student profile could not be matched to the course roster. Ask your lecturer to check your matric number.';
    }
    if (message.contains('multiple roster records') ||
        message.contains('linked to another account')) {
      return 'Your student record needs attention. Please contact your lecturer.';
    }
    if (message.contains('course enrollment is incomplete')) {
      return 'Your student account is not linked to a course. Please contact your lecturer.';
    }
    if (message.contains('no open attendance session')) {
      return 'No session is open for your enrolled course. Ask your lecturer to open the correct course session.';
    }
    if (message.contains('attendance session is closed') ||
        message.contains('session is closed or invalid')) {
      return 'The attendance session closed before check-in completed. Ask your lecturer to reopen it.';
    }
    if (message.contains('face not enrolled') ||
        message.contains('no enrolled face embeddings')) {
      return 'Your face enrollment could not be found on the server. Please re-enroll your face.';
    }
    return 'Check-in could not be completed. Please try again.';
  }

  Future<void> _recordAttendance(
    List<List<double>> faceEmbeddings,
    double faceMatchScore,
  ) async {
    if (!mounted) return;
    final bloc = context.read<UniversityBloc>();
    final studentId = bloc.dataSource.userId;
    final courseId = bloc.state.openSessionCourseId;
    if (courseId == null || courseId.isEmpty) {
      setState(() {
        _error = 'No open course session was found. Ask your lecturer to open the session.';
        _isProcessing = false;
      });
      return;
    }
    try {
      await bloc.dataSource.checkIn(
        studentId: studentId,
        courseId: courseId,
        faceEmbeddings: faceEmbeddings,
        faceMatchScore: faceMatchScore,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseFunctionsException catch (e, stackTrace) {
      debugPrint(
        '[CheckIn] Cloud Function failed: code=${e.code}, '
        'message=${e.message}, details=${e.details}\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _error = switch (e.code) {
            'unauthenticated' => 'Your session expired. Please sign in again.',
            'permission-denied' => 'You do not have permission to check in.',
            'failed-precondition' =>
              _friendlyPreconditionMessage(e.message),
            'not-found' || 'unavailable' || 'deadline-exceeded' || 'internal' =>
              'Check-in service unavailable, please try again.',
            _ => 'Check-in could not be completed. Please try again.',
          };
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[CheckIn] Failed: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _error = 'Check-in could not be completed. Please try again.';
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _openEnrollment() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FaceEnrollmentScreen(
          userId: widget.userId,
          universityId: widget.universityId,
          livenessService: widget.livenessService,
          dataSource: widget.dataSource,
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

  void _retryLoading() {
    _checkEnrollment();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFaceData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Verification')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading face data...'),
            ],
          ),
        ),
      );
    }

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
                if (_showRetry) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retryLoading,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry loading face data'),
                  ),
                ],
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
                      if (_showRetry) ...[
                        OutlinedButton.icon(
                          onPressed: _retryLoading,
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text(
                            'Retry',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
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
