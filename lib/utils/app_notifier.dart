import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum NotifyType { success, error, info }

class AppNotifier {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    NotifyType type = NotifyType.info,
  }) {
    switch (type) {
      case NotifyType.success:
        HapticFeedback.lightImpact();
        break;
      case NotifyType.error:
        HapticFeedback.heavyImpact();
        break;
      case NotifyType.info:
        HapticFeedback.selectionClick();
        break;
    }

    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    void dismiss() {
      if (_current == entry) {
        _current = null;
      }
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) =>
          _TopToast(message: message, type: type, onDismissed: dismiss),
    );

    _current = entry;
    overlay.insert(entry);
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, type: NotifyType.success);

  static void error(BuildContext context, String message) =>
      show(context, message: message, type: NotifyType.error);

  static void info(BuildContext context, String message) =>
      show(context, message: message, type: NotifyType.info);
}

class _TopToast extends StatefulWidget {
  final String message;
  final NotifyType type;
  final VoidCallback onDismissed;

  const _TopToast({
    required this.message,
    required this.type,
    required this.onDismissed,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({IconData icon, Color color}) _style(BuildContext context) {
    switch (widget.type) {
      case NotifyType.success:
        return (icon: Icons.check_circle, color: Colors.green.shade600);
      case NotifyType.error:
        return (icon: Icons.error, color: Colors.red.shade600);
      case NotifyType.info:
        return (icon: Icons.info, color: Theme.of(context).colorScheme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onVerticalDragEnd: (_) => _dismiss(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border(
                    left: BorderSide(color: style.color, width: 4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(style.icon, color: style.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
