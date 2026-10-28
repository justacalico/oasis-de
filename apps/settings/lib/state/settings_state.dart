import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SettingsPane { appearance, general, wifi, bluetooth, about }

abstract class SettingsStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

class MemorySettingsStore extends SettingsStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async =>
      _values[key] = value;
}

class PrefsSettingsStore extends SettingsStore {
  PrefsSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _prefs.setString(key, value);
}

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
