import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'keymap.dart';
import 'wayland_service.dart';

const _mouseButtons = {
  kPrimaryMouseButton: 0x110,
  kSecondaryMouseButton: 0x111,
  kMiddleMouseButton: 0x112,
  kBackMouseButton: 0x113,
  kForwardMouseButton: 0x114,
};

void forwardButtonDiff(WaylandService service, int before, int after) {
  for (final entry in _mouseButtons.entries) {
    final was = (before & entry.key) != 0;
    final now = (after & entry.key) != 0;
    if (was != now) service.pointerButton(entry.value, now);
  }
}

Size logicalSurfaceSize(WaylandSurface s) {
  final vp = s.vpSrc;
  if (vp != null && vp.width > 0 && vp.height > 0) return vp.size;
  final b = s.bufferSize;
  final sc = s.scale <= 0 ? 1.0 : s.scale;
  if (b.width > 0 && b.height > 0) {
    final w = b.width / sc;
    final h = b.height / sc;
    return (s.transform & 1) != 0 ? Size(h, w) : Size(w, h);
  }
  return s.size;
}

Offset surfaceCoordsAt(WaylandSurface surface, Offset local, Size box) {
  final src = surface.vpSrc;
  final s = src != null ? src.size : surface.size;
  if (s.width <= 0 || s.height <= 0) return local;
  return Offset(
    (src?.left ?? 0) +
        surface.geoOffset.dx +
        local.dx * s.width / box.width,
    (src?.top ?? 0) +
        surface.geoOffset.dy +
        local.dy * s.height / box.height,
  );
}

(WaylandSurface, Offset)? subSurfaceHit(
  WaylandService service,
  WaylandSurface root,
  Offset p,
) {
  for (final id in root.children.reversed) {
    final sub = service.surfaces[id];
    if (sub == null) continue;
    final lp = p - sub.offset;
    final size = logicalSurfaceSize(sub);
    if (lp.dx < 0 ||
        lp.dy < 0 ||
        lp.dx >= size.width ||
        lp.dy >= size.height) {
      continue;
    }
    final region = sub.inputRegion;
    if (region != null && !region.any((r) => r.contains(lp))) {
      continue;
    }
    return subSurfaceHit(service, sub, lp) ?? (sub, lp);
  }
  return null;
}

KeyEventResult waylandKeyEvent(
  WaylandService service,
  Set<int> pressed,
  KeyEvent event, {
  bool escReserved = false,
  bool inhibited = false,
}) {
  final hw = HardwareKeyboard.instance;
  final shellChord = switch (event.logicalKey) {
    LogicalKeyboardKey.tab => hw.isAltPressed,
    LogicalKeyboardKey.keyD => isMetaOrSuperPressed(hw),
    LogicalKeyboardKey.arrowUp => isMetaOrSuperPressed(hw),
    LogicalKeyboardKey.space =>
      isMetaOrSuperPressed(hw) || hw.isControlPressed,
    LogicalKeyboardKey.escape => escReserved,
    _ => false,
  };
  if (shellChord && !inhibited) return KeyEventResult.ignored;
  final code = evdevCodeFor(event.physicalKey);
  if (code == null) return KeyEventResult.ignored;
  if (event is KeyUpEvent) {
    pressed.remove(code);
    service.key(code, false);
  } else if (event is KeyDownEvent) {
    pressed.add(code);
    service.key(code, true);
  }
  return KeyEventResult.handled;
}

Widget applyBufferTransform(Widget child, int transform) {
  switch (transform) {
    case 1:
    case 2:
    case 3:
      return RotatedBox(quarterTurns: transform, child: child);
    case 4:
    case 5:
    case 6:
    case 7:
      final inner = transform == 4
          ? child
          : RotatedBox(quarterTurns: transform - 4, child: child);
      return Transform(
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        alignment: Alignment.center,
        child: inner,
      );
    default:
      return child;
  }
}

