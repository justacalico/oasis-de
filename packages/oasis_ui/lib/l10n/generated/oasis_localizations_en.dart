// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'oasis_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class OasisLocalizationsEn extends OasisLocalizations {
  OasisLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Oasis';

  @override
  String get appUnknown => 'Application';

  @override
  String get menuFile => 'File';

  @override
  String get menuView => 'View';

  @override
  String get menuWindow => 'Window';

  @override
  String get menuHelp => 'Help';

  @override
  String menuAboutApp(String app) {
    return 'About $app';
  }

  @override
  String get menuSettings => 'Settings…';

  @override
  String get menuCloseWindow => 'Close Window';

  @override
  String get menuMinimise => 'Minimise';

  @override
  String get menuZoom => 'Zoom';

  @override
  String get menuNewWindow => 'New Window';

  @override
  String get menuEnterFullScreen => 'Enter Full Screen';

  @override
  String get menuAbout => 'About Oasis';

  @override
  String get launchPad => 'Launch Pad';

  @override
  String launchFailed(String app) {
    return 'Couldn\'t open $app';
  }

  @override
  String get launcherHint => 'Search apps';

  @override
  String get launcherNoResults => 'No results';

  @override
  String get ccWifi => 'Wi-Fi';

  @override
  String get wifiMenuScanning => 'Scanning…';

  @override
  String get wifiMenuNoNetworks => 'No networks found';

  @override
  String get wifiMenuSettings => 'Wi-Fi Settings…';

  @override
  String get ccBluetooth => 'Bluetooth';

  @override
  String get ccFocus => 'Focus';

  @override
  String get ccBrightness => 'Brightness';

  @override
  String get ccVolume => 'Volume';

  @override
  String get ccAppearance => 'Appearance';

  @override
  String get ccDarkMode => 'Dark Mode';

  @override
  String get aboutDeviceName => 'Device name';

  @override
  String get aboutOs => 'Operating system';

  @override
  String get aboutKernel => 'Kernel';

  @override
  String get aboutCpu => 'Processor';

  @override
  String get aboutMemory => 'Memory';

  @override
  String get aboutDisk => 'Disk';

  @override
  String get aboutGpu => 'Graphics';

  @override
  String get aboutTagline => 'A calm, glassy desktop environment for Linux.';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get updateCheck => 'Check for Updates';

  @override
  String get updateCheckNow => 'Check now';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateUpToDate => 'Oasis is up to date';

  @override
  String updateAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateFailed => 'Couldn\'t check for updates';

  @override
  String get updateViewRelease => 'View release';

  @override
  String get updateAllReleases => 'All releases';

  @override
  String get updateInstall => 'Install';

  @override
  String get updateInstalling => 'Downloading and installing…';

  @override
  String get updateInstalled => 'Update installed';

  @override
  String get updateInstallFailed => 'Couldn\'t install the update';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsWifi => 'Wi-Fi';

  @override
  String get settingsBluetooth => 'Bluetooth';

  @override
  String get settingsDisplays => 'Displays';

  @override
  String get settingsDock => 'Dock';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsPower => 'Power';

  @override
  String get settingsDateTime => 'Date & Time';

  @override
  String get settingsUsers => 'Users';

  @override
  String get settingsBrightness => 'Brightness';

  @override
  String get settingsNightLight => 'Night light';

  @override
  String get settingsVolume => 'Volume';

  @override
  String get settingsBattery => 'Battery';

  @override
  String get settingsSuspend => 'Suspend';

  @override
  String get settingsReboot => 'Restart';

  @override
  String get settingsPowerOff => 'Power off';

  @override
  String get powerDisplayOffAfter => 'Turn display off after';

  @override
  String get powerSleepAfter => 'Sleep after';

  @override
  String get powerNever => 'Never';

  @override
  String powerMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String powerHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsCurrentUser => 'Current user';

  @override
  String get settingsDate => 'Date';

  @override
  String get settingsTime => 'Time';

  @override
  String get settingsTimezone => 'Time zone';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsAccent => 'Accent colour';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsWifiBody => 'Toggle Wi-Fi on or off.';

  @override
  String get settingsWifiNetworks => 'Networks';

  @override
  String get settingsBluetoothBody => 'Toggle Bluetooth on or off.';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeOled => 'OLED';

  @override
  String get settingsWallpaper => 'Wallpaper';

  @override
  String get wallpaperDunes => 'Oasis Dunes';

  @override
  String get wallpaperCustom => 'Custom image';

  @override
  String get wallpaperPathHint => 'Image path';

  @override
  String get wallpaperApply => 'Apply';

  @override
  String get wallpaperInvalidPath => 'Image not found';

  @override
  String get wallpaperFit => 'Fit';

  @override
  String get wallpaperFitCover => 'Fill screen';

  @override
  String get wallpaperFitContain => 'Fit to screen';

  @override
  String get wallpaperFitFill => 'Stretch';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEn => 'English';

  @override
  String get languageEnGb => 'English (UK)';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageGa => 'Gaeilge';

  @override
  String get landingTagline => 'Your desktop, distilled.';

  @override
  String get landingHeroBody =>
      'Oasis is a desktop environment for Linux that pairs a calm, glassy design with a workflow that feels instantly familiar.';

  @override
  String get landingOpenApp => 'Launch web app';

  @override
  String get landingGetStarted => 'Download';

  @override
  String get landingShowcaseTitle => 'Designed to disappear';

  @override
  String get landingShowcaseBody =>
      'Glass surfaces, honest typography and controls that behave the way you expect. Nothing gets between you and your work.';

  @override
  String get landingFeatureGlassTitle => 'Liquid surfaces';

  @override
  String get landingFeatureGlassBody =>
      'Menus, docks and windows float on real translucency with specular highlights.';

  @override
  String get landingFeatureCalmTitle => 'Calm by default';

  @override
  String get landingFeatureCalmBody =>
      'A quiet menu bar, a dock that stays out of the way, and notifications that never shout.';

  @override
  String get landingFeatureOpenTitle => 'Open underneath';

  @override
  String get landingFeatureOpenBody =>
      'Runs on the Linux stack you already know. Free and open source, no ads, no tracking.';

  @override
  String get landingDownloadsTitle => 'Get Oasis';

  @override
  String get landingDownloadsBody =>
      'Grab the latest release for your machine, or browse every release on GitLab.';

  @override
  String get landingLoadingReleases => 'Loading releases…';

  @override
  String get landingNoReleases => 'No releases yet';

  @override
  String get landingReleasesFailed => 'Couldn\'t load releases';

  @override
  String get landingRetry => 'Retry';

  @override
  String get landingAllReleases => 'All releases on GitLab';

  @override
  String get landingSource => 'Source code';

  @override
  String get landingFooter => 'Free and open source, forever.';

  @override
  String get landingTryWeb => 'Try it in your browser';

  @override
  String get landingWebBody =>
      'The whole desktop runs on the web too. No install required.';

  @override
  String get appNotes => 'Notes';

  @override
  String get menuQuit => 'Quit Oasis';

  @override
  String get ccOn => 'On';

  @override
  String get ccOff => 'Off';

  @override
  String get ccNightLight => 'Night Light';

  @override
  String get ccBattery => 'Battery';

  @override
  String get ccMedia => 'Media';

  @override
  String get ccNothingPlaying => 'Nothing playing';

  @override
  String get dockPin => 'Pin to Dock';

  @override
  String get dockUnpin => 'Unpin';

  @override
  String get dockQuit => 'Quit';

  @override
  String get dockMode => 'Mode';

  @override
  String get dockModePush => 'Push';

  @override
  String get dockModeAutoHide => 'Auto-hide';

  @override
  String get dockModeOff => 'Off';

  @override
  String get dockPosition => 'Position';

  @override
  String get dockPositionLeft => 'Left';

  @override
  String get dockPositionBottom => 'Bottom';

  @override
  String get dockPositionRight => 'Right';

  @override
  String get dockIconSize => 'Icon size';

  @override
  String get dockSizeSmall => 'Small';

  @override
  String get dockSizeMedium => 'Medium';

  @override
  String get dockSizeLarge => 'Large';

  @override
  String get dockSizeCustom => 'Custom';

  @override
  String get dockCustomSize => 'Custom size';

  @override
  String get wallpaperPeaks => 'Peaks';

  @override
  String get wallpaperAurora => 'Aurora';

  @override
  String get wallpaperEmber => 'Ember';

  @override
  String get appCalculator => 'Calculator';

  @override
  String get appFiles => 'Files';

  @override
  String get appScreenshot => 'Screenshot';

  @override
  String get filesBookmarkHome => 'Home';

  @override
  String get filesBookmarkDocuments => 'Documents';

  @override
  String get filesBookmarkDownloads => 'Downloads';

  @override
  String get filesBookmarkPictures => 'Pictures';

  @override
  String get filesBookmarkMusic => 'Music';

  @override
  String get filesBookmarkVideos => 'Videos';

  @override
  String get filesBookmarkTrash => 'Trash';

  @override
  String get filesBookmarkRoot => 'File System';

  @override
  String get filesUp => 'Up';

  @override
  String get filesLocation => 'Location';

  @override
  String get filesSearch => 'Search this folder';

  @override
  String get filesShowHidden => 'Show hidden files';

  @override
  String get filesListView => 'List view';

  @override
  String get filesGridView => 'Grid view';

  @override
  String filesItems(int count) {
    return '$count items';
  }

  @override
  String filesSelected(int count) {
    return '$count selected';
  }

  @override
  String get filesFolder => 'Folder';

  @override
  String get filesClearSearch => 'Clear search';

  @override
  String get filesNewFolder => 'New folder';

  @override
  String get filesPaste => 'Paste';

  @override
  String get filesCopy => 'Copy';

  @override
  String get filesCut => 'Cut';

  @override
  String get filesDelete => 'Move to trash';

  @override
  String get filesRename => 'Rename';

  @override
  String get filesOpen => 'Open';

  @override
  String get filesName => 'Name';

  @override
  String get filesCancel => 'Cancel';

  @override
  String get filesCreate => 'Create';

  @override
  String get filesEmpty => 'This folder is empty';

  @override
  String get filesNoResults => 'No matching files';

  @override
  String filesError(String path) {
    return 'Can\'t open $path';
  }

  @override
  String ctxMoveToDesktop(int n) {
    return 'Move to desktop $n';
  }

  @override
  String get sessionLock => 'Lock';

  @override
  String get sessionLogOut => 'Log Out';

  @override
  String get sessionSleep => 'Sleep';

  @override
  String get sessionRestart => 'Restart';

  @override
  String get sessionShutDown => 'Shut Down';

  @override
  String get notifCenter => 'Notifications';

  @override
  String get notifClearAll => 'Clear All';

  @override
  String get notifEmpty => 'No notifications';

  @override
  String get notifDismiss => 'Dismiss';

  @override
  String get sessionConfirmLogOut => 'Log out of this session?';

  @override
  String get sessionConfirmSuspend => 'Suspend the system?';

  @override
  String get sessionConfirmRestart => 'Restart the system?';

  @override
  String get sessionConfirmPoweroff => 'Shut down the system?';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get tipControlCenter => 'Control Center';

  @override
  String get lockHint => 'Enter your password';

  @override
  String get lockWrong => 'Wrong password';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get displaysIdentify => 'Identify';

  @override
  String get displaysNone => 'No displays found';

  @override
  String get displaysArrangeHint => 'Drag displays to arrange them.';

  @override
  String get displaysApply => 'Apply';

  @override
  String get displaysRevert => 'Revert';

  @override
  String get displaysResolution => 'Resolution';

  @override
  String get displaysRefresh => 'Refresh rate';

  @override
  String get displaysScale => 'Scale';

  @override
  String get displaysRotation => 'Rotation';

  @override
  String get displaysRotationNone => 'Default';

  @override
  String get displaysPrimary => 'primary';

  @override
  String get soundOutput => 'Output';

  @override
  String get soundInput => 'Input';

  @override
  String get soundProfiles => 'Device profiles';

  @override
  String get settingsKeyboard => 'Keyboard';

  @override
  String get keybindShortcuts => 'Shortcuts';

  @override
  String get keybindCustom => 'Custom shortcuts';

  @override
  String get keybindLauncher => 'App search';

  @override
  String get keybindCycleWindows => 'Next window';

  @override
  String get keybindCycleWindowsBack => 'Previous window';

  @override
  String get keybindDismiss => 'Close overlays';

  @override
  String get keybindShowDesktop => 'Show desktop';

  @override
  String get keybindZoom => 'Zoom window';

  @override
  String get keybindQuit => 'Quit app';

  @override
  String get keybindNotSet => 'Not set';

  @override
  String get keybindRecording => 'Type shortcut…';

  @override
  String get keybindAdd => 'Add shortcut';

  @override
  String get keybindReset => 'Reset to defaults';

  @override
  String get keybindCommandHint => 'Command to run';

  @override
  String get keybindRemove => 'Remove';

  @override
  String get settingsMouse => 'Mouse';

  @override
  String get settingsTrackpad => 'Trackpad';

  @override
  String get pointerSpeed => 'Pointer speed';

  @override
  String get pointerPrimaryButton => 'Primary button';

  @override
  String get pointerButtonLeft => 'Left';

  @override
  String get pointerButtonRight => 'Right';

  @override
  String get pointerScrolling => 'Scrolling';

  @override
  String get pointerScrollSpeed => 'Scroll speed';

  @override
  String get pointerNaturalScrolling => 'Natural scrolling';

  @override
  String get trackpadTapToClick => 'Tap to click';

  @override
  String get trackpadTwoFingerScroll => 'Two-finger scrolling';

  @override
  String get keybindScreenshot => 'Take a screenshot';

  @override
  String get screenshotModeRegion => 'Region';

  @override
  String get screenshotModeFullscreen => 'Full screen';

  @override
  String get screenshotDelay => 'Delay';

  @override
  String get screenshotDelayNone => 'None';

  @override
  String screenshotDelaySeconds(int count) {
    return '$count s';
  }

  @override
  String get screenshotTake => 'Take screenshot';

  @override
  String get screenshotHint =>
      'Drag to select a region — Esc or right-click cancels';

  @override
  String get screenshotSavedTitle => 'Screenshot saved';

  @override
  String get screenshotFailed => 'Couldn\'t save the screenshot';

  @override
  String get screenshotNoCapture => 'No captures yet';
}
