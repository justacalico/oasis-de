import 'package:flutter/widgets.dart';

import '../services/oasis_store.dart';

class OasisWallpaperService extends ChangeNotifier {
  OasisWallpaperService({OasisStore? store})
      : _store = store ?? MemoryOasisStore() {
    _imagePath = _store.read(kImagePathKey);
    _fit = _fitFromName(_store.read(kFitKey));
  }

  static const kImagePathKey = 'wallpaper.imagePath';
  static const kFitKey = 'wallpaper.fit';

  static const supportedFits = [BoxFit.cover, BoxFit.contain, BoxFit.fill];

  final OasisStore _store;
  String? _imagePath;
  BoxFit _fit = BoxFit.cover;

  String? get imagePath => _imagePath;
  bool get hasCustomImage => _imagePath != null;
  BoxFit get fit => _fit;

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

  static BoxFit _fitFromName(String? name) {
    for (final fit in supportedFits) {
      if (fit.name == name) return fit;
    }
    return BoxFit.cover;
  }
}