MouseCursor waylandMouseCursor(WaylandService service) {
  if (service.cursor != null) return SystemMouseCursors.none;
  switch (service.cursorShape) {
    case 4:
      return SystemMouseCursors.click;
    case 5:
      return SystemMouseCursors.progress;
    case 6:
      return SystemMouseCursors.wait;
    case 7:
      return SystemMouseCursors.cell;
    case 8:
      return SystemMouseCursors.precise;
    case 9:
      return SystemMouseCursors.text;
    case 11:
      return SystemMouseCursors.alias;
    case 12:
      return SystemMouseCursors.copy;
    case 13:
      return SystemMouseCursors.move;
    case 14:
    case 15:
      return SystemMouseCursors.forbidden;
    case 16:
      return SystemMouseCursors.grab;
    case 17:
      return SystemMouseCursors.grabbing;
    case 18:
    case 25:
    case 26:
      return SystemMouseCursors.resizeLeftRight;
    case 19:
    case 22:
    case 27:
      return SystemMouseCursors.resizeUpDown;
    case 20:
    case 24:
    case 28:
      return SystemMouseCursors.resizeUpRightDownLeft;
    case 21:
    case 23:
    case 29:
      return SystemMouseCursors.resizeUpLeftDownRight;
    case 30:
      return SystemMouseCursors.resizeLeftRight;
    case 31:
      return SystemMouseCursors.resizeUpDown;
    case 32:
      return SystemMouseCursors.move;
    case 33:
      return SystemMouseCursors.zoomIn;
    case 34:
      return SystemMouseCursors.zoomOut;
    default:
      return MouseCursor.defer;
  }
}

class SurfaceHitRegion extends SingleChildRenderObjectWidget {
  const SurfaceHitRegion({
    super.key,
    required this.region,
    required this.surfaceSize,
    this.geoOffset = Offset.zero,
    super.child,
  });

  final List<Rect>? region;
  final Size surfaceSize;
  final Offset geoOffset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSurfaceHitRegion(
        region: region,
        surfaceSize: surfaceSize,
        geoOffset: geoOffset,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSurfaceHitRegion renderObject,
  ) {
    renderObject
      ..region = region
      ..surfaceSize = surfaceSize
      ..geoOffset = geoOffset;
  }
}

class RenderSurfaceHitRegion extends RenderProxyBox {
  RenderSurfaceHitRegion({
    required List<Rect>? region,
    required Size surfaceSize,
    required Offset geoOffset,
  }) : _region = region,
       _surfaceSize = surfaceSize,
       _geoOffset = geoOffset;

  List<Rect>? _region;
  Size _surfaceSize;
  Offset _geoOffset;

  set region(List<Rect>? v) => _region = v;
  set surfaceSize(Size v) => _surfaceSize = v;
  set geoOffset(Offset v) => _geoOffset = v;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final region = _region;
    if (region != null && size.width > 0 && size.height > 0) {
      final p = _geoOffset +
          Offset(
            position.dx * _surfaceSize.width / size.width,
            position.dy * _surfaceSize.height / size.height,
          );
      if (!region.any((r) => r.contains(p))) return false;
    }
    return super.hitTest(result, position: position);
  }
}

class WaylandSurfaceView extends StatefulWidget {
  const WaylandSurfaceView({
    super.key,
    required this.surface,
    required this.service,
    required this.focused,
    required this.maximized,
    this.fullscreen = false,
    this.resizing = false,
    this.escReserved = false,
  });

  final WaylandSurface surface;
  final WaylandService service;
  final bool focused;
  final bool maximized;
  final bool fullscreen;
  final bool resizing;
  final bool escReserved;

  @override
  State<WaylandSurfaceView> createState() => _WaylandSurfaceViewState();
}

class _WaylandSurfaceViewState extends State<WaylandSurfaceView> {
  final _keys = FocusNode();
  final _pressed = <int>{};
  var _buttons = 0;
  ({Size size, bool max, bool fs, bool resizing})? _reported;

