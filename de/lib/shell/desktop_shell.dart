import 'package:flutter/material.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';
import '../wayland/wayland_surface_view.dart';
import 'control_center.dart';
import 'dock.dart';
import 'genie_window.dart';
import 'launch_pad.dart';
import 'launcher.dart';
import 'menu_bar.dart';
import 'shell_controller.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.controller,
    this.wallpaper,
    required this.menusBuilder,
  });

  final ShellController controller;
  final OasisWallpaperService? wallpaper;
  final List<ShellMenu> Function() menusBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final menus = menusBuilder();
        return Listener(
          onPointerDown: _onShellPointerDown,
          onPointerMove: (e) =>
              _onShellPointerMove(e, MediaQuery.sizeOf(context)),
          onPointerUp: (_) => controller.endSurfaceGesture(),
          child: Stack(
            children: [
              Positioned.fill(
                  child: OasisWallpaper(service: wallpaper)),
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
                                    MediaQuery.sizeOf(context)
                                            .height -
                                        kMenuBarHeight -
                                        8,
                                child: _windowContent(w, context),
                              )
                            : _windowContent(w, context),
                      ),
                    ),
                  ),
              if (controller.wayland != null)
                for (final popup in controller.wayland!.popups)
                  Builder(builder: (context) {
                    final offset = _popupOffset(popup);
                    if (offset == null) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      left: offset.dx,
                      top: offset.dy,
                      child: WaylandPopupView(
                          surface: popup,
                          service: controller.wayland!),
                    );
                  }),
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
                  child:
                      ShellControlCenter(controller: controller),
                ),
              if (controller.launchPadOpen)
                Positioned.fill(
                    child:
                        ShellLaunchPad(controller: controller)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child:
                    Center(child: ShellDock(controller: controller)),
              ),
              if (controller.launcherOpen)
                Positioned.fill(
                    child: ShellLauncher(controller: controller)),
            ],
          ),
        );
      },
    );
  }

  void _onShellPointerDown(PointerDownEvent e) {
    final service = controller.wayland;
    if (service == null || service.popups.isEmpty) return;
    for (final popup in service.popups) {
      final origin = _popupOffset(popup);
      if (origin == null) continue;
      if (!(origin & popup.size).contains(e.position)) {
        service.close(popup.id);
      }
    }
  }

  void _onShellPointerMove(PointerMoveEvent e, Size screen) {
    final resize = controller.surfaceResize;
    if (resize != null) {
      controller.resizeWindow(resize.id, e.delta, resize.edge,
          _defaultWindowSize(screen));
      return;
    }
    final id = controller.surfaceDragWindowId;
    if (id != null) controller.dragWindow(id, e.delta);
  }

  Offset? _popupOffset(WaylandSurface popup) {
    final service = controller.wayland!;
    var offset = popup.offset;
    var parent = service.surfaces[popup.parentId];
    while (parent != null && parent.isPopup) {
      offset += parent.offset;
      parent = service.surfaces[parent.parentId];
    }
    if (parent == null) return null;
    final w = controller.windowForSurface(parent.id);
    if (w == null) return null;
    final base = w.zoomed
        ? const Offset(0, kMenuBarHeight + 4)
        : w.position;
    return base + const Offset(0, kOasisWindowTitleBarHeight) + offset;
  }

  Size _defaultWindowSize(Size screen) => Size(
      (screen.width * 0.62).clamp(kMinWindowWidth, 940.0),
      (screen.height * 0.62).clamp(kMinWindowHeight, 720.0));

  Size _windowSize(ShellWindowData w, Size screen) =>
      w.size ?? _defaultWindowSize(screen);

  Rect _windowRect(ShellWindowData w, BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final s = w.zoomed
        ? Size(screen.width, screen.height - kMenuBarHeight - 8)
        : _windowSize(w, screen);
    return (w.zoomed ? const Offset(0, kMenuBarHeight + 4) : w.position) &
        s;
  }

  Widget _windowContent(ShellWindowData w, BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    Widget body;
    final surface = w.surface;
    final service = controller.wayland;
    if (surface != null && service != null) {
      body = WaylandSurfaceView(
        surface: surface,
        service: service,
        focused: controller.focusedId == w.id,
        maximized: w.zoomed,
      );
    } else if (w.launching) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OasisAppIcon(
                icon: w.app.icon,
                colors: w.app.iconColors,
                iconPath: w.app.iconPath,
                size: 64),
            const SizedBox(height: 12),
            Text(w.app.name,
                style:
                    Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    } else {
      body = Builder(builder: w.app.builder);
    }
    final windowSize = _windowSize(w, size);
    return OasisWindow(
      title: w.displayTitle,
      focused: controller.focusedId == w.id,
      width: w.zoomed ? size.width : windowSize.width,
      height: w.zoomed
          ? size.height - kMenuBarHeight - 8
          : windowSize.height,
      onClose: () => controller.closeWindow(w.id),
      onMinimize: () => controller.minimizeWindow(w.id),
      onMaximize: () => controller.toggleZoom(w.id),
      onDrag: (d) => controller.dragWindow(w.id, d),
      onResize: w.zoomed
          ? null
          : (d, edge) => controller.resizeWindow(
              w.id, d, edge, _defaultWindowSize(size)),
      child: body,
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
