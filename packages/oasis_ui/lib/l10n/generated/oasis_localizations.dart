import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'oasis_localizations_en.dart';
import 'oasis_localizations_ga.dart';
import 'oasis_localizations_ru.dart';
import 'oasis_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of OasisLocalizations
/// returned by `OasisLocalizations.of(context)`.
///
/// Applications need to include `OasisLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/oasis_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: OasisLocalizations.localizationsDelegates,
///   supportedLocales: OasisLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the OasisLocalizations.supportedLocales
/// property.
abstract class OasisLocalizations {
  OasisLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static OasisLocalizations of(BuildContext context) {
    return Localizations.of<OasisLocalizations>(context, OasisLocalizations)!;
  }

  static const LocalizationsDelegate<OasisLocalizations> delegate =
      _OasisLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ga'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Oasis'**
  String get appName;

  /// No description provided for @appUnknown.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get appUnknown;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @menuAboutApp.
  ///
  /// In en, this message translates to:
  /// **'About {app}'**
  String menuAboutApp(String app);

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get menuSettings;

  /// No description provided for @menuCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Close Window'**
  String get menuCloseWindow;

  /// No description provided for @menuMinimise.
  ///
  /// In en, this message translates to:
  /// **'Minimise'**
  String get menuMinimise;

  /// No description provided for @menuZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get menuZoom;

  /// No description provided for @menuNewWindow.
  ///
  /// In en, this message translates to:
  /// **'New Window'**
  String get menuNewWindow;

  /// No description provided for @menuEnterFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Enter Full Screen'**
  String get menuEnterFullScreen;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About Oasis'**
  String get menuAbout;

  /// No description provided for @launchPad.
  ///
  /// In en, this message translates to:
  /// **'Launch Pad'**
  String get launchPad;

  /// No description provided for @launchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open {app}'**
  String launchFailed(String app);

  /// No description provided for @launcherHint.
  ///
  /// In en, this message translates to:
  /// **'Search apps'**
  String get launcherHint;

  /// No description provided for @launcherNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get launcherNoResults;

  /// No description provided for @ccWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get ccWifi;

  /// No description provided for @ccBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get ccBluetooth;

  /// No description provided for @ccFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get ccFocus;

  /// No description provided for @ccBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get ccBrightness;

  /// No description provided for @ccVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get ccVolume;

  /// No description provided for @ccAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get ccAppearance;

  /// No description provided for @ccDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get ccDarkMode;

  /// No description provided for @aboutDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get aboutDeviceName;

  /// No description provided for @aboutOs.
  ///
  /// In en, this message translates to:
  /// **'Operating system'**
  String get aboutOs;

  /// No description provided for @aboutKernel.
  ///
  /// In en, this message translates to:
  /// **'Kernel'**
  String get aboutKernel;

  /// No description provided for @aboutCpu.
  ///
  /// In en, this message translates to:
  /// **'Processor'**
  String get aboutCpu;

  /// No description provided for @aboutMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get aboutMemory;

  /// No description provided for @aboutDisk.
  ///
  /// In en, this message translates to:
  /// **'Disk'**
  String get aboutDisk;

  /// No description provided for @aboutGpu.
  ///
  /// In en, this message translates to:
  /// **'Graphics'**
  String get aboutGpu;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A calm, glassy desktop environment for Linux.'**
  String get aboutTagline;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get updateCheck;

  /// No description provided for @updateCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get updateCheckNow;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Oasis is up to date'**
  String get updateUpToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateAvailable(String version);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates'**
  String get updateFailed;

  /// No description provided for @updateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'View release'**
  String get updateViewRelease;

  /// No description provided for @updateAllReleases.
  ///
  /// In en, this message translates to:
  /// **'All releases'**
  String get updateAllReleases;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get settingsWifi;

  /// No description provided for @settingsBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get settingsBluetooth;

  /// No description provided for @settingsDisplays.
  ///
  /// In en, this message translates to:
  /// **'Displays'**
  String get settingsDisplays;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsPower.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get settingsPower;

  /// No description provided for @settingsDateTime.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get settingsDateTime;

  /// No description provided for @settingsUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get settingsUsers;

  /// No description provided for @settingsBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get settingsBrightness;

  /// No description provided for @settingsNightLight.
  ///
  /// In en, this message translates to:
  /// **'Night light'**
  String get settingsNightLight;

  /// No description provided for @settingsVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get settingsVolume;

  /// No description provided for @settingsBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get settingsBattery;

  /// No description provided for @settingsSuspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get settingsSuspend;

  /// No description provided for @settingsReboot.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get settingsReboot;

  /// No description provided for @settingsPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Power off'**
  String get settingsPowerOff;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogout;

