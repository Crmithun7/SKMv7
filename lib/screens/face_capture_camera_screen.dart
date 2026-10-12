import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum _CaptureStatus { initializing, searching, aligning, captured, error }

/// A full-screen camera capture flow with a live oval face guide.
///
/// The photo is captured automatically once a face is detected centered
/// and correctly sized inside the oval for a short, stable moment — there
/// is no manual capture button. Pops with the captured [File], or `null`
/// if the user backs out.
class FaceCaptureCameraScreen extends StatefulWidget {
  final String title;
  final CameraLensDirection initialLensDirection;

  const FaceCaptureCameraScreen({
    super.key,
    required this.title,
    this.initialLensDirection = CameraLensDirection.back,
  });

  @override
  State<FaceCaptureCameraScreen> createState() =>
      _FaceCaptureCameraScreenState();
}

class _FaceCaptureCameraScreenState extends State<FaceCaptureCameraScreen>
    with WidgetsBindingObserver {
  static const int _requiredAlignedFrames = 6;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  CameraController? _controller;
  CameraDescription? _camera;
  Size? _previewSize;
  late CameraLensDirection _lensDirection;

  _CaptureStatus _status = _CaptureStatus.initializing;
  String _statusMessage = 'Starting camera…';
  String? _errorMessage;

  bool _isDetecting = false;
  bool _isCapturing = false;
  bool _isSwitchingCamera = false;
  int _consecutiveAligned = 0;

  @override
  void initState() {
    super.initState();
    _lensDirection = widget.initialLensDirection;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Drop the reference and rebuild (swapping CameraPreview out for the
      // loading spinner) *before* disposing — otherwise a stray rebuild of
      // the still-mounted CameraPreview after dispose() throws
      // "buildPreview() was called on a disposed CameraController".
      _controller = null;
      setState(() {});
      _disposeControllerAfterNextFrame(controller);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  /// Waits for the frame scheduled by the caller's `setState()` to actually
  /// commit (so no widget still references [controller]) before stopping
  /// its image stream and disposing it.
  Future<void> _disposeControllerAfterNextFrame(
    CameraController controller,
  ) async {
    await _waitForNextFrame();
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Stream may already be stopped (e.g. mid-capture); ignore.
    }
    await controller.dispose();
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _faceDetector.close();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() {
      _status = _CaptureStatus.initializing;
      _statusMessage = 'Starting camera…';
      _errorMessage = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera found on this device.');
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == _lensDirection,
        orElse: () => cameras.first,
      );
      _camera = camera;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      _consecutiveAligned = 0;
      _isCapturing = false;
      setState(() {
        _status = _CaptureStatus.searching;
        _statusMessage = 'Position your face inside the oval';
      });
      await controller.startImageStream(_processCameraImage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CaptureStatus.error;
        _errorMessage = friendlyError(
          e,
          fallback: "The camera couldn't be started. Close any other app using the camera and try again.",
        );
      });
    } finally {
      _isSwitchingCamera = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _status == _CaptureStatus.initializing) return;
    _isSwitchingCamera = true;

    final oldController = _controller;
    _controller = null;
    if (mounted) setState(() {});
    if (oldController != null) {
      await _disposeControllerAfterNextFrame(oldController);
    }

    _lensDirection = _lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    await _initCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _isCapturing) return;
    final camera = _camera;
    if (camera == null) return;

    _isDetecting = true;
    try {
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage?.metadata == null) return;

      final faces = await _faceDetector.processImage(inputImage!);
      if (!mounted || _isCapturing) return;

      _evaluateFaces(
        faces,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        camera.lensDirection,
      );
    } catch (_) {
      // Ignore transient per-frame detection errors.
    } finally {
      _isDetecting = false;
    }
  }

  void _evaluateFaces(
    List<Face> faces,
    Size imageSize,
    InputImageRotation rotation,
    CameraLensDirection lensDirection,
  ) {
    final canvasSize = _previewSize;
    if (canvasSize == null || canvasSize.isEmpty) return;

    if (faces.isEmpty) {
      _consecutiveAligned = 0;
      setState(() {
        _status = _CaptureStatus.searching;
        _statusMessage = 'Position your face inside the oval';
      });
      return;
    }

    var largest = faces.first;
    for (final face in faces) {
      final area = face.boundingBox.width * face.boundingBox.height;
      final largestArea = largest.boundingBox.width * largest.boundingBox.height;
      if (area > largestArea) largest = face;
    }

    final box = largest.boundingBox;
    final left = _translateX(box.left, canvasSize, imageSize, rotation, lensDirection);
    final right = _translateX(box.right, canvasSize, imageSize, rotation, lensDirection);
    final top = _translateY(box.top, canvasSize, imageSize, rotation, lensDirection);
    final bottom = _translateY(box.bottom, canvasSize, imageSize, rotation, lensDirection);

    final faceRect = Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      left < right ? right : left,
      top < bottom ? bottom : top,
    );

    final oval = ovalRectFor(canvasSize);
    final isCentered = oval.contains(faceRect.center);
    final sizeRatio = faceRect.width / oval.width;
    final isGoodDistance = sizeRatio >= 0.5 && sizeRatio <= 1.2;
    final aligned = isCentered && isGoodDistance;

    String message;
    if (!isCentered) {
      message = 'Center your face in the oval';
    } else if (sizeRatio < 0.5) {
      message = 'Move closer';
    } else if (sizeRatio > 1.2) {
      message = 'Move back a little';
    } else {
      message = 'Hold still…';
    }

    _consecutiveAligned = aligned ? _consecutiveAligned + 1 : 0;

    setState(() {
      _status = aligned ? _CaptureStatus.aligning : _CaptureStatus.searching;
      _statusMessage = message;
    });

    if (aligned && _consecutiveAligned >= _requiredAlignedFrames) {
      _captureNow();
    }
  }

  Future<void> _captureNow() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;

    _isCapturing = true;
    setState(() {
      _status = _CaptureStatus.captured;
      _statusMessage = 'Captured!';
    });

    try {
      await controller.stopImageStream();
      final picture = await controller.takePicture();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pop(File(picture.path));
    } catch (_) {
      if (!mounted) return;
      _isCapturing = false;
      _consecutiveAligned = 0;
      setState(() {
        _status = _CaptureStatus.error;
        _errorMessage = 'Could not capture the photo. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            tooltip: 'Switch camera',
            onPressed: _status == _CaptureStatus.initializing
                ? null
                : _switchCamera,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_status == _CaptureStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _initCamera, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final overlayColor = switch (_status) {
      _CaptureStatus.captured => Colors.greenAccent,
      _CaptureStatus.aligning => Colors.lightGreenAccent,
      _ => Colors.white70,
    };

    final progress = _status == _CaptureStatus.captured
        ? 1.0
        : (_consecutiveAligned / _requiredAlignedFrames).clamp(0.0, 1.0);

    final statusIcon = switch (_status) {
      _CaptureStatus.captured => Icons.check_circle,
      _CaptureStatus.aligning => Icons.center_focus_strong,
      _CaptureStatus.error => Icons.error_outline,
      _ => Icons.search,
    };

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _previewSize = constraints.biggest;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: overlayColor),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, color, _) => CustomPaint(
                          painter: _OvalOverlayPainter(
                            color: color ?? overlayColor,
                            progress: progress,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  statusIcon,
                  key: ValueKey(statusIcon),
                  size: 18,
                  color: overlayColor,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The oval face guide, sized and centered relative to the preview area.
Rect ovalRectFor(Size size) {
  final ovalWidth = size.width * 0.72;
  final ovalHeight = ovalWidth / 0.75;
  final center = Offset(size.width / 2, size.height * 0.42);
  return Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);
}

class _OvalOverlayPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _OvalOverlayPainter({required this.color, this.progress = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final oval = ovalRectFor(size);
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(oval);
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      oval,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (progress > 0) {
      canvas.drawArc(
        oval,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}

const Map<DeviceOrientation, int> _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

InputImage? _inputImageFromCameraImage(
  CameraImage image,
  CameraDescription camera,
) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (Platform.isAndroid) {
    // The capture screen is locked to portraitUp, so the base compensation
    // is fixed rather than tracked from a live device-orientation stream.
    var rotationCompensation = _orientations[DeviceOrientation.portraitUp]!;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;
  if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
  if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
  if (image.planes.length != 1) return null;
  final plane = image.planes.first;

  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

double _translateX(
  double x,
  Size canvasSize,
  Size imageSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection,
) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
      return x *
          canvasSize.width /
          (Platform.isIOS ? imageSize.width : imageSize.height);
    case InputImageRotation.rotation270deg:
      return canvasSize.width -
          x *
              canvasSize.width /
              (Platform.isIOS ? imageSize.width : imageSize.height);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      if (lensDirection == CameraLensDirection.back) {
        return x * canvasSize.width / imageSize.width;
      }
      return canvasSize.width - x * canvasSize.width / imageSize.width;
  }
}

double _translateY(
  double y,
  Size canvasSize,
  Size imageSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection,
) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      return y *
          canvasSize.height /
          (Platform.isIOS ? imageSize.height : imageSize.width);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      return y * canvasSize.height / imageSize.height;
  }
}
