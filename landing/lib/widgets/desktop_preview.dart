import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

class DesktopPreview extends StatelessWidget {
  const DesktopPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: p.glassBorder, width: 0.5),
          ),
          child: CustomPaint(
            painter: _PreviewPainter(
              skyTop: p.desktopGradientStart,
              skyMid: p.desktopGradientMid,
              dune: p.desktopGradientEnd,
              glass: p.glassFill,
              glassBorder: p.glassBorder,
              accent: p.accent,
              dark: p.isDark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.skyTop,
    required this.skyMid,
    required this.dune,
    required this.glass,
    required this.glassBorder,
    required this.accent,
    required this.dark,
  });

  final Color skyTop;
  final Color skyMid;
  final Color dune;
  final Color glass;
  final Color glassBorder;
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 800;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyMid, dune],
          stops: const [0, 0.55, 1],
        ).createShader(Offset.zero & size),
    );

    final orbCenter = Offset(w * 0.72, h * 0.3);
    canvas.drawCircle(
      orbCenter,
      40 * r,
      Paint()
        ..color = (dark ? const Color(0xFFF2EEE2) : const Color(0xFFFFE9B8)),
    );

    final dunePath = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.3, h * 0.5, w * 0.62, h * 0.66)
      ..quadraticBezierTo(w * 0.85, h * 0.78, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(dunePath, Paint()..color = dune.withValues(alpha: 0.85));

    void glassRect(Rect rect, double rad) {
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(rad));
      canvas.drawRRect(rr, Paint()..color = glass);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = glassBorder,
      );
    }

    final menu = Rect.fromLTWH(0, 0, w, 20 * r);
    canvas.drawRect(menu, Paint()..color = glass.withValues(alpha: 0.35));

    final win = Rect.fromLTWH(w * 0.12, h * 0.16, w * 0.5, h * 0.52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, Radius.circular(12 * r)),
      Paint()
        ..color = (dark ? const Color(0xFF2D2C2F) : const Color(0xFFF5F5F7))
            .withValues(alpha: 0.92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, Radius.circular(12 * r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = glassBorder,
    );
    canvas.drawRect(
      Rect.fromLTWH(win.left, win.top, win.width, 24 * r),
      Paint()..color = glass.withValues(alpha: 0.5),
    );
    final lightY = win.top + 12 * r;
    const lightCols = [0xFFFF5F57, 0xFFFEBC2E, 0xFF28C840];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(win.left + (14 + i * 14) * r, lightY),
        4.5 * r,
        Paint()..color = Color(lightCols[i]),
      );
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              win.left + 16 * r,
              win.top + (40 + i * 22) * r,
              win.width * (0.7 - i * 0.1),
              8 * r),
          Radius.circular(4 * r),
        ),
        Paint()
          ..color = (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
              .withValues(alpha: 0.08),
      );
    }

    final card =
        Rect.fromLTWH(w * 0.66, h * 0.2, w * 0.24, h * 0.34);
    glassRect(card, 10 * r);
    canvas.drawCircle(
      Offset(card.left + card.width / 2, card.top + card.height * 0.32),
      16 * r,
      Paint()..color = accent,
    );
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              card.left + 14 * r,
              card.top + card.height * (0.6 + i * 0.18),
              card.width - 28 * r,
              7 * r),
          Radius.circular(3.5 * r),
        ),
        Paint()
          ..color = (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
              .withValues(alpha: 0.1),
      );
    }

    final dockW = w * 0.42;
    final dockRect = Rect.fromCenter(
      center: Offset(w / 2, h * 0.93),
      width: dockW,
      height: h * 0.1,
    );
    glassRect(dockRect, 14 * r);
    const iconCols = [
      [0xFF8E8E93, 0xFF48484A],
      [0xFF4FC3F7, 0xFF0078C8],
      [0xFFFFD66E, 0xFFE6A817],
      [0xFF7BD88F, 0xFF2F9E4F],
      [0xFFBF5AF2, 0xFF8E3DBE],
    ];
    final iconSize = dockRect.height * 0.62;
    final gap = (dockW - iconSize * iconCols.length) / (iconCols.length + 1);
    for (var i = 0; i < iconCols.length; i++) {
      final x = dockRect.left + gap * (i + 1) + iconSize * i;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, dockRect.center.dy - iconSize / 2, iconSize,
              iconSize),
          Radius.circular(iconSize * 0.28),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, dockRect.center.dy - iconSize / 2),
            Offset(x, dockRect.center.dy + iconSize / 2),
            [Color(iconCols[i][0]), Color(iconCols[i][1])],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.skyTop != skyTop ||
      old.skyMid != skyMid ||
      old.dune != dune ||
      old.glass != glass ||
      old.accent != accent ||
      old.dark != dark;
}
