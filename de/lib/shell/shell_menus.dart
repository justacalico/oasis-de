import 'package:oasis_ui/oasis_ui.dart';

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
        ShellMenuItem(label: l10n.menuQuit, enabled: false),
      ],
    ),
    ShellMenu(
      label: l10n.menuFile,
      items: (context) => [
        ShellMenuItem(label: l10n.menuNewWindow, enabled: false),
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
      label: l10n.menuEdit,
      items: (context) => [
        ShellMenuItem(label: l10n.menuUndo, enabled: false),
        ShellMenuItem(
            label: l10n.menuRedo, enabled: false, separatorAfter: true),
        ShellMenuItem(label: l10n.menuCut, enabled: false),
        ShellMenuItem(label: l10n.menuCopy, enabled: false),
        ShellMenuItem(label: l10n.menuPaste, enabled: false),
        ShellMenuItem(label: l10n.menuSelectAll, enabled: false),
      ],
    ),
    ShellMenu(
      label: l10n.menuView,
      items: (context) => [
        ShellMenuItem(label: l10n.menuEnterFullScreen, enabled: false),
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
          action: (_) {
            final w = controller.focusedWindow;
            if (w != null) controller.toggleZoom(w.id);
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
