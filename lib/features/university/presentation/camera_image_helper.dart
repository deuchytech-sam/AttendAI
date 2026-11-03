import 'dart:io' show Platform;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Result of converting a camera image to an upright JPEG.
class UprightJpeg {
  const UprightJpeg({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// JPEG-encoded image bytes.
  final Uint8List bytes;

  /// Width of the JPEG image in pixels.
  final int width;

  /// Height of the JPEG image in pixels.
  final int height;

  /// Size of the JPEG image.
  Size get size => Size(width.toDouble(), height.toDouble());
}

/// Converts a platform-specific camera image to an upright JPEG suitable for
/// the face_liveness_verification package.
///
/// The package's FaceEmbeddingExtractor expects encoded JPEG/PNG bytes and
/// uses the ML Kit face bounding boxes which are in the upright coordinate
/// system. This helper handles the NV21 (Android) or BGRA8888 (iOS) to JPEG
/// conversion with proper rotation.
UprightJpeg? convertCameraImageToUprightJpeg(CameraImage cameraImage,
    CameraDescription cameraDescription) {
  try {
    if (cameraImage.planes.isEmpty) return null;

    // On Android, camera image is NV21 (YUV420SP) with a single plane.
    // On iOS, it's BGRA8888 with a single plane.
    final plane = cameraImage.planes.first;
    final bytes = plane.bytes;

    img.Image? sourceImage;

    if (Platform.isAndroid) {
      // NV21 to RGB conversion using the image package
      sourceImage = _nv21ToImage(bytes, cameraImage.width, cameraImage.height);
    } else {
      // iOS: BGRA8888
      sourceImage = img.Image.fromBytes(
        width: cameraImage.width,
        height: cameraImage.height,
        bytes: bytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );
    }

    if (sourceImage == null) return null;

    // Rotate the image to upright based on sensor orientation
    final rotation = _getImageRotation(cameraDescription.sensorOrientation,
        cameraDescription.lensDirection);
    final uprightImage = _rotateImage(sourceImage, rotation);

    // Encode as JPEG
    final jpegBytes = img.encodeJpg(uprightImage, quality: 90);
    if (jpegBytes.isEmpty) return null;

    return UprightJpeg(
      bytes: Uint8List.fromList(jpegBytes),
      width: uprightImage.width,
      height: uprightImage.height,
    );
  } catch (e) {
    // Log error but don't crash - caller will handle null
    debugPrint('convertCameraImageToUprightJpeg failed: $e');
    return null;
  }
}

/// Converts NV21 (YUV420SP) bytes to an RGB image using the image package.
img.Image? _nv21ToImage(Uint8List nv21Bytes, int width, int height) {
  // Manual NV21 (YUV420SP) to RGB conversion.
  // NV21 layout: Y plane (width * height) followed by interleaved VU plane (width * height / 2).
  try {
    final ySize = width * height;
    final uvSize = ySize ~/ 2;

    if (nv21Bytes.length < ySize + uvSize) {
      debugPrint('NV21 buffer too small: ${nv21Bytes.length} < $ySize + $uvSize');
      return null;
    }

    final yPlane = nv21Bytes.sublist(0, ySize);
    final vuPlane = nv21Bytes.sublist(ySize, ySize + uvSize);

    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = (y ~/ 2) * width + (x ~/ 2) * 2;

        final Y = yPlane[yIndex];
        final V = vuPlane[uvIndex];
        final U = vuPlane[uvIndex + 1];

        // YUV to RGB conversion (BT.601)
        int r = (Y + 1.402 * (V - 128)).round().clamp(0, 255);
        int g = (Y - 0.344 * (U - 128) - 0.714 * (V - 128)).round().clamp(0, 255);
        int b = (Y + 1.772 * (U - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  } catch (e) {
    debugPrint('NV21 decode failed: $e');
    return null;
  }
}

/// Rotates an image to upright orientation.
img.Image _rotateImage(img.Image source, int rotationDegrees) {
  switch (rotationDegrees) {
    case 90:
      return img.copyRotate(source, angle: 90);
    case 180:
      return img.copyRotate(source, angle: 180);
    case 270:
      return img.copyRotate(source, angle: 270);
    default:
      return source;
  }
}

/// Calculates the rotation needed to make the camera image upright.
///
/// The sensor orientation is the angle the camera sensor is rotated clockwise
/// from the device's natural orientation (portrait). To make the image upright,
/// we need to rotate by (360 - sensorOrientation) % 360 degrees clockwise.
///
/// For front-facing cameras on Android, the sensor orientation is typically 270
/// degrees (landscape right), meaning we need to rotate 90 degrees clockwise
/// to get an upright image. ML Kit's InputImageRotation uses the same convention,
/// so the face bounding boxes it returns are in the upright coordinate system.
int _getImageRotation(int sensorOrientation, CameraLensDirection lensDirection) {
  // Rotation to apply to make the image upright (clockwise degrees).
  // Formula: (360 - sensorOrientation) % 360
  switch (sensorOrientation) {
    case 0:
      return 0;
    case 90:
      return 270;
    case 180:
      return 180;
    case 270:
      return 90;
    default:
      return 0;
  }
}