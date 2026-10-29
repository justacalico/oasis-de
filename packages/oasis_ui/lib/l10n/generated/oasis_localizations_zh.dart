// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'oasis_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class OasisLocalizationsZh extends OasisLocalizations {
  OasisLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Oasis';

  @override
  String get appUnknown => '应用程序';

  @override
  String get menuFile => '文件';

  @override
  String get menuView => '显示';

  @override
  String get menuWindow => '窗口';

  @override
  String get menuHelp => '帮助';

  @override
  String menuAboutApp(String app) {
    return '关于 $app';
  }

  @override
  String get menuSettings => '设置…';

  @override
  String get menuCloseWindow => '关闭窗口';

  @override
  String get menuMinimise => '最小化';

  @override
  String get menuZoom => '缩放';

  @override
  String get menuNewWindow => '新建窗口';

  @override
  String get menuEnterFullScreen => '进入全屏';

  @override
  String get menuAbout => '关于 Oasis';

  @override
  String get launchPad => '启动台';

  @override
  String launchFailed(String app) {
    return '无法打开$app';
  }

  @override
  String get launcherHint => '搜索应用';

  @override
  String get launcherNoResults => '无结果';

  @override
  String get ccWifi => '无线局域网';

  @override
  String get ccBluetooth => '蓝牙';

  @override
  String get ccFocus => '专注模式';

  @override
  String get ccBrightness => '亮度';

  @override
  String get ccVolume => '音量';

  @override
  String get ccAppearance => '外观';

  @override
  String get ccDarkMode => '深色模式';

  @override
  String get aboutTagline => '为 Linux 打造的宁静、通透的桌面环境。';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String get updateCheck => '检查更新';

  @override
  String get updateCheckNow => '立即检查';

  @override
  String get updateChecking => '正在检查更新…';

  @override
  String get updateUpToDate => 'Oasis 已是最新版本';

  @override
  String updateAvailable(String version) {
    return '版本 $version 现已推出';
  }

  @override
  String get updateFailed => '无法检查更新';

  @override
  String get updateViewRelease => '查看发布';

  @override
  String get updateAllReleases => '所有发布';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsGeneral => '通用';

  @override
  String get settingsWifi => '无线局域网';

  @override
  String get settingsBluetooth => '蓝牙';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsAccent => '强调色';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsWifiBody => '开启或关闭 Wi-Fi。';

  @override
  String get settingsBluetoothBody => '开启或关闭蓝牙。';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeOled => 'OLED';

  @override
  String get settingsWallpaper => '壁纸';

  @override
  String get wallpaperDunes => 'Oasis 沙丘';

  @override
  String get wallpaperCustom => '自定义图片';

  @override
  String get wallpaperPathHint => '图片路径';

  @override
  String get wallpaperApply => '应用';

  @override
  String get wallpaperInvalidPath => '找不到图片';

  @override
  String get wallpaperFit => '填充方式';

  @override
  String get wallpaperFitCover => '填满屏幕';

  @override
  String get wallpaperFitContain => '适应屏幕';

  @override
  String get wallpaperFitFill => '拉伸填充';

  @override
  String get languageSystem => '跟随系统';

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
  String get landingTagline => '桌面，回归纯粹。';

  @override
  String get landingHeroBody => 'Oasis 是一个 Linux 桌面环境，将宁静通透的设计与熟悉顺手的操作融为一体。';

  @override
  String get landingOpenApp => '启动网页版';

  @override
  String get landingGetStarted => '下载';

  @override
  String get landingShowcaseTitle => '为专注而生';

  @override
  String get landingShowcaseBody => '玻璃质感、诚实的排版与合乎直觉的控件。没有任何东西挡在你和工作之间。';

  @override
  String get landingFeatureGlassTitle => '流动的表面';

  @override
  String get landingFeatureGlassBody => '菜单、Dock 和窗口悬浮在真实的半透明质感之上，带有高光细节。';

  @override
  String get landingFeatureCalmTitle => '默认即安静';

  @override
  String get landingFeatureCalmBody => '安静的菜单栏、不打扰的程序坞，以及从不喧哗的通知。';

  @override
  String get landingFeatureOpenTitle => '底层开放';

  @override
  String get landingFeatureOpenBody => '运行在你熟悉的 Linux 技术栈上。自由开源，无广告，无追踪。';

  @override
  String get landingDownloadsTitle => '获取 Oasis';

  @override
  String get landingDownloadsBody => '为你的设备下载最新版本，或在 GitLab 上浏览所有发布。';

  @override
  String get landingLoadingReleases => '正在加载发布…';

  @override
  String get landingNoReleases => '暂无发布';

  @override
  String get landingReleasesFailed => '无法加载发布';

  @override
  String get landingAllReleases => 'GitLab 上的所有发布';

  @override
  String get landingSource => '源代码';

  @override
  String get landingFooter => '永远自由开源。';

  @override
  String get landingTryWeb => '在浏览器中体验';

  @override
  String get landingWebBody => '整套桌面也能在网页中运行，无需安装。';

  @override
  String get appNotes => '备忘录';

  @override
  String get menuQuit => '退出 Oasis';

  @override
  String get ccOn => '开';

  @override
  String get ccOff => '关';

  @override
  String get ccNightLight => '夜间模式';

  @override
  String get ccBattery => '电池';

  @override
  String get ccMedia => '媒体';

  @override
  String get ccNothingPlaying => '暂无播放';

  @override
  String get dockPin => '固定到 Dock';

  @override
  String get dockUnpin => '取消固定';

  @override
  String get wallpaperPeaks => '山峰';

  @override
  String get wallpaperAurora => '极光';

  @override
  String get wallpaperEmber => '余烬';

  @override
  String get appCalculator => '计算器';

  @override
  String ctxMoveToDesktop(int n) {
    return '移到桌面 $n';
  }

  @override
  String get sessionLock => '锁定';

  @override
  String get sessionLogOut => '注销';

  @override
  String get sessionSleep => '睡眠';

  @override
  String get sessionRestart => '重启';

  @override
  String get sessionShutDown => '关机';

  @override
  String get notifCenter => '通知';

  @override
  String get notifClearAll => '全部清除';

  @override
  String get notifEmpty => '没有通知';
}
