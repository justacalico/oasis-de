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

class OasisWifiNetwork {
  const OasisWifiNetwork({
    required this.ssid,
    this.signal = 0,
    this.secured = false,
    this.connected = false,
  });

  final String ssid;
  final int signal;
  final bool secured;
  final bool connected;
}

class OasisAudioDevice {
  const OasisAudioDevice({
    required this.name,
    this.description = '',
    this.isDefault = false,
  });

  final String name;
  final String description;
  final bool isDefault;

  OasisAudioDevice copyWith({bool? isDefault}) => OasisAudioDevice(
        name: name,
        description: description,
        isDefault: isDefault ?? this.isDefault,
      );
}

class OasisAudioProfile {
  const OasisAudioProfile({
    required this.name,
    this.description = '',
    this.available = true,
  });

  final String name;
  final String description;
  final bool available;
}

class OasisAudioCard {
  const OasisAudioCard({
    required this.name,
    this.description = '',
    this.activeProfile = '',
    this.profiles = const [],
  });

  final String name;
  final String description;
  final String activeProfile;
  final List<OasisAudioProfile> profiles;

  OasisAudioCard copyWith({String? activeProfile}) => OasisAudioCard(
        name: name,
        description: description,
        activeProfile: activeProfile ?? this.activeProfile,
        profiles: profiles,
      );
}

abstract class OasisSystemBackend {
  Future<void> wifi(bool enabled);
  Future<List<OasisWifiNetwork>> wifiNetworks();
  Future<void> connectWifi(String ssid);
  Future<void> bluetooth(bool enabled);
  Future<void> brightness(double level);
  Future<void> volume(double level);
  Future<List<OasisAudioDevice>> audioOutputs();
  Future<List<OasisAudioDevice>> audioInputs();
  Future<List<OasisAudioCard>> audioCards();
  Future<void> setAudioOutput(String name);
  Future<void> setAudioInput(String name);
  Future<void> setAudioCardProfile(String card, String profile);
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
  Future<List<OasisWifiNetwork>> wifiNetworks() async => const [];

  @override
  Future<void> connectWifi(String ssid) async {}

  @override
  Future<void> bluetooth(bool enabled) async {}

  @override
  Future<void> brightness(double level) async {}

  @override
  Future<void> volume(double level) async {}

  @override
  Future<List<OasisAudioDevice>> audioOutputs() async => const [];

  @override
  Future<List<OasisAudioDevice>> audioInputs() async => const [];

  @override
  Future<List<OasisAudioCard>> audioCards() async => const [];

  @override
  Future<void> setAudioOutput(String name) async {}

  @override
  Future<void> setAudioInput(String name) async {}

  @override
  Future<void> setAudioCardProfile(String card, String profile) async {}

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