  WaylandSurface get surface => widget.surface;
  WaylandService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_flushKeysOnBlur);
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
    }
  }

  void _flushKeysOnBlur() {
    if (_keys.hasFocus) return;
    for (final c in _pressed) {
      service.key(c, false);
    }
    _pressed.clear();
  }

  @override
  void didUpdateWidget(WaylandSurfaceView old) {
    super.didUpdateWidget(old);
    if (widget.focused && !old.focused) _grabFocus();
  }

  void _grabFocus() {
    _keys.requestFocus();
  }

  void _motion(PointerEvent e, Size box) {
    final p = surfaceCoordsAt(surface, e.localPosition, box);
    final hit = subSurfaceHit(service, surface, p);
    if (hit != null) {
      service.pointerMotion(hit.$1.id, hit.$2.dx, hit.$2.dy);
      return;
    }
    service.pointerMotion(surface.id, p.dx, p.dy);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) =>
      waylandKeyEvent(
        service,
        _pressed,
        event,
        escReserved: widget.escReserved,
        inhibited: surface.shortcutsInhibited,
      );

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
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final last = _reported;
            if (last == null ||
                last.size != box ||
                last.max != widget.maximized ||
                last.fs != widget.fullscreen ||
                last.resizing != widget.resizing) {
              _reported = (
                size: box,
                max: widget.maximized,
                fs: widget.fullscreen,
                resizing: widget.resizing,
              );
              service.configure(
                surface.id,
                box.width.round(),
                box.height.round(),
                maximized: widget.maximized,
                fullscreen: widget.fullscreen,
                resizing: widget.resizing,
              );
            }
          });
          return AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final size = surface.size;
              return SurfaceHitRegion(
                region: surface.inputRegion,
                surfaceSize: surface.size,
                geoOffset: surface.geoOffset,
                child: MouseRegion(
                  onExit: (_) => service.pointerExit(surface.id),
                  cursor: waylandMouseCursor(service),
                  child: Listener(
                    onPointerHover: (e) {
                      _motion(e, box);
                      _buttons = e.buttons;
                    },
                    onPointerMove: (e) {
                      if (e.kind == PointerDeviceKind.touch) {
                        final p = surfaceCoordsAt(
                          surface,
                          e.localPosition,
                          box,
                        );
                        service.touchMotion(e.pointer, p.dx, p.dy);
                        return;
                      }
                      _motion(e, box);
                      _buttons = e.buttons;
                    },
                    onPointerDown: (e) {
                      final p = surfaceCoordsAt(
                        surface,
                        e.localPosition,
                        box,
                      );
                      if (e.kind == PointerDeviceKind.touch) {
                        service.touchDown(
                          surface.id,
                          e.pointer,
                          p.dx,
                          p.dy,
                        );
                        return;
                      }
                      _motion(e, box);
                      forwardButtonDiff(service, _buttons, e.buttons);
                      _buttons = e.buttons;
                    },
                    onPointerUp: (e) {
                      if (e.kind == PointerDeviceKind.touch) {
                        service.touchUp(e.pointer);
                        return;
                      }
                      _motion(e, box);
                      forwardButtonDiff(service, _buttons, e.buttons);
                      _buttons = e.buttons;
                    },
                    onPointerCancel: (e) {
                      if (e.kind == PointerDeviceKind.touch) {
                        service.touchUp(e.pointer);
                        return;
                      }
                      forwardButtonDiff(service, _buttons, e.buttons);
                      _buttons = e.buttons;
                    },
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        service.pointerAxis(
                          e.scrollDelta.dx,
                          e.scrollDelta.dy,
                          discrete: (e.scrollDelta.dy / 20).round(),
                        );
                      }
                    },
                    onPointerPanZoomUpdate: (e) {
                      service.pointerAxis(
                        e.panDelta.dx,
                        e.panDelta.dy,
                        source: 1,
                      );
                    },
                    onPointerPanZoomEnd: (_) {
                      service.pointerAxisStop();
                    },
                    child: ColoredBox(
                      color: const Color(0xFF000000),
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox(
                          width: size.width <= 0 ? 1 : size.width,
                          height: size.height <= 0 ? 1 : size.height,
                          child: WaylandLayerTree(
                            service: service,
                            surface: surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class WaylandPopupView extends StatefulWidget {
  const WaylandPopupView({
    super.key,
    required this.surface,
    required this.service,
  });

  final WaylandSurface surface;
  final WaylandService service;

  @override
  State<WaylandPopupView> createState() => _WaylandPopupViewState();
}

class _WaylandPopupViewState extends State<WaylandPopupView> {
  var _buttons = 0;

  void _motion(PointerEvent e) {
    final p = surfaceCoordsAt(
      widget.surface,
      e.localPosition,
      widget.surface.size,
    );
    final hit = subSurfaceHit(widget.service, widget.surface, p);
    if (hit != null) {
      widget.service.pointerMotion(hit.$1.id, hit.$2.dx, hit.$2.dy);
      return;
    }
    widget.service.pointerMotion(widget.surface.id, p.dx, p.dy);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final size = widget.surface.size;
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }
        return SurfaceHitRegion(
          region: widget.surface.inputRegion,
          surfaceSize: size,
          geoOffset: widget.surface.geoOffset,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MouseRegion(
              onExit: (_) => widget.service.pointerExit(widget.surface.id),
              cursor: waylandMouseCursor(widget.service),
              child: Listener(
                onPointerHover: (e) {
                  _motion(e);
                  _buttons = e.buttons;
                },
                onPointerMove: (e) {
                  _motion(e);
                  _buttons = e.buttons;
                },
                onPointerDown: (e) {
                  _motion(e);
                  forwardButtonDiff(widget.service, _buttons, e.buttons);
                  _buttons = e.buttons;
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
                child: WaylandLayerTree(
                  service: widget.service,
                  surface: widget.surface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class WaylandLayerTree extends StatelessWidget {
  const WaylandLayerTree({
    super.key,
    required this.service,
    required this.surface,
  });

  final WaylandService service;
  final WaylandSurface surface;

  // Surface coordinates map 1:1 to widget pixels: the view shows the
  // window geometry region of the surface space, so buffer, geometry
  // offset and subsurface positions all share that coordinate system.
  // The only stretch happens with wp_viewport: the source rect scales
  // up to the surface size the compositor reports.
  (double, double) _srcScale() {
    final src = surface.vpSrc;
    final sx = src != null && src.width > 0
        ? surface.size.width / src.width
        : 1.0;
    final sy = src != null && src.height > 0
        ? surface.size.height / src.height
        : 1.0;
    return (sx, sy);
  }

  List<Widget> _layers(WaylandSurface root, Offset base) {
    final (sx, sy) = _srcScale();
    final out = <Widget>[];
    for (final id in root.children) {
      final sub = service.surfaces[id];
      if (sub == null) continue;
      final pos = base + sub.offset;
      final sw = sub.size.width * sx;
      final sh = sub.size.height * sy;
      out.add(
        Positioned(
          left: pos.dx * sx,
          top: pos.dy * sy,
          width: sw <= 0 ? 1 : sw,
          height: sh <= 0 ? 1 : sh,
          child: sub.textureId >= 0
              ? applyBufferTransform(
                  Texture(textureId: sub.textureId),
                  sub.transform,
                )
              : const SizedBox.shrink(),
        ),
      );
      out.addAll(_layers(sub, pos));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final buf = logicalSurfaceSize(surface);
    final (sx, sy) = _srcScale();
    return Stack(
      children: [
        if (surface.textureId >= 0)
          Positioned(
            left: -surface.geoOffset.dx * sx,
            top: -surface.geoOffset.dy * sy,
            width: buf.width * sx,
            height: buf.height * sy,
            child: applyBufferTransform(
              Texture(textureId: surface.textureId),
              surface.transform,
            ),
          ),
        ..._layers(surface, -surface.geoOffset),
      ],
    );
  }
}
