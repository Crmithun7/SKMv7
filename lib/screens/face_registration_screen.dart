import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:flutter/services.dart';
import '../services/face_service.dart';
import '../utils/app_notifier.dart';
import 'face_capture_camera_screen.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final String companyCode;
  final String employeeId;
  final String employeeName;

  const FaceRegistrationScreen({
    super.key,
    required this.companyCode,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  static const List<Map<String, dynamic>> poses = [
    {'name': 'Front', 'icon': Icons.face},
    {'name': 'Left', 'icon': Icons.arrow_back},
    {'name': 'Right', 'icon': Icons.arrow_forward},
    {'name': 'Up', 'icon': Icons.arrow_upward},
    {'name': 'Down', 'icon': Icons.arrow_downward},
  ];

  final Set<String> _completedPoses = {};
  String? _capturingPose;
  String? _errorMessage;

  Future<void> _capturePose(String pose) async {
    HapticFeedback.selectionClick();
    setState(() {
      _capturingPose = pose;
      _errorMessage = null;
    });

    try {
      final image = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => FaceCaptureCameraScreen(title: '$pose Pose'),
        ),
      );

      if (image == null) return;

      final result = await FaceService.registerFace(
        companyCode: widget.companyCode,
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        pose: pose,
        image: image,
      );

      setState(() {
        _completedPoses.add(pose);
      });

      if (!mounted) return;
      final remaining =
          result['remaining_pose'] as int? ?? (5 - _completedPoses.length);
      AppNotifier.success(
        context,
        remaining <= 0
            ? 'All poses registered successfully!'
            : '$pose pose registered. $remaining pose(s) remaining.',
      );
    } on FaceException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      debugPrint('FACE CAPTURE ERROR: $e');
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _capturingPose = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _completedPoses.length / poses.length;
    final colorScheme = Theme.of(context).colorScheme;
    final isComplete = _completedPoses.length == poses.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Face Registration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isComplete
                            ? Icons.check_circle
                            : Icons.face_retouching_natural,
                        color: isComplete ? Colors.green : colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isComplete
                              ? 'All poses registered'
                              : 'Capture all 5 poses to complete registration',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        color: isComplete ? Colors.green : colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_completedPoses.length} / ${poses.length} poses captured',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                  if (isComplete) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final pose in poses) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _PoseTile(
                key: ValueKey(
                  '${pose['name']}_${_completedPoses.contains(pose['name'])}',
                ),
                name: pose['name'] as String,
                icon: pose['icon'] as IconData,
                isCompleted: _completedPoses.contains(pose['name']),
                isCapturing: _capturingPose == pose['name'],
                onTap:
                    _capturingPose != null ||
                        _completedPoses.contains(pose['name'])
                    ? null
                    : () => _capturePose(pose['name'] as String),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PoseTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool isCompleted;
  final bool isCapturing;
  final VoidCallback? onTap;

  const _PoseTile({
    super.key,
    required this.name,
    required this.icon,
    required this.isCompleted,
    required this.isCapturing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCompleted
              ? Colors.green.withValues(alpha: 0.15)
              : colorScheme.primaryContainer,
          child: Icon(
            isCompleted ? Icons.check_circle : icon,
            color: isCompleted ? Colors.green : colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          '$name Pose',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isCompleted
              ? 'Registered'
              : isCapturing
              ? 'Capturing...'
              : 'Tap to capture',
        ),
        trailing: isCapturing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (isCompleted ? null : const Icon(Icons.camera_alt_outlined)),
        onTap: onTap,
      ),
    );
  }
}
