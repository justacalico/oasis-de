import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'services/release_client.dart';
import 'views/landing_page.dart';

class LandingApp extends StatefulWidget {
  const LandingApp({
    super.key,
    this.client,
    this.appUrl = 'app/',
    this.repoUrl = 'https://gitlab.com/HttpAnimations/oasis-de',
    this.onOpenUrl,
    this.appearance,
    this.onThemeChanged,
    this.locale,
    this.onLocaleChanged,
    this.showcaseImages = const [],
  });

  final ReleaseClient? client;
  final String appUrl;
  final String repoUrl;
  final ValueChanged<String>? onOpenUrl;
  final OasisAppearance? appearance;
  final ValueChanged<OasisThemeMode>? onThemeChanged;
  final Locale? locale;
  final ValueChanged<Locale?>? onLocaleChanged;
  final List<ImageProvider> showcaseImages;

  @override
  State<LandingApp> createState() => _LandingAppState();
}

class _LandingAppState extends State<LandingApp> {
  late final OasisAppearance _appearance;
  late final ReleaseClient _client;
  late Locale? _locale = widget.locale;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    _appearance.addListener(_onAppearanceChanged);
    _client = widget.client ?? ReleaseClient();
  }

  void _setLocale(Locale? locale) {
    setState(() => _locale = locale);
    widget.onLocaleChanged?.call(locale);
  }

  void _onAppearanceChanged() =>
      widget.onThemeChanged?.call(_appearance.themeMode);

  @override
  void dispose() {
    _appearance.removeListener(_onAppearanceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platformDark =
        View.of(context).platformDispatcher.platformBrightness ==
            Brightness.dark;
    return AnimatedBuilder(
      animation: _appearance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) =>
              OasisLocalizations.of(context).appName,
          theme: _appearance.themeForBrightness(platformDark),
          locale: _locale,
          supportedLocales: OasisLocalizations.supportedLocales,
          localizationsDelegates: const [
            OasisLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OasisHost(
            appearance: _appearance,
            setLocale: _setLocale,
            locale: _locale,
            openUrl: widget.onOpenUrl,
            child: LandingPage(
              client: _client,
              appUrl: widget.appUrl,
              repoUrl: widget.repoUrl,
              onOpenUrl: widget.onOpenUrl,
              showcaseImages: widget.showcaseImages,
            ),
          ),
        );
      },
    );
  }
}
