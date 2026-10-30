import 'package:flutter/material.dart';

class OasisTrafficLights extends StatefulWidget {
  const OasisTrafficLights({
    super.key,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.size = 12,
  });

  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final double size;

  @override
  State<OasisTrafficLights> createState() => _OasisTrafficLightsState();
}

class _OasisTrafficLightsState extends State<OasisTrafficLights> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Light(
            color: const Color(0xFFFF5F57),
            glyph: Icons.close,
            onTap: widget.onClose,
            size: widget.size,
            showGlyph: _hovered,
            semantic: 'close',
          ),
          SizedBox(width: widget.size * 2 / 3),
          _Light(
            color: const Color(0xFFFEBC2E),
            glyph: Icons.remove,
            onTap: widget.onMinimize,
            size: widget.size,
            showGlyph: _hovered,
            semantic: 'minimize',
          ),
          SizedBox(width: widget.size * 2 / 3),
          _Light(
            color: const Color(0xFF28C840),
            glyph: Icons.add,
            onTap: widget.onMaximize,
            size: widget.size,
            showGlyph: _hovered,
            semantic: 'maximize',
          ),
        ],
      ),
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.glyph,
    required this.onTap,
    required this.size,
    required this.showGlyph,
    required this.semantic,
  });

  final Color color;
  final IconData glyph;
  final VoidCallback? onTap;
  final double size;
  final bool showGlyph;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: semantic,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
            border: Border.all(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
          child: showGlyph && onTap != null
              ? Icon(glyph, size: size * 0.75, color: const Color(0x8A000000))
              : null,
        ),
      ),
    );
  }
}
