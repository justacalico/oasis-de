import 'package:flutter/foundation.dart';
import 'package:oasis_ui/oasis_ui.dart';

typedef SettingsStore = OasisStore;
typedef MemorySettingsStore = MemoryOasisStore;
typedef PrefsSettingsStore = PrefsOasisStore;

enum SettingsPane { appearance, wallpaper, general, wifi, bluetooth, about }

class SettingsState extends ChangeNotifier {
  SettingsState({SettingsStore? store})
      : _store = store ?? MemorySettingsStore() {
    wifiOn = _store.read('wifi') != 'off';
    bluetoothOn = _store.read('bluetooth') != 'off';
  }

  final SettingsStore _store;

  var pane = SettingsPane.appearance;
  var wifiOn = true;
  var bluetoothOn = true;

  void selectPane(SettingsPane next) {
    if (pane == next) return;
    pane = next;
    notifyListeners();
  }

  set wifiEnabled(bool v) => _set('wifi', v, () => wifiOn = v);
  set bluetoothEnabled(bool v) =>
      _set('bluetooth', v, () => bluetoothOn = v);

  void _set(String key, bool v, void Function() apply) {
    apply();
    _store.write(key, v ? 'on' : 'off');
    notifyListeners();
  }
}
