import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisCheckbox extends StatelessWidget {
  const OasisCheckbox({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: !enabled
                ? p.divider
                : value
                ? p.accent
                : const Color(0x00000000),
            border: Border.all(
              color: value || !enabled ? const Color(0x00000000) : p.divider,
              width: 1.5,
            ),
          ),
          child: value
              ? const Icon(Icons.check, size: 14, color: Color(0xFFFFFFFF))
              : null,
        ),
      ),
    );
  }
}

class OasisRadio<T> extends StatelessWidget {
  const OasisRadio({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
  });

  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final selected = value == groupValue;
    final enabled = onChanged != null;
    return Semantics(
      checked: selected,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(value) : null,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !enabled
                ? p.divider
                : selected
                ? p.accent
                : const Color(0x00000000),
            border: Border.all(
              color: selected || !enabled
                  ? const Color(0x00000000)
                  : p.divider,
              width: 1.5,
            ),
          ),
          child: selected
              ? const Center(
                  child: SizedBox(
                    width: 6,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
