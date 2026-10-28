import 'package:flutter/widgets.dart';

enum OasisThemeMode { system, light, dark, oled }

class OasisPalette {
  const OasisPalette({
    required this.accent,
    required this.accentSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.windowBackground,
    required this.sidebarBackground,
    required this.groupedBackground,
    required this.cardBackground,
    required this.divider,
    required this.glassFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.selection,
    required this.shadow,
    required this.desktopGradientStart,
    required this.desktopGradientMid,
    required this.desktopGradientEnd,
    required this.dockFill,
    required this.isDark,
    required this.isOled,
  });

  final Color accent;
  final Color accentSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color windowBackground;
  final Color sidebarBackground;
  final Color groupedBackground;
  final Color cardBackground;
  final Color divider;
  final Color glassFill;
  final Color glassBorder;
  final Color glassHighlight;
  final Color selection;
  final Color shadow;
  final Color desktopGradientStart;
  final Color desktopGradientMid;
  final Color desktopGradientEnd;
  final Color dockFill;
  final bool isDark;
  final bool isOled;

  static const light = OasisPalette(
    accent: Color(0xFF007AFF),
    accentSoft: Color(0x1F007AFF),
    textPrimary: Color(0xE61A1A1A),
    textSecondary: Color(0x993C3C43),
    textTertiary: Color(0x4D3C3C43),
    windowBackground: Color(0xF5F5F5F7),
    sidebarBackground: Color(0xEBE7E7E7),
    groupedBackground: Color(0xFFF2F1F6),
    cardBackground: Color(0xFFFFFFFF),
    divider: Color(0x14000000),
    glassFill: Color(0xB8FAFAFA),
    glassBorder: Color(0x59FFFFFF),
    glassHighlight: Color(0x40FFFFFF),
    selection: Color(0x2E007AFF),
    shadow: Color(0x33000000),
    desktopGradientStart: Color(0xFF7EC8E3),
    desktopGradientMid: Color(0xFFE8C99B),
    desktopGradientEnd: Color(0xFFC98D5E),
    dockFill: Color(0x61FFFFFF),
    isDark: false,
    isOled: false,
  );

  static const dark = OasisPalette(
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x330A84FF),
    textPrimary: Color(0xF2FFFFFF),
    textSecondary: Color(0x99EBEBF5),
    textTertiary: Color(0x4DEBEBF5),
    windowBackground: Color(0xF5322C2E),
    sidebarBackground: Color(0xEB27252A),
    groupedBackground: Color(0xFF1C1B1E),
    cardBackground: Color(0xFF2C2B2E),
    divider: Color(0x1FFFFFFF),
    glassFill: Color(0x8C2D2C2F),
    glassBorder: Color(0x40FFFFFF),
    glassHighlight: Color(0x1FFFFFFF),
    selection: Color(0x4D0A84FF),
    shadow: Color(0x66000000),
    desktopGradientStart: Color(0xFF1B2A4A),
    desktopGradientMid: Color(0xFF46324A),
    desktopGradientEnd: Color(0xFF6B3B2E),
    dockFill: Color(0x40FFFFFF),
    isDark: true,
    isOled: false,
  );

  static const oled = OasisPalette(
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x330A84FF),
    textPrimary: Color(0xF2FFFFFF),
    textSecondary: Color(0x99EBEBF5),
    textTertiary: Color(0x4DEBEBF5),
    windowBackground: Color(0xF5000000),
    sidebarBackground: Color(0xEB000000),
    groupedBackground: Color(0xFF000000),
    cardBackground: Color(0xFF161617),
    divider: Color(0x26FFFFFF),
    glassFill: Color(0x73000000),
    glassBorder: Color(0x33FFFFFF),
    glassHighlight: Color(0x1AFFFFFF),
    selection: Color(0x590A84FF),
    shadow: Color(0xB3000000),
    desktopGradientStart: Color(0xFF05070F),
    desktopGradientMid: Color(0xFF0E0B14),
    desktopGradientEnd: Color(0xFF140A08),
    dockFill: Color(0x2EFFFFFF),
    isDark: true,
    isOled: true,
  );

  static OasisPalette of(OasisThemeMode mode, {required bool platformDark}) {
    switch (mode) {
      case OasisThemeMode.system:
        return platformDark ? dark : light;
      case OasisThemeMode.light:
        return light;
      case OasisThemeMode.dark:
        return dark;
      case OasisThemeMode.oled:
        return oled;
    }
  }
}
