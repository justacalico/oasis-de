import 'package:flutter/widgets.dart';

import '../services/oasis_store.dart';

class OasisWallpaperService extends ChangeNotifier {
  OasisWallpaperService({OasisStore? store})
      : _store = store ?? MemoryOasisStore() {
    _imagePath = _store.read(kImagePathKey);
    _fit = _fitFromName(_store.read(kFitKey));
    _preset = _store.read(kPresetKey) ?? 'dunes';
  }

  static const kImagePathKey = 'wallpaper.imagePath';
  static const kFitKey = 'wallpaper.fit';
  static const kPresetKey = 'wallpaper.preset';

  static const supportedFits = [BoxFit.cover, BoxFit.contain, BoxFit.fill];

  final OasisStore _store;
  String? _imagePath;
  BoxFit _fit = BoxFit.cover;
  String _preset = 'dunes';

  String? get imagePath => _imagePath;
  bool get hasCustomImage => _imagePath != null;
  BoxFit get fit => _fit;
  String get preset => _preset;

  set imagePath(String? path) {
    if (path == _imagePath) return;
    _imagePath = path;
    if (path == null) {
      _store.remove(kImagePathKey);
    } else {
      _store.write(kImagePathKey, path);
    }
    notifyListeners();
  }

  set fit(BoxFit fit) {
    if (fit == _fit) return;
    _fit = fit;
    _store.write(kFitKey, fit.name);
    notifyListeners();
  }

  void useDefault() => imagePath = null;

  void usePreset(String id) {
    _preset = id;
    _store.write(kPresetKey, id);
    imagePath = null;
  }

  static BoxFit _fitFromName(String? name) {
    for (final fit in supportedFits) {
      if (fit.name == name) return fit;
    }
    return BoxFit.cover;
  }
}

class OasisWallpaperPreset {
  const OasisWallpaperPreset({required this.id, this.top, this.mid, this.bottom});

  final String id;
  final Color? top;
  final Color? mid;
  final Color? bottom;
}

const oasisWallpaperPresets = <OasisWallpaperPreset>[
  OasisWallpaperPreset(id: 'dunes'),
  OasisWallpaperPreset(
    id: 'peaks',
    top: Color(0xFF2C3E50),
    mid: Color(0xFF4A6572),
    bottom: Color(0xFF15202B),
  ),
  OasisWallpaperPreset(
    id: 'aurora',
    top: Color(0xFF0B3D36),
    mid: Color(0xFF12766E),
    bottom: Color(0xFF04181C),
  ),
  OasisWallpaperPreset(
    id: 'ember',
    top: Color(0xFF3B1C32),
    mid: Color(0xFF7A2E4D),
    bottom: Color(0xFF1B0E14),
  ),
];
