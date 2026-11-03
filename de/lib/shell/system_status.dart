import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'package:oasis_ui/oasis_ui.dart';

import 'shell_constants.dart';

class SystemStatus {
  SystemStatus({
    required this.backend,
    required void Function() onChanged,
    Future<void> Function()? onUnlocked,
    Duration? batteryPollInterval,
  })  : _onChanged = onChanged,
        _onUnlocked = onUnlocked {
    unawaited(_refresh());
    if (batteryPollInterval != null) {
      _batteryTimer = Timer.periodic(
        batteryPollInterval,
        (_) => unawaited(pollBattery()),
      );
    }
  }

  final OasisSystemBackend backend;
  final void Function() _onChanged;
  final Future<void> Function()? _onUnlocked;

  double? batteryLevel;
  bool batteryCharging = false;
  Timer? _batteryTimer;

  var wifiOn = true;
  List<OasisWifiNetwork> wifiNetworks = const [];
  var wifiScanning = false;
  var bluetoothOn = true;
  var focusOn = false;
  var nightLightOn = false;
  var brightness = kDefaultBrightness;
  var volume = kDefaultVolume;
  var _appliedBrightnessPct = -1;
  var _appliedVolumePct = -1;

  var locked = false;
  var _failedUnlocks = 0;
  DateTime? _unlockLockedUntil;

  var _disposed = false;

  Future<void> pollBattery() async {
    OasisBattery b;
    try {
      b = await backend.battery();
    } catch (e) {
      debugPrint('Oasis: battery poll failed: $e');
      return;
    }
    if (_disposed) return;
    if (b.level == batteryLevel && b.charging == batteryCharging) return;
    batteryLevel = b.level;
    batteryCharging = b.charging;
    _onChanged();
  }

  Future<void> _refresh() async {
    unawaited(pollBattery());
    OasisSystemState s;
    try {
      s = await backend.read();
    } catch (e) {
      debugPrint('Oasis: system state read failed: $e');
      return;
    }
    if (_disposed) return;
    if (s.wifi != null) wifiOn = s.wifi!;
    if (s.bluetooth != null) bluetoothOn = s.bluetooth!;
    if (s.brightness != null) brightness = s.brightness!;
    if (s.volume != null) volume = s.volume!;
    if (s.nightLight != null) nightLightOn = s.nightLight!;
    _onChanged();
  }

  Future<void> refreshWifiNetworks() async {
    if (!wifiOn) {
      if (wifiNetworks.isNotEmpty) {
        wifiNetworks = const [];
        _onChanged();
      }
      return;
    }
    wifiScanning = true;
    _onChanged();
    List<OasisWifiNetwork> found;
    try {
      found = await backend.wifiNetworks();
    } catch (e) {
      debugPrint('Oasis: wifi scan failed: $e');
      found = const [];
    }
    if (_disposed) return;
    wifiNetworks = wifiOn ? found : const [];
    wifiScanning = false;
    _onChanged();
  }

  Future<void> connectWifiNetwork(String ssid) async {
    await backend.connectWifi(ssid);
    if (_disposed) return;
    unawaited(refreshWifiNetworks());
  }

  set wifiOnValue(bool v) => _set(() => wifiOn = v, () => backend.wifi(v));
  set bluetoothOnValue(bool v) =>
      _set(() => bluetoothOn = v, () => backend.bluetooth(v));
  set focusOnValue(bool v) => _set(() => focusOn = v);
  set nightLightOnValue(bool v) =>
      _set(() => nightLightOn = v, () => backend.nightLight(v));

  int _percent(double v) => (v.clamp(0.0, 1.0) * 100).round();

  set brightnessValue(double v) {
    _appliedBrightnessPct = _percent(v);
    _set(() => brightness = v, () => backend.brightness(v));
  }

  set volumeValue(double v) {
    _appliedVolumePct = _percent(v);
    _set(() => volume = v, () => backend.volume(v));
  }

  set brightnessPreview(double v) {
    _set(() => brightness = v);
    final pct = _percent(v);
    if (pct == _appliedBrightnessPct) return;
    _appliedBrightnessPct = pct;
    unawaited(backend.brightness(v));
  }

  set volumePreview(double v) {
    _set(() => volume = v);
    final pct = _percent(v);
    if (pct == _appliedVolumePct) return;
    _appliedVolumePct = pct;
    unawaited(backend.volume(v));
  }

  void idleSuspend() => session(OasisSessionAction.suspend);

  void session(OasisSessionAction action) {
    if (action == OasisSessionAction.lock ||
        action == OasisSessionAction.suspend) {
      locked = true;
      if (action == OasisSessionAction.suspend) {
        backend.session(OasisSessionAction.lock);
      }
    }
    backend.session(action);
    _onChanged();
  }

  Future<bool> tryUnlock(String password) async {
    final until = _unlockLockedUntil;
    if (until != null) {
      final wait = until.difference(clock.now());
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    if (await backend.verifyPassword(password)) {
      locked = false;
      _failedUnlocks = 0;
      await _onUnlocked?.call();
      _onChanged();
      return true;
    }
    _failedUnlocks++;
    _unlockLockedUntil = clock.now().add(
      kUnlockBackoffStep * _failedUnlocks,
    );
    return false;
  }

  void _set(void Function() apply, [Future<void> Function()? after]) {
    apply();
    final done = after?.call();
    if (done != null) {
      unawaited(done.then((_) => _refresh()));
    }
    _onChanged();
  }

  void dispose() {
    _disposed = true;
    _batteryTimer?.cancel();
  }
}
