import 'package:flutter_face_liveness/flutter_face_liveness.dart';

/// Service for face liveness detection and face identity using flutter_face_liveness package.
class FaceLivenessService {
  FaceLivenessService({
    FaceIdMode faceIdMode = FaceIdMode.verificationOnly,
    double similarityThreshold = 0.82,
    double registrationDuplicateThreshold = 0.75,
    double minEmbeddingQuality = 0.50,
    int maxEmbeddingsPerFace = 5,
  }) : _faceIdentityService = FaceIdentityService(
          similarityThreshold: similarityThreshold,
          registrationDuplicateThreshold: registrationDuplicateThreshold,
          minEmbeddingQuality: minEmbeddingQuality,
          mode: faceIdMode,
          maxEmbeddingsPerFace: maxEmbeddingsPerFace,
        );

  final FaceIdentityService _faceIdentityService;

  /// Initializes the face identity service (loads models and stored faces).
  Future<void> initialize({
    void Function(double progress)? onModelDownloadProgress,
  }) async {
    await _faceIdentityService.initialize(onModelDownloadProgress: onModelDownloadProgress);
  }

  /// Disposes resources.
  void dispose() {
    _faceIdentityService.dispose();
  }

  /// Gets the face identity service for direct access if needed.
  FaceIdentityService get faceIdentityService => _faceIdentityService;

  /// Checks if a face template exists for the given user ID.
  Future<bool> hasTemplate({required String faceId}) async {
    return _faceIdentityService.registeredFaceIds.contains(faceId);
  }

  /// Gets all registered face IDs.
  List<String> getRegisteredFaceIds() {
    return _faceIdentityService.registeredFaceIds;
  }

  /// Deletes a face template for the given user ID.
  Future<void> deleteTemplate({required String faceId}) async {
    await _faceIdentityService.removeFace(faceId);
  }

  /// Clears all face templates.
  Future<void> clearAllTemplates() async {
    await _faceIdentityService.clearAllFaces();
  }

  /// Creates the liveness configuration for enrollment (registration).
  LivenessConfig createEnrollmentConfig({
    bool randomizeActions = true,
    bool enableAntiSpoof = true,
    bool enableFaceId = true,
    bool enableBestFrontalCapture = true,
    bool showDebugOverlay = false,
  }) {
    return LivenessConfig(
      randomizeActions: randomizeActions,
      enableAntiSpoof: enableAntiSpoof,
      enableFaceId: enableFaceId,
      faceIdMode: FaceIdMode.registrationOnly,
      enableBestFrontalCapture: enableBestFrontalCapture,
      showDebugOverlay: showDebugOverlay,
    );
  }

  /// Creates the liveness configuration for verification.
  LivenessConfig createVerificationConfig({
    bool randomizeActions = true,
    bool enableAntiSpoof = true,
    bool enableFaceId = true,
    bool enableBestFrontalCapture = false,
    bool showDebugOverlay = false,
  }) {
    return LivenessConfig(
      randomizeActions: randomizeActions,
      enableAntiSpoof: enableAntiSpoof,
      enableFaceId: enableFaceId,
      faceIdMode: FaceIdMode.verificationOnly,
      enableBestFrontalCapture: enableBestFrontalCapture,
      showDebugOverlay: showDebugOverlay,
    );
  }

  /// Creates the liveness configuration for auto mode (match or register).
  LivenessConfig createAutoConfig({
    bool randomizeActions = true,
    bool enableAntiSpoof = true,
    bool enableFaceId = true,
    bool enableBestFrontalCapture = false,
    bool showDebugOverlay = false,
  }) {
    return LivenessConfig(
      randomizeActions: randomizeActions,
      enableAntiSpoof: enableAntiSpoof,
      enableFaceId: enableFaceId,
      faceIdMode: FaceIdMode.auto,
      enableBestFrontalCapture: enableBestFrontalCapture,
      showDebugOverlay: showDebugOverlay,
    );
  }
}

/// Default actions for liveness challenges (enrollment and verification).
const List<LivenessAction> defaultLivenessActions = [
  LivenessAction.smile,
  LivenessAction.blink,
  LivenessAction.turnLeft,
  LivenessAction.turnRight,
];

/// Result of enrollment operation.
class EnrollmentResult {
  const EnrollmentResult({
    required this.enrolled,
    required this.faceId,
    required this.confidenceScore,
    required this.completedActions,
    this.message,
  });

  final bool enrolled;
  final String faceId;
  final double confidenceScore;
  final List<LivenessAction> completedActions;
  final String? message;
}

/// Result of verification operation.
class VerificationResult {
  const VerificationResult({
    required this.verified,
    required this.faceId,
    required this.confidenceScore,
    required this.faceMatchScore,
    required this.completedActions,
    this.message,
  });

  final bool verified;
  final String faceId;
  final double confidenceScore;
  final double faceMatchScore;
  final List<LivenessAction> completedActions;
  final String? message;
}