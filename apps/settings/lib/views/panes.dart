import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

const kAccentChoices = <Color?>[
  null,
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
    final p = OasisStyle.of(context).palette;
    final host = OasisHost.of(context);
    final appearance = host.appearance;
    final text = Theme.of(context).textTheme;

    final modes = [
      (OasisThemeMode.system, l10n.themeSystem),
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
                          color: c ?? const Color(0xFF007AFF),
                          label: c == null ? 'A' : null,
                          selected: appearance.accent == c,
                          onTap: () => appearance.accent = c,
                          ring: c == null ? p.accent : null,
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
    final p = OasisPalette.of(mode, platformDark: false);
    final host = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
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
                  Container(
                    height: 12,
                    color: p.sidebarBackground,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                            flex: 2,
                            child: Container(color: p.sidebarBackground)),
                        Expanded(
                            flex: 5,
                            child: Container(color: p.windowBackground)),
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
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.ring,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? ring ?? color : p.divider,
            width: selected ? 3 : 0.5,
          ),
        ),
        child: label == null
            ? null
            : Center(
                child: Text(
                  label!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFFFF)),
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
      (const Locale('en', 'GB'), l10n.languageEnGb),
      (const Locale('zh'), l10n.languageZh),
      (const Locale('ru'), l10n.languageRu),
      (const Locale('ga'), l10n.languageGa),
    ];

    bool selected(Locale? l) {
      final current = host.locale;
      if (l == null) return current == null;
      return current?.languageCode == l.languageCode &&
          (l.countryCode == null || current?.countryCode == l.countryCode);
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
                    ? Icon(Icons.check,
                        size: 16,
                        color: OasisStyle.of(context).palette.accent)
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
  });

  final String title;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
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
              subtitle: l10n.settingsNetworkBody,
              trailing: OasisToggle(value: enabled, onChanged: onChanged),
            ),
          ],
        ),
      ],
    );
  }
}

class AboutPane extends StatelessWidget {
  const AboutPane({super.key, required this.version});

  final String version;

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
                Text(l10n.versionLabel(version), style: text.bodySmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.aboutTagline,
            style: text.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 16),
        OasisSection(
          children: [
            UpdateCheckTile(
                service: host.updates, onOpenUrl: host.openUrl),
          ],
        ),
      ],
    );
  }
}
