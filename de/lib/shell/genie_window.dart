import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'dock.dart';
import 'shell_controller.dart';

class GenieWindow extends StatefulWidget {
  const GenieWindow({
    super.key,
    required this.window,
    required this.rect,
    required this.onEnd,
    required this.child,
  });

  final ShellWindowData window;
  final Rect rect;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<GenieWindow> createState() => _GenieWindowState();
}

class _GenieWindowState extends State<GenieWindow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _genie;

  @override
  void initState() {
    super.initState();
    _genie = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 380),
      value: widget.window.transition == ShellWindowTransition.restoring
          ? 1.0
          : 0.0,
    )..addStatusListener(_onStatus);
    _sync();
  }

  @override
  void didUpdateWidget(GenieWindow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    switch (widget.window.transition) {
      case ShellWindowTransition.minimizing:
        _genie.forward();
      case ShellWindowTransition.restoring:
        _genie.reverse();
      case ShellWindowTransition.none:
        _genie.stop();
    }
  }

  void _onStatus(AnimationStatus status) {
    final done = (status == AnimationStatus.completed &&
            widget.window.transition ==
                ShellWindowTransition.minimizing) ||
        (status == AnimationStatus.dismissed &&
            widget.window.transition ==
                ShellWindowTransition.restoring);
    if (done) widget.onEnd();
  }

  @override
  void dispose() {
    _genie.dispose();
    super.dispose();
  }

  Rect _dockIconRect(BuildContext context) {
    final box =
        widget.window.dockIconKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final screen = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height - 24),
      width: kDockIconSize,
      height: kDockIconSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _genie,
      child: widget.child,
      builder: (context, child) {
        final t = _genie.value;
        if (t <= 0) return child!;
        final eased = Curves.easeInOut.transform(t);
        final origin = widget.rect;
        final target = _dockIconRect(context);
        return IgnorePointer(
          child: Transform.translate(
            offset: Offset(
              lerpDouble(0, target.center.dx - origin.center.dx,
                  eased)!,
              lerpDouble(
                  0,
                  target.center.dy - origin.center.dy,
                  Curves.easeIn.transform(t))!,
            ),
            child: Transform.scale(
              scaleX: lerpDouble(1, target.width / origin.width, eased),
              scaleY:
                  lerpDouble(1, target.height / origin.height, eased),
              child: ClipPath(
                clipper: _GenieClip(
                  pinch: eased,
                  pullX: target.center.dx - origin.left,
                ),
                child: Opacity(
                  opacity: 1 - 0.3 * eased,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GenieClip extends CustomClipper<Path> {
  const _GenieClip({required this.pinch, required this.pullX});

  final double pinch;
  final double pullX;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final topCx = w / 2;
    final botCx = lerpDouble(topCx, pullX, pinch)!;
    final topHalf = w / 2 * (1 - 0.35 * pinch);
    final botHalf = w / 2 * (1 - pinch);
    final bow = (pullX - topCx) * pinch * 0.15;
    final left =
        lerpDouble(topCx - topHalf, botCx - botHalf, 0.55)! - bow;
    final right =
        lerpDouble(topCx + topHalf, botCx + botHalf, 0.55)! - bow;
    return Path()
      ..moveTo(topCx - topHalf, 0)
      ..quadraticBezierTo(left, h * 0.6, botCx - botHalf, h)
      ..lineTo(botCx + botHalf, h)
      ..quadraticBezierTo(right, h * 0.6, topCx + topHalf, 0)
      ..close();
  }

  @override
  bool shouldReclip(_GenieClip old) =>
      old.pinch != pinch || old.pullX != pullX;
}
