import 'dart:io';

import 'package:flutter/foundation.dart';

class OasisSystemState {
  const OasisSystemState({
    this.wifi,
    this.bluetooth,
    this.brightness,
    this.volume,
    this.nightLight,
  });

  final bool? wifi;
  final bool? bluetooth;
  final double? brightness;
  final double? volume;
  final bool? nightLight;
}

class OasisBattery {
  const OasisBattery({required this.level, required this.charging});

  final double? level;
  final bool charging;
}

abstract class OasisSystemBackend {
  void wifi(bool enabled);
  void bluetooth(bool enabled);
  void brightness(double level);
  void volume(double level);
  void nightLight(bool enabled);
  Future<OasisSystemState> read();
  Future<OasisBattery> battery();
}

class NoopSystemBackend implements OasisSystemBackend {
  const NoopSystemBackend();

  @override
  void wifi(bool enabled) {}

  @override
  void bluetooth(bool enabled) {}

  @override
  void brightness(double level) {}

  @override
  void volume(double level) {}

  @override
  void nightLight(bool enabled) {}

  @override
  Future<OasisSystemState> read() async => const OasisSystemState();

  @override
  Future<OasisBattery> battery() async =>
      const OasisBattery(level: null, charging: false);
}

class CliSystemBackend implements OasisSystemBackend {
  const CliSystemBackend({this.run, this.powerSupplyDir});

  final Future<ProcessResult> Function(String, List<String>)? run;
  final Directory? powerSupplyDir;

  void _exec(String exe, List<String> args) {
    if (kIsWeb) return;
    final r = run ?? Process.run;
    r(exe, args).ignore();
  }

  @override
  void wifi(bool enabled) =>
      _exec('nmcli', ['radio', 'wifi', enabled ? 'on' : 'off']);

  @override
  void bluetooth(bool enabled) =>
      _exec('bluetoothctl', ['power', enabled ? 'on' : 'off']);

  @override
  void brightness(double level) {
    final pct = (level.clamp(0.0, 1.0) * 100).round();
    _exec('brightnessctl', ['set', '$pct%']);
  }

  @override
  void volume(double level) {
    final v = level.clamp(0.0, 1.0);
    _exec('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '$v']);
  }

  @override
  void nightLight(bool enabled) {
    _exec('gammastep', enabled ? ['-O', '3500'] : ['-x']);
  }

  Future<String?> _read(String exe, List<String> args) async {
    if (kIsWeb) return null;
    try {
      final r = await (run ?? Process.run)(exe, args);
      return r.exitCode == 0 ? r.stdout.toString() : null;
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<OasisSystemState> read() async {
    final wifiOut = await _read('nmcli', ['radio', 'wifi']);
    final btOut = await _read('bluetoothctl', ['show']);
    final brightOut = await _read('brightnessctl', ['-m']);
    final volOut = await _read('wpctl', [
      'get-volume',
      '@DEFAULT_AUDIO_SINK@',
    ]);
    final nlOut = await _read('gammastep', ['-p']);
    return OasisSystemState(
      wifi: wifiOut?.contains('enabled'),
      bluetooth: btOut?.contains('Powered: yes'),
      brightness: _parseBrightness(brightOut),
      volume: _parseVolume(volOut),
      nightLight: nlOut?.contains('3500'),
    );
  }

  static double? _parseBrightness(String? out) {
    if (out == null) return null;
    final pct = RegExp(r'(\d+)%').firstMatch(out)?.group(1);
    if (pct == null) return null;
    return int.parse(pct) / 100;
  }

  static double? _parseVolume(String? out) {
    if (out == null) return null;
    final v = RegExp(r'Volume:\s*([\d.]+)').firstMatch(out)?.group(1);
    if (v == null) return null;
    return double.parse(v).clamp(0.0, 1.0);
  }

  @override
  Future<OasisBattery> battery() async {
    if (kIsWeb) return const OasisBattery(level: null, charging: false);
    try {
      final dir = powerSupplyDir ?? Directory('/sys/class/power_supply');
      if (!dir.existsSync()) {
        return const OasisBattery(level: null, charging: false);
      }
      for (final e in dir.listSync()) {
        final name = e.path.split('/').last;
        if (!name.startsWith('BAT')) continue;
        final cap = await File('${e.path}/capacity').readAsString();
        final status = await File('${e.path}/status').readAsString();
        return OasisBattery(
          level: (int.tryParse(cap.trim()) ?? 0) / 100,
          charging: status.trim() == 'Charging' ||
              status.trim() == 'Full',
        );
      }
    } on FileSystemException {
      return const OasisBattery(level: null, charging: false);
    }
    return const OasisBattery(level: null, charging: false);
  }
}
