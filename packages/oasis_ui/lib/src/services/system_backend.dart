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
  Future<OasisSystemInfo> systemInfo();
}

class OasisSystemInfo {
  const OasisSystemInfo({
    this.deviceName = '',
    this.osName = '',
    this.kernel = '',
    this.cpu = '',
    this.memory = '',
    this.disk = '',
    this.gpu = '',
  });

  final String deviceName;
  final String osName;
  final String kernel;
  final String cpu;
  final String memory;
  final String disk;
  final String gpu;
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

  @override
  Future<OasisSystemInfo> systemInfo() async => const OasisSystemInfo();
}
