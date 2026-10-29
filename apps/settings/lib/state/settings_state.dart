import 'package:flutter/foundation.dart';
import 'package:oasis_ui/oasis_ui.dart';

typedef SettingsStore = OasisStore;
typedef MemorySettingsStore = MemoryOasisStore;
typedef PrefsSettingsStore = PrefsOasisStore;

enum SettingsPane { appearance, wallpaper, general, wifi, bluetooth, about }

class SettingsState extends ChangeNotifier {
  SettingsState({SettingsStore? store, this.backend})
      : _store = store ?? MemorySettingsStore() {
    wifiOn = _store.read('shell.wifi') != '0';
    bluetoothOn = _store.read('shell.bluetooth') != '0';
  }

  final SettingsStore _store;
  final OasisSystemBackend? backend;

  var pane = SettingsPane.appearance;
  var wifiOn = true;
  var bluetoothOn = true;

  void selectPane(SettingsPane next) {
    if (pane == next) return;
    pane = next;
    notifyListeners();
  }

  set wifiEnabled(bool v) =>
      _set('shell.wifi', v, () => wifiOn = v, () => backend?.wifi(v));
  set bluetoothEnabled(bool v) => _set('shell.bluetooth', v,
      () => bluetoothOn = v, () => backend?.bluetooth(v));

  void _set(String key, bool v, void Function() apply,
      [void Function()? after]) {
    apply();
    _store.write(key, v ? '1' : '0');
    after?.call();
    notifyListeners();
  }
}
