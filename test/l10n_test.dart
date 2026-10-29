import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

void exerciseStrings(OasisLocalizations l) {
  l.appName;
  l.menuFile;
  l.dockPin;
  l.dockUnpin;
  l.menuView;
  l.menuWindow;
  l.menuHelp;
  l.menuAboutApp('X');
  l.menuSettings;
  l.menuCloseWindow;
  l.menuMinimise;
  l.menuZoom;
  l.menuNewWindow;
  l.menuEnterFullScreen;
  l.menuAbout;
  l.launchPad;
  l.launcherHint;
  l.launcherNoResults;
  l.ccWifi;
  l.ccBluetooth;
  l.ccFocus;
  l.ccBrightness;
  l.ccVolume;
  l.ccAppearance;
  l.ccDarkMode;
  l.ccOn;
  l.ccOff;
  l.ccNightLight;
  l.ccBattery;
  l.ccMedia;
  l.ccNothingPlaying;
  l.aboutTagline;
  l.versionLabel('9.9.9');
  l.updateCheck;
  l.updateChecking;
  l.updateUpToDate;
  l.updateAvailable('9.9.9');
  l.updateFailed;
  l.updateViewRelease;
  l.updateAllReleases;
  l.settingsTitle;
  l.settingsAppearance;
  l.settingsGeneral;
  l.settingsWifi;
  l.settingsBluetooth;
  l.settingsAbout;
  l.settingsTheme;
  l.settingsAccent;
  l.settingsLanguage;
  l.settingsEnabled;
  l.settingsNetworkBody;
  l.themeSystem;
  l.themeLight;
  l.themeDark;
  l.themeOled;
  l.settingsWallpaper;
  l.wallpaperDunes;
  l.wallpaperPeaks;
  l.wallpaperAurora;
  l.wallpaperEmber;
  l.wallpaperCustom;
  l.wallpaperPathHint;
  l.wallpaperApply;
  l.wallpaperFit;
  l.wallpaperFitCover;
  l.wallpaperFitContain;
  l.wallpaperFitFill;
  l.languageSystem;
  l.languageEnGb;
  l.languageZh;
  l.languageRu;
  l.languageGa;
  l.landingTagline;
  l.landingHeroBody;
  l.landingOpenApp;
  l.landingGetStarted;
  l.landingShowcaseTitle;
  l.landingShowcaseBody;
  l.landingFeatureGlassTitle;
  l.landingFeatureGlassBody;
  l.landingFeatureCalmTitle;
  l.landingFeatureCalmBody;
  l.landingFeatureOpenTitle;
  l.landingFeatureOpenBody;
  l.landingDownloadsTitle;
  l.landingDownloadsBody;
  l.landingLoadingReleases;
  l.landingNoReleases;
  l.landingReleasesFailed;
  l.landingAllReleases;
  l.landingSource;
  l.landingFooter;
  l.landingTryWeb;
  l.landingWebBody;
  l.appNotes;
  l.appCalculator;
  l.menuQuit;
}

void main() {
  test('every locale resolves and exposes all strings', () {
    for (final locale in [
      const Locale('en'),
      const Locale('en', 'GB'),
      const Locale('zh'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      const Locale('ru'),
      const Locale('ga'),
    ]) {
      exerciseStrings(lookupOasisLocalizations(locale));
    }
  });

  test('unsupported locale throws in direct lookup', () {
    expect(
      () => lookupOasisLocalizations(const Locale('fr')),
      throwsA(isA<FlutterError>()),
    );
  });

  test('delegate supports the declared locales', () {
    for (final l in OasisLocalizations.supportedLocales) {
      expect(OasisLocalizations.delegate.isSupported(l), isTrue);
    }
    expect(
      OasisLocalizations.delegate.isSupported(const Locale('de')),
      isFalse,
    );
  });

  testWidgets('of() resolves inside a widget and falls back', (tester) async {
    late OasisLocalizations l10n;
    await pumpOasis(
      tester,
      Builder(
        builder: (context) {
          l10n = OasisLocalizations.of(context);
          return Text(l10n.appName);
        },
      ),
      locale: const Locale('zh'),
    );
    expect(l10n.menuFile, '文件');
    expect(find.text('Oasis'), findsOneWidget);

    await pumpOasis(
      tester,
      Builder(
        builder: (context) {
          l10n = OasisLocalizations.of(context);
          return const SizedBox();
        },
      ),
      locale: const Locale('pt'),
    );
    expect(l10n.menuFile, isNotEmpty);
  });
}
