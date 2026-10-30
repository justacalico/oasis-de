import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';

class OasisTooltip extends StatelessWidget {
  const OasisTooltip({
    super.key,
    required this.message,
    this.preferBelow,
    this.triggerMode,
    required this.child,
  });

  final String? message;
  final bool? preferBelow;
  final TooltipTriggerMode? triggerMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return child;
    final p = OasisStyle.of(context).palette;
    return Tooltip(
      message: message,
      preferBelow: preferBelow,
      triggerMode: triggerMode,
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.glassBorder),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: p.textPrimary),
      child: child,
    );
  }
}
