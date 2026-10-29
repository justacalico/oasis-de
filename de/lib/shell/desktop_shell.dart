import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'control_center.dart';
import 'dock.dart';
import 'genie_window.dart';
import 'launcher.dart';
import 'menu_bar.dart';
import 'shell_controller.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.controller,
    required this.menusBuilder,
  });

  final ShellController controller;
  final List<ShellMenu> Function() menusBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final menus = menusBuilder();
        return Stack(
          children: [
            const Positioned.fill(child: OasisWallpaper()),
            for (final w in controller.windows)
              if (!w.minimized ||
                  w.transition != ShellWindowTransition.none)
                Positioned(
                  key: ValueKey(w.id),
                  left: w.zoomed ? 0 : w.position.dx,
                  top: w.zoomed
                      ? kMenuBarHeight + 4
                      : w.position.dy,
                  child: GenieWindow(
                    window: w,
                    rect: _windowRect(w, context),
                    onEnd: () => controller.finishTransition(w.id),
                    child: Listener(
                      onPointerDown: (_) =>
                          controller.focusWindow(w.id),
                      child: w.zoomed
                          ? SizedBox(
                              width:
                                  MediaQuery.sizeOf(context).width,
                              height:
                                  MediaQuery.sizeOf(context).height -
                                      kMenuBarHeight -
                                      8,
                              child: _windowContent(w, context),
                            )
                          : _windowContent(w, context),
                    ),
                  ),
                ),
            if (controller.openMenu != null ||
                controller.controlCenterOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.closeOverlays,
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ShellMenuBar(
                controller: controller,
                menus: menus,
              ),
            ),
            if (controller.openMenu != null)
              Positioned(
                top: kMenuBarHeight + 2,
                left: _menuLeft(context, menus),
                child: MenuDropdown(
                  menuIndex: _menuIndex(menus),
                  menus: menus,
                  controller: controller,
                ),
              ),
            if (controller.controlCenterOpen)
              Positioned.fill(
                child: ShellControlCenter(controller: controller),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(child: ShellDock(controller: controller)),
            ),
            if (controller.launcherOpen)
              Positioned.fill(
                  child: ShellLauncher(controller: controller)),
          ],
        );
      },
    );
  }

  Rect _windowRect(ShellWindowData w, BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final s = w.zoomed
        ? Size(size.width, size.height - kMenuBarHeight - 8)
        : Size((size.width * 0.62).clamp(360.0, 940.0),
            (size.height * 0.62).clamp(300.0, 720.0));
    return (w.zoomed ? const Offset(0, kMenuBarHeight + 4) : w.position) &
        s;
  }

  Widget _windowContent(ShellWindowData w, BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return OasisWindow(
      title: w.app.name,
      focused: controller.focusedId == w.id,
      width: w.zoomed ? size.width : (size.width * 0.62).clamp(360.0, 940.0),
      height: w.zoomed
          ? size.height - kMenuBarHeight - 8
          : (size.height * 0.62).clamp(300.0, 720.0),
      onClose: () => controller.closeWindow(w.id),
      onMinimize: () => controller.minimizeWindow(w.id),
      onMaximize: () => controller.toggleZoom(w.id),
      onDrag: (d) => controller.dragWindow(w.id, d),
      child: Builder(builder: w.app.builder),
    );
  }

  int _menuIndex(List<ShellMenu> menus) {
    final open = controller.openMenu;
    final i = menus.indexWhere((m) => m.label == open);
    return i < 0 ? 0 : i;
  }

  double _menuLeft(BuildContext context, List<ShellMenu> menus) {
    final idx = _menuIndex(menus);
    var x = 40.0;
    for (var i = 0; i < idx; i++) {
      x += menus[i].label.length * 8.5 + 22;
    }
    return x;
  }
}
