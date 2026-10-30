import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisTextField extends StatelessWidget {
  const OasisTextField({
    super.key,
    this.controller,
    this.autofocus = false,
    this.obscureText = false,
    this.hintText,
    this.hintStyle,
    this.icon,
    this.style,
    this.maxLines = 1,
    this.expands = false,
    this.filled = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final bool autofocus;
  final bool obscureText;
  final String? hintText;
  final TextStyle? hintStyle;
  final Widget? icon;
  final TextStyle? style;
  final int? maxLines;
  final bool expands;
  final bool filled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final style_ = OasisStyle.of(context);
    final p = style_.palette;
    final decoration = filled
        ? InputDecoration(
            isDense: true,
            filled: true,
            fillColor: p.cardBackground.withValues(alpha: 0.6),
            hintText: hintText,
            hintStyle: hintStyle ?? TextStyle(color: p.textTertiary),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(style_.cardRadius),
              borderSide: BorderSide(color: p.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(style_.cardRadius),
              borderSide: BorderSide(color: p.glassBorder),
            ),
          )
        : InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hintText,
            hintStyle:
                hintStyle ??
                Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: p.textTertiary),
            icon: icon,
          );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscureText,
      maxLines: expands ? null : maxLines,
      expands: expands,
      style: style,
      cursorColor: p.accent,
      decoration: decoration,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
