import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/oasis_theme.dart';
import '../wallpaper/wallpaper_service.dart';

class OasisWallpaper extends StatelessWidget {
  const OasisWallpaper({super.key, this.service});

  final OasisWallpaperService? service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    if (s == null) return _build(context, null);
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => _build(context, s),
    );
  }

  Widget _build(BuildContext context, OasisWallpaperService? s) {
    final p = OasisStyle.of(context).palette;
    final path = s?.imagePath;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: OasisDunesPainter(
            skyTop: p.desktopGradientStart,
            skyBottom: p.desktopGradientMid,
            duneFar: p.desktopGradientEnd,
            duneNear: p.isDark
                ? p.desktopGradientEnd.withValues(alpha: 0.55)
                : p.desktopGradientEnd.withValues(alpha: 0.85),
            night: p.isDark,
          ),
          child: const SizedBox.expand(),
        ),
        if (!kIsWeb && path != null)
          Image.file(
            File(path),
            fit: s?.fit ?? BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class OasisDunesPainter extends CustomPainter {
  const OasisDunesPainter({
    required this.skyTop,
    required this.skyBottom,
    required this.duneFar,
    required this.duneNear,
    this.night = false,
  });

  final Color skyTop;
  final Color skyBottom;
  final Color duneFar;
  final Color duneNear;
  final bool night;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Rect.fromLTWH(0, 0, size.width, size.height * 0.62);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyBottom],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final orbCenter =
        Offset(size.width * 0.72, sky.bottom * 0.55);
    final orbRadius = size.shortestSide * 0.11;
    canvas.drawCircle(
      orbCenter,
      orbRadius * 1.9,
      Paint()
        ..color = (night ? const Color(0xFFE8E4DA) : const Color(0xFFFFF3D6))
            .withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      orbCenter,
      orbRadius,
      Paint()
        ..color = night ? const Color(0xFFF2EEE2) : const Color(0xFFFFE9B8),
    );

    final far = Path()
      ..moveTo(0, sky.bottom * 0.92)
      ..quadraticBezierTo(size.width * 0.3, sky.bottom * 0.72,
          size.width * 0.62, sky.bottom * 0.9)
      ..quadraticBezierTo(size.width * 0.85, sky.bottom * 1.02,
          size.width, sky.bottom * 0.86)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(far, Paint()..color = duneFar);

    final near = Path()
      ..moveTo(0, size.height * 0.82)
      ..quadraticBezierTo(size.width * 0.22, size.height * 0.68,
          size.width * 0.5, size.height * 0.8)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.92,
          size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = duneNear);

    final lagoon = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(size.width * 0.34, size.height * 0.9),
        width: size.width * 0.2,
        height: size.height * 0.045,
      ));
    canvas.drawPath(
      lagoon,
      Paint()..color = skyTop.withValues(alpha: night ? 0.5 : 0.75),
    );
  }

  @override
  bool shouldRepaint(OasisDunesPainter oldDelegate) =>
      oldDelegate.skyTop != skyTop ||
      oldDelegate.skyBottom != skyBottom ||
      oldDelegate.duneFar != duneFar ||
      oldDelegate.duneNear != duneNear ||
      oldDelegate.night != night;
}
