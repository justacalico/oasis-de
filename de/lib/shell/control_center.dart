import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class ShellControlCenter extends StatelessWidget {
  const ShellControlCenter({super.key, required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final c = controller;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: kCcTopOffset, right: 10),
        child: SizedBox(
          width: 330,
          child: OasisGlass(
            borderRadius: 18,
            blur: 40,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _CcToggle(
                      icon: Icons.wifi,
                      label: l10n.ccWifi,
                      value: c.wifiOn,
                      onChanged: (v) => c.wifiOnValue = v,
                    ),
                    const SizedBox(width: 10),
                    _CcToggle(
                      icon: Icons.bluetooth,
                      label: l10n.ccBluetooth,
                      value: c.bluetoothOn,
                      onChanged: (v) => c.bluetoothOnValue = v,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _CcToggle(
                      icon: Icons.do_not_disturb_on,
                      label: l10n.ccFocus,
                      value: c.focusOn,
                      onChanged: (v) => c.focusOnValue = v,
                    ),
                    const SizedBox(width: 10),
                    _CcToggle(
                      icon: Icons.dark_mode,
                      label: l10n.ccDarkMode,
                      value: OasisStyle.of(context).palette.isDark,
                      onChanged: (v) {
                        final host = OasisHost.maybeOf(context);
                        host?.appearance.themeMode = v
                            ? OasisThemeMode.dark
                            : OasisThemeMode.light;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _CcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.ccBrightness,
                          style: Theme.of(context).textTheme.bodySmall),
                      OasisSlider(
                        value: c.brightness,
                        onChanged: (v) => c.brightnessValue = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _CcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.ccVolume,
                          style: Theme.of(context).textTheme.bodySmall),
                      OasisSlider(
                        value: c.volume,
                        onChanged: (v) => c.volumeValue = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.circle,
                      size: 6, color: p.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const kCcTopOffset = 34.0;

class _CcToggle extends StatelessWidget {
  const _CcToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: _CcCard(
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value
                      ? p.accent
                      : p.textTertiary.withValues(alpha: 0.3),
                ),
                child: Icon(icon,
                    size: 16,
                    color: value
                        ? const Color(0xFFFFFFFF)
                        : p.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CcCard extends StatelessWidget {
  const _CcCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.cardBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
