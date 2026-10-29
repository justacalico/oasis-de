import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

const kDockIconSize = 52.0;

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

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final c = widget.controller;
    final minimized = c.windows
        .where((w) =>
            w.minimized ||
            w.transition != ShellWindowTransition.none)
        .toList(growable: false);
    final running = {for (final w in c.windows) w.app.id};

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: p.dockFill,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final app in c.apps)
                    _DockIcon(
                      app: app,
                      running: running.contains(app.id),
                      measure: _sizeAt,
                      onTap: () => c.openApp(app),
                    ),
                  if (minimized.isNotEmpty)
                    Container(
                      width: 1,
                      height: kDockIconSize * 0.8,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: p.glassBorder,
                    ),
                  for (final w in minimized)
                    _DockIcon(
                      key: w.dockIconKey,
                      app: w.app,
                      running: true,
                      measure: _sizeAt,
                      onTap: () => c.restoreWindow(w.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    super.key,
    required this.app,
    required this.running,
    required this.measure,
    required this.onTap,
  });

  final OasisApp app;
  final bool running;
  final double Function(double centerX) measure;
  final VoidCallback onTap;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: app.name,
                preferBelow: false,
                child: GestureDetector(
                  onTap: onTap,
                  child: SizedBox(
                    width: s,
                    height: s,
                    child: OasisAppIcon(
                      icon: app.icon,
                      colors: app.iconColors,
                      size: s,
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
        );
      },
    );
  }
}
