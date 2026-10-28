import 'package:flutter/widgets.dart';

import 'package:oasis_ui/oasis_ui.dart';

class ShellWindowData {
  ShellWindowData({
    required this.id,
    required this.app,
    required this.position,
  });

  final int id;
  OasisApp app;
  Offset position;
  var minimized = false;
  var zoomed = false;
}

class ShellMenuItem {
  const ShellMenuItem({
    required this.label,
    this.enabled = true,
    this.separatorAfter = false,
    this.action,
  });

  final String label;
  final bool enabled;
  final bool separatorAfter;
  final void Function(BuildContext context)? action;
}

typedef ShellMenuAction = void Function(BuildContext context);

class ShellMenu {
  const ShellMenu({required this.label, required this.items});

  final String label;
  final List<ShellMenuItem> Function(BuildContext context) items;
}

class ShellController extends ChangeNotifier {
  ShellController({required List<OasisApp> apps})
      : apps = List.of(apps);

  final List<OasisApp> apps;
  final List<ShellWindowData> windows = [];

  int _nextId = 1;
  int? _focusedId;
  String? _openMenu;
  var launcherOpen = false;
  var controlCenterOpen = false;
  var wifiOn = true;
  var bluetoothOn = true;
  var focusOn = false;
  var brightness = 0.8;
  var volume = 0.6;

  int? get focusedId => _focusedId;
  String? get openMenu => _openMenu;

  void syncApps(List<OasisApp> fresh) {
    apps
      ..clear()
      ..addAll(fresh);
    final byId = {for (final a in fresh) a.id: a};
    for (final w in windows) {
      final updated = byId[w.app.id];
      if (updated != null) w.app = updated;
    }
  }

  ShellWindowData? get focusedWindow {
    final id = _focusedId;
    if (id == null) return null;
    for (final w in windows) {
      if (w.id == id && !w.minimized) return w;
    }
    return null;
  }

  List<OasisApp> filterApps(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return apps;
    return apps.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  void openApp(OasisApp app) {
    for (final w in windows) {
      if (w.app.id == app.id) {
        w.minimized = false;
        _focus(w.id);
        closeOverlays();
        return;
      }
    }
    final window = ShellWindowData(
      id: _nextId++,
      app: app,
      position: Offset(56 + windows.length * 28.0, 52 + windows.length * 24.0),
    );
    windows.add(window);
    _focus(window.id);
    closeOverlays();
  }

  void closeWindow(int id) {
    windows.removeWhere((w) => w.id == id);
    if (_focusedId == id) _focusedId = null;
    notifyListeners();
  }

  void minimizeWindow(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.minimized = true;
    if (_focusedId == id) _focusedId = null;
    notifyListeners();
  }

  void restoreWindow(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.minimized = false;
    _focus(id);
  }

  void toggleZoom(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.zoomed = !window.zoomed;
    notifyListeners();
  }

  void focusWindow(int id) => _focus(id);

  void _focus(int id) {
    if (_focusedId == id) return;
    final window = _byId(id);
    if (window == null) return;
    _focusedId = id;
    windows.remove(window);
    windows.add(window);
    notifyListeners();
  }

  void dragWindow(int id, Offset delta) {
    final window = _byId(id);
    if (window == null || window.zoomed) return;
    window.position += delta;
    notifyListeners();
  }

  ShellWindowData? _byId(int id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  void selectMenu(String? label) {
    if (_openMenu == label) return;
    _openMenu = label;
    notifyListeners();
  }

  void toggleLauncher() {
    launcherOpen = !launcherOpen;
    if (launcherOpen) {
      controlCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void toggleControlCenter() {
    controlCenterOpen = !controlCenterOpen;
    if (controlCenterOpen) {
      launcherOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void closeOverlays() {
    launcherOpen = false;
    controlCenterOpen = false;
    _openMenu = null;
    notifyListeners();
  }

  set wifiOnValue(bool v) => _set(() => wifiOn = v);
  set bluetoothOnValue(bool v) => _set(() => bluetoothOn = v);
  set focusOnValue(bool v) => _set(() => focusOn = v);
  set brightnessValue(double v) => _set(() => brightness = v);
  set volumeValue(double v) => _set(() => volume = v);

  void _set(void Function() apply) {
    apply();
    notifyListeners();
  }
}
