import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisSearchField extends StatelessWidget {
  const OasisSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.fontSize = 13,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = OasisStyle.of(context);
    final p = style.palette;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontSize: fontSize),
      cursorColor: p.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontSize: fontSize, color: p.textTertiary),
        prefixIcon: Icon(Icons.search,
            size: fontSize + 4, color: p.textTertiary),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 0),
        filled: true,
        fillColor: p.isDark
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
            : const Color(0xFF000000).withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.controlRadius + 2),
          borderSide: BorderSide(color: p.divider, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.controlRadius + 2),
          borderSide: BorderSide(color: p.divider, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.controlRadius + 2),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
      ),
    );
  }
}
