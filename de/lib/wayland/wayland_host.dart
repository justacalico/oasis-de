import 'package:flutter/services.dart';

abstract class WaylandHost {
  const WaylandHost();

  Stream<Map<String, Object?>> get events;

  Future<String?> start();
  Future<void> launch(List<String> argv);
  Future<void> configure(
    int id,
    int width,
    int height, {
    bool maximized = false,
    bool fullscreen = false,
    bool resizing = false,
  });
  Future<void> close(int id);
  Future<void> focus(int? id);
  Future<void> pointerMotion(int id, double x, double y);
  Future<void> pointerExit(int id);
  Future<void> pointerButton(int button, bool pressed);
  Future<void> pointerAxis(double dx, double dy);
  Future<void> key(int code, bool pressed);
}

class ChannelWaylandHost extends WaylandHost {
  const ChannelWaylandHost();

  static const _methods = MethodChannel('oasis/wayland');
  static const _events = EventChannel('oasis/wayland/events');

  @override
  Stream<Map<String, Object?>> get events => _events
      .receiveBroadcastStream()
      .map((event) => (event as Map).cast<String, Object?>());

  @override
  Future<String?> start() async {
    final result = await _methods.invokeMapMethod<String, dynamic>('start');
    return result?['socket'] as String?;
  }

  @override
  Future<void> launch(List<String> argv) =>
      _methods.invokeMethod('launch', {'argv': argv});

  @override
  Future<void> configure(
    int id,
    int width,
    int height, {
    bool maximized = false,
    bool fullscreen = false,
    bool resizing = false,
  }) => _methods.invokeMethod('configure', {
    'id': id,
    'w': width,
    'h': height,
    'maximized': maximized ? 1 : 0,
    'fullscreen': fullscreen ? 1 : 0,
    'resizing': resizing ? 1 : 0,
  });

  @override
  Future<void> close(int id) => _methods.invokeMethod('close', {'id': id});

  @override
  Future<void> focus(int? id) =>
      _methods.invokeMethod('focus', {'id': id ?? -1});

  @override
  Future<void> pointerMotion(int id, double x, double y) =>
      _methods.invokeMethod('pointerMotion', {'id': id, 'x': x, 'y': y});

  @override
  Future<void> pointerExit(int id) =>
      _methods.invokeMethod('pointerExit', {'id': id});

  @override
  Future<void> pointerButton(int button, bool pressed) => _methods.invokeMethod(
    'pointerButton',
    {'button': button, 'state': pressed ? 1 : 0},
  );

  @override
  Future<void> pointerAxis(double dx, double dy) =>
      _methods.invokeMethod('pointerAxis', {'dx': dx, 'dy': dy});

  @override
  Future<void> key(int code, bool pressed) =>
      _methods.invokeMethod('key', {'code': code, 'state': pressed ? 1 : 0});
}
