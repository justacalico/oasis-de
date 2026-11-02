import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'settings_row.dart';

class DockPane extends StatelessWidget {
  const DockPane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dock = state.dock;

    return AnimatedBuilder(
      animation: dock,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsDock, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                SettingsDropdownRow(
                  title: l10n.dockMode,
                  value: dock.mode.name,
                  items: [for (final m in OasisDockMode.values) m.name],
                  labels: {
                    OasisDockMode.push.name: l10n.dockModePush,
                    OasisDockMode.autoHide.name: l10n.dockModeAutoHide,
                    OasisDockMode.off.name: l10n.dockModeOff,
                  },
                  onChanged: (v) => dock.mode = OasisDockMode.values.byName(v),
                ),
                SettingsDropdownRow(
                  title: l10n.dockPosition,
                  value: dock.position.name,
                  items: [for (final p in OasisDockPosition.values) p.name],
                  labels: {
                    OasisDockPosition.left.name: l10n.dockPositionLeft,
                    OasisDockPosition.bottom.name: l10n.dockPositionBottom,
                    OasisDockPosition.right.name: l10n.dockPositionRight,
                  },
                  onChanged: (v) =>
                      dock.position = OasisDockPosition.values.byName(v),
                ),
                SettingsDropdownRow(
                  title: l10n.dockIconSize,
                  value: dock.size.name,
                  items: [for (final s in OasisDockSize.values) s.name],
                  labels: {
                    OasisDockSize.small.name: l10n.dockSizeSmall,
                    OasisDockSize.medium.name: l10n.dockSizeMedium,
                    OasisDockSize.large.name: l10n.dockSizeLarge,
                    OasisDockSize.custom.name: l10n.dockSizeCustom,
                  },
                  onChanged: (v) => dock.size = OasisDockSize.values.byName(v),
                ),
                if (dock.size == OasisDockSize.custom)
                  OasisRow(
                    title: l10n.dockCustomSize,
                    trailing: SizedBox(
                      width: 180,
                      child: OasisSlider(
                        value: dock.customSize,
                        min: kDockCustomSizeMin,
                        max: kDockCustomSizeMax,
                        onChanged: (v) => dock.customSize = v,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
