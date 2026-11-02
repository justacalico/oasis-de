import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'context_menu.dart';
import 'minute_clock.dart';
import 'shell_controller.dart';
import 'view_scale.dart';
import 'wifi_menu.dart';


class ShellMenuBar extends StatelessWidget {
  const ShellMenuBar({
    super.key,
    required this.controller,
    required this.menus,
  });

  final ShellController controller;
  final List<ShellMenu> menus;

  Rect? _logicalAnchor(BuildContext context, Rect? global) {
    if (global == null) return null;
    final k = ViewScale.of(context);
    return global.topLeft / k & global.size / k;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: const Color(0xFFFFFFFF),
      fontWeight: FontWeight.w500,
      fontSize: 13,
      shadows: [
        const Shadow(
          color: Color(0x66000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    );

    final p = OasisStyle.of(context).palette;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: kMenuBarHeight,
          color: p.glassFill.withValues(alpha: 0.55),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (menus.isNotEmpty)
                  GestureDetector(
                    onTap: () => controller.selectMenu(
                      controller.openMenu == menus[0].label
                          ? null
                          : menus[0].label,
                    ),
                    child: const Icon(
                      Icons.water_drop,
                      size: 15,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < menus.length; i++) ...[
                          _MenuLabel(
                            label: menus[i].label,
                            bold: i == 0,
                            open: controller.openMenu == menus[i].label,
                            style: textStyle,
                            onTap: (anchor) => controller.selectMenu(
                              controller.openMenu == menus[i].label
                                  ? null
                                  : menus[i].label,
                              anchor: _logicalAnchor(context, anchor),
                            ),
                            onHover: (anchor) {
                              if (controller.openMenu != null &&
                                  controller.openMenu != menus[i].label) {
                                controller.selectMenu(
                                  menus[i].label,
                                  anchor: _logicalAnchor(context, anchor),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 2),
                        ],
                      ],
                    ),
                  ),
                ),
                _StatusIcon(
                  icon: Icons.search,
                  onTap: controller.toggleLauncher,
                  style: textStyle,
                  tooltip: l10n.launcherHint,
                ),
                _WifiMenu(controller: controller, style: textStyle),
                if (controller.batteryLevel != null)
                  _StatusIcon(
                    icon: controller.batteryCharging
                        ? Icons.battery_charging_full
                        : switch ((controller.batteryLevel! * 10).round()) {
                            <= 2 => Icons.battery_1_bar,
                            <= 4 => Icons.battery_3_bar,
                            <= 6 => Icons.battery_4_bar,
                            <= 8 => Icons.battery_6_bar,
                            _ => Icons.battery_full,
                          },
                    onTap: controller.toggleControlCenter,
                    style: textStyle,
                    tooltip: l10n.ccBattery,
                  ),
                _StatusIcon(
                  icon: Icons.tune,
                  onTap: controller.toggleControlCenter,
                  style: textStyle,
                  tooltip: l10n.tipControlCenter,
                ),
                _StatusIcon(
                  icon: controller.notifications.isEmpty
                      ? Icons.notifications_none
                      : Icons.notifications,
                  onTap: controller.toggleNotificationCenter,
                  style: textStyle,
                  tooltip: l10n.notifCenter,
                ),
                _SessionMenu(controller: controller, style: textStyle),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: controller.toggleNotificationCenter,
                  child: MinuteClock(
                    builder: (context, now) {
                      final locale =
                          Localizations.localeOf(context).toString();
                      final text =
                          '${DateFormat.MEd(locale).format(now)} '
                          '${DateFormat.jm(locale).format(now)}';
                      return Text(text, style: textStyle);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({
    required this.label,
    required this.bold,
    required this.open,
    required this.style,
    required this.onTap,
    required this.onHover,
  });

  final String label;
  final bool bold;
  final bool open;
  final TextStyle? style;
  final ValueChanged<Rect?> onTap;
  final ValueChanged<Rect?> onHover;

  Rect? _anchor(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final effective = bold
        ? style?.copyWith(fontWeight: FontWeight.w700)
        : style;
    return MouseRegion(
      onEnter: (_) => onHover(_anchor(context)),
      child: GestureDetector(
        onTap: () => onTap(_anchor(context)),
        child: Semantics(
          button: true,
          label: label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: open
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.25)
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label, style: effective),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.icon,
    required this.onTap,
    required this.style,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final TextStyle? style;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tip = tooltip;
    final iconWidget = Semantics(
      button: true,
      label: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Icon(icon, size: 15, color: style?.color),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: tip == null
          ? iconWidget
          : OasisTooltip(message: tip, child: iconWidget),
    );
  }
}

class MenuDropdown extends StatelessWidget {
  const MenuDropdown({
    super.key,
    required this.menuIndex,
    required this.menus,
    required this.controller,
  });

  final int menuIndex;
  final List<ShellMenu> menus;
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final items = menus[menuIndex].items(context);
    return OasisGlass(
      borderRadius: style.menuRadius,
      blur: 36,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 210),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) ...[
                OasisMenuEntry(
                  item: item,
                  onSelect: () => controller.selectMenu(null),
                ),
                if (item.separatorAfter)
                  Divider(
                    height: 9,
                    thickness: 0.5,
                    indent: 12,
                    endIndent: 12,
                    color: style.palette.divider,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WifiMenu extends StatelessWidget {
  const _WifiMenu({required this.controller, required this.style});

  final ShellController controller;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final c = controller;
    return _StatusIcon(
      icon: c.wifiOn ? Icons.wifi : Icons.wifi_off,
      style: style,
      tooltip: l10n.ccWifi,
      onTap: () {
        final box = context.findRenderObject()! as RenderBox;
        final pos = box.localToGlobal(Offset(0, box.size.height + 4));
        showWifiMenu(context, pos, c);
      },
    );
  }
}

class _SessionMenu extends StatelessWidget {
  const _SessionMenu({required this.controller, required this.style});

  final ShellController controller;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final c = controller;
    return _StatusIcon(
      icon: Icons.power_settings_new,
      style: style,
      tooltip: l10n.sessionShutDown,
      onTap: () {
        final box = context.findRenderObject()! as RenderBox;
        final pos = box.localToGlobal(Offset(0, box.size.height + 4));
        void confirm(String message, String label, OasisSessionAction action) =>
            confirmShellAction(
              context,
              message: message,
              cancelLabel: l10n.dialogCancel,
              confirmLabel: label,
              onConfirm: () => c.session(action),
            );
        showShellContextMenu(context, pos, [
          ShellMenuItem(
            label: l10n.sessionLock,
            action: (_) => c.session(OasisSessionAction.lock),
          ),
          ShellMenuItem(
            label: l10n.sessionLogOut,
            action: (ctx) => confirm(
              l10n.sessionConfirmLogOut,
              l10n.sessionLogOut,
              OasisSessionAction.logout,
            ),
          ),
          ShellMenuItem(
            label: l10n.sessionSleep,
            action: (ctx) => confirm(
              l10n.sessionConfirmSuspend,
              l10n.sessionSleep,
              OasisSessionAction.suspend,
            ),
          ),
          ShellMenuItem(
            label: l10n.sessionRestart,
            action: (ctx) => confirm(
              l10n.sessionConfirmRestart,
              l10n.sessionRestart,
              OasisSessionAction.reboot,
            ),
          ),
          ShellMenuItem(
            label: l10n.sessionShutDown,
            action: (ctx) => confirm(
              l10n.sessionConfirmPoweroff,
              l10n.sessionShutDown,
              OasisSessionAction.poweroff,
            ),
          ),
        ]);
      },
    );
  }
}
