import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';
import 'oasis_traffic_lights.dart';

const kOasisWindowTitleBarHeight = 38.0;

enum OasisResizeEdge {
  top(0, -1),
  bottom(0, 1),
  left(-1, 0),
  right(1, 0),
  topLeft(-1, -1),
  topRight(1, -1),
  bottomLeft(-1, 1),
  bottomRight(1, 1);

  const OasisResizeEdge(this.dx, this.dy);

  final int dx;
  final int dy;
}

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
    this.onResize,
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
  final void Function(Offset delta, OasisResizeEdge edge)? onResize;

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
      onPointerMove: onDrag == null ? null : (e) => onDrag(e.delta),
      onPointerDown: widget.onMaximize == null
          ? null
          : (e) {
              final now = clock.now();
              final last = _lastTitlebarTap;
              _lastTitlebarTap = now;
              if (last != null &&
                  now.difference(last) < const Duration(milliseconds: 350)) {
                _lastTitlebarTap = null;
                widget.onMaximize!();
              }
            },
      behavior: HitTestBehavior.deferToChild,
      child: Container(
        height: kOasisWindowTitleBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.windowBackground.withValues(
            alpha: widget.focused ? 0.55 : 0.35,
          ),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(style.windowRadius),
          ),
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
                color: widget.focused ? p.textPrimary : p.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );

    final onResize = widget.onResize;
    final window = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: p.windowBackground,
        borderRadius: BorderRadius.circular(style.windowRadius),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: widget.focused ? 0.4 : 0.2),
            blurRadius: widget.focused ? 48 : 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(style.windowRadius),
        border: Border.all(color: p.glassBorder, width: 0.5),
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
    );
    if (onResize == null) return window;
    const grab = 6.0;
    const corner = 16.0;
    return Stack(
      children: [
        window,
        Positioned(
          top: 0,
          left: corner,
          right: corner,
          height: grab,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.top,
            cursor: SystemMouseCursors.resizeUpDown,
            onResize: onResize,
          ),
        ),
        Positioned(
          bottom: 0,
          left: corner,
          right: corner,
          height: grab,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.bottom,
            cursor: SystemMouseCursors.resizeUpDown,
            onResize: onResize,
          ),
        ),
        Positioned(
          left: 0,
          top: corner,
          bottom: corner,
          width: grab,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.left,
            cursor: SystemMouseCursors.resizeLeftRight,
            onResize: onResize,
          ),
        ),
        Positioned(
          right: 0,
          top: corner,
          bottom: corner,
          width: grab,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.right,
            cursor: SystemMouseCursors.resizeLeftRight,
            onResize: onResize,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          width: corner,
          height: corner,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.topLeft,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            onResize: onResize,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          width: corner,
          height: corner,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.topRight,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
            onResize: onResize,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: corner,
          height: corner,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.bottomLeft,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
            onResize: onResize,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          width: corner,
          height: corner,
          child: _ResizeGrabber(
            edge: OasisResizeEdge.bottomRight,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            onResize: onResize,
          ),
        ),
      ],
    );
  }
}

class _ResizeGrabber extends StatelessWidget {
  const _ResizeGrabber({
    required this.edge,
    required this.cursor,
    required this.onResize,
  });

  final OasisResizeEdge edge;
  final MouseCursor cursor;
  final void Function(Offset delta, OasisResizeEdge edge) onResize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerMove: (e) => onResize(e.delta, edge),
        child: const SizedBox.expand(),
      ),
    );
  }
}
