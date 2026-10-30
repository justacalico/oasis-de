import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../services/release_client.dart';
import '../widgets/desktop_preview.dart';
import '../widgets/downloads_section.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({
    super.key,
    required this.client,
    required this.appUrl,
    required this.repoUrl,
    this.onOpenUrl,
    this.showcaseImages = const [],
  });

  final ReleaseClient client;
  final String appUrl;
  final String repoUrl;
  final ValueChanged<String>? onOpenUrl;
  final List<ImageProvider> showcaseImages;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width > 820;

    return Scaffold(
      backgroundColor: p.groupedBackground,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  _NavBar(repoUrl: repoUrl, onOpenUrl: onOpenUrl),
                  const SizedBox(height: 56),
                  Center(
                    child: Column(
                      children: [
                        const OasisAppIcon(
                          icon: Icons.water_drop,
                          colors: [Color(0xFF4FC3F7), Color(0xFF0078C8)],
                          size: 88,
                        ),
                        const SizedBox(height: 22),
                        Text(l10n.landingTagline,
                            style: text.displayLarge,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 520),
                          child: Text(
                            l10n.landingHeroBody,
                            style: text.bodyMedium?.copyWith(
                                color: p.textSecondary, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            OasisButton(
                              label: l10n.landingOpenApp,
                              variant: OasisButtonVariant.primary,
                              onPressed: onOpenUrl == null
                                  ? null
                                  : () => onOpenUrl!(appUrl),
                            ),
                            OasisButton(
                              label: l10n.landingGetStarted,
                              onPressed: onOpenUrl == null
                                  ? null
                                  : () =>
                                      onOpenUrl!(client.releasesUrl),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 64),
                  Text(l10n.landingShowcaseTitle,
                      style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(l10n.landingShowcaseBody,
                      style: text.bodyMedium
                          ?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: 22),
                  const DesktopPreview(),
                  const SizedBox(height: 22),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _featureCards(l10n, context)
                          .map((c) => Expanded(
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  child: c)))
                          .toList(),
                    )
                  else
                    Column(
                      children: _featureCards(l10n, context)
                          .map((c) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: c))
                          .toList(),
                    ),
                  if (showcaseImages.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final img in showcaseImages)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  child: Image(image: img),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          for (final img in showcaseImages)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(12),
                                child: Image(image: img),
                              ),
                            ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 56),
                  _WebCta(appUrl: appUrl, onOpenUrl: onOpenUrl),
                  const SizedBox(height: 56),
                  DownloadsSection(
                      client: client, onOpenUrl: onOpenUrl),
                  const SizedBox(height: 56),
                  Center(
                    child: Text(l10n.landingFooter,
                        style: text.bodySmall),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _featureCards(
      OasisLocalizations l10n, BuildContext context) {
    final items = [
      (l10n.landingFeatureGlassTitle, l10n.landingFeatureGlassBody,
          Icons.blur_on),
      (l10n.landingFeatureCalmTitle, l10n.landingFeatureCalmBody,
          Icons.spa),
      (l10n.landingFeatureOpenTitle, l10n.landingFeatureOpenBody,
          Icons.code),
    ];
    return [
      for (final item in items)
        _FeatureCard(icon: item.$3, title: item.$1, body: item.$2),
    ];
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.repoUrl, this.onOpenUrl});

  final String repoUrl;
  final ValueChanged<String>? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final appearance = OasisHost.maybeOf(context)?.appearance;

    return Row(
      children: [
        const OasisAppIcon(
          icon: Icons.water_drop,
          colors: [Color(0xFF4FC3F7), Color(0xFF0078C8)],
          size: 30,
        ),
        const SizedBox(width: 10),
        Text(l10n.appName,
            style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (appearance != null) _ThemeMenu(appearance: appearance),
        const SizedBox(width: 4),
        const _LocaleMenu(),
        const SizedBox(width: 8),
        OasisButton(
          label: l10n.landingSource,
          variant: OasisButtonVariant.text,
          dense: true,
          onPressed:
              onOpenUrl == null ? null : () => onOpenUrl!(repoUrl),
        ),
      ],
    );
  }
}

class _LocaleMenu extends StatelessWidget {
  const _LocaleMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final host = OasisHost.maybeOf(context);
    if (host == null) return const SizedBox.shrink();
    final entries = <(Locale?, String)>[
      (null, l10n.languageSystem),
      (const Locale('en'), l10n.languageEn),
      (const Locale('zh'), l10n.languageZh),
      (const Locale('ru'), l10n.languageRu),
      (const Locale('ga'), l10n.languageGa),
    ];
    return PopupMenuButton<Locale?>(
      tooltip: l10n.settingsLanguage,
      icon: Icon(Icons.language, size: 18, color: p.textSecondary),
      onSelected: host.setLocale,
      itemBuilder: (context) => [
        for (final e in entries)
          PopupMenuItem<Locale?>(
            value: e.$1,
            child: Row(
              children: [
                Icon(
                  host.locale == e.$1 ? Icons.check : Icons.language,
                  size: 16,
                  color: p.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(e.$2),
              ],
            ),
          ),
      ],
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.appearance});

  final OasisAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final entries = [
      (OasisThemeMode.system, l10n.themeSystem,
          Icons.brightness_auto),
      (OasisThemeMode.light, l10n.themeLight, Icons.light_mode),
      (OasisThemeMode.dark, l10n.themeDark, Icons.dark_mode),
      (OasisThemeMode.oled, l10n.themeOled, Icons.contrast),
    ];
    return AnimatedBuilder(
      animation: appearance,
      builder: (context, _) {
        return PopupMenuButton<OasisThemeMode>(
          tooltip: l10n.settingsTheme,
          icon: Icon(Icons.contrast, size: 18, color: p.textSecondary),
          onSelected: (m) => appearance.themeMode = m,
          itemBuilder: (context) => [
            for (final e in entries)
              PopupMenuItem<OasisThemeMode>(
                value: e.$1,
                child: Row(
                  children: [
                    Icon(
                        appearance.themeMode == e.$1
                            ? Icons.check
                            : e.$3,
                        size: 16,
                        color: p.textSecondary),
                    const SizedBox(width: 10),
                    Text(e.$2),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: p.accent),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

class _WebCta extends StatelessWidget {
  const _WebCta({required this.appUrl, this.onOpenUrl});

  final String appUrl;
  final ValueChanged<String>? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    return OasisGlass(
      borderRadius: 18,
      blur: 24,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.landingTryWeb,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(l10n.landingWebBody,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          OasisButton(
            label: l10n.landingOpenApp,
            variant: OasisButtonVariant.primary,
            onPressed:
                onOpenUrl == null ? null : () => onOpenUrl!(appUrl),
          ),
        ],
      ),
    );
  }
}
