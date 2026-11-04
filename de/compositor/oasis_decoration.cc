#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void apply_decoration(Surface* s) {
  if (s->deco == nullptr || s->xdg == nullptr || !s->xdg->initialized) {
    return;
  }
  auto mode = s->deco->requested_mode;
  if (mode == WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_NONE) {
    mode = WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
  }
  wlr_xdg_toplevel_decoration_v1_set_mode(s->deco, mode);
}

void emit_decoration(Surface* s) {
  if (!s->announced || s->role != ROLE_TOPLEVEL) return;
  int mode = 2;
  if (s->xsurface != nullptr) {
    if (s->xsurface->decorations !=
        WLR_XWAYLAND_SURFACE_DECORATIONS_ALL) {
      mode = 1;
    }
  } else if (s->deco != nullptr && s->deco->scheduled_mode != 0) {
    mode = (int)s->deco->scheduled_mode;
  } else if (s->kde_deco != nullptr && s->kde_req) {
    mode = (int)s->kde_deco->mode;
  }
  if (mode == s->rep_deco) return;
  s->rep_deco = mode;
  OEvent m;
  m["mode"] = (int64_t)mode;
  emit_id(s, "decoration", std::move(m));
}

static void deco_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, deco_destroy);
  s->deco = nullptr;
  wl_list_remove(&listener->link);
  wl_list_init(&listener->link);
  wl_list_remove(&s->deco_request.link);
  wl_list_init(&s->deco_request.link);
  emit_decoration(s);
}

static void deco_requested(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, deco_request);
  apply_decoration(s);
  emit_decoration(s);
  comp_flush(s->comp);
}

static void handle_new_decoration(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_decoration);
  auto* deco = static_cast<wlr_xdg_toplevel_decoration_v1*>(data);
  Surface* s = surface_of(c, deco->toplevel->base->surface);
  if (s == nullptr) return;
  s->deco = deco;
  s->deco_destroy.notify = deco_destroyed;
  wl_signal_add(&deco->events.destroy, &s->deco_destroy);
  s->deco_request.notify = deco_requested;
  wl_signal_add(&deco->events.request_mode, &s->deco_request);
  apply_decoration(s);
}

static void kde_mode_changed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, kde_mode);
  s->kde_req = true;
  emit_decoration(s);
}

static void kde_deco_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, kde_destroy);
  s->kde_deco = nullptr;
  s->kde_req = false;
  wl_list_remove(&s->kde_mode.link);
  wl_list_init(&s->kde_mode.link);
  wl_list_remove(&s->kde_destroy.link);
  wl_list_init(&s->kde_destroy.link);
  emit_decoration(s);
}

static void handle_new_server_decoration(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_server_decoration);
  auto* deco = static_cast<wlr_server_decoration*>(data);
  Surface* s = surface_of(c, deco->surface);
  if (s == nullptr || s->role != ROLE_TOPLEVEL || s->deco != nullptr) {
    return;
  }
  s->kde_deco = deco;
  s->kde_mode.notify = kde_mode_changed;
  wl_signal_add(&deco->events.mode, &s->kde_mode);
  s->kde_destroy.notify = kde_deco_destroyed;
  wl_signal_add(&deco->events.destroy, &s->kde_destroy);
  emit_decoration(s);
}

void decoration_init(OasisPrivate* c) {
  c->new_decoration.notify = handle_new_decoration;
  wl_signal_add(&c->deco_mgr->events.new_toplevel_decoration,
                &c->new_decoration);
  c->new_server_decoration.notify = handle_new_server_decoration;
  wl_signal_add(&c->kde_deco_mgr->events.new_decoration,
                &c->new_server_decoration);
}

}  // namespace oasis
