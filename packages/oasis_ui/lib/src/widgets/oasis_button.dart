import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

enum OasisButtonVariant { primary, secondary, text }

class OasisButton extends StatefulWidget {
  const OasisButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OasisButtonVariant.secondary,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final OasisButtonVariant variant;
  final bool dense;

  @override
  State<OasisButton> createState() => _OasisButtonState();
}

class _OasisButtonState extends State<OasisButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final p = style.palette;
    final enabled = widget.onPressed != null;

    Color background;
    Color foreground;
    switch (widget.variant) {
      case OasisButtonVariant.primary:
        background = p.accent;
        foreground = const Color(0xFFFFFFFF);
      case OasisButtonVariant.secondary:
        background = p.isDark
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.12)
            : const Color(0xFF000000).withValues(alpha: 0.06);
        foreground = p.textPrimary;
      case OasisButtonVariant.text:
        background = const Color(0x00000000);
        foreground = p.accent;
    }
    if (!enabled) {
      foreground = p.textTertiary;
      if (widget.variant == OasisButtonVariant.primary) {
        background = p.accent.withValues(alpha: 0.4);
      }
    } else if (_pressed) {
      background = background.withValues(
          alpha: widget.variant == OasisButtonVariant.text ? 0.12 : 0.75);
    } else if (_hovered) {
      background = widget.variant == OasisButtonVariant.text
          ? p.accentSoft
          : background.withValues(alpha: (background.a * 0.88).clamp(0, 1));
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp:
            enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 10 : 16,
              vertical: widget.dense ? 3 : 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(style.controlRadius),
            border: widget.variant == OasisButtonVariant.secondary
                ? Border.all(color: p.divider, width: 0.5)
                : null,
          ),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w500,
                fontSize: 13),
          ),
        ),
      ),
    );
  }
}
