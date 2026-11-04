import 'dart:io';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../state/settings_state.dart';
import 'settings_row.dart';

const kAccentChoices = <Color>[
  Color(0xFF007AFF),
  Color(0xFFBF5AF2),
  Color(0xFFFF375F),
  Color(0xFFFF9F0A),
  Color(0xFFFFD60A),
  Color(0xFF32D74B),
  Color(0xFF64D2FF),
  Color(0xFF8E8E93),
];

class AppearancePane extends StatelessWidget {
  const AppearancePane({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final host = OasisHost.of(context);
    final appearance = host.appearance;
    final text = Theme.of(context).textTheme;

    final modes = [
      (OasisThemeMode.light, l10n.themeLight),
      (OasisThemeMode.dark, l10n.themeDark),
      (OasisThemeMode.oled, l10n.themeOled),
    ];

    return AnimatedBuilder(
      animation: appearance,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsAppearance, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.settingsTheme,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      for (final m in modes) ...[
                        _ThemeCard(
                          mode: m.$1,
                          label: m.$2,
                          selected: appearance.themeMode == m.$1,
                          onTap: () => appearance.themeMode = m.$1,
                        ),
                        if (m != modes.last) const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.settingsAccent,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in kAccentChoices)
                        _AccentSwatch(
                          key: ValueKey(c),
                          color: c,
                          selected: (appearance.accent ??
                                  kAccentChoices.first) ==
                              c,
                          onTap: () => appearance.accent = c,
                        ),
                    ],
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

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final OasisThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisPalette.of(mode);
    final host = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? host.accent : host.divider,
                  width: selected ? 2.5 : 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: [
                    Container(height: 12, color: p.sidebarBackground),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Container(color: p.sidebarBackground),
                          ),
                          Expanded(
                            flex: 5,
                            child: Container(color: p.windowBackground),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected ? color : p.divider,
                width: selected ? 3 : 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GeneralPane extends StatelessWidget {
  const GeneralPane({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final host = OasisHost.of(context);
    final text = Theme.of(context).textTheme;

    final languages = <(Locale?, String)>[
      (null, l10n.languageSystem),
      (const Locale('en'), l10n.languageEn),
      (const Locale('en', 'GB'), l10n.languageEnGb),
      (const Locale('zh'), l10n.languageZh),
      (const Locale('ru'), l10n.languageRu),
      (const Locale('ga'), l10n.languageGa),
    ];

    bool selected(Locale? l) {
      final current = host.locale;
      if (l == null) return current == null;
      return current?.languageCode == l.languageCode &&
          current?.countryCode == l.countryCode;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsGeneral, style: text.titleLarge),
        const SizedBox(height: 16),
        OasisSection(
          title: l10n.settingsLanguage,
          children: [
            for (final entry in languages)
              OasisRow(
                title: entry.$2,
                trailing: selected(entry.$1)
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: OasisStyle.of(context).palette.accent,
                      )
                    : const SizedBox.shrink(),
                onTap: () => host.setLocale(entry.$1),
              ),
          ],
        ),
      ],
    );
  }
}

class NetworkPane extends StatelessWidget {
  const NetworkPane({
    super.key,
    required this.title,
    required this.icon,
    required this.enabled,
    required this.onChanged,
    required this.subtitle,
  });

  final String title;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleLarge),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            OasisRow(
              leading: Icon(icon, size: 20, color: p.accent),
              title: title,
              subtitle: subtitle,
              trailing: OasisToggle(value: enabled, onChanged: onChanged),
            ),
          ],
        ),
      ],
    );
  }
}

class AboutPane extends StatefulWidget {
  const AboutPane({super.key, required this.version, this.backend});

  final String version;
  final OasisSystemBackend? backend;

  @override
  State<AboutPane> createState() => _AboutPaneState();
}

class _AboutPaneState extends State<AboutPane> {
  late final Future<OasisSystemInfo> _info;

  @override
  void initState() {
    super.initState();
    _info = widget.backend?.systemInfo() ??
        Future<OasisSystemInfo>.value(const OasisSystemInfo());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final host = OasisHost.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsAbout, style: text.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            const OasisAppIcon(
              icon: Icons.water_drop,
              colors: [Color(0xFF4FC3F7), Color(0xFF0078C8)],
              size: 64,
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appName, style: text.titleLarge),
                Text(l10n.versionLabel(widget.version), style: text.bodySmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.aboutTagline,
          style: text.bodyMedium?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            if (host.updates != null)
              UpdateCheckTile(service: host.updates!, onOpenUrl: host.openUrl),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<OasisSystemInfo>(
          future: _info,
          builder: (context, snap) {
            final i = snap.data;
            if (i == null) return const SizedBox.shrink();
            return OasisSection(
              children: [
                for (final row in [
                  (l10n.aboutDeviceName, i.deviceName),
                  (l10n.aboutOs, i.osName),
                  (l10n.aboutKernel, i.kernel),
                  (l10n.aboutCpu, i.cpu),
                  (l10n.aboutMemory, i.memory),
                  (l10n.aboutDisk, i.disk),
                  (l10n.aboutGpu, i.gpu),
                ])
                  if (row.$2.isNotEmpty)
                    OasisRow(title: row.$1, subtitle: row.$2),
              ],
            );
          },
        ),
      ],
    );
  }
}

