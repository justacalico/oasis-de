import 'package:flutter/material.dart';

import 'oasis_colors.dart';

const kOasisFontFamily = 'packages/oasis_ui/Inter';

class OasisStyle extends ThemeExtension<OasisStyle> {
  const OasisStyle({
    required this.palette,
    required this.windowRadius,
    required this.cardRadius,
    required this.controlRadius,
    required this.menuRadius,
  });

  final OasisPalette palette;
  final double windowRadius;
  final double cardRadius;
  final double controlRadius;
  final double menuRadius;

  @override
  OasisStyle copyWith({
    OasisPalette? palette,
    double? windowRadius,
    double? cardRadius,
    double? controlRadius,
    double? menuRadius,
  }) =>
      OasisStyle(
        palette: palette ?? this.palette,
        windowRadius: windowRadius ?? this.windowRadius,
        cardRadius: cardRadius ?? this.cardRadius,
        controlRadius: controlRadius ?? this.controlRadius,
        menuRadius: menuRadius ?? this.menuRadius,
      );

  @override
  OasisStyle lerp(OasisStyle? other, double t) =>
      t < 0.5 ? this : (other ?? this);

  static OasisStyle of(BuildContext context) =>
      Theme.of(context).extension<OasisStyle>()!;
}

TextTheme _textTheme(OasisPalette p) => TextTheme(
      displayLarge: TextStyle(
          fontSize: 34, fontWeight: FontWeight.w700, color: p.textPrimary),
      headlineMedium: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: p.textPrimary),
      titleLarge: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: p.textPrimary),
      titleMedium: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: p.textPrimary),
      bodyLarge: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w400, color: p.textPrimary),
      bodyMedium: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w400, color: p.textPrimary),
      bodySmall: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w400, color: p.textSecondary),
      labelMedium: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: p.textSecondary),
    );

class OasisTheme {
  static ThemeData fromPalette(OasisPalette palette) {
    final textTheme = _textTheme(palette);
    return ThemeData(
      useMaterial3: true,
      fontFamily: kOasisFontFamily,
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.windowBackground,
      dividerColor: palette.divider,
      colorScheme: ColorScheme(
        brightness: palette.isDark ? Brightness.dark : Brightness.light,
        primary: palette.accent,
        onPrimary: const Color(0xFFFFFFFF),
        secondary: palette.accentSoft,
        onSecondary: palette.accent,
        error: const Color(0xFFFF453A),
        onError: const Color(0xFFFFFFFF),
        surface: palette.windowBackground,
        onSurface: palette.textPrimary,
        surfaceContainerHighest: palette.cardBackground,
        outline: palette.divider,
      ),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x00000000),
      extensions: [
        OasisStyle(
          palette: palette,
          windowRadius: 16,
          cardRadius: 12,
          controlRadius: 7,
          menuRadius: 10,
        ),
      ],
    );
  }

  static ThemeData light() => fromPalette(OasisPalette.light);

  static ThemeData dark() => fromPalette(OasisPalette.dark);

  static ThemeData oled() => fromPalette(OasisPalette.oled);

  static ThemeData resolve(OasisThemeMode mode, {required bool platformDark}) =>
      fromPalette(OasisPalette.of(mode, platformDark: platformDark));
}

class OasisAppearance extends ChangeNotifier {
  OasisAppearance({
    OasisThemeMode themeMode = OasisThemeMode.system,
    Color? accent,
  })  : _themeMode = themeMode,
        _accent = accent;

  OasisThemeMode _themeMode;
  Color? _accent;

  OasisThemeMode get themeMode => _themeMode;
  Color? get accent => _accent;

  set themeMode(OasisThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
  }

  set accent(Color? color) {
    if (color == _accent) return;
    _accent = color;
    notifyListeners();
  }

  ThemeData themeFor(BuildContext context) => themeForBrightness(
      MediaQuery.platformBrightnessOf(context) == Brightness.dark);

  ThemeData themeForBrightness(bool platformDark) {
    var palette = OasisPalette.of(_themeMode, platformDark: platformDark);
    final custom = _accent;
    if (custom != null) {
      palette = OasisPalette(
        accent: custom,
        accentSoft: custom.withValues(alpha: 0.14),
        textPrimary: palette.textPrimary,
        textSecondary: palette.textSecondary,
        textTertiary: palette.textTertiary,
        windowBackground: palette.windowBackground,
        sidebarBackground: palette.sidebarBackground,
        groupedBackground: palette.groupedBackground,
        cardBackground: palette.cardBackground,
        divider: palette.divider,
        glassFill: palette.glassFill,
        glassBorder: palette.glassBorder,
        glassHighlight: palette.glassHighlight,
        selection: custom.withValues(alpha: 0.3),
        shadow: palette.shadow,
        desktopGradientStart: palette.desktopGradientStart,
        desktopGradientMid: palette.desktopGradientMid,
        desktopGradientEnd: palette.desktopGradientEnd,
        dockFill: palette.dockFill,
        isDark: palette.isDark,
        isOled: palette.isOled,
      );
    }
    return OasisTheme.fromPalette(palette);
  }
}
