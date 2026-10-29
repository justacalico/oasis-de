import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

void showShellContextMenu(
  BuildContext context,
  Offset position,
  List<ShellMenuItem> items,
) {
  final overlay = Overlay.of(context);
  final box = overlay.context.findRenderObject()! as RenderBox;
  late final OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      final style = OasisStyle.of(context);
      const menuWidth = 250.0;
      const menuHeight = 400.0;
      final maxX = box.size.width - menuWidth - 8;
      final maxY = box.size.height - 8;
      final dx = position.dx.clamp(8.0, maxX > 8 ? maxX : 8.0);
      final dy = position.dy.clamp(8.0, maxY > 8 ? maxY : 8.0);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: close,
              onSecondaryTapUp: (_) => close(),
            ),
          ),
          Positioned(
            left: dx,
            top: dy,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: menuHeight),
              child: OasisGlass(
                borderRadius: style.menuRadius,
                blur: 36,
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 210,
                    maxWidth: 240,
                  ),
                  child: IntrinsicWidth(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in items) ...[
                            OasisMenuEntry(item: item, onSelect: close),
                            if (item.separatorAfter)
                              Divider(
                                height: 9,
                                thickness: 0.5,
                                indent: 12,
                                endIndent: 12,
                                color: style.palette.divider,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

void confirmShellAction(
  BuildContext context, {
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    onConfirm();
    return;
  }
  late final OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      final style = OasisStyle.of(context);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: OasisGlass(
                borderRadius: style.menuRadius,
                blur: 40,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

class OasisMenuEntry extends StatefulWidget {
  const OasisMenuEntry({
    super.key,
    required this.item,
    required this.onSelect,
  });

  final ShellMenuItem item;
  final VoidCallback onSelect;

  @override
  State<OasisMenuEntry> createState() => _OasisMenuEntryState();
}

class _OasisMenuEntryState extends State<OasisMenuEntry> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = OasisStyle.of(context).palette;
    final enabled = widget.item.enabled;
    final color = !enabled
        ? p.textTertiary
        : _hovered
        ? const Color(0xFFFFFFFF)
        : p.textPrimary;
    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                widget.onSelect();
                widget.item.action?.call(context);
              }
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: _hovered ? p.accent : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: widget.item.checked
                      ? Icon(Icons.check, size: 14, color: color)
                      : null,
                ),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
