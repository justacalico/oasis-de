import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';

class WifiPane extends StatefulWidget {
  const WifiPane({super.key, required this.state});

  final SettingsState state;

  @override
  State<WifiPane> createState() => _WifiPaneState();
}

class _WifiPaneState extends State<WifiPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(widget.state.refreshWifiNetworks()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    final s = widget.state;

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsWifi, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                OasisRow(
                  leading: Icon(Icons.wifi, size: 20, color: p.accent),
                  title: l10n.settingsWifi,
                  subtitle: l10n.settingsWifiBody,
                  trailing: OasisToggle(
                    value: s.wifiOn,
                    onChanged: (v) => s.wifiEnabled = v,
                  ),
                ),
              ],
            ),
            if (s.wifiOn) ...[
              const SizedBox(height: 16),
              OasisSection(
                title: l10n.settingsWifiNetworks,
                children: [
                  if (s.wifiNetworks.isEmpty)
                    OasisRow(
                      title: s.wifiScanning
                          ? l10n.wifiMenuScanning
                          : l10n.wifiMenuNoNetworks,
                    )
                  else
                    for (final n in s.wifiNetworks)
                      OasisRow(
                        leading: Icon(
                          wifiSignalIcon(n.signal),
                          size: 20,
                          color: n.connected ? p.accent : null,
                        ),
                        title: n.ssid,
                        trailing: _networkTrailing(n, p),
                        onTap: n.connected
                            ? null
                            : () =>
                                unawaited(s.connectWifiNetwork(n.ssid)),
                      ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

Widget _networkTrailing(OasisWifiNetwork n, OasisPalette p) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (n.secured) ...[
      Icon(Icons.lock_outline, size: 14, color: p.textSecondary),
      const SizedBox(width: 6),
    ],
    if (n.connected) Icon(Icons.check, size: 16, color: p.accent),
  ],
);
