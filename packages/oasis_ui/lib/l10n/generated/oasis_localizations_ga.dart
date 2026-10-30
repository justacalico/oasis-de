// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'oasis_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Irish (`ga`).
class OasisLocalizationsGa extends OasisLocalizations {
  OasisLocalizationsGa([String locale = 'ga']) : super(locale);

  @override
  String get appName => 'Oasis';

  @override
  String get appUnknown => 'Feidhmchlár';

  @override
  String get menuFile => 'Comhad';

  @override
  String get menuView => 'Amharc';

  @override
  String get menuWindow => 'Fuinneog';

  @override
  String get menuHelp => 'Cabhair';

  @override
  String menuAboutApp(String app) {
    return 'Faoi $app';
  }

  @override
  String get menuSettings => 'Socruithe…';

  @override
  String get menuCloseWindow => 'Dún an Fhuinneog';

  @override
  String get menuMinimise => 'Íoslaghdaigh';

  @override
  String get menuZoom => 'Zúmáil';

  @override
  String get menuNewWindow => 'Fuinneog Nua';

  @override
  String get menuEnterFullScreen => 'Scáileán Iomlán';

  @override
  String get menuAbout => 'Faoi Oasis';

  @override
  String get launchPad => 'Painéal Tosaithe';

  @override
  String launchFailed(String app) {
    return 'Níorbh fhéidir $app a oscailt';
  }

  @override
  String get launcherHint => 'Cuardaigh aipeanna';

  @override
  String get launcherNoResults => 'Torthaí ar bith';

  @override
  String get ccWifi => 'Wi-Fi';

  @override
  String get ccBluetooth => 'Bluetooth';

  @override
  String get ccFocus => 'Fócas';

  @override
  String get ccBrightness => 'Gile';

  @override
  String get ccVolume => 'Toirt';

  @override
  String get ccAppearance => 'Dealramh';

  @override
  String get ccDarkMode => 'Mód Dorcha';

  @override
  String get aboutDeviceName => 'Ainm an ghléis';

  @override
  String get aboutOs => 'Córas oibriúcháin';

  @override
  String get aboutKernel => 'Eithne';

  @override
  String get aboutCpu => 'Próiseálaí';

  @override
  String get aboutMemory => 'Cuimhne';

  @override
  String get aboutDisk => 'Diosca';

  @override
  String get aboutGpu => 'Grafaicí';

  @override
  String get aboutTagline =>
      'Timpeallacht deisce shochréatach ghloineach do Linux.';

  @override
  String versionLabel(String version) {
    return 'Leagan $version';
  }

  @override
  String get updateCheck => 'Seiceáil Nuashonruithe';

  @override
  String get updateCheckNow => 'Seiceáil anois';

  @override
  String get updateChecking => 'Nuashonruithe á seiceáil…';

  @override
  String get updateUpToDate => 'Tá Oasis cothrom le dáta';

  @override
  String updateAvailable(String version) {
    return 'Tá leagan $version ar fáil';
  }

  @override
  String get updateFailed => 'Níorbh fhéidir nuashonruithe a sheiceáil';

  @override
  String get updateViewRelease => 'Féach ar an eisiúint';

  @override
  String get updateAllReleases => 'Gach eisiúint';

  @override
  String get updateInstall => 'Suiteáil';

  @override
  String get updateInstalling => 'Á íoslódáil agus á shuiteáil…';

  @override
  String get updateInstalled => 'Nuashonrú suiteáilte';

  @override
  String get updateInstallFailed => 'Níorbh fhéidir an nuashonrú a shuiteáil';

  @override
  String get settingsTitle => 'Socruithe';

  @override
  String get settingsAppearance => 'Dealramh';

  @override
  String get settingsGeneral => 'Ginearálta';

  @override
  String get settingsWifi => 'Wi-Fi';

  @override
  String get settingsBluetooth => 'Bluetooth';

  @override
  String get settingsDisplays => 'Taispeántais';

  @override
  String get settingsSound => 'Fuaim';

  @override
  String get settingsPower => 'Cumhacht';

  @override
  String get settingsDateTime => 'Dáta agus Am';

  @override
  String get settingsUsers => 'Úsáideoirí';

  @override
  String get settingsBrightness => 'Gile';

  @override
  String get settingsNightLight => 'Solas oíche';

  @override
  String get settingsVolume => 'Airde';

  @override
  String get settingsBattery => 'Cadhnra';

