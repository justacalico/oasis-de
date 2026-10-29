import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../theme/oasis_theme.dart';

class OasisGlass extends StatelessWidget {
  const OasisGlass({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blur = 28,
    this.padding,
    this.fillOpacity = 1,
    this.border = true,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final double fillOpacity;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final p = style.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: p.glassFill.withValues(alpha: p.glassFill.a * fillOpacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: border
                  ? Border.all(color: p.glassBorder, width: 0.5)
                  : null,
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: borderRadius,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            p.glassHighlight,
                            p.glassHighlight.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
