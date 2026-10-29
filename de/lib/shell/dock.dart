import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'context_menu.dart';
import 'shell_controller.dart';

const kDockIconSize = 52.0;

OasisApp launchPadEntry(OasisLocalizations l10n, OasisPalette palette) =>
    OasisApp(
      id: 'launch-pad',
      name: l10n.launchPad,
      icon: Icons.rocket_launch,
      iconColors: [
        palette.accent,
        Color.lerp(palette.accent, const Color(0xFF000000), 0.35)!,
      ],
      builder: (_) => const SizedBox.shrink(),
    );

class ShellDock extends StatefulWidget {
  const ShellDock({super.key, required this.controller});

  final ShellController controller;

  @override
  State<ShellDock> createState() => _ShellDockState();
}

class _ShellDockState extends State<ShellDock> {
  double? _pointerX;

  static const _maxBoost = 20.0;
  static const _range = 110.0;

  double _sizeAt(double centerX) {
    final px = _pointerX;
    if (px == null) return kDockIconSize;
    final d = (px - centerX).abs();
    if (d >= _range) return kDockIconSize;
    final falloff = 1 - d / _range;
    return kDockIconSize + _maxBoost * falloff * falloff;
  }

  Widget _dockMenu(
    BuildContext context,
    Widget child,
    OasisApp app, {
    required bool pinned,
  }) {
    final l10n = OasisLocalizations.of(context);
    final c = widget.controller;
    return GestureDetector(
      onSecondaryTapUp: (e) => showShellContextMenu(
        context,
        e.globalPosition,
        [
          ShellMenuItem(
            label: pinned ? l10n.dockUnpin : l10n.dockPin,
            action: (_) => pinned ? c.unpinApp(app.id) : c.pinApp(app.id),
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
    final pinnedIds = {for (final a in c.pinned) a.id};
    final minimized = c.windows
        .where((w) => w.minimized && !pinnedIds.contains(w.app.id))
        .toList(growable: false);
    final running = {for (final w in c.windows) w.app.id};
    final pinnedMinimizedKeys = {
      for (final w in c.windows)
        if ((w.minimized || w.transition != ShellWindowTransition.none) &&
            pinnedIds.contains(w.app.id))
          w.app.id: w.dockIconKey,
    };
    final unpinnedRunning = <ShellWindowData>[];
    final seenRunning = <String>{};
    for (final w in c.windows) {
      if (w.minimized || pinnedIds.contains(w.app.id)) continue;
      if (seenRunning.add(w.app.id)) unpinnedRunning.add(w);
    }

    return MouseRegion(
      onHover: (e) => setState(() => _pointerX = e.position.dx),
      onExit: (_) => setState(() => _pointerX = null),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  child: Container(color: p.dockFill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _DockIcon(
                    app: launchPadEntry(l10n, p),
                    running: c.launchPadOpen,
                    measure: _sizeAt,
                    onTap: c.toggleLaunchPad,
                  ),
                  const _DockDivider(),
                  for (final app in c.pinned)
                    DragTarget<OasisApp>(
                      onAcceptWithDetails: (d) =>
                          c.movePinned(d.data.id, app.id),
                      builder: (_, _, _) => LongPressDraggable<OasisApp>(
                        data: app,
                        feedback: Material(
                          type: MaterialType.transparency,
                          child: _DockIcon(
                            app: app,
                            running: false,
                            measure: _sizeAt,
                            onTap: null,
                          ),
                        ),
                        child: _dockMenu(
                          context,
                          _DockIcon(
                            key: pinnedMinimizedKeys[app.id],
                            triggerMode: TooltipTriggerMode.manual,
                            app: app,
                            running: running.contains(app.id),
                            measure: _sizeAt,
                            onTap: () => c.openApp(app),
                          ),
                          app,
                          pinned: true,
                        ),
                      ),
                    ),
                  for (final w in unpinnedRunning)
                    _dockMenu(
                      context,
                      _DockIcon(
                        app: w.app,
                        running: true,
                        measure: _sizeAt,
                        onTap: () => c.focusWindow(w.id),
                      ),
                      w.app,
                      pinned: pinnedIds.contains(w.app.id),
                    ),
                  if (minimized.isNotEmpty) const _DockDivider(),
                  for (final w in minimized)
                    _dockMenu(
                      context,
                      _DockIcon(
                        key: w.dockIconKey,
                        app: w.app,
                        running: true,
                        measure: _sizeAt,
                        onTap: () => c.restoreWindow(w.id),
                      ),
                      w.app,
                      pinned: pinnedIds.contains(w.app.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Container(
      width: 1,
      height: kDockIconSize * 0.8,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: p.glassBorder,
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    super.key,
    required this.app,
    required this.running,
    required this.measure,
    this.onTap,
    this.triggerMode,
  });

  final OasisApp app;
  final bool running;
  final double Function(double centerX) measure;
  final VoidCallback? onTap;
  final TooltipTriggerMode? triggerMode;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        var s = kDockIconSize;
        final box = context.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          s = measure(box.localToGlobal(Offset.zero).dx + box.size.width / 2);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            label: app.name,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: app.name,
                  preferBelow: false,
                  triggerMode: triggerMode,
                  child: GestureDetector(
                    onTap: onTap,
                    child: SizedBox(
                      width: kDockIconSize,
                      height: kDockIconSize,
                      child: Transform.scale(
                        scale: s / kDockIconSize,
                        alignment: Alignment.bottomCenter,
                        child: OasisAppIcon(
                          icon: app.icon,
                          colors: app.iconColors,
                          iconPath: app.iconPath,
                          size: kDockIconSize,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedOpacity(
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