  /// No description provided for @settingsCurrentUser.
  ///
  /// In en, this message translates to:
  /// **'Current user'**
  String get settingsCurrentUser;

  /// No description provided for @settingsDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get settingsDate;

  /// No description provided for @settingsTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get settingsTime;

  /// No description provided for @settingsTimezone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get settingsTimezone;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get settingsAccent;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsWifiBody.
  ///
  /// In en, this message translates to:
  /// **'Toggle Wi-Fi on or off.'**
  String get settingsWifiBody;

  /// No description provided for @settingsBluetoothBody.
  ///
  /// In en, this message translates to:
  /// **'Toggle Bluetooth on or off.'**
  String get settingsBluetoothBody;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeOled.
  ///
  /// In en, this message translates to:
  /// **'OLED'**
  String get themeOled;

  /// No description provided for @settingsWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get settingsWallpaper;

  /// No description provided for @wallpaperDunes.
  ///
  /// In en, this message translates to:
  /// **'Oasis Dunes'**
  String get wallpaperDunes;

  /// No description provided for @wallpaperCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom image'**
  String get wallpaperCustom;

  /// No description provided for @wallpaperPathHint.
  ///
  /// In en, this message translates to:
  /// **'Image path'**
  String get wallpaperPathHint;

  /// No description provided for @wallpaperApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get wallpaperApply;

  /// No description provided for @wallpaperInvalidPath.
  ///
  /// In en, this message translates to:
  /// **'Image not found'**
  String get wallpaperInvalidPath;

  /// No description provided for @wallpaperFit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get wallpaperFit;

  /// No description provided for @wallpaperFitCover.
  ///
  /// In en, this message translates to:
  /// **'Fill screen'**
  String get wallpaperFitCover;

  /// No description provided for @wallpaperFitContain.
  ///
  /// In en, this message translates to:
  /// **'Fit to screen'**
  String get wallpaperFitContain;

  /// No description provided for @wallpaperFitFill.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get wallpaperFitFill;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageEnGb.
  ///
  /// In en, this message translates to:
  /// **'English (UK)'**
  String get languageEnGb;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageRu.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRu;

  /// No description provided for @languageGa.
  ///
  /// In en, this message translates to:
  /// **'Gaeilge'**
  String get languageGa;

  /// No description provided for @landingTagline.
  ///
  /// In en, this message translates to:
  /// **'Your desktop, distilled.'**
  String get landingTagline;

  /// No description provided for @landingHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Oasis is a desktop environment for Linux that pairs a calm, glassy design with a workflow that feels instantly familiar.'**
  String get landingHeroBody;

  /// No description provided for @landingOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Launch web app'**
  String get landingOpenApp;

  /// No description provided for @landingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get landingGetStarted;

  /// No description provided for @landingShowcaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Designed to disappear'**
  String get landingShowcaseTitle;

  /// No description provided for @landingShowcaseBody.
  ///
  /// In en, this message translates to:
  /// **'Glass surfaces, honest typography and controls that behave the way you expect. Nothing gets between you and your work.'**
  String get landingShowcaseBody;

  /// No description provided for @landingFeatureGlassTitle.
  ///
  /// In en, this message translates to:
  /// **'Liquid surfaces'**
  String get landingFeatureGlassTitle;

  /// No description provided for @landingFeatureGlassBody.
  ///
  /// In en, this message translates to:
  /// **'Menus, docks and windows float on real translucency with specular highlights.'**
  String get landingFeatureGlassBody;

  /// No description provided for @landingFeatureCalmTitle.
  ///
  /// In en, this message translates to:
  /// **'Calm by default'**
  String get landingFeatureCalmTitle;

  /// No description provided for @landingFeatureCalmBody.
  ///
  /// In en, this message translates to:
  /// **'A quiet menu bar, a dock that stays out of the way, and notifications that never shout.'**
  String get landingFeatureCalmBody;

  /// No description provided for @landingFeatureOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open underneath'**
  String get landingFeatureOpenTitle;

  /// No description provided for @landingFeatureOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Runs on the Linux stack you already know. Free and open source, no ads, no tracking.'**
  String get landingFeatureOpenBody;

  /// No description provided for @landingDownloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Get Oasis'**
  String get landingDownloadsTitle;

  /// No description provided for @landingDownloadsBody.
  ///
  /// In en, this message translates to:
  /// **'Grab the latest release for your machine, or browse every release on GitLab.'**
  String get landingDownloadsBody;

  /// No description provided for @landingLoadingReleases.
  ///
  /// In en, this message translates to:
  /// **'Loading releases…'**
  String get landingLoadingReleases;

