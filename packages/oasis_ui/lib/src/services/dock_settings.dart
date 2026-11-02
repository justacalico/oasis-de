import 'package:flutter/foundation.dart';

import 'oasis_store.dart';

/// How the dock shares the screen with windows.
enum OasisDockMode {
  /// Always visible; maximised windows keep clear of it.
  push,

  /// Hidden until the pointer reaches the screen edge.
  autoHide,

  /// No dock at all.
  off,
}

enum OasisDockPosition { left, bottom, right }

enum OasisDockSize { small, medium, large, custom }

const kDockIconSizeSmall = 40.0;
const kDockIconSizeMedium = 52.0;
const kDockIconSizeLarge = 68.0;
const kDockCustomSizeMin = 32.0;
const kDockCustomSizeMax = 96.0;

/// User preferences for the dock, persisted through [OasisStore] so the
/// settings app and the shell share one live instance.
class OasisDockSettings extends ChangeNotifier {
  OasisDockSettings({OasisStore? store}) : _store = store {
    final s = _store;
    if (s == null) return;
    _mode =
        OasisDockMode.values.asNameMap()[s.read('shell.dock.mode')] ?? _mode;
    _position =
        OasisDockPosition.values.asNameMap()[s.read('shell.dock.position')] ??
        _position;
    _size =
        OasisDockSize.values.asNameMap()[s.read('shell.dock.size')] ?? _size;
    final custom = double.tryParse(s.read('shell.dock.customSize') ?? '');
    if (custom != null) {
      _customSize = custom
          .clamp(kDockCustomSizeMin, kDockCustomSizeMax)
          .toDouble();
    }
  }

  final OasisStore? _store;

  var _mode = OasisDockMode.push;
  var _position = OasisDockPosition.bottom;
  var _size = OasisDockSize.medium;
  var _customSize = 64.0;

  OasisDockMode get mode => _mode;
  OasisDockPosition get position => _position;
  OasisDockSize get size => _size;
  double get customSize => _customSize;

  /// Resolved icon size in logical pixels.
  double get iconSize => switch (_size) {
    OasisDockSize.small => kDockIconSizeSmall,
    OasisDockSize.medium => kDockIconSizeMedium,
    OasisDockSize.large => kDockIconSizeLarge,
    OasisDockSize.custom => _customSize,
  };

  set mode(OasisDockMode v) =>
      _set(v, _mode, (v) => _mode = v, 'shell.dock.mode');
  set position(OasisDockPosition v) =>
      _set(v, _position, (v) => _position = v, 'shell.dock.position');
  set size(OasisDockSize v) =>
      _set(v, _size, (v) => _size = v, 'shell.dock.size');

  set customSize(double v) {
    final clamped = v.clamp(kDockCustomSizeMin, kDockCustomSizeMax).toDouble();
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