const _displayOffChoices = <int>[0, 1, 2, 5, 10, 15, 30, 60];
const _sleepChoices = <int>[0, 5, 10, 15, 20, 30, 60, 120];

String _timeoutLabel(OasisLocalizations l10n, int minutes) {
  if (minutes == 0) return l10n.powerNever;
  if (minutes < 60) return l10n.powerMinutes(minutes);
  return l10n.powerHours(minutes ~/ 60);
}

void _confirmSession(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  final l10n = OasisLocalizations.of(context);
  showOasisDialog(
    context,
    (ctx, close) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OasisButton(
              label: l10n.dialogCancel,
              variant: OasisButtonVariant.text,
              dense: true,
              onPressed: close,
            ),
            const SizedBox(width: 8),
            OasisButton(
              label: confirmLabel,
              variant: OasisButtonVariant.primary,
              dense: true,
              onPressed: () {
                close();
                onConfirm();
              },
            ),
          ],
        ),
      ],
    ),
  );
}

class PowerPane extends StatelessWidget {
  const PowerPane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final b = state.backend;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsPower, style: text.titleLarge),
            const SizedBox(height: 16),
            OasisSection(
              children: [
                FutureBuilder<OasisBattery>(
                  future: state.battery(),
                  builder: (context, snap) {
                    final bat = snap.data;
                    return OasisRow(
                      leading: const Icon(Icons.battery_std, size: 20),
                      title: l10n.settingsBattery,
                      subtitle: bat?.level == null
                          ? null
                          : '${(bat!.level! * 100).round()}%',
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            OasisSection(
              title: l10n.sessionSleep,
              children: [
                SettingsDropdownRow(
                  title: l10n.powerDisplayOffAfter,
                  value: '${state.displayOffDelay.inMinutes}',
                  items: [
                    for (final m in _displayOffChoices) '$m',
                  ],
                  labels: {
                    for (final m in _displayOffChoices)
                      '$m': _timeoutLabel(l10n, m),
                  },
                  onChanged: (v) => state.displayOffTimeout =
                      Duration(minutes: int.parse(v)),
                ),
                SettingsDropdownRow(
                  title: l10n.powerSleepAfter,
                  value: '${state.sleepDelay.inMinutes}',
                  items: [for (final m in _sleepChoices) '$m'],
                  labels: {
                    for (final m in _sleepChoices)
                      '$m': _timeoutLabel(l10n, m),
                  },
                  onChanged: (v) => state.sleepTimeout =
                      Duration(minutes: int.parse(v)),
                ),
              ],
            ),
            if (b != null) ...[
              const SizedBox(height: 16),
              OasisSection(
                children: [
                  for (final a in [
                    (
                      l10n.settingsSuspend,
                      OasisSessionAction.suspend,
                      l10n.sessionConfirmSuspend,
                      l10n.sessionSleep,
                    ),
                    (
                      l10n.settingsReboot,
                      OasisSessionAction.reboot,
                      l10n.sessionConfirmRestart,
                      l10n.sessionRestart,
                    ),
                    (
                      l10n.settingsPowerOff,
                      OasisSessionAction.poweroff,
                      l10n.sessionConfirmPoweroff,
                      l10n.sessionShutDown,
                    ),
                  ])
                    OasisRow(
                      leading:
                          const Icon(Icons.power_settings_new, size: 20),
                      title: a.$1,
                      onTap: () => _confirmSession(
                        context,
                        message: a.$3,
                        confirmLabel: a.$4,
                        onConfirm: () => b.session(a.$2),
                      ),
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

class DateTimePane extends StatelessWidget {
  const DateTimePane({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsDateTime, style: text.titleLarge),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            OasisRow(
              leading: const Icon(Icons.calendar_today, size: 20),
              title: l10n.settingsDate,
              subtitle: '${now.year}-${two(now.month)}-${two(now.day)}',
            ),
            OasisRow(
              leading: const Icon(Icons.schedule, size: 20),
              title: l10n.settingsTime,
              subtitle:
                  '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
            ),
            OasisRow(
              leading: const Icon(Icons.public, size: 20),
              title: l10n.settingsTimezone,
              subtitle: now.timeZoneName,
            ),
          ],
        ),
      ],
    );
  }
}

class UsersPane extends StatelessWidget {
  const UsersPane({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final b = state.backend;
    final user = Platform.environment['USER'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsUsers, style: text.titleLarge),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            OasisRow(
              leading: const Icon(Icons.person, size: 20),
              title: l10n.settingsCurrentUser,
              subtitle: user.isEmpty ? null : user,
            ),
            if (b != null)
              OasisRow(
                leading: const Icon(Icons.logout, size: 20),
                title: l10n.settingsLogout,
                onTap: () => _confirmSession(
                  context,
                  message: l10n.sessionConfirmLogOut,
                  confirmLabel: l10n.sessionLogOut,
                  onConfirm: () => b.session(OasisSessionAction.logout),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
