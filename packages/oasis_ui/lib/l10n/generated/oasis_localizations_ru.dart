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
  String get appUnknown => 'Приложение';

  @override
  String get menuFile => 'Файл';

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
  String get menuEnterFullScreen => 'На весь экран';

  @override
  String get menuAbout => 'О Oasis';

  @override
  String get launchPad => 'Панель запуска';

  @override
  String launchFailed(String app) {
    return 'Не удалось открыть $app';
  }

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
  String get aboutDeviceName => 'Имя устройства';

  @override
  String get aboutOs => 'Операционная система';

  @override
  String get aboutKernel => 'Ядро';

  @override
  String get aboutCpu => 'Процессор';

  @override
  String get aboutMemory => 'Память';

  @override
  String get aboutDisk => 'Диск';

  @override
  String get aboutGpu => 'Графика';

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
  String get updateCheckNow => 'Проверить сейчас';

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
  String get settingsWifiBody => 'Включение и отключение Wi-Fi.';

  @override
  String get settingsBluetoothBody => 'Включение и отключение Bluetooth.';

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
  String get wallpaperInvalidPath => 'Изображение не найдено';

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
  String get landingRetry => 'Повторить';

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

  @override
  String get ccOn => 'Вкл';

  @override
  String get ccOff => 'Выкл';

  @override
  String get ccNightLight => 'Ночной свет';

  @override
  String get ccBattery => 'Батарея';

  @override
  String get ccMedia => 'Медиа';

  @override
  String get ccNothingPlaying => 'Ничего не воспроизводится';

  @override
  String get dockPin => 'Закрепить в доке';

  @override
  String get dockUnpin => 'Открепить';

  @override
  String get dockQuit => 'Выйти';

  @override
  String get wallpaperPeaks => 'Вершины';

  @override
  String get wallpaperAurora => 'Сияние';

  @override
  String get wallpaperEmber => 'Угли';

  @override
  String get appCalculator => 'Калькулятор';

  @override
  String ctxMoveToDesktop(int n) {
    return 'Переместить на стол $n';
  }

  @override
  String get sessionLock => 'Блокировать';

  @override
  String get sessionLogOut => 'Выйти';

  @override
  String get sessionSleep => 'Сон';

  @override
  String get sessionRestart => 'Перезапуск';

  @override
  String get sessionShutDown => 'Выключение';

  @override
  String get notifCenter => 'Уведомления';

  @override
  String get notifClearAll => 'Очистить всё';

  @override
  String get notifEmpty => 'Нет уведомлений';

  @override
  String get notifDismiss => 'Скрыть';

  @override
  String get sessionConfirmLogOut => 'Выйти из сеанса?';

  @override
  String get sessionConfirmSuspend => 'Приостановить систему?';

  @override
  String get sessionConfirmRestart => 'Перезагрузить систему?';

  @override
  String get sessionConfirmPoweroff => 'Выключить систему?';

  @override
  String get dialogCancel => 'Отмена';

  @override
  String get tipControlCenter => 'Центр управления';

  @override
  String get lockHint => 'Введите пароль';

  @override
  String get lockWrong => 'Неверный пароль';

  @override
  String get lockUnlock => 'Разблокировать';
}
