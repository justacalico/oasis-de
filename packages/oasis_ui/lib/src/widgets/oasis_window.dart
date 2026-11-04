import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';
import 'oasis_traffic_lights.dart';

const kOasisWindowTitleBarHeight = 38.0;

enum OasisResizeEdge {
  top(0, -1, SystemMouseCursors.resizeUpDown),
  bottom(0, 1, SystemMouseCursors.resizeUpDown),
  left(-1, 0, SystemMouseCursors.resizeLeftRight),
  right(1, 0, SystemMouseCursors.resizeLeftRight),
  topLeft(-1, -1, SystemMouseCursors.resizeUpLeftDownRight),
  topRight(1, -1, SystemMouseCursors.resizeUpRightDownLeft),
  bottomLeft(-1, 1, SystemMouseCursors.resizeUpRightDownLeft),
  bottomRight(1, 1, SystemMouseCursors.resizeUpLeftDownRight);

  const OasisResizeEdge(this.dx, this.dy, this.cursor);

  final int dx;
  final int dy;
  final MouseCursor cursor;
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
    this.decorated = true,
    this.onDrag,
    this.onResizeStart,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final double width;
  final double height;
  final bool focused;

  /// When false the title bar is omitted and [child] fills the window;
  /// used for surfaces that draw their own client-side decorations.
  final bool decorated;
  final ValueChanged<Offset>? onDrag;

  /// Called when the pointer presses a resize grabber. The grab is
  /// expected to be driven by the embedder's own pointer tracking so it
  /// keeps working when the pointer leaves the grab strip.
  final ValueChanged<OasisResizeEdge>? onResizeStart;

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
      onPointerMove: onDrag == null ? null : (e) => onDrag(e.localDelta),
      onPointerDown: widget.onMaximize == null
          ? null
          : (e) {
              if (e.buttons != kPrimaryButton) return;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 72),
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: widget.focused ? p.textPrimary : p.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final onResizeStart = widget.onResizeStart;
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
            if (widget.decorated) titleBar,
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
    if (onResizeStart == null) return window;
    return Stack(
      children: [
        window,
        for (final g in _grabbers)
          Positioned(
            top: g.top,
            bottom: g.bottom,
            left: g.left,
            right: g.right,
            width: g.width,
            height: g.height,
            child: _ResizeGrabber(edge: g.edge, onStart: onResizeStart),
          ),
      ],
    );
  }
}

class _GrabberSpec {
  const _GrabberSpec(
    this.edge, {
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.width,
    this.height,
  });

  final OasisResizeEdge edge;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double? width;
  final double? height;
}

const _grab = 6.0;
const _corner = 16.0;

const _grabbers = [
  _GrabberSpec(
    OasisResizeEdge.top,
    top: 0,
    left: _corner,
    right: _corner,
    height: _grab,
  ),
  _GrabberSpec(
    OasisResizeEdge.bottom,
    bottom: 0,
    left: _corner,
    right: _corner,
    height: _grab,
  ),
  _GrabberSpec(
    OasisResizeEdge.left,
    left: 0,
    top: _corner,
    bottom: _corner,
    width: _grab,
  ),
  _GrabberSpec(
    OasisResizeEdge.right,
    right: 0,
    top: _corner,
    bottom: _corner,
    width: _grab,
  ),
  _GrabberSpec(
    OasisResizeEdge.topLeft,
    top: 0,
    left: 0,
    width: _corner,
    height: _corner,
  ),
  _GrabberSpec(
    OasisResizeEdge.topRight,
    top: 0,
    right: 0,
    width: _corner,
    height: _corner,
  ),
  _GrabberSpec(
    OasisResizeEdge.bottomLeft,
    bottom: 0,
    left: 0,
    width: _corner,
    height: _corner,
  ),
  _GrabberSpec(
    OasisResizeEdge.bottomRight,
    bottom: 0,
    right: 0,
    width: _corner,
    height: _corner,
  ),
];

class _ResizeGrabber extends StatelessWidget {
  const _ResizeGrabber({required this.edge, required this.onStart});

  final OasisResizeEdge edge;
  final ValueChanged<OasisResizeEdge> onStart;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: edge.cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (e.buttons == kPrimaryButton) onStart(edge);
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
