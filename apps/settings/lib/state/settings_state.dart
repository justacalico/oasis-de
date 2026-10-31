import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:oasis_ui/oasis_ui.dart';

typedef SettingsStore = OasisStore;
typedef MemorySettingsStore = MemoryOasisStore;
typedef PrefsSettingsStore = PrefsOasisStore;

enum SettingsPane {
  appearance,
  wallpaper,
  displays,
  sound,
  general,
  wifi,
  bluetooth,
  power,
  datetime,
  users,
  about,
}

class SettingsState extends ChangeNotifier {
  SettingsState({SettingsStore? store, this.backend, this.displayBackend})
      : _store = store ?? MemorySettingsStore() {
    wifiOn = _store.read('shell.wifi') != '0';
    bluetoothOn = _store.read('shell.bluetooth') != '0';
    nightLightOn = _store.read('shell.nightLight') == '1';
    brightness =
        double.tryParse(_store.read('shell.brightness') ?? '') ?? 0.8;
    volume = double.tryParse(_store.read('shell.volume') ?? '') ?? 0.6;
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    final b = backend;
    if (b == null) return;
    final s = await b.read();
    if (s.wifi != null) wifiOn = s.wifi!;
    if (s.bluetooth != null) bluetoothOn = s.bluetooth!;
    if (s.brightness != null) brightness = s.brightness!;
    if (s.volume != null) volume = s.volume!;
    if (s.nightLight != null) nightLightOn = s.nightLight!;
    notifyListeners();
  }

  final SettingsStore _store;
  final OasisSystemBackend? backend;
  final OasisDisplayBackend? displayBackend;

  List<OasisDisplay> displays = const [];
  var displaysBusy = false;

  Future<void> refreshDisplays() async {
    final b = displayBackend;
    if (b == null) return;
    displaysBusy = true;
    notifyListeners();
    displays = await b.displays();
    displaysBusy = false;
    notifyListeners();
  }

  Future<void> applyDisplay(OasisDisplay d) async {
    final b = displayBackend;
    if (b == null) return;
    await b.setDisplay(d);
    await refreshDisplays();
  }

  Future<void> identifyDisplays() =>
      displayBackend?.identifyDisplays() ?? Future.value();

  List<OasisAudioDevice> audioOutputs = const [];
  List<OasisAudioDevice> audioInputs = const [];
  List<OasisAudioCard> audioCards = const [];

  Future<void> refreshAudio() async {
    final b = backend;
    if (b == null) return;
    final results = await Future.wait([
      b.audioOutputs(),
      b.audioInputs(),
      b.audioCards(),
    ]);
    audioOutputs = results[0] as List<OasisAudioDevice>;
    audioInputs = results[1] as List<OasisAudioDevice>;
    audioCards = results[2] as List<OasisAudioCard>;
    notifyListeners();
  }

  Future<void> selectAudioOutput(String name) async {
    await backend?.setAudioOutput(name);
    audioOutputs = _markDefault(audioOutputs, name);
    notifyListeners();
  }

  Future<void> selectAudioInput(String name) async {
    await backend?.setAudioInput(name);
    audioInputs = _markDefault(audioInputs, name);
    notifyListeners();
  }

  Future<void> selectAudioProfile(String card, String profile) async {
    await backend?.setAudioCardProfile(card, profile);
    audioCards = [
      for (final c in audioCards)
        c.name == card ? c.copyWith(activeProfile: profile) : c,
    ];
    notifyListeners();
  }

  static List<OasisAudioDevice> _markDefault(
    List<OasisAudioDevice> devices,
    String name,
  ) =>
      [
        for (final d in devices) d.copyWith(isDefault: d.name == name),
      ];

  var pane = SettingsPane.appearance;
  var wifiOn = true;
  var bluetoothOn = true;
  var nightLightOn = false;
  var brightness = 0.8;
  var volume = 0.6;
  var query = '';

  void selectPane(SettingsPane next) {
    if (pane == next) return;
    pane = next;
    notifyListeners();
  }

  set searchQuery(String v) {
    if (query == v) return;
    query = v;
    notifyListeners();
  }

  set wifiEnabled(bool v) =>
      _set('shell.wifi', v, () => wifiOn = v, () => backend?.wifi(v));
  set bluetoothEnabled(bool v) => _set('shell.bluetooth', v,
      () => bluetoothOn = v, () => backend?.bluetooth(v));
  set nightLightEnabled(bool v) => _set('shell.nightLight', v,
      () => nightLightOn = v, () => backend?.nightLight(v));

  set brightnessLevel(double v) {
    brightness = v;
    _store.write('shell.brightness', '$v');
    backend?.brightness(v);
    notifyListeners();
  }

  set volumeLevel(double v) {
    volume = v;
    _store.write('shell.volume', '$v');
    backend?.volume(v);
    notifyListeners();
  }

  Future<OasisBattery> battery() =>
      backend?.battery() ??
      Future<OasisBattery>.value(
        const OasisBattery(level: null, charging: false),
      );

  void session(OasisSessionAction action) => backend?.session(action);

  void _set(String key, bool v, void Function() apply,
      [void Function()? after]) {
    apply();
    _store.write(key, v ? '1' : '0');
    after?.call();
    notifyListeners();
  }
}
