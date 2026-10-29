import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

class WaylandSurfaceView extends StatefulWidget {
  const WaylandSurfaceView({
    super.key,
    required this.surface,
    required this.service,
    required this.focused,
    required this.maximized,
  });

  final WaylandSurface surface;
  final WaylandService service;
  final bool focused;
  final bool maximized;

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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _grabFocus());
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
    final s = surface.size;
    if (s.width <= 0 || s.height <= 0) return local;
    final scale = math.min(
        box.width / s.width, box.height / s.height);
    final origin = Offset((box.width - s.width * scale) / 2,
        (box.height - s.height * scale) / 2);
    return (local - origin) / scale;
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
              service.configure(surface.id, box.width.round(),
                  box.height.round(), widget.maximized);
            }
          });
          return AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final size = surface.size;
              return MouseRegion(
                onExit: (_) => service.pointerExit(surface.id),
                child: Listener(
                  onPointerHover: (e) => _motion(e, box),
                  onPointerMove: (e) => _motion(e, box),
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
                      service.pointerAxis(
                          e.scrollDelta.dx, e.scrollDelta.dy);
                    }
                  },
                  child: ColoredBox(
                    color: const Color(0xFF000000),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: size.width <= 0 ? 1 : size.width,
                        height: size.height <= 0 ? 1 : size.height,
                        child:
                            Texture(textureId: surface.textureId),
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

class WaylandPopupView extends StatelessWidget {
  const WaylandPopupView({
    super.key,
    required this.surface,
    required this.service,
  });

  final WaylandSurface surface;
  final WaylandService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final size = surface.size;
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }
        var buttons = 0;
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Listener(
            onPointerHover: (e) => service.pointerMotion(
                surface.id, e.localPosition.dx, e.localPosition.dy),
            onPointerMove: (e) => service.pointerMotion(
                surface.id, e.localPosition.dx, e.localPosition.dy),
            onPointerDown: (e) {
              service.pointerMotion(
                  surface.id, e.localPosition.dx, e.localPosition.dy);
              forwardButtonDiff(service, buttons, e.buttons);
              buttons = e.buttons;
            },
            onPointerUp: (e) {
              forwardButtonDiff(service, buttons, e.buttons);
              buttons = e.buttons;
            },
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                service.pointerAxis(
                    e.scrollDelta.dx, e.scrollDelta.dy);
              }
            },
            child: Texture(textureId: surface.textureId),
          ),
        );
      },
    );
  }
}