  /// No description provided for @landingNoReleases.
  ///
  /// In en, this message translates to:
  /// **'No releases yet'**
  String get landingNoReleases;

  /// No description provided for @landingReleasesFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load releases'**
  String get landingReleasesFailed;

  /// No description provided for @landingRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get landingRetry;

  /// No description provided for @landingAllReleases.
  ///
  /// In en, this message translates to:
  /// **'All releases on GitLab'**
  String get landingAllReleases;

  /// No description provided for @landingSource.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get landingSource;

  /// No description provided for @landingFooter.
  ///
  /// In en, this message translates to:
  /// **'Free and open source, forever.'**
  String get landingFooter;

  /// No description provided for @landingTryWeb.
  ///
  /// In en, this message translates to:
  /// **'Try it in your browser'**
  String get landingTryWeb;

  /// No description provided for @landingWebBody.
  ///
  /// In en, this message translates to:
  /// **'The whole desktop runs on the web too. No install required.'**
  String get landingWebBody;

  /// No description provided for @appNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get appNotes;

  /// No description provided for @menuQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Oasis'**
  String get menuQuit;

  /// No description provided for @ccOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get ccOn;

  /// No description provided for @ccOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get ccOff;

  /// No description provided for @ccNightLight.
  ///
  /// In en, this message translates to:
  /// **'Night Light'**
  String get ccNightLight;

  /// No description provided for @ccBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get ccBattery;

  /// No description provided for @ccMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get ccMedia;

  /// No description provided for @ccNothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get ccNothingPlaying;

  /// No description provided for @dockPin.
  ///
  /// In en, this message translates to:
  /// **'Pin to Dock'**
  String get dockPin;

  /// No description provided for @dockUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get dockUnpin;

  /// No description provided for @dockQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get dockQuit;

  /// No description provided for @wallpaperPeaks.
  ///
  /// In en, this message translates to:
  /// **'Peaks'**
  String get wallpaperPeaks;

  /// No description provided for @wallpaperAurora.
  ///
  /// In en, this message translates to:
  /// **'Aurora'**
  String get wallpaperAurora;

  /// No description provided for @wallpaperEmber.
  ///
  /// In en, this message translates to:
  /// **'Ember'**
  String get wallpaperEmber;

  /// No description provided for @appCalculator.
  ///
  /// In en, this message translates to:
  /// **'Calculator'**
  String get appCalculator;

  /// No description provided for @ctxMoveToDesktop.
  ///
  /// In en, this message translates to:
  /// **'Move to desktop {n}'**
  String ctxMoveToDesktop(int n);

  /// No description provided for @sessionLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get sessionLock;

  /// No description provided for @sessionLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get sessionLogOut;

  /// No description provided for @sessionSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sessionSleep;

  /// No description provided for @sessionRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get sessionRestart;

  /// No description provided for @sessionShutDown.
  ///
  /// In en, this message translates to:
  /// **'Shut Down'**
  String get sessionShutDown;

  /// No description provided for @notifCenter.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifCenter;

  /// No description provided for @notifClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get notifClearAll;

  /// No description provided for @notifEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notifEmpty;

  /// No description provided for @notifDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get notifDismiss;

  /// No description provided for @sessionConfirmLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out of this session?'**
  String get sessionConfirmLogOut;

  /// No description provided for @sessionConfirmSuspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend the system?'**
  String get sessionConfirmSuspend;

  /// No description provided for @sessionConfirmRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart the system?'**
  String get sessionConfirmRestart;

  /// No description provided for @sessionConfirmPoweroff.
  ///
  /// In en, this message translates to:
  /// **'Shut down the system?'**
  String get sessionConfirmPoweroff;

  /// No description provided for @dialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dialogCancel;

  /// No description provided for @tipControlCenter.
  ///
  /// In en, this message translates to:
  /// **'Control Center'**
  String get tipControlCenter;

  /// No description provided for @lockHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get lockHint;

  /// No description provided for @lockWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get lockWrong;

  /// No description provided for @lockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlock;
}

class _OasisLocalizationsDelegate
    extends LocalizationsDelegate<OasisLocalizations> {
  const _OasisLocalizationsDelegate();

  @override
  Future<OasisLocalizations> load(Locale locale) {
    return SynchronousFuture<OasisLocalizations>(
      lookupOasisLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ga', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_OasisLocalizationsDelegate old) => false;
}

OasisLocalizations lookupOasisLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return OasisLocalizationsEn();
    case 'ga':
      return OasisLocalizationsGa();
    case 'ru':
      return OasisLocalizationsRu();
    case 'zh':
      return OasisLocalizationsZh();
  }

  throw FlutterError(
    'OasisLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
