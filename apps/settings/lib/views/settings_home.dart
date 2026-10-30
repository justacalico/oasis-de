import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'panes.dart';
import 'wallpaper_pane.dart';

class SettingsHome extends StatefulWidget {
  const SettingsHome({
    super.key,
    this.state,
    this.wallpaper,
    this.version = '0.1.0',
  });

  final SettingsState? state;
  final OasisWallpaperService? wallpaper;
  final String version;

  @override
  State<SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<SettingsHome> {
  late final SettingsState _owned;
  late final OasisWallpaperService _ownedWallpaper;
  SettingsState get s => widget.state ?? _owned;
  OasisWallpaperService get wallpaper =>
      widget.wallpaper ?? _ownedWallpaper;

  @override
  void initState() {
    super.initState();
    if (widget.state == null) _owned = SettingsState();
    if (widget.wallpaper == null) {
      _ownedWallpaper = OasisWallpaperService();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;

    final entries = [
      (SettingsPane.appearance, l10n.settingsAppearance,
          Icons.brightness_6, const Color(0xFF5E5CE6)),
      (SettingsPane.wallpaper, l10n.settingsWallpaper,
          Icons.landscape, const Color(0xFF30B0C7)),
      (SettingsPane.displays, l10n.settingsDisplays,
          Icons.desktop_windows, const Color(0xFF0A84FF)),
      (SettingsPane.sound, l10n.settingsSound, Icons.volume_up,
          const Color(0xFFFF375F)),
      (SettingsPane.general, l10n.settingsGeneral, Icons.settings,
          const Color(0xFF8E8E93)),
      (SettingsPane.wifi, l10n.settingsWifi, Icons.wifi,
          const Color(0xFF0A84FF)),
      (SettingsPane.bluetooth, l10n.settingsBluetooth, Icons.bluetooth,
          const Color(0xFF0A84FF)),
      (SettingsPane.power, l10n.settingsPower,
          Icons.power_settings_new, const Color(0xFF32D74B)),
      (SettingsPane.datetime, l10n.settingsDateTime, Icons.schedule,
          const Color(0xFFBF5AF2)),
      (SettingsPane.users, l10n.settingsUsers, Icons.person,
          const Color(0xFFFF9F0A)),
      (SettingsPane.about, l10n.settingsAbout, Icons.water_drop,
          const Color(0xFF4FC3F7)),
    ];

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final query = s.query.toLowerCase();
        final visible = [
          for (final e in entries)
            if (query.isEmpty || e.$2.toLowerCase().contains(query)) e,
        ];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 216,
              color: p.sidebarBackground,
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: OasisSearchField(
                        hint: l10n.settingsSearchHint,
                        onChanged: (v) => s.searchQuery = v,
                      ),
                    ),
                  ),
                  for (final e in visible)
                    OasisNavRow(
                      icon: e.$3,
                      label: e.$2,
                      iconColor: e.$4,
                      selected: s.pane == e.$1,
                      onTap: () => s.selectPane(e.$1),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 0.5, color: p.divider),
            Expanded(
              child: Container(
                color: p.groupedBackground,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: switch (s.pane) {
                    SettingsPane.appearance => const AppearancePane(),
                    SettingsPane.wallpaper =>
                      WallpaperPane(wallpaper: wallpaper),
                    SettingsPane.general => const GeneralPane(),
                    SettingsPane.displays => DisplaysPane(state: s),
                    SettingsPane.sound => SoundPane(state: s),
                    SettingsPane.power => PowerPane(state: s),
                    SettingsPane.datetime => const DateTimePane(),
                    SettingsPane.users => UsersPane(state: s),
                    SettingsPane.wifi => NetworkPane(
                        title: l10n.settingsWifi,
                        icon: Icons.wifi,
                        enabled: s.wifiOn,
                        onChanged: (v) => s.wifiEnabled = v,
                        subtitle: l10n.settingsWifiBody,
                      ),
                    SettingsPane.bluetooth => NetworkPane(
                        title: l10n.settingsBluetooth,
                        icon: Icons.bluetooth,
                        enabled: s.bluetoothOn,
                        onChanged: (v) => s.bluetoothEnabled = v,
                        subtitle: l10n.settingsBluetoothBody,
                      ),
                    SettingsPane.about => AboutPane(
                      version: widget.version,
                      backend: s.backend,
                    ),
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
