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
      ..volume(0.4)
      ..nightLight(true)
      ..nightLight(false)
      ..session(OasisSessionAction.lock)
      ..session(OasisSessionAction.logout)
      ..session(OasisSessionAction.suspend)
      ..session(OasisSessionAction.reboot)
      ..session(OasisSessionAction.poweroff);

    expect(calls, [
      'nmcli radio wifi on',
      'nmcli radio wifi off',
      'bluetoothctl power on',
      'bluetoothctl power off',
      'brightnessctl set 50%',
      'brightnessctl set 100%',
      'wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.4',
      'gammastep -O 3500',
      'gammastep -x',
      'loginctl lock-session',
      Platform.environment['XDG_SESSION_ID']?.isNotEmpty == true
          ? 'loginctl terminate-session ${Platform.environment['XDG_SESSION_ID']}'
          : 'loginctl terminate-user self',
      'systemctl suspend',
      'systemctl reboot',
      'systemctl poweroff',
    ]);
  });

  test('cli backend reads real system state', () async {
    Future<ProcessResult> fakeRun(String exe, List<String> args) async {
      final out = switch (exe) {
        'nmcli' => 'enabled',
        'bluetoothctl' => 'Powered: yes\nName: host',
        'brightnessctl' => 'dev,class,80,75%,100',
        'wpctl' => 'Volume: 0.65',
        'gammastep' => 'Period: Night\nColor temperature: 3500',
        _ => '',
      };
      return ProcessResult(0, 0, out, '');
    }

    final s = await CliSystemBackend(run: fakeRun).read();
    expect(s.wifi, isTrue);
    expect(s.bluetooth, isTrue);
    expect(s.brightness, 0.75);
    expect(s.volume, 0.65);
    expect(s.nightLight, isTrue);
  });

  test('cli backend read tolerates missing tools', () async {
    Future<ProcessResult> fakeRun(String exe, List<String> args) async {
      if (exe == 'brightnessctl') {
        throw const ProcessException('brightnessctl', []);
      }
      return ProcessResult(0, 1, '', '');
    }

    final s = await CliSystemBackend(run: fakeRun).read();
    expect(s.wifi, isNull);
    expect(s.brightness, isNull);
    expect(s.volume, isNull);
  });

  test('cli backend reads battery from sysfs', () async {
    final root = Directory.systemTemp.createTempSync();
    final bat = Directory('${root.path}/BAT0')..createSync();
    File('${bat.path}/capacity').writeAsStringSync('75');
    File('${bat.path}/status').writeAsStringSync('Discharging');
    var b = await CliSystemBackend(powerSupplyDir: root).battery();
    expect(b.level, 0.75);
    expect(b.charging, isFalse);
    File('${bat.path}/status').writeAsStringSync('Charging');
    b = await CliSystemBackend(powerSupplyDir: root).battery();
    expect(b.charging, isTrue);
    File('${bat.path}/status').writeAsStringSync('Full');
    b = await CliSystemBackend(powerSupplyDir: root).battery();
    expect(b.charging, isTrue);
    b = await CliSystemBackend(
      powerSupplyDir: Directory.systemTemp.createTempSync(),
    ).battery();
    expect(b.level, isNull);
    final gone = Directory.systemTemp.createTempSync()..deleteSync();
    b = await CliSystemBackend(powerSupplyDir: gone).battery();
    expect(b.level, isNull);
    final emptyBat = Directory.systemTemp.createTempSync();
    Directory('${emptyBat.path}/BAT1').createSync();
    b = await CliSystemBackend(powerSupplyDir: emptyBat).battery();
    expect(b.level, isNull);
  });

  test('noop backend accepts calls', () async {
    NoopSystemBackend()
      ..wifi(true)
      ..bluetooth(true)
      ..brightness(0.5)
      ..volume(0.5)
      ..nightLight(true)
      ..session(OasisSessionAction.lock);
    expect(
      (await NoopSystemBackend().read()).wifi,
      isNull,
    );
    expect((await NoopSystemBackend().battery()).level, isNull);
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
  Future<void> wifi(bool enabled) async => calls.add('wifi');

  @override
  Future<void> bluetooth(bool enabled) async => calls.add('bluetooth');

  @override
  Future<void> brightness(double level) async => calls.add('brightness');

  @override
  Future<void> volume(double level) async => calls.add('volume');

  @override
  Future<void> nightLight(bool enabled) async => calls.add('nightLight');

  @override
  Future<OasisSystemState> read() async => const OasisSystemState();

  @override
  Future<OasisBattery> battery() async =>
      const OasisBattery(level: null, charging: false);

  @override
  void session(OasisSessionAction action) => calls.add('session');

  @override
  Future<bool> verifyPassword(String password) async => true;
}
