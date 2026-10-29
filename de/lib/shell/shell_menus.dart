import 'package:oasis_ui/oasis_ui.dart';

import 'context_menu.dart';
import 'shell_controller.dart';

List<ShellMenu> buildShellMenus(
  OasisLocalizations l10n,
  ShellController controller,
  String appName,
  Map<String, OasisApp> apps,
) {
  final focused = controller.focusedWindow;
  final about = apps['about'];
  final settings = apps['settings'];
  return [
    ShellMenu(
      label: appName,
      items: (context) => [
        ShellMenuItem(
          label: l10n.menuAbout,
          separatorAfter: true,
          enabled: about != null,
          action: (_) {
            if (about != null) controller.openApp(about);
          },
        ),
        ShellMenuItem(
          label: l10n.menuSettings,
          separatorAfter: true,
          enabled: settings != null,
          action: (_) {
            if (settings != null) controller.openApp(settings);
          },
        ),
        ShellMenuItem(
          label: l10n.menuQuit,
          action: (ctx) => confirmShellAction(
            ctx,
            message: l10n.sessionConfirmLogOut,
            cancelLabel: l10n.dialogCancel,
            confirmLabel: l10n.sessionLogOut,
            onConfirm: () => controller.session(OasisSessionAction.logout),
          ),
        ),
      ],
    ),
    ShellMenu(
      label: l10n.menuFile,
      items: (context) => [
        ShellMenuItem(
          label: l10n.menuNewWindow,
          enabled: focused != null,
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.openApp(w.app, newWindow: true);
          },
        ),
        ShellMenuItem(
          label: l10n.menuCloseWindow,
          enabled: focused != null,
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.closeWindow(w.id);
          },
        ),
      ],
    ),
    ShellMenu(
      label: l10n.menuView,
      items: (context) => [
        ShellMenuItem(
          label: l10n.menuEnterFullScreen,
          enabled: focused != null,
          checked: focused?.fullscreen ?? false,
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.toggleFullscreen(w.id);
          },
        ),
      ],
    ),
    ShellMenu(
      label: l10n.menuWindow,
      items: (context) => [
        ShellMenuItem(
          label: l10n.menuMinimise,
          enabled: focused != null,
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.minimizeWindow(w.id);
          },
        ),
        ShellMenuItem(
          label: l10n.menuZoom,
          enabled: focused != null,
          checked: focused?.zoomed ?? false,
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.toggleZoom(w.id);
          },
        ),
        for (final w in controller.windows)
          ShellMenuItem(
            label: w.displayTitle,
            checked: controller.focusedId == w.id,
            action: (_) {
              if (w.minimized) {
                controller.restoreWindow(w.id);
              } else {
                controller.focusWindow(w.id);
              }
            },
          ),
      ],
    ),
    ShellMenu(
      label: l10n.menuHelp,
      items: (context) => [
        ShellMenuItem(
          label: l10n.menuAbout,
          enabled: about != null,
          action: (_) {
            if (about != null) controller.openApp(about);
          },
        ),
      ],
    ),
  ];
}