  @override
  String get settingsSuspend => 'Cuir ar fionraí';

  @override
  String get settingsReboot => 'Atosaigh';

  @override
  String get settingsPowerOff => 'Múch';

  @override
  String get settingsLogout => 'Logáil amach';

  @override
  String get settingsCurrentUser => 'Úsáideoir reatha';

  @override
  String get settingsDate => 'Dáta';

  @override
  String get settingsTime => 'Am';

  @override
  String get settingsTimezone => 'Crios ama';

  @override
  String get settingsSearchHint => 'Cuardaigh socruithe';

  @override
  String get settingsAbout => 'Faoi';

  @override
  String get settingsTheme => 'Téama';

  @override
  String get settingsAccent => 'Dath aicem';

  @override
  String get settingsLanguage => 'Teanga';

  @override
  String get settingsWifiBody => 'Cas Wi-Fi air nó as.';

  @override
  String get settingsBluetoothBody => 'Cas Bluetooth air nó as.';

  @override
  String get themeSystem => 'Córas';

  @override
  String get themeLight => 'Solas';

  @override
  String get themeDark => 'Dorcha';

  @override
  String get themeOled => 'OLED';

  @override
  String get settingsWallpaper => 'Páipéar balla';

  @override
  String get wallpaperDunes => 'Dumhcha Oasis';

  @override
  String get wallpaperCustom => 'Íomhá shaincheaptha';

  @override
  String get wallpaperPathHint => 'Conair na híomhá';

  @override
  String get wallpaperApply => 'Cuir i bhfeidhm';

  @override
  String get wallpaperInvalidPath => 'Íomhá gan aimsiú';

  @override
  String get wallpaperFit => 'Oiriúnú';

  @override
  String get wallpaperFitCover => 'Líon an scáileán';

  @override
  String get wallpaperFitContain => 'Oiriúnaigh don scáileán';

  @override
  String get wallpaperFitFill => 'Sín';

  @override
  String get languageSystem => 'Córas';

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
  String get landingTagline => 'Do dheasc, íochtaithe.';

  @override
  String get landingHeroBody =>
      'Is timpeallacht deisce do Linux é Oasis a chumascann dearadh gloineach suaimhneach le sreabhadh oibre aithnid.';

  @override
  String get landingOpenApp => 'Tosaigh an feidhmchlár gréasáin';

  @override
  String get landingGetStarted => 'Íoslódáil';

  @override
  String get landingShowcaseTitle => 'Deartha le himeacht';

  @override
  String get landingShowcaseBody =>
      'Dromchlaí gloine, clófhoireacht ionraic agus rialuithe a fheidhmíonn mar a bhféadfá. Níl aon rud idir tú agus d\'obair.';

  @override
  String get landingFeatureGlassTitle => 'Dromchlaí leachtacha';

  @override
  String get landingFeatureGlassBody =>
      'Snámhann biachláir, dugaí agus fuinneoga ar thrédhearcacht fhíor le soilsiú spéaclaíoch.';

  @override
  String get landingFeatureCalmTitle => 'Ciúin ó thús';

  @override
  String get landingFeatureCalmBody =>
      'Barra roghchláir ciúin, duga a fhanann as do bhealach, agus fógraí nach mbíonn ag béiceáil.';

  @override
  String get landingFeatureOpenTitle => 'Oscailte thíos';

  @override
  String get landingFeatureOpenBody =>
      'Ritheann sé ar an gcruach Linux a aithníonn tú. Saor in aisce agus foinse oscailte, gan fógraí, gan rianú.';

  @override
  String get landingDownloadsTitle => 'Faigh Oasis';

  @override
  String get landingDownloadsBody =>
      'Faigh an t-eisiúint is déanaí do do mheaisín, nó féach ar gach eisiúint ar GitLab.';

  @override
  String get landingLoadingReleases => 'Eisiúintí á lódáil…';

  @override
  String get landingNoReleases => 'Eisiúint ar bith go fóil';

  @override
  String get landingReleasesFailed => 'Níorbh fhéidir eisiúintí a lódáil';

  @override
  String get landingRetry => 'Atriail';

  @override
  String get landingAllReleases => 'Gach eisiúint ar GitLab';

  @override
  String get landingSource => 'Cód foinse';

  @override
  String get landingFooter => 'Saor in aisce agus foinse oscailte, go deo.';

  @override
  String get landingTryWeb => 'Bain triail as sa bhrabhsálaí';

