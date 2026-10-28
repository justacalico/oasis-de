import 'package:flutter/material.dart';

class OasisAppIcon extends StatelessWidget {
  const OasisAppIcon({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 48,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.25),
            width: size * 0.02),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.25),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.04,
            left: size * 0.12,
            right: size * 0.12,
            height: size * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFFFFF).withValues(alpha: 0.38),
                    const Color(0xFFFFFFFF).withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Icon(icon, size: size * 0.55, color: const Color(0xFFFFFFFF)),
        ],
      ),
    );
  }
}
