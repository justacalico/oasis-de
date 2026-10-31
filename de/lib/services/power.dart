import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';

class WaylandPowerBackend implements OasisPowerBackend {
  const WaylandPowerBackend(this._wayland, {this.store});

  final WaylandService _wayland;
  final OasisStore? store;

  @override
  Future<void> setIdleTimeouts({Duration? displayOff, Duration? suspend}) =>
      _wayland.setIdleTimeouts(
        displayOff?.inMilliseconds ?? 0,
        suspend?.inMilliseconds ?? 0,
      );

  void restore() {
    final off = int.tryParse(store?.read('shell.displayOffAfter') ?? '');
    final suspend = int.tryParse(store?.read('shell.sleepAfter') ?? '');
    if (off == null && suspend == null) return;
    _wayland.setIdleTimeouts(off ?? 300000, suspend ?? 0);
  }
}
