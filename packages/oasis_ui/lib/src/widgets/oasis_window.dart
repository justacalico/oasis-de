import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';
import 'oasis_traffic_lights.dart';

class OasisWindow extends StatefulWidget {
  const OasisWindow({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.width = 720,
    this.height = 480,
    this.focused = true,
    this.onDrag,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final double width;
  final double height;
  final bool focused;
  final ValueChanged<Offset>? onDrag;

  @override
  State<OasisWindow> createState() => _OasisWindowState();
}

class _OasisWindowState extends State<OasisWindow> {
  DateTime? _lastTitlebarTap;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final p = style.palette;
    final onDrag = widget.onDrag;
    final titleBar = Listener(
      onPointerMove:
          onDrag == null ? null : (e) => onDrag(e.delta),
      onPointerDown: widget.onMaximize == null
          ? null
          : (e) {
              final now = clock.now();
              final last = _lastTitlebarTap;
              _lastTitlebarTap = now;
              if (last != null &&
                  now.difference(last) <
                      const Duration(milliseconds: 350)) {
                _lastTitlebarTap = null;
                widget.onMaximize!();
              }
            },
      behavior: HitTestBehavior.deferToChild,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.windowBackground.withValues(alpha: 0.55),
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(style.windowRadius)),
          border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OasisTrafficLights(
                onClose: widget.onClose,
                onMinimize: widget.onMinimize,
                onMaximize: widget.onMaximize,
              ),
            ),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: widget.focused ? p.textPrimary : p.textTertiary),
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: widget.focused ? 1 : 0.92,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: p.windowBackground,
          borderRadius: BorderRadius.circular(style.windowRadius),
          border: Border.all(color: p.glassBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: widget.focused ? 0.4 : 0.2),
              blurRadius: widget.focused ? 48 : 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(style.windowRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBar,
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
