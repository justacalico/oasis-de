import 'package:flutter/foundation.dart';

import 'oasis_store.dart';

/// How the dash shares the screen with windows.
enum OasisDashMode {
  /// Always visible; maximised windows keep clear of it.
  push,

  /// Hidden until the pointer reaches the screen edge.
  autoHide,

  /// No dash at all.
  off,
}

enum OasisDashPosition { left, bottom, right }

enum OasisDashSize { small, medium, large, custom }

const kDashIconSizeSmall = 40.0;
const kDashIconSizeMedium = 52.0;
const kDashIconSizeLarge = 68.0;
const kDashCustomSizeMin = 32.0;
const kDashCustomSizeMax = 96.0;

/// User preferences for the dash, persisted through [OasisStore] so the
/// settings app and the shell share one live instance.
class OasisDashSettings extends ChangeNotifier {
  OasisDashSettings({OasisStore? store}) : _store = store {
    final s = _store;
    if (s == null) return;
    _mode =
        OasisDashMode.values.asNameMap()[s.read('shell.dock.mode')] ?? _mode;
    _position =
        OasisDashPosition.values.asNameMap()[s.read('shell.dock.position')] ??
        _position;
    _size =
        OasisDashSize.values.asNameMap()[s.read('shell.dock.size')] ?? _size;
    final custom = double.tryParse(s.read('shell.dock.customSize') ?? '');
    if (custom != null) {
      _customSize = custom
          .clamp(kDashCustomSizeMin, kDashCustomSizeMax)
          .toDouble();
    }
  }

  final OasisStore? _store;

  var _mode = OasisDashMode.push;
  var _position = OasisDashPosition.bottom;
  var _size = OasisDashSize.medium;
  var _customSize = 64.0;

  OasisDashMode get mode => _mode;
  OasisDashPosition get position => _position;
  OasisDashSize get size => _size;
  double get customSize => _customSize;

  /// Resolved icon size in logical pixels.
  double get iconSize => switch (_size) {
    OasisDashSize.small => kDashIconSizeSmall,
    OasisDashSize.medium => kDashIconSizeMedium,
    OasisDashSize.large => kDashIconSizeLarge,
    OasisDashSize.custom => _customSize,
  };

  set mode(OasisDashMode v) =>
      _set(v, _mode, (v) => _mode = v, 'shell.dock.mode');
  set position(OasisDashPosition v) =>
      _set(v, _position, (v) => _position = v, 'shell.dock.position');
  set size(OasisDashSize v) =>
      _set(v, _size, (v) => _size = v, 'shell.dock.size');

  set customSize(double v) {
    final clamped = v.clamp(kDashCustomSizeMin, kDashCustomSizeMax).toDouble();
    if (clamped == _customSize) return;
    _customSize = clamped;
    _store?.write('shell.dock.customSize', '$clamped');
    notifyListeners();
  }

  void _set<T extends Enum>(
    T v,
    T current,
    void Function(T) apply,
    String key,
  ) {
    if (v == current) return;
    apply(v);
    _store?.write(key, v.name);
    notifyListeners();
  }
}
