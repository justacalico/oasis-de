import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'context_menu.dart';
import 'shell_controller.dart';

OasisApp appGridEntry(OasisLocalizations l10n, OasisPalette palette) =>
    OasisApp(
      id: 'launch-pad',
      name: l10n.appGrid,
      icon: Icons.rocket_launch,
      iconColors: [
        palette.accent,
        Color.lerp(palette.accent, const Color(0xFF000000), 0.35)!,
      ],
      builder: (_) => const SizedBox.shrink(),
    );

class ShellDash extends StatefulWidget {
  const ShellDash({
    super.key,
    required this.controller,
    this.iconSize = kDashIconSize,
    this.position = OasisDashPosition.bottom,
  });

  final ShellController controller;
  final double iconSize;
  final OasisDashPosition position;

  bool get vertical => position != OasisDashPosition.bottom;

  @override
  State<ShellDash> createState() => _ShellDashState();
}

class _ShellDashState extends State<ShellDash>
    with SingleTickerProviderStateMixin {
  double? _pointer;
  late final AnimationController _magnify = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _magnify.dispose();
    super.dispose();
  }

  double _sizeAt(double center) {
    final px = _pointer;
    final base = widget.iconSize;
    if (px == null) return base;
    final range = base * 2.1;
    final d = (px - center).abs();
    if (d >= range) return base;
    final falloff = 1 - d / range;
    return base + base * 0.38 * falloff * falloff * _magnify.value;
  }

  Widget _dashMenu(
    BuildContext context,
    Widget child,
    OasisApp app, {
    required bool pinned,
  }) {
    final l10n = OasisLocalizations.of(context);
    final c = widget.controller;
    final appWindows = [
      for (final w in c.windows)
        if (w.app.id == app.id) w,
    ];
    final canPin = c.apps.any((a) => a.id == app.id);
    return GestureDetector(
      onSecondaryTapUp: (e) => showShellContextMenu(
        context,
        e.globalPosition,
        [
          for (final w in appWindows)
            ShellMenuItem(
              label: w.displayTitle,
              checked: c.focusedId == w.id,
              action: (_) =>
                  w.minimized ? c.restoreWindow(w.id) : c.focusWindow(w.id),
              separatorAfter: w == appWindows.last,
            ),
          for (final a in app.actions)
            ShellMenuItem(
              label: a.name,
              action: (_) => c.launchAction(a.exec),
              separatorAfter: a == app.actions.last,
            ),
          if (canPin)
            ShellMenuItem(
              label: pinned ? l10n.dashUnpin : l10n.dashPin,
              action: (_) =>
                  pinned ? c.unpinApp(app.id) : c.pinApp(app.id),
              separatorAfter: appWindows.isNotEmpty,
            ),
          if (appWindows.isNotEmpty)
            ShellMenuItem(
              label: l10n.dashQuit,
              action: (_) {
                for (final w in appWindows) {
                  c.closeWindow(w.id);
                }
              },
            ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final c = widget.controller;
    final vertical = widget.vertical;
    final pinnedIds = {for (final a in c.pinned) a.id};
    final minimized = c.windows
        .where((w) => w.minimized && !pinnedIds.contains(w.app.id))
        .toList(growable: false);
    final running = {for (final w in c.windows) w.app.id};
    final launching = {
      for (final w in c.windows)
        if (w.launching) w.app.id,
    };
    final pinnedMinimizedKeys = {
      for (final w in c.windows)
        if ((w.minimized || w.transition != ShellWindowTransition.none) &&
            pinnedIds.contains(w.app.id))
          w.app.id: w.dashIconKey,
    };
    final unpinnedRunning = <ShellWindowData>[];
    final seenRunning = <String>{};
    for (final w in c.windows) {
      if (w.minimized || pinnedIds.contains(w.app.id)) continue;
      if (seenRunning.add(w.app.id)) unpinnedRunning.add(w);
    }

    final icons = <Widget>[
      _DashIcon(
        app: appGridEntry(l10n, p),
        running: c.appGridOpen,
        measure: _sizeAt,
        size: widget.iconSize,
        position: widget.position,
        onTap: c.toggleAppGrid,
      ),
      _DashDivider(length: widget.iconSize * 0.8, vertical: vertical),
      for (final app in c.pinned)
        DragTarget<OasisApp>(
          onAcceptWithDetails: (d) => c.movePinned(d.data.id, app.id),
          builder: (_, _, _) => LongPressDraggable<OasisApp>(
            data: app,
            feedback: Material(
              type: MaterialType.transparency,
              child: _DashIcon(
                app: app,
                running: false,
                measure: _sizeAt,
                size: widget.iconSize,
                position: widget.position,
                onTap: null,
              ),
            ),
            child: _dashMenu(
              context,
              _DashIcon(
                key: pinnedMinimizedKeys[app.id],
                triggerMode: TooltipTriggerMode.manual,
                app: app,
                running: running.contains(app.id),
                bouncing: launching.contains(app.id),
                measure: _sizeAt,
                size: widget.iconSize,
                position: widget.position,
                onTap: () => c.openApp(app),
              ),
              app,
              pinned: true,
            ),
          ),
        ),
      for (final w in unpinnedRunning)
        _dashMenu(
          context,
          _DashIcon(
            app: w.app,
            running: true,
            bouncing: launching.contains(w.app.id),
            measure: _sizeAt,
            size: widget.iconSize,
            position: widget.position,
            onTap: () => c.focusWindow(w.id),
          ),
          w.app,
          pinned: pinnedIds.contains(w.app.id),
        ),
      if (minimized.isNotEmpty)
        _DashDivider(length: widget.iconSize * 0.8, vertical: vertical),
      for (final w in minimized)
        _dashMenu(
          context,
          _DashIcon(
            key: w.dashIconKey,
            app: w.app,
            running: true,
            bouncing: launching.contains(w.app.id),
            measure: _sizeAt,
            size: widget.iconSize,
            position: widget.position,
            onTap: () => c.restoreWindow(w.id),
          ),
          w.app,
          pinned: pinnedIds.contains(w.app.id),
        ),
    ];

    return MouseRegion(
      onHover: (e) {
        setState(() => _pointer = vertical ? e.position.dy : e.position.dx);
        _magnify.forward();
      },
      onExit: (_) => _magnify.reverse(),
      child: Container(
        margin: switch (widget.position) {
          OasisDashPosition.left => const EdgeInsets.only(left: 10),
          OasisDashPosition.right => const EdgeInsets.only(right: 10),
          OasisDashPosition.bottom => const EdgeInsets.only(bottom: 10),
        },
        padding: vertical
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.glassBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(color: p.dashFill),
                ),
              ),
            ),
            Padding(
              padding: vertical
                  ? const EdgeInsets.symmetric(horizontal: 2, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Flex(
                direction: vertical ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: vertical
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.end,
                children: icons,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashDivider extends StatelessWidget {
  const _DashDivider({required this.length, required this.vertical});

  final double length;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      width: vertical ? length : 1,
      height: vertical ? 1 : length,
      margin: vertical
          ? const EdgeInsets.symmetric(vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 8),
      color: p.glassBorder,
    );
  }
}

class _DashIcon extends StatelessWidget {
  const _DashIcon({
    super.key,
    required this.app,
    required this.running,
    required this.measure,
    this.bouncing = false,
    this.size = kDashIconSize,
    this.position = OasisDashPosition.bottom,
    this.onTap,
    this.triggerMode,
  });

  final OasisApp app;
  final bool running;
  final bool bouncing;
  final double Function(double center) measure;
  final double size;
  final OasisDashPosition position;
  final VoidCallback? onTap;
  final TooltipTriggerMode? triggerMode;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final vertical = position != OasisDashPosition.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        var s = size;
        final box = context.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          final origin = box.localToGlobal(Offset.zero);
          s = measure(
            vertical
                ? origin.dy + box.size.height / 2
                : origin.dx + box.size.width / 2,
          );
        }
        final peak = switch (position) {
          OasisDashPosition.bottom => Offset(0, -size * 0.55),
          OasisDashPosition.left => Offset(size * 0.55, 0),
          OasisDashPosition.right => Offset(-size * 0.55, 0),
        };
        final icon = _DashBounce(
          active: bouncing,
          peak: peak,
          child: OasisTooltip(
            message: app.name,
            preferBelow: false,
            triggerMode: triggerMode,
            child: GestureDetector(
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Transform.scale(
                  scale: s / size,
                  alignment: switch (position) {
                    OasisDashPosition.left => Alignment.centerLeft,
                    OasisDashPosition.right => Alignment.centerRight,
                    OasisDashPosition.bottom => Alignment.bottomCenter,
                  },
                  child: OasisAppIcon(
                    icon: app.icon,
                    colors: app.iconColors,
                    iconPath: app.iconPath,
                    size: size,
                  ),
                ),
              ),
            ),
          ),
        );
        final dot = AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: running ? 1 : 0,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.isDark
                  ? const Color(0xFFFFFFFF)
                  : const Color(0x99000000),
            ),
          ),
        );
        return Padding(
          padding: vertical
              ? const EdgeInsets.symmetric(vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            label: app.name,
            child: switch (position) {
              OasisDashPosition.bottom => Column(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(height: 3), dot],
              ),
              OasisDashPosition.left => Row(
                mainAxisSize: MainAxisSize.min,
                children: [dot, const SizedBox(width: 3), icon],
              ),
              OasisDashPosition.right => Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(width: 3), dot],
              ),
            },
          ),
        );
      },
    );
  }
}

class _DashBounce extends StatefulWidget {
  const _DashBounce({
    required this.active,
    required this.peak,
    required this.child,
  });

  final bool active;
  final Offset peak;
  final Widget child;

  @override
  State<_DashBounce> createState() => _DashBounceState();
}

class _DashBounceState extends State<_DashBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  static final _rise = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 55,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.active) _hop.repeat();
  }

  @override
  void didUpdateWidget(_DashBounce old) {
    super.didUpdateWidget(old);
    if (widget.active && !_hop.isAnimating) {
      _hop.repeat();
    } else if (!widget.active && _hop.isAnimating) {
      _hop.animateTo(
        0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeIn,
      );
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hop,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: widget.peak * _rise.evaluate(_hop),
        child: child,
      ),
    );
  }
}
