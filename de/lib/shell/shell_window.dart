import 'dart:async';

import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';

enum ShellWindowTransition { none, minimizing, restoring }

class ShellWindowData {
  ShellWindowData({
    required this.id,
    required this.app,
    required this.position,
    this.workspace = 0,
  });

  final int id;
  OasisApp app;
  Offset position;
  Size? size;
  Size? adoptedSize;
  final dockIconKey = GlobalKey();
  var workspace = 0;
  var animateGeom = false;

  WaylandSurface? _surface;
  Rect? _preSnapRect;
  bool _minimized = false;
  bool _zoomed = false;
  bool _fullscreen = false;
  ShellWindowTransition _transition = ShellWindowTransition.none;
  bool _launching = false;
  Timer? _launchTimer;

  WaylandSurface? get surface => _surface;
  bool get minimized => _minimized;
  bool get zoomed => _zoomed;
  bool get fullscreen => _fullscreen;
  ShellWindowTransition get transition => _transition;
  bool get launching => _launching;

  String get displayTitle =>
      _surface != null && _surface!.title.isNotEmpty
          ? _surface!.title
          : app.name;

  bool get clientDecorated => _surface?.clientDecorated ?? false;

  double get titleBarHeight =>
      clientDecorated ? 0 : kOasisWindowTitleBarHeight;

  void markMinimizing() {
    _minimized = true;
    _transition = ShellWindowTransition.minimizing;
  }

  void markRestoring() {
    _minimized = false;
    _transition = ShellWindowTransition.restoring;
  }

  void finishTransition() => _transition = ShellWindowTransition.none;

  void setZoomed(bool on, {bool animate = true}) {
    _zoomed = on;
    adoptedSize = _surface?.size;
    animateGeom = animate;
  }

  void setFullscreen(bool on, {bool animate = true}) {
    _fullscreen = on;
    adoptedSize = _surface?.size;
    animateGeom = animate;
  }

  void unzoomTo(Offset position) {
    _zoomed = false;
    this.position = position;
  }

  void snapTo({
    required Rect preSnap,
    required Offset position,
    required Size size,
  }) {
    _preSnapRect = preSnap;
    _zoomed = false;
    _fullscreen = false;
    this.position = position;
    this.size = size;
    adoptedSize = _surface?.size;
    animateGeom = true;
  }

  Rect? takePreSnap() {
    final r = _preSnapRect;
    _preSnapRect = null;
    return r;
  }

  void beginLaunch(Timer timeout) {
    _launching = true;
    _launchTimer = timeout;
  }

  void cancelLaunch() {
    _launching = false;
    _launchTimer?.cancel();
    _launchTimer = null;
  }

  void bindSurface(WaylandSurface surface) {
    _surface = surface;
    cancelLaunch();
  }
}
