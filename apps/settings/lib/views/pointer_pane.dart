import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'settings_row.dart';

class MousePane extends StatelessWidget {
  const MousePane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final mouse = state.mouse;

    return AnimatedBuilder(
      animation: mouse,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsMouse, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                _SpeedSliderRow(
                  title: l10n.pointerSpeed,
                  value: mouse.pointerSpeed,
                  onChanged: (v) => mouse.pointerSpeed = v,
                ),
                _SpeedSliderRow(
                  title: l10n.pointerDoubleClickSpeed,
                  value: mouse.doubleClickSpeed,
                  onChanged: (v) => mouse.doubleClickSpeed = v,
                ),
                SettingsDropdownRow(
                  title: l10n.pointerPrimaryButton,
                  value: mouse.primaryButton.name,
                  items: [
                    for (final b in OasisPrimaryButton.values) b.name,
                  ],
                  labels: {
                    OasisPrimaryButton.left.name: l10n.pointerButtonLeft,
                    OasisPrimaryButton.right.name: l10n.pointerButtonRight,
                  },
                  onChanged: (v) =>
                      mouse.primaryButton = OasisPrimaryButton.values.byName(v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.pointerScrolling,
              children: [
                _SpeedSliderRow(
                  title: l10n.pointerScrollSpeed,
                  value: mouse.scrollSpeed,
                  onChanged: (v) => mouse.scrollSpeed = v,
                ),
                OasisRow(
                  title: l10n.pointerNaturalScrolling,
                  trailing: OasisToggle(
                    value: mouse.naturalScrolling,
                    onChanged: (v) => mouse.naturalScrolling = v,
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

class TrackpadPane extends StatelessWidget {
  const TrackpadPane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final trackpad = state.trackpad;

    return AnimatedBuilder(
      animation: trackpad,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsTrackpad, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                _SpeedSliderRow(
                  title: l10n.pointerSpeed,
                  value: trackpad.pointerSpeed,
                  onChanged: (v) => trackpad.pointerSpeed = v,
                ),
                OasisRow(
                  title: l10n.trackpadTapToClick,
                  trailing: OasisToggle(
                    value: trackpad.tapToClick,
                    onChanged: (v) => trackpad.tapToClick = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.pointerScrolling,
              children: [
                _SpeedSliderRow(
                  title: l10n.pointerScrollSpeed,
                  value: trackpad.scrollSpeed,
                  onChanged: (v) => trackpad.scrollSpeed = v,
                ),
                OasisRow(
                  title: l10n.pointerNaturalScrolling,
                  trailing: OasisToggle(
                    value: trackpad.naturalScrolling,
                    onChanged: (v) => trackpad.naturalScrolling = v,
                  ),
                ),
                OasisRow(
                  title: l10n.trackpadTwoFingerScroll,
                  trailing: OasisToggle(
                    value: trackpad.twoFingerScrolling,
                    onChanged: (v) => trackpad.twoFingerScrolling = v,
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

class _SpeedSliderRow extends StatelessWidget {
  const _SpeedSliderRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return OasisRow(
      title: title,
      trailing: SizedBox(
        width: 180,
        child: OasisSlider(value: value, onChanged: onChanged),
      ),
    );
  }
}
