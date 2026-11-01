import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

void showWifiMenu(
  BuildContext context,
  Offset position,
  ShellController controller,
) {
  final overlay = Overlay.of(context);
  final box = overlay.context.findRenderObject()! as RenderBox;
  final local = box.globalToLocal(position);
  late final OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
  }

  controller.closeOverlays();
  unawaited(controller.refreshWifiNetworks());
  entry = OverlayEntry(
    builder: (context) {
      final style = OasisStyle.of(context);
      const menuWidth = 250.0;
      const menuHeight = 400.0;
      final maxX = box.size.width - menuWidth - 8;
      final maxY = box.size.height - 8;
      final dx = local.dx.clamp(8.0, maxX > 8 ? maxX : 8.0);
      final dy = local.dy.clamp(8.0, maxY > 8 ? maxY : 8.0);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: close,
              onSecondaryTapUp: (_) => close(),
            ),
          ),
          Positioned(
            left: dx,
            top: dy,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: menuHeight),
              child: OasisGlass(
                borderRadius: style.menuRadius,
                blur: 36,
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 210,
                    maxWidth: 260,
                  ),
                  child: IntrinsicWidth(
                    child: SingleChildScrollView(
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          final items = _wifiMenuItems(
                            context,
                            controller,
                          );
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              for (final item in items) ...[
                                OasisMenuEntry(
                                  item: item,
                                  onSelect: close,
                                ),
                                if (item.separatorAfter)
                                  Divider(
                                    height: 9,
                                    thickness: 0.5,
                                    indent: 12,
                                    endIndent: 12,
                                    color: style.palette.divider,
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

List<OasisMenuItem> _wifiMenuItems(
  BuildContext context,
  ShellController c,
) {
  final l10n = OasisLocalizations.of(context);
  OasisApp? settings;
  for (final a in c.apps) {
    if (a.id == 'settings') settings = a;
  }
  return [
    OasisMenuItem(
      label: l10n.ccWifi,
      checked: c.wifiOn,
      separatorAfter: true,
      action: (_) {
        c.wifiOnValue = !c.wifiOn;
        if (c.wifiOn) unawaited(c.refreshWifiNetworks());
      },
    ),
    if (c.wifiOn) ..._networkItems(l10n, c),
    OasisMenuItem(
      label: l10n.wifiMenuSettings,
      enabled: settings != null,
      action: (_) {
        if (settings != null) c.openApp(settings);
      },
    ),
  ];
}

List<OasisMenuItem> _networkItems(
  OasisLocalizations l10n,
  ShellController c,
) {
  if (c.wifiNetworks.isEmpty) {
    return [
      OasisMenuItem(
        label: c.wifiScanning
            ? l10n.wifiMenuScanning
            : l10n.wifiMenuNoNetworks,
        enabled: false,
        separatorAfter: true,
      ),
    ];
  }
  return [
    for (var i = 0; i < c.wifiNetworks.length; i++)
      OasisMenuItem(
        label: c.wifiNetworks[i].ssid,
        checked: c.wifiNetworks[i].connected,
        separatorAfter: i == c.wifiNetworks.length - 1,
        trailing: _networkTrailing(c.wifiNetworks[i]),
        action: (_) => unawaited(
          c.connectWifiNetwork(c.wifiNetworks[i].ssid),
        ),
      ),
  ];
}

Widget _networkTrailing(OasisWifiNetwork n) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (n.secured) ...[
      const Icon(Icons.lock_outline, size: 12),
      const SizedBox(width: 4),
    ],
    Icon(wifiSignalIcon(n.signal)),
  ],
);
