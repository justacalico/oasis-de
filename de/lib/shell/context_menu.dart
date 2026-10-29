import 'package:flutter/material.dart';

import 'shell_controller.dart';

Future<void> showShellContextMenu(
  BuildContext context,
  Offset position,
  List<ShellMenuItem> items,
) async {
  final overlay = Overlay.of(context);
  final box = overlay.context.findRenderObject()! as RenderBox;
  final index = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & box.size,
    ),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem(
          value: i,
          enabled: items[i].enabled,
          height: 32,
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: items[i].checked
                    ? const Icon(Icons.check, size: 14)
                    : null,
              ),
              Text(items[i].label),
            ],
          ),
        ),
    ],
  );
  if (index == null) return;
  if (!context.mounted) return;
  items[index].action?.call(context);
}
