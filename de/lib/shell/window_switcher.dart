import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'shell_controller.dart';

class WindowSwitcher extends StatelessWidget {
  const WindowSwitcher({super.key, required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final wins = c.switcherWindows;
    final selected = c.switcherIndex ?? 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: c.closeSwitcher,
      child: Center(
        child: OasisGlass(
          borderRadius: 18,
          blur: 40,
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, w) in wins.indexed)
                GestureDetector(
                  onTap: () => c.selectSwitcherWindow(w.id),
                  child: Semantics(
                    button: true,
                    label: w.displayTitle,
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: i == selected
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OasisAppIcon(
                            icon: w.app.icon,
                            colors: w.app.iconColors,
                            iconPath: w.app.iconPath,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            w.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
