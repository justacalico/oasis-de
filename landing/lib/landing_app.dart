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
    this.showcaseImages = const [],
  });

  final ReleaseClient? client;
  final String appUrl;
  final String repoUrl;
  final ValueChanged<String>? onOpenUrl;
  final OasisAppearance? appearance;
  final ValueChanged<OasisThemeMode>? onThemeChanged;
  final List<ImageProvider> showcaseImages;

  @override
  State<LandingApp> createState() => _LandingAppState();
}

class _LandingAppState extends State<LandingApp> {
  late final OasisAppearance _appearance;
  late final UpdateService _updates;
  late final ReleaseClient _client;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    if (widget.onThemeChanged != null) {
      _appearance.addListener(
          () => widget.onThemeChanged!(_appearance.themeMode));
    }
    _updates = UpdateService();
    _client = widget.client ?? ReleaseClient();
  }

  @override
  void dispose() {
    _updates.dispose();
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
          supportedLocales: OasisLocalizations.supportedLocales,
          localizationsDelegates: const [
            OasisLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OasisHost(
            appearance: _appearance,
            updates: _updates,
            setLocale: (_) {},
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
