import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'settings_row.dart';

class DashPane extends StatelessWidget {
  const DashPane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dash = state.dash;

    return AnimatedBuilder(
      animation: dash,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsDash, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                SettingsDropdownRow(
                  title: l10n.dashMode,
                  value: dash.mode.name,
                  items: [for (final m in OasisDashMode.values) m.name],
                  labels: {
                    OasisDashMode.push.name: l10n.dashModePush,
                    OasisDashMode.autoHide.name: l10n.dashModeAutoHide,
                    OasisDashMode.off.name: l10n.dashModeOff,
                  },
                  onChanged: (v) => dash.mode = OasisDashMode.values.byName(v),
                ),
                SettingsDropdownRow(
                  title: l10n.dashPosition,
                  value: dash.position.name,
                  items: [for (final p in OasisDashPosition.values) p.name],
                  labels: {
                    OasisDashPosition.left.name: l10n.dashPositionLeft,
                    OasisDashPosition.bottom.name: l10n.dashPositionBottom,
                    OasisDashPosition.right.name: l10n.dashPositionRight,
                  },
                  onChanged: (v) =>
                      dash.position = OasisDashPosition.values.byName(v),
                ),
                SettingsDropdownRow(
                  title: l10n.dashIconSize,
                  value: dash.size.name,
                  items: [for (final s in OasisDashSize.values) s.name],
                  labels: {
                    OasisDashSize.small.name: l10n.dashSizeSmall,
                    OasisDashSize.medium.name: l10n.dashSizeMedium,
                    OasisDashSize.large.name: l10n.dashSizeLarge,
                    OasisDashSize.custom.name: l10n.dashSizeCustom,
                  },
                  onChanged: (v) => dash.size = OasisDashSize.values.byName(v),
                ),
                if (dash.size == OasisDashSize.custom)
                  OasisRow(
                    title: l10n.dashCustomSize,
                    trailing: SizedBox(
                      width: 180,
                      child: OasisSlider(
                        value: dash.customSize,
                        min: kDashCustomSizeMin,
                        max: kDashCustomSizeMax,
                        onChanged: (v) => dash.customSize = v,
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
