import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_backend.dart';

class CliSystemBackend implements OasisSystemBackend {
  const CliSystemBackend({
    this.run,
    this.powerSupplyDir,
    this.startProcess,
    this.userName,
    this.drmDir,
    this.sessionId,
    this.procDir,
  });

  final Future<ProcessResult> Function(String, List<String>)? run;
  final Directory? powerSupplyDir;
  final Future<Process> Function(String, List<String>)? startProcess;
  final String Function()? userName;
  final Directory? drmDir;
  final String Function()? sessionId;
  final Directory? procDir;

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
  Future<void> connectWifi(String ssid) =>
      _exec('nmcli', ['device', 'wifi', 'connect', ssid]);

  @override
  Future<List<OasisWifiNetwork>> wifiNetworks() async {
    final out = await _read('nmcli', [
      '-t',
      '-f',
      'ACTIVE,SSID,SIGNAL,SECURITY',
      'device',
      'wifi',
      'list',
    ]);
    if (out == null) return const [];
    final seen = <String>{};
    final networks = <OasisWifiNetwork>[];
    for (final line in out.split('\n')) {
      final fields = _splitTerse(line);
      if (fields.length < 4) continue;
      final ssid = fields[1].trim();
      if (ssid.isEmpty || !seen.add(ssid)) continue;
      networks.add(
        OasisWifiNetwork(
          ssid: ssid,
          signal: int.tryParse(fields[2].trim()) ?? 0,
          secured:
              fields[3].trim().isNotEmpty && fields[3].trim() != '--',
          connected: fields[0].trim() == 'yes',
        ),
      );
    }
    networks.sort((a, b) {
      final byActive = (b.connected ? 1 : 0).compareTo(
        a.connected ? 1 : 0,
      );
      return byActive != 0 ? byActive : b.signal.compareTo(a.signal);
    });
    return networks;
  }

  static List<String> _splitTerse(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var escaped = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == ':') {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

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
  Future<List<OasisAudioDevice>> audioOutputs() => _audioNodes('sink');

  @override
  Future<List<OasisAudioDevice>> audioInputs() => _audioNodes('source');

  Future<List<OasisAudioDevice>> _audioNodes(String kind) async {
    final results = await Future.wait([
      _read('pactl', ['--format=json', 'list', '${kind}s']),
      _read('pactl', ['get-default-$kind']),
    ]);
    final out = results[0];
    if (out == null) return const [];
    try {
      final list = jsonDecode(out);
      if (list is! List) return const [];
      final defaultName = results[1]?.trim();
      return [
        for (final e in list)
          if (e is Map &&
              e['name'] is String &&
              (kind == 'sink' || !_isMonitor(e)))
            OasisAudioDevice(
              name: e['name'] as String,
              description: '${e['description'] ?? e['name']}',
              isDefault: e['name'] == defaultName,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static bool _isMonitor(Map e) =>
      '${e['monitor_source'] ?? ''}'.isNotEmpty ||
      e['monitor_of_sink'] != null;

  @override
  Future<List<OasisAudioCard>> audioCards() async {
    final out = await _read('pactl', ['--format=json', 'list', 'cards']);
    if (out == null) return const [];
    try {
      final list = jsonDecode(out);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map && e['name'] is String) _audioCard(e),
      ];
    } on FormatException {
      return const [];
    }
  }

  static OasisAudioCard _audioCard(Map e) {
    final props = e['properties'];
    final profiles = e['profiles'];
    return OasisAudioCard(
      name: e['name'] as String,
      description: props is Map
          ? '${props['device.description'] ?? e['name']}'
          : e['name'] as String,
      activeProfile: '${e['active_profile'] ?? ''}',
      profiles: [
        if (profiles is Map)
          for (final p in profiles.entries)
            if (p.value is Map)
              OasisAudioProfile(
                name: '${p.key}',
                description: '${p.value['description'] ?? p.key}',
                available: p.value['available'] != false,
              ),
      ],
    );
  }

  @override
  Future<void> setAudioOutput(String name) =>
      _exec('pactl', ['set-default-sink', name]);

  @override
  Future<void> setAudioInput(String name) =>
      _exec('pactl', ['set-default-source', name]);

  @override
  Future<void> setAudioCardProfile(String card, String profile) =>
      _exec('pactl', ['set-card-profile', card, profile]);

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
        final sid = sessionId?.call() ??
            Platform.environment['XDG_SESSION_ID'];
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
    final user = (userName ?? () => Platform.environment['USER'] ?? '')();
    if (user.isEmpty) return false;
    try {
      final p = await (startProcess ?? Process.start)(
        'unix_chkpwd',
        [user],
      );
      p.stdin.writeln(password);
      await p.stdin.close();
      return await p.exitCode == 0;
    } catch (_) {
      return false;
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

    final proc = procDir?.path ?? '/proc';
    final cpuLine = read('$proc/cpuinfo')
        .split('\n')
        .firstWhere((l) => l.startsWith('model name'), orElse: () => '');
    final memKb = RegExp(r'MemTotal:\s+(\d+)')
        .firstMatch(read('$proc/meminfo'))
        ?.group(1);
    String disk = '';
    try {
      final r = await (run ?? Process.run)('df', ['-h', '/']);
      if (r.exitCode == 0) {
        final line = '${r.stdout}'
            .split('\n')
            .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) disk = '${parts[1]} (${parts[2]} used)';
      }
    } catch (_) {}
    String gpu = '';
    final drm = drmDir ?? Directory('/sys/class/drm');
    try {
      for (final e in drm.listSync()) {
        final uevent = File('${e.path}/device/uevent');
        if (!uevent.existsSync()) continue;
        for (final l in read(uevent.path).split('\n')) {
          if (l.startsWith('DRIVER=')) gpu = l.substring(7);
        }
        if (gpu.isNotEmpty) break;
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
      kernel: read('$proc/version').split(' ').take(3).join(' '),
      cpu: cpuLine.contains(':') ? cpuLine.split(':').last.trim() : '',
      memory: memKb == null
          ? ''
          : '${(int.parse(memKb) / 1048576).toStringAsFixed(1)} GB',
      disk: disk,
      gpu: gpu,
    );
  }
}
