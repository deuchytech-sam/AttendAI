import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detects face count and basic face features for camera framing guidance.
///
/// ML Kit face detection does not recognize people, check liveness, or verify
/// that a face belongs to the student named by the client.
class FaceDetectionService {
  FaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: true,
          enableClassification: true,
        ),
      );

  final FaceDetector _detector;

  Future<bool> containsExactlyOneFace(InputImage inputImage) async {
    final faces = await _detector.processImage(inputImage);
    return faces.length == 1;
  }

  Future<void> dispose() => _detector.close();
}