  @override
  String get landingWebBody =>
      'Ritheann an deasc iomlán ar an ngréasán freisin. Gan shuiteáil.';

  @override
  String get appNotes => 'Nótaí';

  @override
  String get menuQuit => 'Scoir Oasis';

  @override
  String get ccOn => 'Ar';

  @override
  String get ccOff => 'As';

  @override
  String get ccNightLight => 'Solais Oíche';

  @override
  String get ccBattery => 'Cadhnra';

  @override
  String get ccMedia => 'Meáin';

  @override
  String get ccNothingPlaying => 'Níl aon rud á sheinm';

  @override
  String get dockPin => 'Greamaigh sa Duga';

  @override
  String get dockUnpin => 'Díghreamaigh';

  @override
  String get dockQuit => 'Scoir';

  @override
  String get wallpaperPeaks => 'Sléibhte';

  @override
  String get wallpaperAurora => 'Na Saobhrí';

  @override
  String get wallpaperEmber => 'Smóidí';

  @override
  String get appCalculator => 'Áireamhán';

  @override
  String get appFiles => 'Comhaid';

  @override
  String get filesBookmarkHome => 'Baile';

  @override
  String get filesBookmarkDocuments => 'Doiciméid';

  @override
  String get filesBookmarkDownloads => 'Íoslódálacha';

  @override
  String get filesBookmarkPictures => 'Pictiúir';

  @override
  String get filesBookmarkMusic => 'Ceol';

  @override
  String get filesBookmarkVideos => 'Físeáin';

  @override
  String get filesBookmarkTrash => 'Bruscar';

  @override
  String get filesBookmarkRoot => 'Córas Comhad';

  @override
  String get filesUp => 'Suas';

  @override
  String get filesLocation => 'Suíomh';

  @override
  String get filesSearch => 'Cuardaigh san fhillteán seo';

  @override
  String get filesShowHidden => 'Taispeáin comhaid i bhfolach';

  @override
  String get filesListView => 'Amharc liosta';

  @override
  String get filesGridView => 'Amharc greille';

  @override
  String filesItems(int count) {
    return '$count mír';
  }

  @override
  String filesSelected(int count) {
    return '$count roghnaithe';
  }

  @override
  String get filesFolder => 'Fillteán';

  @override
  String get filesClearSearch => 'Glan an cuardach';

  @override
  String get filesNewFolder => 'Fillteán nua';

  @override
  String get filesPaste => 'Greamaigh';

  @override
  String get filesCopy => 'Cóipeáil';

  @override
  String get filesCut => 'Gearr';

  @override
  String get filesDelete => 'Bog chun an bhruscair';

  @override
  String get filesRename => 'Athainmnigh';

  @override
  String get filesOpen => 'Oscail';

  @override
  String get filesName => 'Ainm';

  @override
  String get filesCancel => 'Cealaigh';

  @override
  String get filesCreate => 'Cruthaigh';

  @override
  String get filesEmpty => 'Tá an fillteán seo folamh';

  @override
  String get filesNoResults => 'Níor aimsíodh comhad ar bith';

  @override
  String filesError(String path) {
    return 'Ní féidir $path a oscailt';
  }

  @override
  String ctxMoveToDesktop(int n) {
    return 'Bog go deasc $n';
  }

  @override
  String get sessionLock => 'Glasáil';

  @override
  String get sessionLogOut => 'Logáil Amach';

  @override
  String get sessionSleep => 'Codladh';

  @override
  String get sessionRestart => 'Atosaigh';

  @override
  String get sessionShutDown => 'Múch';

  @override
  String get notifCenter => 'Fógraí';

  @override
  String get notifClearAll => 'Glan Gach';

  @override
  String get notifEmpty => 'Gan fhógraí';

  @override
  String get notifDismiss => 'Rua';

  @override
  String get sessionConfirmLogOut => 'Logáil amach as an seisiún?';

  @override
  String get sessionConfirmSuspend => 'Cuir an córas ar fionraí?';

  @override
  String get sessionConfirmRestart => 'Atosaigh an córas?';

  @override
  String get sessionConfirmPoweroff => 'Múch an córas?';

  @override
  String get dialogCancel => 'Cealaigh';

  @override
  String get tipControlCenter => 'Lárionad Rialaithe';

  @override
  String get lockHint => 'Cuir isteach do phasfhocal';

  @override
  String get lockWrong => 'Pasfhocal mícheart';

  @override
  String get lockUnlock => 'Díghlasáil';
}
