import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisSlider extends StatefulWidget {
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

  @override
  State<OasisSlider> createState() => _OasisSliderState();
}

class _OasisSliderState extends State<OasisSlider> {
  double? _last;

  double get _fraction => widget.max <= widget.min
      ? 0.0
      : ((widget.value - widget.min) / (widget.max - widget.min))
          .clamp(0.0, 1.0);

  void _update(Offset local, double width) {
    final onChanged = widget.onChanged;
    if (onChanged == null || width <= 0) return;
    final f = (local.dx / width).clamp(0.0, 1.0);
    _last = widget.min + f * (widget.max - widget.min);
    onChanged(_last!);
  }

  void _end() => widget.onChangeEnd?.call(_last ?? widget.value);

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final slider = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _update(d.localPosition, width),
          onTapUp: (_) => _end(),
          onPanStart: (d) => _update(d.localPosition, width),
          onPanUpdate: (d) => _update(d.localPosition, width),
          onPanEnd: (_) => _end(),
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
    return widget.onChanged == null
        ? Opacity(opacity: 0.4, child: slider)
        : slider;
  }
}
