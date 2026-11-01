# Architecture

Oasis is a nested compositor. The whole shell is one Flutter app that runs as a normal GTK/Wayland client of the host session, and inside it a small embedded wayland-server hosts real Wayland applications in shell windows.

Installed sessions boot through `oasis-session`, which runs the shell under cage (a single-window Wayland kiosk compositor) so the shell is fullscreen and its nested compositor is the only place app windows can go. When running nested for development, any host compositor works the same way.

```
host compositor (cage in session, GNOME/Sway/... when nested)
  └─ oasis (Flutter + GTK)
       ├─ shell UI: menu bar, dock, launcher, control center
       ├─ bundled apps (settings, notes, ...) as Flutter widgets
       └─ oasis_compositor: wl_display listening on a unix socket
            └─ external apps (any Wayland client) → wl_surface → GL texture → Flutter Texture
```

## Pieces

- `de/` - the shell. `de/lib/shell/` is the desktop UI (desktop, menu bar, dock, launcher, launch pad, control center, window chrome). `de/lib/wayland/` is the Dart side of the compositor bridge: method channel, surface model, .desktop discovery.
- `de/linux/runner/oasis_compositor.cc` - the embedded compositor. Implements the globals below, imports client buffers (shm swizzle or dmabuf via EGL), and hands GL textures to Flutter over a method channel. Kept deliberately small; surface state lives in Dart.
- `packages/oasis_ui/` - theme engine and widget library shared by the shell and every bundled app.
- `apps/` - bundled apps written in plain Flutter against `oasis_ui` + `OasisHost`.
- `landing/` - the web landing page.

## Window model

Each external toplevel maps to a `WaylandSurface` in Dart and gets an `OasisWindow` (chrome: traffic lights, title, drag, resize). The compositor forwards xdg configure events through the channel; the shell decides geometry, focus, minimize/zoom/fullscreen and sends configure back. Decoration mode is negotiated per client: `zxdg_decoration_manager_v1` (and the KDE `server_decoration` protocol) grant whatever mode the client asks for, defaulting to server-side when it doesn't say. Clients that settle on client-side decorations are reported to the shell, which drops the `OasisWindow` title bar so the app's own header is the only one. XWayland clients get the same treatment via `_MOTIF_WM_HINTS`.

## Protocol support matrix

| Global / interface | Status | Notes |
|---|---|---|
| `wl_compositor`, `wl_surface`, `wl_region`, `wl_callback` | supported | frame callbacks sent at commit |
| `wl_subcompositor`, `wl_subsurface` | supported | |
| `wl_shm` | supported | client buffers swizzled to GL textures |
| `zwp_linux_dmabuf_v1` | supported | EGLImage import, zero-copy path |
| `wl_seat` (`wl_pointer`, `wl_keyboard`, `wl_touch`) | supported | input forwarded from Flutter pointer/key events |
| `wl_data_device_manager` | supported | clipboard + drag selection inside the session |
| `wl_output` | supported | single output advertized to clients |
| `xdg_wm_base`, `xdg_surface`, `xdg_toplevel`, `xdg_popup`, `xdg_positioner` | supported | |
| `zxdg_decoration_manager_v1` | supported | client's requested mode granted; server-side default |
| `org_kde_kwin_server_decoration` | supported | server-side default |
| `wp_viewporter`, `wp_fractional_scale_manager_v1` | supported | |
| `zwp_idle_inhibit_manager_v1`, `wp_cursor_shape_manager_v1`, `wp_presentation` | supported | |
| `xdg_activation_v1`, `zwp_text_input_manager_v3`, `zwp_primary_selection_device_manager_v1` | supported | |
| `zwlr_layer_shell_v1` | supported | third-party panels, wallpapers, OSDs |
| `ext_session_lock_v1`, `ext_idle_notify_v1` | supported | output blanks after 5 min idle unless inhibited |
| `ext_output_image_capture_source_manager_v1`, `ext_image_copy_capture_manager_v1` | supported | black frames while locked or blanked |
| `zwlr_output_power_manager_v1` | supported | |
| `zwp_pointer_constraints`, `relative-pointer`, `zwp_keyboard_shortcuts_inhibit_v1` | supported | |
| `xdg_foreign` | not implemented | |

X11 clients are unsupported until the compositor embeds Xwayland: `DISPLAY` and `XAUTHORITY` are stripped from spawned apps so they cannot escape to the host X server. Apps must run as Wayland clients.

## Bundled apps vs external apps

Bundled apps (`apps/settings`) are Dart packages whose windows are `OasisApp` entries: the shell builds their UI in-process, so they get theme, locale and host services for free. External apps are discovered from XDG `.desktop` files (`de/lib/wayland/desktop_entries.dart`), spawned with `WAYLAND_DISPLAY` pointing at the nested socket, and their `StartupWMClass`/appId is matched back to the launcher entry.

## State and services

`OasisStore` (shared_preferences) persists wallpaper, accent, locale and shell toggles. Update checks compare `PackageInfo` against GitLab releases. Real system services (NetworkManager, BlueZ, PipeWire) are reached per-feature; panes without a backend yet keep honest disabled UI rather than fake state.
