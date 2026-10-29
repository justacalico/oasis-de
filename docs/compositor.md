# Compositor notes

`de/linux/runner/oasis_compositor.cc` is a hand-rolled wlroots-free
compositor for the Oasis shell. The texture path (EGLImage import, GL
texture population, pixel-buffer staging, dmabuf bookkeeping) lives in
`oasis_textures.{h,cc}`; protocol dispatch for surfaces, xdg-shell,
seat, data-device and linux-dmabuf remains in `oasis_compositor.cc`
and should keep splitting along those lines.

## Configure tracking

`xdg_surface.configure` serials are recorded as `pending_serial` on
each `Surface`. `ack_configure` verifies the serial against the last
one sent, records it in `acked_serial`, and emits a `configureAcked`
event on the event channel, so the shell can distinguish "client
applied a configure" from "configure still in flight".

## Liveness

`xdg_wm_base.ping` is sent to every bound client every 5 seconds.
`pong` resets the client's miss counter; three missed pings destroys
the `wl_client`, which unblocks a shell that would otherwise wait on
dead processes.

## wlroots

wlroots is the right answer for a production Wayland compositor and
the hand-rolled code here should be treated as scaffolding. Migrating
today buys scene-graph, dmabuf, and output-management code for free,
but it costs a GTK host process that owns the wl_display plus a bridge
between Flutter's render loop and wlroots' frame callbacks. Since the
current surface set is small (xdg toplevels, popups, subsurfaces,
cursors) and the custom path already works, the pragmatic order is:
finish per-protocol splits first, then evaluate `wlr_scene` + GTK
embed when multi-output or layer-shell lands on the roadmap.
