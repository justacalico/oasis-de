import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_settings/state/settings_state.dart';
import 'package:oasis_ui/oasis_ui.dart';

void main() {
  test('cli backend runs system commands', () {
    final calls = <String>[];
    Future<ProcessResult> fakeRun(String exe, List<String> args) async {
      calls.add('$exe ${args.join(' ')}');
      return ProcessResult(0, 0, '', '');
    }

    CliSystemBackend(run: fakeRun)
      ..wifi(true)
      ..wifi(false)
      ..bluetooth(true)
      ..bluetooth(false)
      ..brightness(0.5)
      ..brightness(2.0)
      ..volume(0.4);

    expect(calls, [
      'nmcli radio wifi on',
      'nmcli radio wifi off',
      'bluetoothctl power on',
      'bluetoothctl power off',
      'brightnessctl set 50%',
      'brightnessctl set 100%',
      'wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.4',
    ]);
  });

  test('noop backend accepts calls', () {
    const NoopSystemBackend()
      ..wifi(true)
      ..bluetooth(true)
      ..brightness(0.5)
      ..volume(0.5);
  });

  test('settings state writes shared keys and calls backend', () {
    final calls = <String>[];
    final store = MemoryOasisStore();
    final s = SettingsState(store: store, backend: _RecordingBackend(calls));
    s.wifiEnabled = false;
    s.bluetoothEnabled = true;
    expect(store.read('shell.wifi'), '0');
    expect(store.read('shell.bluetooth'), '1');
    expect(calls, ['wifi', 'bluetooth']);

    final s2 = SettingsState(store: store);
    expect(s2.wifiOn, isFalse);
    expect(s2.bluetoothOn, isTrue);
  });
}

class _RecordingBackend implements OasisSystemBackend {
  _RecordingBackend(this.calls);

  final List<String> calls;

  @override
  void wifi(bool enabled) => calls.add('wifi');

  @override
  void bluetooth(bool enabled) => calls.add('bluetooth');

  @override
  void brightness(double level) => calls.add('brightness');

  @override
  void volume(double level) => calls.add('volume');
}
