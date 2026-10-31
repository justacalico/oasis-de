# Compositor notes

`de/compositor/` is a wlroots-based Wayland compositor (wlroots 0.20) that
runs inside the Oasis shell. The split:

- `oasis_core.cc` — wl_display, headless backend, renderer/allocator,
  globals (seat, xdg-shell, dmabuf, fractional-scale, text-input-v3, ...)
  and timers.
- `oasis_surface.cc` — wl_surface lifecycle: commit, buffer export
  (texture readback, dmabuf, shm swizzle), size and input-region events.
- `oasis_xdg.cc` — xdg toplevels and popups.
- `oasis_xwayland.cc` — Xwayland surfaces.
- `oasis_input.cc` — seat input fed from Flutter pointer/touch/key events.
- `oasis_wlr.h` — wraps the C-only wlroots headers for C++ (`class`
  member names, and the `[static N]` array parameters added to
  `wlr/render/color.h` in 0.20).

`de/linux/runner/oasis_compositor.cc` is the Flutter bridge on top of the
core: it drives the wl_event_loop from GTK, registers `FlTexture`s and
forwards events over the method channel. `de/kms/oasis_kms.cc` drives the
same core directly on KMS/DRM via the Flutter embedder API.

## Configure tracking

Client `xdg_surface.ack_configure` arrives on wlroots' `ack_configure`
signal and is forwarded to Dart as `configureAcked` with the serial, so
the shell can distinguish "client applied a configure" from "configure
still in flight".

## Liveness

`wlr_xdg_surface_ping` is sent to every announced toplevel every 5
seconds; `ping_timeout` SIGKILLs the client's pid, which unblocks a shell
that would otherwise wait on dead processes. `closeSurface` schedules a
separate SIGTERM-then-SIGKILL escalation for toplevels that ignore a
close request.

## wlroots

Pinned at 0.20 in CI (built from source on Debian/Ubuntu; Fedora 44
ships 0.20.x natively). Since 0.20, upstream's installed headers are
self-contained, so CI no longer copies wayland-scanner `*-protocol.h`
output into the wlroots include dir. Signal data notes for future ports:
the manager `new_*` signals still pass the object, while the per-object
`wlr_text_input_v3`/`wlr_input_method_v2` signals pass NULL — our
handlers always recover the object via `wl_container_of`, so this is
already safe.
