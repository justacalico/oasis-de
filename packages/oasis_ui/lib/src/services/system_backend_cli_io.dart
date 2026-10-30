import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_backend.dart';

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

  @override
  Future<OasisSystemInfo> systemInfo() async {
    if (kIsWeb) return const OasisSystemInfo();
    String read(String p) {
      try {
        return File(p).readAsStringSync().trim();
      } catch (_) {
        return '';
      }
    }

    final cpuLine = read('/proc/cpuinfo')
        .split('\n')
        .firstWhere((l) => l.startsWith('model name'), orElse: () => '');
    final memKb = RegExp(r'MemTotal:\s+(\d+)')
        .firstMatch(read('/proc/meminfo'))
        ?.group(1);
    String disk = '';
    try {
      final r = await (run ?? Process.run)('df', ['-h', '/']);
      if (r.exitCode == 0) {
        final parts = '${r.stdout}'
            .split('\n')
            .last
            .trim()
            .split(RegExp(r'\s+'));
        if (parts.length >= 4) disk = '${parts[1]} (${parts[2]} used)';
      }
    } catch (_) {}
    String osName = '';
    for (final line in read('/etc/os-release').split('\n')) {
      if (line.startsWith('PRETTY_NAME=')) {
        osName = line.substring(12).replaceAll('"', '');
      }
    }
    return OasisSystemInfo(
      deviceName: Platform.localHostname,
      osName: osName,
      kernel: read('/proc/version').split(' ').take(3).join(' '),
      cpu: cpuLine.contains(':') ? cpuLine.split(':').last.trim() : '',
      memory: memKb == null
          ? ''
          : '${(int.parse(memKb) / 1048576).toStringAsFixed(1)} GB',
      disk: disk,
      gpu: '',
    );
  }
}
