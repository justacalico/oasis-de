import 'package:flutter/foundation.dart';

import 'oasis_store.dart';

/// Which side of the mouse acts as the primary click.
enum OasisPrimaryButton { left, right }

double _clamp(double v) => v.clamp(0.0, 1.0).toDouble();

/// Preferences shared by every pointing device: pointer acceleration, scroll
/// distance, and whether scrolling follows the content or the wheel.
/// Persisted through [OasisStore] so the settings app and the shell share
/// one live instance per device type.
class OasisPointerSettings extends ChangeNotifier {
  OasisPointerSettings({OasisStore? store, required String prefix})
      : _store = store,
        _prefix = prefix {
    final s = _store;
    if (s == null) return;
    final pointer = double.tryParse(s.read('$_prefix.pointerSpeed') ?? '');
    if (pointer != null) _pointerSpeed = _clamp(pointer);
    final scroll = double.tryParse(s.read('$_prefix.scrollSpeed') ?? '');
    if (scroll != null) _scrollSpeed = _clamp(scroll);
    _naturalScrolling = s.read('$_prefix.naturalScrolling') == '1';
  }

  final OasisStore? _store;
  final String _prefix;

  var _pointerSpeed = 0.5;
  var _scrollSpeed = 0.5;
  var _naturalScrolling = false;

  double get pointerSpeed => _pointerSpeed;
  double get scrollSpeed => _scrollSpeed;
  bool get naturalScrolling => _naturalScrolling;

  set pointerSpeed(double v) =>
      _applySpeed(v, _pointerSpeed, (x) => _pointerSpeed = x, 'pointerSpeed');
  set scrollSpeed(double v) =>
      _applySpeed(v, _scrollSpeed, (x) => _scrollSpeed = x, 'scrollSpeed');
  set naturalScrolling(bool v) => _applyBool(
      v, _naturalScrolling, (x) => _naturalScrolling = x, 'naturalScrolling');

  void _applySpeed(
    double v,
    double current,
    void Function(double) assign,
    String key,
  ) {
    final clamped = _clamp(v);
    if (clamped == current) return;
    assign(clamped);
    _store?.write('$_prefix.$key', '$clamped');
    notifyListeners();
  }

  void _applyBool(
    bool v,
    bool current,
    void Function(bool) assign,
    String key,
  ) {
    if (v == current) return;
    assign(v);
    _store?.write('$_prefix.$key', v ? '1' : '0');
    notifyListeners();
  }

  void _applyEnum<T extends Enum>(
    T v,
    T current,
    void Function(T) assign,
    String key,
  ) {
    if (v == current) return;
    assign(v);
    _store?.write('$_prefix.$key', v.name);
    notifyListeners();
  }
}

/// Mouse preferences under `shell.mouse.*`. Independent from the trackpad so
/// natural scrolling and speeds can differ per device.
class OasisMouseSettings extends OasisPointerSettings {
  OasisMouseSettings({super.store}) : super(prefix: 'shell.mouse') {
    final s = _store;
    if (s == null) return;
    _primaryButton = OasisPrimaryButton.values
            .asNameMap()[s.read('shell.mouse.primaryButton')] ??
        _primaryButton;
    final dbl = double.tryParse(s.read('shell.mouse.doubleClickSpeed') ?? '');
    if (dbl != null) _doubleClickSpeed = _clamp(dbl);
  }

  var _primaryButton = OasisPrimaryButton.left;
  var _doubleClickSpeed = 0.5;

  OasisPrimaryButton get primaryButton => _primaryButton;
  double get doubleClickSpeed => _doubleClickSpeed;

  set primaryButton(OasisPrimaryButton v) => _applyEnum(
      v, _primaryButton, (x) => _primaryButton = x, 'primaryButton');
  set doubleClickSpeed(double v) => _applySpeed(
      v, _doubleClickSpeed, (x) => _doubleClickSpeed = x, 'doubleClickSpeed');
}

/// Trackpad preferences under `shell.trackpad.*`. Independent from the mouse
/// so natural scrolling can stay on for the trackpad and off for the mouse.
class OasisTrackpadSettings extends OasisPointerSettings {
  OasisTrackpadSettings({super.store}) : super(prefix: 'shell.trackpad') {
    final s = _store;
    if (s == null) return;
    _tapToClick = s.read('shell.trackpad.tapToClick') == '1';
    _twoFingerScrolling =
        s.read('shell.trackpad.twoFingerScrolling') != '0';
  }

  var _tapToClick = false;
  var _twoFingerScrolling = true;

  bool get tapToClick => _tapToClick;
  bool get twoFingerScrolling => _twoFingerScrolling;

  set tapToClick(bool v) =>
      _applyBool(v, _tapToClick, (x) => _tapToClick = x, 'tapToClick');
  set twoFingerScrolling(bool v) => _applyBool(v, _twoFingerScrolling,
      (x) => _twoFingerScrolling = x, 'twoFingerScrolling');
}
