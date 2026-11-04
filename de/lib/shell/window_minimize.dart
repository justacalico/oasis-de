import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'shell_controller.dart';
import 'view_scale.dart';

class WindowMinimizeEffect extends StatefulWidget {
  const WindowMinimizeEffect({
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
  State<WindowMinimizeEffect> createState() => _WindowMinimizeEffectState();
}

class _WindowMinimizeEffectState extends State<WindowMinimizeEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
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
  void didUpdateWidget(WindowMinimizeEffect old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    switch (widget.window.transition) {
      case ShellWindowTransition.minimizing:
        _anim.forward();
      case ShellWindowTransition.restoring:
        _anim.reverse();
      case ShellWindowTransition.none:
        _anim.stop();
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
    _anim.dispose();
    super.dispose();
  }

  Rect _dashIconRect(BuildContext context) {
    final box =
        widget.window.dashIconKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final k = ViewScale.of(context);
      final p = box.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        p.dx / k,
        p.dy / k,
        box.size.width / k,
        box.size.height / k,
      );
    }
    final screen = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height - kWindowBottomMargin),
      width: kDashIconSize,
      height: kDashIconSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        final t = _anim.value;
        if (t <= 0) return child!;
        final eased = Curves.easeInOut.transform(t);
        final origin = widget.rect;
        final target = _dashIconRect(context);
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
                clipper: _MinimizeClip(
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

class _MinimizeClip extends CustomClipper<Path> {
  const _MinimizeClip({required this.pinch, required this.pullX});

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
  bool shouldReclip(_MinimizeClip old) =>
      old.pinch != pinch || old.pullX != pullX;
}
