import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/layer_surface_view.dart';
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
  StreamSubscription<WaylandRequest>? _requestSub;
  final _pointerPos = ValueNotifier<Offset>(Offset.zero);
  DateTime? _lastActivity;

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
    final buf = logicalSurfaceSize(s);
    final sx = buf.width > 0 ? s.size.width / buf.width : 1.0;
    final sy = buf.height > 0 ? s.size.height / buf.height : 1.0;
    final head = _windowHeadRect(w, MediaQuery.sizeOf(context));
    final base = w.zoomed
        ? head.topLeft + const Offset(0, kMenuBarHeight + 4)
        : w.fullscreen
        ? head.topLeft
        : w.position;
    final pos =
        base +
        Offset(0, w.titleBarHeight) +
        Offset(request.x * sx, request.y * sy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _windowMenu(context, pos, w);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        controller.keybinds,
        if (controller.wayland != null) controller.wayland!,
      ]),
      builder: (context, _) {
        final menus = widget.menusBuilder();
        final wl = controller.wayland;
        final heads = [
          for (final o in wl?.outputs ?? const <OasisOutput>[])
            if (o.enabled) o,
        ];
        final screen = MediaQuery.sizeOf(context);
        final screenRect = Offset.zero & screen;
        final primary =
            wl?.primaryOutput ?? (heads.isEmpty ? null : heads.first);
        final activeHead = wl?.outputAt(_pointerPos.value) ?? primary;
        final activeRect = activeHead?.rect ?? screenRect;
        final primaryRect = primary?.rect ?? screenRect;
        return CallbackShortcuts(
          bindings: {
            for (final e in controller.keybinds.activators.entries)
              e.key: () => controller.runKeybindAction(e.value),
          },
          child: Listener(
            onPointerDown: _onShellPointerDown,
            onPointerHover: (e) {
              _pointerPos.value = e.localPosition;
              controller.lastPointerPosition = e.localPosition;
              if (e.buttons == 0) controller.endSurfaceGesture();
            },
            onPointerMove: (e) =>
                _onShellPointerMove(e, MediaQuery.sizeOf(context)),
            onPointerUp: (e) => controller.endSurfaceGesture(
              e.localPosition,
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
                for (final s in _layerItems(0)) s,
                for (final s in _layerItems(1)) s,
                for (final w in controller.windows)
                  if (w.workspace == controller.activeWorkspace &&
                      (!w.minimized ||
                          w.transition != ShellWindowTransition.none))
                    Builder(
                      key: ValueKey(w.id),
                      builder: (context) {
                        final screen = MediaQuery.sizeOf(context);
                        final zoomHead = _windowHeadRect(w, screen);
                        final target = w.zoomed
                            ? _zoomedRect(zoomHead)
                            : w.fullscreen
                            ? zoomHead
                            : w.position & _windowSize(w, screen);
                        return TweenAnimationBuilder<Rect?>(
                          tween: RectTween(end: target),
                          duration: w.animateGeom
                              ? const Duration(milliseconds: 180)
                              : Duration.zero,
                          curve: Curves.easeOutCubic,
                          builder: (context, r, _) {
                            r ??= target;
                            return Positioned(
                              left: r.left,
                              top: r.top,
                              child: GenieWindow(
                                window: w,
                                rect: _windowRect(w, context),
                                onEnd: () =>
                                    controller.finishTransition(w.id),
                                child: Listener(
                                  onPointerDown: (_) =>
                                      controller.focusWindow(w.id),
                                  child: GestureDetector(
                                    onSecondaryTapUp: (e) {
                                      if (e.localPosition.dy <=
                                          w.titleBarHeight) {
                                        _windowMenu(
                                          context,
                                          e.globalPosition,
                                          w,
                                        );
                                      }
                                    },
                                    child: SizedBox(
                                      width: r.width,
                                      height: r.height,
                                      child: _windowContent(
                                        w,
                                        context,
                                        r.size,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                for (final s in _layerItems(2)) s,
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
                if (!controller.fullscreenOnActiveWorkspace)
                  for (var i = 0; i < (heads.isEmpty ? 1 : heads.length); i++)
                    Positioned.fromRect(
                      rect: heads.isEmpty
                          ? Rect.fromLTWH(
                              0, 0, screen.width, kMenuBarHeight)
                          : Rect.fromLTWH(
                              heads[i].rect.left,
                              heads[i].rect.top,
                              heads[i].rect.width,
                              kMenuBarHeight,
                            ),
                      child: ShellMenuBar(
                        controller: controller,
                        menus: menus,
                      ),
                    ),
                if (controller.openMenu != null)
                  Positioned(
                    top: (controller.menuAnchor?.bottom ?? kMenuBarHeight) + 2,
                    left: _menuLeft(context, menus),
                    child: MenuDropdown(
                      menuIndex: _menuIndex(menus),
                      menus: menus,
                      controller: controller,
                    ),
                  ),
                if (controller.controlCenterOpen)
                  Positioned.fromRect(
                    rect: activeRect,
                    child: ShellControlCenter(controller: controller),
                  ),
                if (controller.launchPadOpen)
                  Positioned.fromRect(
                    rect: activeRect,
                    child: ShellLaunchPad(controller: controller),
                  ),
                if (controller.notificationCenterOpen)
                  Positioned.fromRect(
                    rect: activeRect,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.toggleNotificationCenter,
                      child: NotificationCenterPanel(controller: controller),
                    ),
                  ),
                if (controller.switcherIndex != null)
                  Positioned.fromRect(
                    rect: activeRect,
                    child: WindowSwitcher(controller: controller),
                  ),
                if (!controller.fullscreenOnActiveWorkspace)
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
                        final wl = controller.wayland;
                        final cursor = wl?.cursor;
                        if (cursor == null ||
                            !wl!.pointerOverClient ||
                            wl.pointerLocked) {
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
                if (!controller.fullscreenOnActiveWorkspace)
                  Positioned.fromRect(
                    rect: primaryRect,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ShellDock(controller: controller),
                    ),
                  ),
                if (controller.launcherOpen)
                  Positioned.fromRect(
                    rect: activeRect,
                    child: ShellLauncher(controller: controller),
                  ),
                if (controller.identifyActive)
                  for (var i = 0; i < heads.length; i++)
                    Positioned.fromRect(
                      rect: heads[i].rect,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white54),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 72,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                for (final s in _layerItems(3)) s,
                if (controller.wayland?.sessionLocked ?? false)
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF000000)),
                  ),
                if (controller.wayland != null)
                  for (final s in controller.wayland!.lockSurfaces)
                    Positioned.fill(
                      key: ValueKey('lock-${s.id}'),
                      child: LockSurfaceView(
                        surface: s,
                        service: controller.wayland!,
                      ),
                    ),
                if (controller.locked)
                  Positioned.fill(
                    child: ShellLockScreen(controller: controller),
                  ),
                if (controller.wayland?.displayOff ?? false)
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _pokeActivity(),
                      onPointerHover: (_) => _pokeActivity(),
                      child: const ColoredBox(color: Color(0xFF000000)),
                    ),
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
      if (!(origin & popup.size).contains(e.localPosition)) continue;
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

  void _pokeActivity() {
    final now = DateTime.now();
    final last = _lastActivity;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastActivity = now;
    controller.wayland?.activity();
  }

  void _onShellPointerMove(PointerMoveEvent e, Size screen) {
    _pointerPos.value = e.localPosition;
    final resize = controller.surfaceResize;
    if (resize != null) {
      controller.resizeWindow(
        resize.id,
        e.localDelta,
        resize.edge,
        _defaultWindowSize(screen),
      );
      return;
    }
    final id = controller.surfaceDragWindowId;
    if (id != null) {
      controller.dragWindow(id, e.localDelta, screen);
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

  List<Widget> _layerItems(int layer) {
    final service = controller.wayland;
    if (service == null) return const [];
    final screen = MediaQuery.sizeOf(context);
    return [
      for (final s in service.layerSurfaces(layer))
        if (s.size.width > 0 && s.size.height > 0)
          () {
            var rect = layerSurfaceRect(s, screen);
            for (final o in service.outputs) {
              if (o.id == s.outputId) {
                rect = layerSurfaceRect(s, o.rect.size)
                    .shift(o.rect.topLeft);
                break;
              }
            }
            s.layerRect = rect;
            return Positioned.fromRect(
              key: ValueKey('layer-${s.id}'),
              rect: rect,
              child: LayerSurfaceView(surface: s, service: service),
            );
          }(),
    ];
  }

  Rect _windowHeadRect(ShellWindowData w, Size screen) {
    final wl = controller.wayland;
    final center = w.position + (w.size ?? Size.zero).center(Offset.zero);
    return (wl?.outputAt(center) ?? wl?.primaryOutput)?.rect ??
        (Offset.zero & screen);
  }

  Rect _zoomedRect(Rect head) {
    final wl = controller.wayland;
    final insets = wl?.exclusiveInsets ?? EdgeInsets.zero;
    final dockInset =
        head == (wl?.primaryOutput?.rect ?? head) ? kDockHeight : 0.0;
    return Rect.fromLTWH(
      head.left + insets.left,
      head.top + kMenuBarHeight + 4 + insets.top,
      math.max(0, head.width - insets.horizontal),
      math.max(
        0,
        head.height - kMenuBarHeight - 8 - insets.vertical - dockInset,
      ),
    );
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
    if (parent.isLayer) {
      final base = parent.layerRect;
      if (base == null) return null;
      final lbuf = logicalSurfaceSize(parent);
      final lsx = lbuf.width > 0 ? base.width / lbuf.width : 1.0;
      final lsy = lbuf.height > 0 ? base.height / lbuf.height : 1.0;
      final lpos =
          base.topLeft + Offset(offset.dx * lsx, offset.dy * lsy);
      final lscreen = MediaQuery.sizeOf(context);
      return Offset(
        lpos.dx.clamp(
          0,
          math.max(0, lscreen.width - popup.size.width),
        ),
        lpos.dy.clamp(
          0,
          math.max(0, lscreen.height - popup.size.height),
        ),
      );
    }
    final w = controller.windowForSurface(parent.id);
    if (w == null) return null;
    if (w.minimized || w.workspace != controller.activeWorkspace) {
      return null;
    }
    final buf = logicalSurfaceSize(parent);
    final sx = buf.width > 0 ? parent.size.width / buf.width : 1.0;
    final sy = buf.height > 0 ? parent.size.height / buf.height : 1.0;
    final head = _windowHeadRect(w, MediaQuery.sizeOf(context));
    final base = w.fullscreen
        ? head.topLeft
        : w.zoomed
        ? head.topLeft + const Offset(0, kMenuBarHeight + 4)
        : w.position;
    var pos =
        base +
        (w.fullscreen ? Offset.zero : Offset(0, w.titleBarHeight)) +
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
    if (w.zoomed) return _zoomedRect(_windowHeadRect(w, screen));
    return w.position & _windowSize(w, screen);
  }

  Widget _windowContent(ShellWindowData w, BuildContext context, Size size) {
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
        escReserved:
            controller.openMenu != null ||
            controller.launcherOpen ||
            controller.launchPadOpen ||
            controller.controlCenterOpen ||
            controller.switcherIndex != null,
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
    return OasisWindow(
      title: w.displayTitle,
      focused: controller.focusedId == w.id,
      decorated: !w.clientDecorated,
      width: size.width,
      height: size.height,
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
              _defaultWindowSize(MediaQuery.sizeOf(context)),
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
    final x = controller.menuAnchor?.left ?? 40;
    final max = MediaQuery.sizeOf(context).width - 218;
    return x.clamp(0.0, max > 0 ? max : 0.0);
  }
}
