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

  /// User-chosen order for unpinned icons (running and minimized),
  /// keyed by app id. Pinned order lives on the controller instead.
  final _unpinnedOrder = <String>[];

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
    final range = base * 2.3;
    final d = (px - center).abs();
    if (d >= range) return base;
    final falloff = 1 - d / range;
    return base + base * 0.5 * falloff * falloff * _magnify.value;
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
      onSecondaryTapUp: (e) => showShellContextMenu(context, e.globalPosition, [
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
            action: (_) => pinned ? c.unpinApp(app.id) : c.pinApp(app.id),
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
      ]),
      child: child,
    );
  }

  void _acceptDashDrag(OasisApp dragged, OasisApp target) {
    if (dragged.id == target.id) return;
    final c = widget.controller;
    final dragPinned = c.pinned.any((a) => a.id == dragged.id);
    final targetPinned = c.pinned.any((a) => a.id == target.id);
    if (targetPinned) {
      if (dragPinned) {
        c.movePinned(dragged.id, target.id);
      } else {
        c.pinApp(dragged.id, beforeId: target.id);
      }
      return;
    }
    if (dragPinned) {
      c.movePinned(dragged.id, c.pinned.last.id);
      return;
    }
    setState(() {
      final to = _unpinnedOrder.indexOf(target.id);
      _unpinnedOrder.remove(dragged.id);
      _unpinnedOrder.insert(to, dragged.id);
    });
  }

  Widget _draggable(OasisApp app, Widget child) => DragTarget<OasisApp>(
    onAcceptWithDetails: (d) => _acceptDashDrag(d.data, app),
    builder: (_, _, _) => Draggable<OasisApp>(
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
      child: child,
    ),
  );

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

    final unpinnedIds = <String>{
      for (final w in unpinnedRunning) w.app.id,
      for (final w in minimized) w.app.id,
    };
    _unpinnedOrder.removeWhere((id) => !unpinnedIds.contains(id));
    for (final id in unpinnedIds) {
      if (!_unpinnedOrder.contains(id)) _unpinnedOrder.add(id);
    }
    int byOrder(ShellWindowData a, ShellWindowData b) => _unpinnedOrder
        .indexOf(a.app.id)
        .compareTo(_unpinnedOrder.indexOf(b.app.id));
    unpinnedRunning.sort(byOrder);
    minimized.sort(byOrder);

    final icons = <Widget>[
      _DashIcon(
        app: appGridEntry(l10n, p),
        running: c.appGridOpen,
        measure: _sizeAt,
        size: widget.iconSize,
        position: widget.position,
        onTap: c.toggleAppGrid,
      ),
      _DashDivider(size: widget.iconSize, position: widget.position),
      for (final app in c.pinned)
        _draggable(
          app,
          _dashMenu(
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
      for (final w in unpinnedRunning)
        _draggable(
          w.app,
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
        ),
      if (minimized.isNotEmpty)
        _DashDivider(size: widget.iconSize, position: widget.position),
      for (final w in minimized)
        _draggable(
          w.app,
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
        ),
    ];

    final radius = widget.iconSize * 0.42;
    return MouseRegion(
      onHover: (e) {
        setState(() => _pointer = vertical ? e.position.dy : e.position.dx);
        _magnify.forward();
      },
      onExit: (_) => _magnify.reverse(),
      child: Padding(
        padding: switch (widget.position) {
          OasisDashPosition.left => EdgeInsets.only(
            right: widget.iconSize * 0.6,
          ),
          OasisDashPosition.right => EdgeInsets.only(
            left: widget.iconSize * 0.6,
          ),
          OasisDashPosition.bottom => EdgeInsets.only(
            top: widget.iconSize * 0.6,
          ),
        },
        child: Container(
          margin: switch (widget.position) {
            OasisDashPosition.left => const EdgeInsets.only(left: 8),
            OasisDashPosition.right => const EdgeInsets.only(right: 8),
            OasisDashPosition.bottom => const EdgeInsets.only(bottom: 8),
          },
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
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
                  borderRadius: BorderRadius.circular(radius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(color: p.dashFill),
                  ),
                ),
              ),
              Flex(
                direction: vertical ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: vertical
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.end,
                children: icons,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashDivider extends StatelessWidget {
  const _DashDivider({required this.size, required this.position});

  final double size;
  final OasisDashPosition position;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    const strip = _DashIcon.dotStrip;
    final line = Container(
      width: position == OasisDashPosition.bottom ? 1 : size * 0.8,
      height: position == OasisDashPosition.bottom ? size * 0.8 : 1,
      color: p.glassBorder,
    );
    return Padding(
      padding: switch (position) {
        OasisDashPosition.left => const EdgeInsets.symmetric(vertical: 6),
        OasisDashPosition.right => const EdgeInsets.symmetric(vertical: 6),
        OasisDashPosition.bottom => const EdgeInsets.symmetric(horizontal: 6),
      },
      child: SizedBox(
        width: position == OasisDashPosition.bottom ? null : size + strip,
        height: position == OasisDashPosition.bottom ? size + strip : null,
        child: Padding(
          padding: switch (position) {
            OasisDashPosition.left => const EdgeInsets.only(left: strip),
            OasisDashPosition.right => const EdgeInsets.only(right: strip),
            OasisDashPosition.bottom => const EdgeInsets.only(bottom: strip),
          },
          child: Center(child: line),
        ),
      ),
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

  /// Space below the icon (or beside it, on vertical dashes) holding the
  /// running dot. Magnified icons grow past the panel edge instead of
  /// stretching it, so this strip stays put.
  static const dotStrip = 8.0;

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
              child: OasisAppIcon(
                icon: app.icon,
                colors: app.iconColors,
                iconPath: app.iconPath,
                size: s,
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
        final slot = switch (position) {
          OasisDashPosition.bottom => SizedBox(
            width: s,
            height: size + dotStrip,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(bottom: dotStrip, child: icon),
                Positioned(bottom: 2, child: dot),
              ],
            ),
          ),
          OasisDashPosition.left => SizedBox(
            width: size + dotStrip,
            height: s,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Positioned(left: dotStrip, child: icon),
                Positioned(left: 2, child: dot),
              ],
            ),
          ),
          OasisDashPosition.right => SizedBox(
            width: size + dotStrip,
            height: s,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerRight,
              children: [
                Positioned(right: dotStrip, child: icon),
                Positioned(right: 2, child: dot),
              ],
            ),
          ),
        };
        return Padding(
          padding: vertical
              ? const EdgeInsets.symmetric(vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(button: true, label: app.name, child: slot),
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
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInCubic)),
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
