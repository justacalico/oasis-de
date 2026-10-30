import 'package:flutter/material.dart';

import '../theme/oasis_theme.dart';
import 'oasis_glass.dart';

void showOasisDialog(
  BuildContext context,
  Widget Function(BuildContext context, VoidCallback close) builder,
) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
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
                child: builder(context, close),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}
