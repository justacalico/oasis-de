import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

const kMenuBarHeight = 30.0;

class ShellMenuBar extends StatelessWidget {
  const ShellMenuBar({
    super.key,
    required this.controller,
    required this.menus,
  });

  final ShellController controller;
  final List<ShellMenu> menus;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w500,
          fontSize: 13,
          shadows: [
            const Shadow(
                color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        );

    return SizedBox(
      height: kMenuBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.water_drop,
                size: 15, color: Color(0xFFFFFFFF)),
            const SizedBox(width: 10),
            for (var i = 0; i < menus.length; i++) ...[
              _MenuLabel(
                label: menus[i].label,
                bold: i == 0,
                open: controller.openMenu == menus[i].label,
                style: textStyle,
                onTap: () => controller.selectMenu(
                    controller.openMenu == menus[i].label
                        ? null
                        : menus[i].label),
                onHover: () {
                  if (controller.openMenu != null &&
                      controller.openMenu != menus[i].label) {
                    controller.selectMenu(menus[i].label);
                  }
                },
              ),
              const SizedBox(width: 2),
            ],
            const Spacer(),
            _StatusIcon(
              icon: Icons.search,
              onTap: controller.toggleLauncher,
              style: textStyle,
            ),
            _StatusIcon(
              icon: controller.wifiOn ? Icons.wifi : Icons.wifi_off,
              onTap: controller.toggleControlCenter,
              style: textStyle,
            ),
            _StatusIcon(
              icon: Icons.battery_full,
              onTap: () {},
              style: textStyle,
            ),
            _StatusIcon(
              icon: Icons.tune,
              onTap: controller.toggleControlCenter,
              style: textStyle,
            ),
            const SizedBox(width: 6),
            _MenuClock(style: textStyle),
          ],
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
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final effective = bold
        ? style?.copyWith(fontWeight: FontWeight.w700)
        : style;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
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
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.icon,
    required this.onTap,
    required this.style,
  });

  final IconData icon;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Icon(icon, size: 15, color: style?.color),
      ),
    );
  }
}

class _MenuClock extends StatefulWidget {
  const _MenuClock({this.style});

  final TextStyle? style;

  @override
  State<_MenuClock> createState() => _MenuClockState();
}

class _MenuClockState extends State<_MenuClock> {
  late DateTime _now;
  late final StreamSubscription _timer;

  @override
  void initState() {
    super.initState();
    _now = clock.now();
    _timer = Stream.periodic(const Duration(seconds: 15)).listen((_) {
      if (mounted) setState(() => _now = clock.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final text = DateFormat('E d MMM  HH:mm', locale).format(_now);
    return Text(text, style: widget.style);
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
              _MenuEntry(item: item, controller: controller),
              if (item.separatorAfter)
                Divider(
                    height: 9,
                    thickness: 0.5,
                    indent: 12,
                    endIndent: 12,
                    color: style.palette.divider),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _MenuEntry extends StatefulWidget {
  const _MenuEntry({required this.item, required this.controller});

  final ShellMenuItem item;
  final ShellController controller;

  @override
  State<_MenuEntry> createState() => _MenuEntryState();
}

class _MenuEntryState extends State<_MenuEntry> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final enabled = widget.item.enabled;
    final color = !enabled
        ? p.textTertiary
        : _hovered
            ? const Color(0xFFFFFFFF)
            : p.textPrimary;
    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                widget.controller.selectMenu(null);
                widget.item.action?.call(context);
              }
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: _hovered ? p.accent : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              widget.item.label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}
