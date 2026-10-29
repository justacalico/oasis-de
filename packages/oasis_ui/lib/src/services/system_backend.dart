import 'dart:io';

import 'package:flutter/foundation.dart';

abstract class OasisSystemBackend {
  void wifi(bool enabled);
  void bluetooth(bool enabled);
  void brightness(double level);
  void volume(double level);
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
}

class CliSystemBackend implements OasisSystemBackend {
  const CliSystemBackend({this.run});

  final Future<ProcessResult> Function(String, List<String>)? run;

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
}
