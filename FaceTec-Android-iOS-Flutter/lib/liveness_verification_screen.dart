import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_liveness_verification/face_liveness_verification.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class LivenessVerificationScreen extends StatefulWidget {
  final String? enrolledFaceId;
  final FaceTemplate? enrolledTemplate;

  const LivenessVerificationScreen({
    super.key,
    this.enrolledFaceId,
    this.enrolledTemplate,
  });

  @override
  State<LivenessVerificationScreen> createState() => _LivenessVerificationScreenState();
}

class _LivenessVerificationScreenState extends State<LivenessVerificationScreen> {
  late FaceLivenessMatchService _service;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  FaceLivenessUiState _uiState = const FaceLivenessUiState(
    message: 'Initializing...',
    ringColor: Colors.orange,
    isCompleted: false,
    isValidFace: false,
    phase: FaceValidationPhase.detection,
    nextAction: null,
  );
  bool _isProcessing = false;
  bool _isInitialized = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Initialize the service
      _service = FaceLivenessMatchService(
        livenessConfig: const FaceLivenessConfig(
          actions: [
            FaceLivenessAction.smile,
            FaceLivenessAction.blink,
            FaceLivenessAction.turnLeft,
            FaceLivenessAction.turnRight,
            FaceLivenessAction.lookUp,
            FaceLivenessAction.lookDown,
          ],
          challengeTimeout: Duration(seconds: 12),
          totalSessionTimeout: Duration(seconds: 45),
          randomizeActionOrder: true,
        ),
        matchingConfig: const FaceMatchingConfig(
          metric: FaceSimilarityMetric.euclidean,
          threshold: 1.0,
        ),
        templateStore: InMemoryFaceTemplateStore(),
      );

      await _service.warmUp();

      // Initialize camera
      _cameras = await availableCameras();
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);

      setState(() {
        _isInitialized = true;
        _uiState = const FaceLivenessUiState(
          message: 'Align your face and perform the action shown',
          ringColor: Colors.orange,
          isCompleted: false,
          isValidFace: true,
          phase: FaceValidationPhase.detection,
          nextAction: FaceLivenessAction.smile,
        );
      });
    } catch (e) {
      setState(() {
        _lastError = e.toString();
        _uiState = FaceLivenessUiState(
          message: 'Error: ${e.toString()}',
          ringColor: Colors.red,
          isCompleted: false,
          isValidFace: false,
          phase: FaceValidationPhase.detection,
          nextAction: null,
        );
      });
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessing || !_isInitialized) return;

    _isProcessing = true;

    try {
      // Convert camera image to format needed by ML Kit
      final inputImage = _convertCameraImage(cameraImage);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      // Detect faces using ML Kit
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableContours: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      if (faces.isEmpty) {
        _isProcessing = false;
        return;
      }

      // Convert CameraImage to Uint8List for the service
      final imageBytes = _cameraImageToUint8List(cameraImage);
      final imageSize = Size(
        cameraImage.width.toDouble(),
        cameraImage.height.toDouble(),
      );

      FaceLivenessMatchResult result;

      if (widget.enrolledTemplate != null) {
        // Verification mode - verify against enrolled template
        result = await _service.verifyWithTemplate(
          template: widget.enrolledTemplate!,
          faces: faces,
          imageSize: imageSize,
          imageBytes: imageBytes,
        );
      } else if (widget.enrolledFaceId != null) {
        // Enrollment mode - enroll new face
        result = await _service.enrollAndPersist(
          faceId: widget.enrolledFaceId!,
          faces: faces,
          imageSize: imageSize,
          imageBytes: imageBytes,
          requireLiveness: true,
        );
      } else {
        // Demo mode - just run liveness check without enrollment/verification
        // Use evaluateFrame with a dummy template for liveness-only check
        final dummyEmbedding = Float32List(128);
        result = await _service.evaluateFrame(
          faces: faces,
          imageSize: imageSize,
          imageBytes: imageBytes,
          templateEmbedding: dummyEmbedding,
          faceId: 'demo_liveness_only',
        );
        // Override match-related fields since we're only doing liveness
        result = FaceLivenessMatchResult(
          isValidFace: result.isValidFace,
          isLivenessComplete: result.isLivenessComplete,
          isMatchComplete: false,
          isMatch: false,
          message: result.message,
          phase: FaceValidationPhase.detection,
          nextAction: result.nextAction,
          faceId: widget.enrolledFaceId,
          completedChallenges: result.completedChallenges,
          failureReason: result.failureReason,
        );
      }

      if (mounted) {
        setState(() {
          _uiState = FaceLivenessUiState.fromLivenessMatchResult(result);
        });

        // Check if completed
        if (result.isMatchComplete && result.isMatch) {
          _showSuccessDialog(result);
        } else if (result.isMatchComplete && !result.isMatch) {
          _showFailureDialog(result);
        } else if (result.failureReason == FaceVerificationFailureReason.sessionTimeout) {
          _showTimeoutDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e.toString();
          _uiState = FaceLivenessUiState(
            message: 'Error: ${e.toString()}',
            ringColor: Colors.red,
            isCompleted: false,
            isValidFace: false,
            phase: FaceValidationPhase.detection,
            nextAction: null,
          );
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage cameraImage) {
    try {
      final bytesBuilder = BytesBuilder();
      for (final Plane plane in cameraImage.planes) {
        bytesBuilder.add(plane.bytes);
      }
      final bytes = bytesBuilder.toBytes();

      final Size imageSize = Size(
        cameraImage.width.toDouble(),
        cameraImage.height.toDouble(),
      );

      final InputImageRotation rotation = _getImageRotation(
        _cameraController!.description.sensorOrientation,
        _cameraController!.description.lensDirection,
      );

      final InputImageFormat format = InputImageFormat.bgra8888;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  Uint8List _cameraImageToUint8List(CameraImage cameraImage) {
    final bytesBuilder = BytesBuilder();
    for (final Plane plane in cameraImage.planes) {
      bytesBuilder.add(plane.bytes);
    }
    return bytesBuilder.toBytes();
  }

  InputImageRotation _getImageRotation(int sensorOrientation, CameraLensDirection lensDirection) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _showSuccessDialog(FaceLivenessMatchResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Success'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Face verification successful!'),
            const SizedBox(height: 16),
            if (result.faceId != null) Text('Face ID: ${result.faceId}'),
            if (result.distance != null)
              Text('Distance: ${result.distance!.toStringAsFixed(4)}'),
            if (result.threshold != null)
              Text('Threshold: ${result.threshold!.toStringAsFixed(4)}'),
            if (result.completedChallenges != null)
              Text('Challenges: ${result.completedChallenges!.join(", ")}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(result);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFailureDialog(FaceLivenessMatchResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Verification Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Face did not match the enrolled template.'),
            const SizedBox(height: 16),
            if (result.distance != null)
              Text('Distance: ${result.distance!.toStringAsFixed(4)}'),
            if (result.threshold != null)
              Text('Threshold: ${result.threshold!.toStringAsFixed(4)}'),
            if (result.failureReason != null)
              Text('Reason: ${result.failureReason}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _service.reset();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('Session Timeout'),
          ],
        ),
        content: const Text('The liveness session has timed out. Please try again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _service.reset();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Liveness Verification')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Liveness Verification'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // Camera preview with liveness UI overlay
          FaceLivenessUi(
            preview: CameraPreview(_cameraController!),
            state: _uiState,
          ),
          // Error display
          if (_lastError != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _lastError!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}