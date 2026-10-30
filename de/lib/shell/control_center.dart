import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class ShellControlCenter extends StatelessWidget {
  const ShellControlCenter({super.key, required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _CcToggle(
                          icon: Icons.wifi,
                          label: l10n.ccWifi,
                          subtitle: c.wifiOn ? l10n.ccOn : l10n.ccOff,
                          value: c.wifiOn,
                          onChanged: (v) => c.wifiOnValue = v,
                        ),
                        const SizedBox(width: 10),
                        _CcToggle(
                          icon: Icons.bluetooth,
                          label: l10n.ccBluetooth,
                          subtitle: c.bluetoothOn ? l10n.ccOn : l10n.ccOff,
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
                    Row(
                      children: [
                        _CcToggle(
                          icon: Icons.nightlight,
                          label: l10n.ccNightLight,
                          value: c.nightLightOn,
                          onChanged: (v) => c.nightLightOnValue = v,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _CcCard(
                      child: Row(
                        children: [
                          for (
                            var i = 0;
                            i < ShellController.workspaceCount;
                            i++
                          )
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: i < ShellController.workspaceCount - 1
                                      ? 6
                                      : 0,
                                ),
                                child: OasisButton(
                                  key: ValueKey('ws$i'),
                                  variant: i == c.activeWorkspace
                                      ? OasisButtonVariant.primary
                                      : OasisButtonVariant.secondary,
                                  onPressed: () => c.setWorkspace(i),
                                  label: '${i + 1}',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CcCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ccBrightness,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          OasisSlider(
                            value: c.brightness,
                            onChanged: (v) => c.brightnessPreview = v,
                            onChangeEnd: (v) => c.brightnessValue = v,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    _CcCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ccVolume,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          OasisSlider(
                            value: c.volume,
                            onChanged: (v) => c.volumePreview = v,
                            onChangeEnd: (v) => c.volumeValue = v,
                          ),
                        ],
                      ),
                    ),

                    if (c.batteryLevel != null) ...[
                      const SizedBox(height: 10),
                      _CcCard(
                        child: Row(
                          children: [
                            Icon(
                              c.batteryCharging
                                  ? Icons.battery_charging_full
                                  : Icons.battery_full,
                              size: 18,
                              color: OasisStyle.of(
                                context,
                              ).palette.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.ccBattery,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              '${(c.batteryLevel! * 100).round()}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    _CcCard(
                      child: Row(
                        children: [
                          Icon(
                            Icons.music_note,
                            size: 18,
                            color: OasisStyle.of(context).palette.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.ccMedia,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  _mediaLabel(l10n, c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: OasisStyle.of(
                                          context,
                                        ).palette.textTertiary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (c.mpris != null && c.mpris!.hasPlayer) ...[
                            _MediaButton(
                              icon: Icons.skip_previous,
                              onTap: c.mpris!.previous,
                            ),
                            _MediaButton(
                              icon: c.mpris!.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              onTap: c.mpris!.playPause,
                            ),
                            _MediaButton(
                              icon: Icons.skip_next,
                              onTap: c.mpris!.next,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _CcToggle extends StatelessWidget {
  const _CcToggle({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Semantics(
          button: true,
          toggled: value,
          label: label,
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
                  child: Icon(
                    icon,
                    size: 16,
                    color: value ? const Color(0xFFFFFFFF) : p.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 10, color: p.textTertiary),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
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

String _mediaLabel(OasisLocalizations l10n, ShellController c) {
  final m = c.mpris;
  if (m == null || !m.hasPlayer) return l10n.ccNothingPlaying;
  final track = [m.artist, m.title]
      .where((s) => s.isNotEmpty)
      .join(' - ');
  return track.isEmpty ? l10n.ccNothingPlaying : track;
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: p.textSecondary),
      ),
    );
  }
}
