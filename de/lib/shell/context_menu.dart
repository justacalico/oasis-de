import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

void showShellContextMenu(
  BuildContext context,
  Offset position,
  List<ShellMenuItem> items,
) => showOasisMenu(context, position, items);

void confirmShellAction(
  BuildContext context, {
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  if (Overlay.maybeOf(context) == null) {
    onConfirm();
    return;
  }
  showOasisDialog(
    context,
    (context, close) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OasisButton(
              label: cancelLabel,
              variant: OasisButtonVariant.text,
              dense: true,
              onPressed: close,
            ),
            const SizedBox(width: 8),
            OasisButton(
              label: confirmLabel,
              variant: OasisButtonVariant.primary,
              dense: true,
              onPressed: () {
                close();
                onConfirm();
              },
            ),
          ],
        ),
      ],
    ),
  );
}
