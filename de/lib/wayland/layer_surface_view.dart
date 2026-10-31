import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'wayland_service.dart';
import 'wayland_surface_view.dart';

const layerEdgeTop = 1;
const layerEdgeBottom = 2;
const layerEdgeLeft = 4;
const layerEdgeRight = 8;

Rect layerSurfaceRect(WaylandSurface s, Size output) {
  final m = s.layerMargins;
  final a = s.layerAnchor;
  var w = a & layerEdgeLeft != 0 && a & layerEdgeRight != 0
      ? output.width - m.left - m.right
      : (s.layerDesired.width > 0
            ? s.layerDesired.width
            : s.size.width);
  var h = a & layerEdgeTop != 0 && a & layerEdgeBottom != 0
      ? output.height - m.top - m.bottom
      : (s.layerDesired.height > 0
            ? s.layerDesired.height
            : s.size.height);
  w = math.max(0, w);
  h = math.max(0, h);
  final x = a & layerEdgeLeft != 0
      ? m.left
      : a & layerEdgeRight != 0
      ? output.width - m.right - w
      : (output.width - w) / 2;
  final y = a & layerEdgeTop != 0
      ? m.top
      : a & layerEdgeBottom != 0
      ? output.height - m.bottom - h
      : (output.height - h) / 2;
  return Rect.fromLTWH(x, y, w, h);
}

class _ClientSurfaceGesture extends StatefulWidget {
  const _ClientSurfaceGesture({
    required this.surface,
    required this.service,
    required this.child,
    this.onDown,
  });

  final WaylandSurface surface;
  final WaylandService service;
  final Widget child;
  final VoidCallback? onDown;

  @override
  State<_ClientSurfaceGesture> createState() =>
      _ClientSurfaceGestureState();
}

class _ClientSurfaceGestureState extends State<_ClientSurfaceGesture> {
  var _buttons = 0;

  void _motion(PointerEvent e, Size box) {
    final surface = widget.surface;
    final service = widget.service;
    final p = surfaceCoordsAt(surface, e.localPosition, box);
    final hit = subSurfaceHit(service, surface, p);
    if (hit != null) {
      service.pointerMotion(hit.$1.id, hit.$2.dx, hit.$2.dy);
      return;
    }
    service.pointerMotion(surface.id, p.dx, p.dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        return SurfaceHitRegion(
          region: widget.surface.inputRegion,
          surfaceSize: logicalSurfaceSize(widget.surface),
          child: MouseRegion(
            onExit: (_) => widget.service.pointerExit(widget.surface.id),
            cursor: waylandMouseCursor(widget.service),
            child: Listener(
              onPointerHover: (e) {
                _motion(e, box);
                _buttons = e.buttons;
              },
              onPointerMove: (e) {
                _motion(e, box);
                _buttons = e.buttons;
              },
              onPointerDown: (e) {
                _motion(e, box);
                forwardButtonDiff(widget.service, _buttons, e.buttons);
                _buttons = e.buttons;
                widget.onDown?.call();
              },
              onPointerUp: (e) {
                forwardButtonDiff(widget.service, _buttons, e.buttons);
                _buttons = e.buttons;
              },
              onPointerCancel: (e) {
                forwardButtonDiff(widget.service, _buttons, e.buttons);
                _buttons = e.buttons;
              },
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  widget.service.pointerAxis(
                    e.scrollDelta.dx,
                    e.scrollDelta.dy,
                  );
                }
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class LayerSurfaceView extends StatefulWidget {
  const LayerSurfaceView({
    super.key,
    required this.surface,
    required this.service,
  });

  final WaylandSurface surface;
  final WaylandService service;

  @override
  State<LayerSurfaceView> createState() => _LayerSurfaceViewState();
}

class _LayerSurfaceViewState extends State<LayerSurfaceView> {
  final _keys = FocusNode();
  final _pressed = <int>{};
  Size? _reported;

  bool get _interactive => widget.surface.layerKeyboard != 0;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_flushKeysOnBlur);
  }

  void _flushKeysOnBlur() {
    if (_keys.hasFocus) return;
    for (final c in _pressed) {
      widget.service.key(c, false);
    }
    _pressed.clear();
  }

  @override
  void dispose() {
    _keys.removeListener(_flushKeysOnBlur);
    _keys.dispose();
    super.dispose();
  }

  void _grabInput() {
    if (!_interactive) return;
    _keys.requestFocus();
    widget.service.focus(widget.surface.id);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      autofocus: widget.surface.layerKeyboard == 1,
      canRequestFocus: _interactive,
      onKeyEvent: (node, event) => waylandKeyEvent(
        widget.service,
        _pressed,
        event,
        inhibited: widget.surface.shortcutsInhibited,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          if (_reported != box && box.width > 0 && box.height > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _reported = box;
              widget.service.configureLayer(
                widget.surface.id,
                box.width.round(),
                box.height.round(),
              );
            });
          }
          return _ClientSurfaceGesture(
            surface: widget.surface,
            service: widget.service,
            onDown: _grabInput,
            child: WaylandLayerTree(
              service: widget.service,
              surface: widget.surface,
            ),
          );
        },
      ),
    );
  }
}

class LockSurfaceView extends StatefulWidget {
  const LockSurfaceView({
    super.key,
    required this.surface,
    required this.service,
  });

  final WaylandSurface surface;
  final WaylandService service;

  @override
  State<LockSurfaceView> createState() => _LockSurfaceViewState();
}

class _LockSurfaceViewState extends State<LockSurfaceView> {
  final _keys = FocusNode();
  final _pressed = <int>{};

  @override
  void initState() {
    super.initState();
    _keys.addListener(_flushKeysOnBlur);
    widget.service.focus(widget.surface.id);
  }

  void _flushKeysOnBlur() {
    if (_keys.hasFocus) return;
    for (final c in _pressed) {
      widget.service.key(c, false);
    }
    _pressed.clear();
  }

  @override
  void dispose() {
    _keys.removeListener(_flushKeysOnBlur);
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: (node, event) => waylandKeyEvent(
        widget.service,
        _pressed,
        event,
        inhibited: widget.surface.shortcutsInhibited,
      ),
      child: _ClientSurfaceGesture(
        surface: widget.surface,
        service: widget.service,
        child: WaylandLayerTree(
          service: widget.service,
          surface: widget.surface,
        ),
      ),
    );
  }
}
