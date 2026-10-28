import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisNavRow extends StatelessWidget {
  const OasisNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: const Color(0x00000000),
        shape: const StadiumBorder(),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: const StadiumBorder(),
          selected: selected,
          selectedTileColor: p.selection,
          hoverColor: p.isDark
              ? const Color(0xFFFFFFFF).withValues(alpha: 0.06)
              : const Color(0xFF000000).withValues(alpha: 0.04),
          onTap: onTap,
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: iconColor ?? p.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 15, color: const Color(0xFFFFFFFF)),
          ),
          title: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          minLeadingWidth: 26,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}
