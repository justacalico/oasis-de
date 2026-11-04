import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

/// Full-screen region picker for the snipping tool. Everything outside
/// the dragged selection is dimmed; releasing a real selection hands
/// it to [ShellController.completeSnip], a click or right-click leaves
/// snip mode alone, and Escape cancels through the dismiss keybind.
class SnipOverlay extends StatefulWidget {
  const SnipOverlay({super.key, required this.controller});

  final ShellController controller;

  /// Selections smaller than this are treated as stray clicks.
  static const minSelection = 4.0;

  @override
  State<SnipOverlay> createState() => _SnipOverlayState();
}

class _SnipOverlayState extends State<SnipOverlay> {
  Offset? _start;
  Offset? _current;

  Rect? get _selection {
    final start = _start, current = _current;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  Offset _clamp(Offset pos) {
    final size = MediaQuery.sizeOf(context);
    return Offset(
      pos.dx.clamp(0.0, size.width),
      pos.dy.clamp(0.0, size.height),
    );
  }

  void _update(Offset pos) => setState(() => _current = _clamp(pos));

  @override
  Widget build(BuildContext context) {
    final l10n = OasisLocalizations.of(context);
    final p = OasisStyle.of(context).palette;
    final sel = _selection;
    // Taking keyboard focus means Escape cancels the snip even when a
    // window was focused before it opened.
    return Focus(
      autofocus: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (e.buttons & kSecondaryButton != 0) {
              widget.controller.cancelSnip();
              return;
            }
            setState(() {
              _start = _clamp(e.localPosition);
              _current = _start;
            });
          },
          onPointerMove: (e) {
            if (_start != null) _update(e.localPosition);
          },
          onPointerUp: (_) {
            final sel = _selection;
            setState(() {
              _start = null;
              _current = null;
            });
            if (sel != null &&
                sel.width >= SnipOverlay.minSelection &&
                sel.height >= SnipOverlay.minSelection) {
              widget.controller.completeSnip(sel);
            }
          },
          onPointerCancel: (_) => setState(() {
            _start = null;
            _current = null;
          }),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SnipPainter(selection: sel, accent: p.accent),
                ),
              ),
              if (sel != null)
                Positioned(
                  left: (sel.right - 64).clamp(
                    0.0,
                    MediaQuery.sizeOf(context).width - 64,
                  ),
                  top: sel.bottom + 8 <= MediaQuery.sizeOf(context).height - 40
                      ? sel.bottom + 8
                      : sel.top - 34,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: p.cardBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${sel.width.round()} × ${sel.height.round()}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              if (sel == null)
                Positioned(
                  bottom: 48,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: p.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.screenshotHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnipPainter extends CustomPainter {
  const _SnipPainter({required this.selection, required this.accent});

  final Rect? selection;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0x59000000);
    final sel = selection;
    if (sel == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(sel),
      ),
      dim,
    );
    canvas.drawRect(
      sel,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SnipPainter old) =>
      old.selection != selection || old.accent != accent;
}
