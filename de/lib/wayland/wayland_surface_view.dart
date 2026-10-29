import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
  final b = s.bufferSize;
  final sc = s.scale <= 0 ? 1.0 : s.scale;
  if (b.width > 0 && b.height > 0) {
    final w = b.width / sc;
    final h = b.height / sc;
    return (s.transform & 1) != 0 ? Size(h, w) : Size(w, h);
  }
  return s.size;
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

class SurfaceHitRegion extends SingleChildRenderObjectWidget {
  const SurfaceHitRegion({
    super.key,
    required this.region,
    required this.surfaceSize,
    super.child,
  });

  final List<Rect>? region;
  final Size surfaceSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSurfaceHitRegion(region: region, surfaceSize: surfaceSize);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSurfaceHitRegion renderObject,
  ) {
    renderObject
      ..region = region
      ..surfaceSize = surfaceSize;
  }
}

class RenderSurfaceHitRegion extends RenderProxyBox {
  RenderSurfaceHitRegion({
    required List<Rect>? region,
    required Size surfaceSize,
  }) : _region = region,
       _surfaceSize = surfaceSize;

  List<Rect>? _region;
  Size _surfaceSize;

  set region(List<Rect>? v) => _region = v;
  set surfaceSize(Size v) => _surfaceSize = v;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final region = _region;
    if (region != null && size.width > 0 && size.height > 0) {
      final p = Offset(
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
  });

  final WaylandSurface surface;
  final WaylandService service;
  final bool focused;
  final bool maximized;
  final bool fullscreen;

  @override
  State<WaylandSurfaceView> createState() => _WaylandSurfaceViewState();
}

class _WaylandSurfaceViewState extends State<WaylandSurfaceView> {
  final _keys = FocusNode();
  var _buttons = 0;
  Size? _reported;

  WaylandSurface get surface => widget.surface;
  WaylandService get service => widget.service;

  @override
  void initState() {
    super.initState();
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
    }
  }

  @override
  void didUpdateWidget(WaylandSurfaceView old) {
    super.didUpdateWidget(old);
    if (widget.focused && !old.focused) {
      _grabFocus();
    } else if (!widget.focused && old.focused) {
      service.focus(null);
    }
  }

  void _grabFocus() {
    _keys.requestFocus();
    service.focus(surface.id);
  }

  Offset _surfaceCoords(Offset local, Size box) {
    final s = logicalSurfaceSize(surface);
    if (s.width <= 0 || s.height <= 0) return local;
    return Offset(
      local.dx * s.width / box.width,
      local.dy * s.height / box.height,
    );
  }

  void _motion(PointerEvent e, Size box) {
    final p = _surfaceCoords(e.localPosition, box);
    service.pointerMotion(surface.id, p.dx, p.dy);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final code = evdevCodeFor(event.physicalKey);
    if (code == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      service.key(code, false);
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      service.key(code, true);
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
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
            if (last == null || last != box) {
              _reported = box;
              service.configure(
                surface.id,
                box.width.round(),
                box.height.round(),
                maximized: widget.maximized,
                fullscreen: widget.fullscreen,
              );
            }
          });
          return AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final size = surface.size;
              return SurfaceHitRegion(
                region: surface.inputRegion,
                surfaceSize: logicalSurfaceSize(surface),
                child: MouseRegion(
                  onExit: (_) => service.pointerExit(surface.id),
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
                      forwardButtonDiff(service, _buttons, e.buttons);
                      _buttons = e.buttons;
                    },
                    onPointerUp: (e) {
                      _motion(e, box);
                      forwardButtonDiff(service, _buttons, e.buttons);
                      _buttons = e.buttons;
                    },
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        service.pointerAxis(e.scrollDelta.dx, e.scrollDelta.dy);
                      }
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
    widget.service.pointerMotion(
      widget.surface.id,
      e.localPosition.dx,
      e.localPosition.dy,
    );
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
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MouseRegion(
              onExit: (_) => widget.service.pointerExit(widget.surface.id),
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

  List<Widget> _layers(WaylandSurface root, Offset base) {
    final buf = logicalSurfaceSize(surface);
    final sx = buf.width > 0 ? surface.size.width / buf.width : 1.0;
    final sy = buf.height > 0 ? surface.size.height / buf.height : 1.0;
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
    return Stack(
      children: [
        if (surface.textureId >= 0)
          Positioned.fill(
            child: applyBufferTransform(
              Texture(textureId: surface.textureId),
              surface.transform,
            ),
          ),
        ..._layers(surface, Offset.zero),
      ],
    );
  }
}
