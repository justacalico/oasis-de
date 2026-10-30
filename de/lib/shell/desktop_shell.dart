import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';
import '../wayland/wayland_surface_view.dart';
import 'control_center.dart';
import 'context_menu.dart';
import 'dock.dart';
import 'genie_window.dart';
import 'launch_pad.dart';
import 'launcher.dart';
import 'lock_screen.dart';
import 'menu_bar.dart';
import 'notification_center.dart';
import 'shell_controller.dart';
import 'window_switcher.dart';

class DesktopShell extends StatefulWidget {
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
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final Map<String, GlobalKey> _menuLabelKeys = {};
  StreamSubscription<WaylandRequest>? _requestSub;
  final _pointerPos = ValueNotifier<Offset>(Offset.zero);

  ShellController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _requestSub = controller.wayland?.requests.listen(_onWaylandRequest);
    HardwareKeyboard.instance.addHandler(_onAltRelease);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onAltRelease);
    _requestSub?.cancel();
    _pointerPos.dispose();
    super.dispose();
  }

  bool _onAltRelease(KeyEvent event) {
    if (event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight) &&
        controller.switcherIndex != null) {
      controller.commitSwitcher();
      return true;
    }
    return false;
  }

  void _onWaylandRequest(WaylandRequest request) {
    if (request.type != WaylandRequestType.windowMenu || !mounted) return;
    final w = controller.windowForSurface(request.id);
    final s = w?.surface;
    if (w == null || s == null) return;
    final buf = s.bufferSize;
    final sx = buf.width > 0 ? s.size.width / buf.width : 1.0;
    final sy = buf.height > 0 ? s.size.height / buf.height : 1.0;
    final base = w.zoomed
        ? const Offset(0, kMenuBarHeight + 4)
        : w.fullscreen
        ? Offset.zero
        : w.position;
    final pos =
        base +
        const Offset(0, kOasisWindowTitleBarHeight) +
        Offset(request.x * sx, request.y * sy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _windowMenu(context, pos, w);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final menus = widget.menusBuilder();
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.tab, alt: true): () =>
                controller.cycleWindows(),
            const SingleActivator(
              LogicalKeyboardKey.tab,
              alt: true,
              shift: true,
            ): () =>
                controller.cycleWindows(backwards: true),
            const SingleActivator(LogicalKeyboardKey.escape): () {
              controller.closeSwitcher();
              controller.closeOverlays();
            },
            const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
                controller.showDesktop,
            const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
                controller.toggleZoomFocused,
            const SingleActivator(LogicalKeyboardKey.space, meta: true):
                controller.toggleLaunchPad,
            const SingleActivator(LogicalKeyboardKey.space, control: true):
                controller.toggleLauncher,
          },
          child: Listener(
            onPointerDown: _onShellPointerDown,
            onPointerHover: (e) {
              _pointerPos.value = e.position;
              if (e.buttons == 0) controller.endSurfaceGesture();
            },
            onPointerMove: (e) =>
                _onShellPointerMove(e, MediaQuery.sizeOf(context)),
            onPointerUp: (e) => controller.endSurfaceGesture(
              e.position,
              MediaQuery.sizeOf(context),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onSecondaryTapUp: (e) =>
                        _wallpaperMenu(context, e.globalPosition),
                    child: OasisWallpaper(service: widget.wallpaper),
                  ),
                ),
                for (final w in controller.windows)
                  if (!w.minimized ||
                      w.transition != ShellWindowTransition.none)
                    Positioned(
                      key: ValueKey(w.id),
                      left: w.zoomed || w.fullscreen ? 0 : w.position.dx,
                      top: w.zoomed
                          ? kMenuBarHeight + 4
                          : w.fullscreen
                          ? 0
                          : w.position.dy,
                      child: GenieWindow(
                        window: w,
                        rect: _windowRect(w, context),
                        onEnd: () => controller.finishTransition(w.id),
                        child: Listener(
                          onPointerDown: (_) => controller.focusWindow(w.id),
                          child: GestureDetector(
                            onSecondaryTapUp: (e) {
                              if (e.localPosition.dy <=
                                  kOasisWindowTitleBarHeight) {
                                _windowMenu(context, e.globalPosition, w);
                              }
                            },
                            child: w.zoomed || w.fullscreen
                                ? SizedBox(
                                    width: MediaQuery.sizeOf(context).width,
                                    height: w.fullscreen
                                        ? MediaQuery.sizeOf(context).height
                                        : MediaQuery.sizeOf(context).height -
                                              kMenuBarHeight -
                                              8,
                                    child: _windowContent(w, context),
                                  )
                                : _windowContent(w, context),
                          ),
                        ),
                      ),
                    ),
                if (controller.wayland != null)
                  for (final popup in controller.wayland!.popups)
                    Builder(
                      builder: (context) {
                        final offset = _popupOffset(popup);
                        if (offset == null) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: offset.dx,
                          top: offset.dy,
                          child: WaylandPopupView(
                            surface: popup,
                            service: controller.wayland!,
                          ),
                        );
                      },
                    ),
                if (controller.openMenu != null || controller.controlCenterOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.closeOverlays,
                    ),
                  ),
                if (!controller.windows.any(
                  (w) => w.fullscreen && !w.minimized,
                ))
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ShellMenuBar(
                      controller: controller,
                      menus: menus,
                      labelKeys: [
                        for (final m in menus)
                          _menuLabelKeys.putIfAbsent(
                            m.label,
                            () => GlobalKey(debugLabel: m.label),
                          ),
                      ],
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
                if (controller.launchPadOpen)
                  Positioned.fill(
                    child: ShellLaunchPad(controller: controller),
                  ),
                if (controller.notificationCenterOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.toggleNotificationCenter,
                      child: NotificationCenterPanel(controller: controller),
                    ),
                  ),
                if (controller.switcherIndex != null)
                  Positioned.fill(
                    child: WindowSwitcher(controller: controller),
                  ),
                if (!controller.windows.any(
                  (w) => w.fullscreen && !w.minimized,
                ))
                  Positioned(
                    top: kCcTopOffset + 4,
                    left: 0,
                    right: 0,
                    child: NotificationBanner(controller: controller),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<Offset>(
                      valueListenable: _pointerPos,
                      builder: (context, pos, _) {
                        final cursor = controller.wayland?.cursor;
                        if (cursor == null) {
                          return const SizedBox.shrink();
                        }
                        return Transform.translate(
                          offset: pos - cursor.hotspot,
                          child: SizedBox.fromSize(
                            size: cursor.size,
                            child: Texture(textureId: cursor.textureId),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (!controller.windows.any(
                  (w) => w.fullscreen && !w.minimized,
                ))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(child: ShellDock(controller: controller)),
                  ),
                if (controller.launcherOpen)
                  Positioned.fill(child: ShellLauncher(controller: controller)),
                if (controller.locked)
                  Positioned.fill(
                    child: ShellLockScreen(controller: controller),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onShellPointerDown(PointerDownEvent e) {
    final service = controller.wayland;
    if (service == null || service.popups.isEmpty) return;
    WaylandSurface? hit;
    var hitDepth = -1;
    for (final popup in service.popups) {
      final origin = _popupOffset(popup);
      if (origin == null) continue;
      if (!(origin & popup.size).contains(e.position)) continue;
      var depth = 0;
      for (
        var p = service.surfaces[popup.parentId];
        p != null && p.isPopup;
        p = service.surfaces[p.parentId]
      ) {
        depth++;
      }
      if (depth >= hitDepth) {
        hit = popup;
        hitDepth = depth;
      }
    }
    final keep = <int>{};
    for (var p = hit; p != null; p = service.surfaces[p.parentId]) {
      keep.add(p.id);
      if (!p.isPopup) break;
    }
    for (final popup in service.popups) {
      if (!keep.contains(popup.id)) service.close(popup.id);
    }
  }

  void _onShellPointerMove(PointerMoveEvent e, Size screen) {
    _pointerPos.value = e.position;
    final resize = controller.surfaceResize;
    if (resize != null) {
      controller.resizeWindow(
        resize.id,
        e.delta,
        resize.edge,
        _defaultWindowSize(screen),
      );
      return;
    }
    final id = controller.surfaceDragWindowId;
    if (id != null) {
      controller.dragWindow(id, e.delta, screen);
    }
  }

  void _wallpaperMenu(BuildContext context, Offset pos) {
    final l10n = OasisLocalizations.of(context);
    final c = controller;
    final settings = c.apps.where((a) => a.id == 'settings');
    final about = c.apps.where((a) => a.id == 'about');
    showShellContextMenu(context, pos, [
      ShellMenuItem(
        label: l10n.settingsWallpaper,
        enabled: settings.isNotEmpty,
        action: (_) => c.openApp(settings.first),
      ),
      ShellMenuItem(
        label: l10n.menuAbout,
        enabled: about.isNotEmpty,
        action: (_) => c.openApp(about.first),
      ),
    ]);
  }

  void _windowMenu(BuildContext context, Offset pos, ShellWindowData w) {
    final l10n = OasisLocalizations.of(context);
    final c = controller;
    showShellContextMenu(context, pos, [
      ShellMenuItem(
        label: l10n.menuMinimise,
        action: (_) => c.minimizeWindow(w.id),
      ),
      ShellMenuItem(
        label: l10n.menuZoom,
        checked: w.zoomed,
        action: (_) => c.toggleZoom(w.id),
      ),
      ShellMenuItem(
        label: l10n.menuEnterFullScreen,
        checked: w.fullscreen,
        separatorAfter: true,
        action: (_) => c.toggleFullscreen(w.id),
      ),
      for (var i = 0; i < ShellController.workspaceCount; i++)
        ShellMenuItem(
          label: l10n.ctxMoveToDesktop(i + 1),
          checked: w.workspace == i,
          separatorAfter: i == ShellController.workspaceCount - 1,
          action: (_) => c.moveWindowToWorkspace(w.id, i),
        ),
      ShellMenuItem(
        label: l10n.menuCloseWindow,
        action: (_) => c.closeWindow(w.id),
      ),
    ]);
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
    if (w.minimized || w.workspace != controller.activeWorkspace) {
      return null;
    }
    final buf = logicalSurfaceSize(parent);
    final sx = buf.width > 0 ? parent.size.width / buf.width : 1.0;
    final sy = buf.height > 0 ? parent.size.height / buf.height : 1.0;
    final base = w.fullscreen
        ? Offset.zero
        : w.zoomed
        ? const Offset(0, kMenuBarHeight + 4)
        : w.position;
    var pos =
        base +
        (w.fullscreen
            ? Offset.zero
            : const Offset(0, kOasisWindowTitleBarHeight)) +
        Offset(offset.dx * sx, offset.dy * sy);
    final screen = MediaQuery.sizeOf(context);
    pos = Offset(
      pos.dx.clamp(0, math.max(0, screen.width - popup.size.width)),
      pos.dy.clamp(0, math.max(0, screen.height - popup.size.height)),
    );
    return pos;
  }

  Size _defaultWindowSize(Size screen) => Size(
    math.min((screen.width * 0.62).clamp(kMinWindowWidth, 940.0), screen.width),
    math.min(
      (screen.height * 0.62).clamp(kMinWindowHeight, 720.0),
      screen.height,
    ),
  );

  Size _windowSize(ShellWindowData w, Size screen) =>
      w.size ?? _defaultWindowSize(screen);

  Rect _windowRect(ShellWindowData w, BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final s = w.zoomed
        ? Size(screen.width, screen.height - kMenuBarHeight - 8)
        : _windowSize(w, screen);
    return (w.zoomed ? const Offset(0, kMenuBarHeight + 4) : w.position) & s;
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
        fullscreen: w.fullscreen,
        resizing: controller.surfaceResize?.id == w.id,
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
              size: 64,
            ),
            const SizedBox(height: 12),
            Text(w.app.name, style: Theme.of(context).textTheme.titleMedium),
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
      height: w.zoomed ? size.height - kMenuBarHeight - 8 : windowSize.height,
      onClose: () => controller.closeWindow(w.id),
      onMinimize: () => controller.minimizeWindow(w.id),
      onMaximize: () => controller.toggleZoom(w.id),
      onDrag: (d) => controller.dragWindow(w.id, d, MediaQuery.sizeOf(context)),
      onResize: w.zoomed
          ? null
          : (d, edge) => controller.resizeWindow(
              w.id,
              d,
              edge,
              _defaultWindowSize(size),
            ),
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
    final box =
        _menuLabelKeys[menus[idx].label]!.currentContext?.findRenderObject()
            as RenderBox?;
    final x = box?.localToGlobal(Offset.zero).dx ?? 40;
    final max = MediaQuery.sizeOf(context).width - 218;
    return x.clamp(0.0, max > 0 ? max : 0.0);
  }
}
