// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'oasis_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class OasisLocalizationsRu extends OasisLocalizations {
  OasisLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'Oasis';

  @override
  String get menuFile => 'Файл';

  @override
  String get menuEdit => 'Правка';

  @override
  String get menuView => 'Вид';

  @override
  String get menuWindow => 'Окно';

  @override
  String get menuHelp => 'Справка';

  @override
  String menuAboutApp(String app) {
    return 'О программе $app';
  }

  @override
  String get menuSettings => 'Настройки…';

  @override
  String get menuCloseWindow => 'Закрыть окно';

  @override
  String get menuMinimise => 'Свернуть';

  @override
  String get menuZoom => 'Масштаб';

  @override
  String get menuNewWindow => 'Новое окно';

  @override
  String get menuUndo => 'Отменить';

  @override
  String get menuRedo => 'Повторить';

  @override
  String get menuCut => 'Вырезать';

  @override
  String get menuCopy => 'Скопировать';

  @override
  String get menuPaste => 'Вставить';

  @override
  String get menuSelectAll => 'Выбрать все';

  @override
  String get menuEnterFullScreen => 'На весь экран';

  @override
  String get menuAbout => 'О Oasis';

  @override
  String get launchPad => 'Панель запуска';

  @override
  String get launcherHint => 'Поиск приложений';

  @override
  String get launcherNoResults => 'Ничего не найдено';

  @override
  String get ccWifi => 'Wi-Fi';

  @override
  String get ccBluetooth => 'Bluetooth';

  @override
  String get ccFocus => 'Фокус';

  @override
  String get ccBrightness => 'Яркость';

  @override
  String get ccVolume => 'Громкость';

  @override
  String get ccAppearance => 'Оформление';

  @override
  String get ccDarkMode => 'Тёмная тема';

  @override
  String get aboutTagline =>
      'Спокойная стеклянная среда рабочего стола для Linux.';

  @override
  String versionLabel(String version) {
    return 'Версия $version';
  }

  @override
  String get updateCheck => 'Проверить обновления';

  @override
  String get updateChecking => 'Проверка обновлений…';

  @override
  String get updateUpToDate => 'Oasis обновлён';

  @override
  String updateAvailable(String version) {
    return 'Доступна версия $version';
  }

  @override
  String get updateFailed => 'Не удалось проверить обновления';

  @override
  String get updateViewRelease => 'Открыть релиз';

  @override
  String get updateAllReleases => 'Все релизы';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsAppearance => 'Оформление';

  @override
  String get settingsGeneral => 'Основные';

  @override
  String get settingsWifi => 'Wi-Fi';

  @override
  String get settingsBluetooth => 'Bluetooth';

  @override
  String get settingsAbout => 'О системе';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsAccent => 'Акцентный цвет';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsEnabled => 'Включено';

  @override
  String get settingsNetworkBody =>
      'Переключите радиомодуль этого демо-рабочего стола.';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeOled => 'OLED';

  @override
  String get settingsWallpaper => 'Обои';

  @override
  String get wallpaperDunes => 'Дюны Oasis';

  @override
  String get wallpaperCustom => 'Своё изображение';

  @override
  String get wallpaperPathHint => 'Путь к изображению';

  @override
  String get wallpaperApply => 'Применить';

  @override
  String get wallpaperFit => 'Размещение';

  @override
  String get wallpaperFitCover => 'Заполнить экран';

  @override
  String get wallpaperFitContain => 'Вместить в экран';

  @override
  String get wallpaperFitFill => 'Растянуть';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get languageEnGb => 'Traditional English';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageGa => 'Gaeilge';

  @override
  String get landingTagline => 'Ваш рабочий стол в чистом виде.';

  @override
  String get landingHeroBody =>
      'Oasis — среда рабочего стола для Linux, сочетающая спокойный стеклянный дизайн с привычным рабочим процессом.';

  @override
  String get landingOpenApp => 'Открыть веб-версию';

  @override
  String get landingGetStarted => 'Скачать';

  @override
  String get landingShowcaseTitle => 'Создано быть незаметным';

  @override
  String get landingShowcaseBody =>
      'Стеклянные поверхности, честная типографика и элементы управления, ведущие себя так, как вы ожидаете. Ничего не мешает работе.';

  @override
  String get landingFeatureGlassTitle => 'Жидкие поверхности';

  @override
  String get landingFeatureGlassBody =>
      'Меню, док и окна парят на настоящей полупрозрачности с бликами.';

  @override
  String get landingFeatureCalmTitle => 'Спокойствие по умолчанию';

  @override
  String get landingFeatureCalmBody =>
      'Тихая строка меню, док, который не мешает, и уведомления, которые не кричат.';

  @override
  String get landingFeatureOpenTitle => 'Открытый фундамент';

  @override
  String get landingFeatureOpenBody =>
      'Работает на знакомом стеке Linux. Свободно и открыто, без рекламы и слежки.';

  @override
  String get landingDownloadsTitle => 'Получить Oasis';

  @override
  String get landingDownloadsBody =>
      'Скачайте последний релиз для вашего устройства или посмотрите все релизы на GitLab.';

  @override
  String get landingLoadingReleases => 'Загрузка релизов…';

  @override
  String get landingNoReleases => 'Релизов пока нет';

  @override
  String get landingReleasesFailed => 'Не удалось загрузить релизы';

  @override
  String get landingAllReleases => 'Все релизы на GitLab';

  @override
  String get landingSource => 'Исходный код';

  @override
  String get landingFooter => 'Свободно и открыто навсегда.';

  @override
  String get landingTryWeb => 'Попробуйте в браузере';

  @override
  String get landingWebBody =>
      'Весь рабочий стол работает и в вебе. Установка не нужна.';

  @override
  String get appNotes => 'Заметки';

  @override
  String get menuQuit => 'Выйти из Oasis';
}
