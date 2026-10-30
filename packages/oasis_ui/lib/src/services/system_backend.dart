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

enum OasisSessionAction { lock, logout, suspend, reboot, poweroff }

abstract class OasisSystemBackend {
  Future<void> wifi(bool enabled);
  Future<void> bluetooth(bool enabled);
  Future<void> brightness(double level);
  Future<void> volume(double level);
  Future<void> nightLight(bool enabled);
  Future<OasisSystemState> read();
  Future<OasisBattery> battery();
  void session(OasisSessionAction action);
  Future<bool> verifyPassword(String password);
}

class NoopSystemBackend implements OasisSystemBackend {
  const NoopSystemBackend();

  @override
  Future<void> wifi(bool enabled) async {}

  @override
  Future<void> bluetooth(bool enabled) async {}

  @override
  Future<void> brightness(double level) async {}

  @override
  Future<void> volume(double level) async {}

  @override
  Future<void> nightLight(bool enabled) async {}

  @override
  Future<OasisSystemState> read() async => const OasisSystemState();

  @override
  Future<OasisBattery> battery() async =>
      const OasisBattery(level: null, charging: false);

  @override
  void session(OasisSessionAction action) {}

  @override
  Future<bool> verifyPassword(String password) async => true;
}

class CliSystemBackend implements OasisSystemBackend {
  const CliSystemBackend({this.run, this.powerSupplyDir});

  final Future<ProcessResult> Function(String, List<String>)? run;
  final Directory? powerSupplyDir;

  Future<void> _exec(String exe, List<String> args) async {
    if (kIsWeb) return;
    try {
      await (run ?? Process.run)(exe, args);
    } on ProcessException {
      return;
    }
  }

  @override
  Future<void> wifi(bool enabled) =>
      _exec('nmcli', ['radio', 'wifi', enabled ? 'on' : 'off']);

  @override
  Future<void> bluetooth(bool enabled) =>
      _exec('bluetoothctl', ['power', enabled ? 'on' : 'off']);

  @override
  Future<void> brightness(double level) {
    final pct = (level.clamp(0.0, 1.0) * 100).round();
    return _exec('brightnessctl', ['set', '$pct%']);
  }

  @override
  Future<void> volume(double level) {
    final v = level.clamp(0.0, 1.0);
    return _exec('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '$v']);
  }

  @override
  Future<void> nightLight(bool enabled) {
    return _exec('gammastep', enabled ? ['-O', '3500'] : ['-x']);
  }

  Future<String?> _read(
    String exe,
    List<String> args, {
    bool stderr = false,
  }) async {
    if (kIsWeb) return null;
    try {
      final r = await (run ?? Process.run)(exe, args);
      if (r.exitCode != 0) return null;
      return stderr ? '${r.stdout}${r.stderr}' : r.stdout.toString();
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<OasisSystemState> read() async {
    final results = await Future.wait([
      _read('nmcli', ['radio', 'wifi']),
      _read('bluetoothctl', ['show']),
      _read('brightnessctl', ['-m']),
      _read('wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@']),
      _read('gammastep', ['-p'], stderr: true),
    ]);
    final [wifiOut, btOut, brightOut, volOut, nlOut] = results;
    return OasisSystemState(
      wifi: wifiOut?.contains('enabled'),
      bluetooth: btOut != null &&
          RegExp(r'Powered:\s*(yes|on|1|true)', caseSensitive: false)
              .hasMatch(btOut),
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

  @override
  void session(OasisSessionAction action) {
    switch (action) {
      case OasisSessionAction.lock:
        _exec('loginctl', ['lock-session']);
      case OasisSessionAction.logout:
        final sid = Platform.environment['XDG_SESSION_ID'];
        if (sid != null && sid.isNotEmpty) {
          _exec('loginctl', ['terminate-session', sid]);
        } else {
          _exec('loginctl', ['terminate-user', 'self']);
        }
      case OasisSessionAction.suspend:
        _exec('systemctl', ['suspend']);
      case OasisSessionAction.reboot:
        _exec('systemctl', ['reboot']);
      case OasisSessionAction.poweroff:
        _exec('systemctl', ['poweroff']);
    }
  }

  @override
  Future<bool> verifyPassword(String password) async {
    if (kIsWeb) return true;
    final user = Platform.environment['USER'];
    if (user == null || user.isEmpty) return true;
    try {
      final p = await Process.start('unix_chkpwd', [user]);
      p.stdin.writeln(password);
      await p.stdin.close();
      return await p.exitCode == 0;
    } catch (_) {
      return true;
    }
  }
}
