import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisSlider extends StatelessWidget {
  const OasisSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;

  double get _fraction => max <= min
      ? 0.0
      : ((value - min) / (max - min)).clamp(0.0, 1.0);

  void _update(Offset local, double width) {
    if (onChanged == null || width <= 0) return;
    final f = (local.dx / width).clamp(0.0, 1.0);
    onChanged!(min + f * (max - min));
  }

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final slider = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _update(d.localPosition, width),
          onTapUp: (_) => onChangeEnd?.call(value),
          onPanStart: (d) => _update(d.localPosition, width),
          onPanUpdate: (d) => _update(d.localPosition, width),
          onPanEnd: (_) => onChangeEnd?.call(value),
          child: SizedBox(
            height: 24,
            width: width,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: p.isDark
                        ? const Color(0xFF464649)
                        : const Color(0xFFE0E0E2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _fraction,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: p.accent,
                    ),
                  ),
                ),
                Positioned(
                  left: (width - 22) * _fraction,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFFFFF),
                      border: Border.all(color: p.divider, width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF000000).withValues(alpha: 0.22),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return onChanged == null
        ? Opacity(opacity: 0.4, child: slider)
        : slider;
  }
}
