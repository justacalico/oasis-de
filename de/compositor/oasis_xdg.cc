#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <signal.h>
#include <wayland-server.h>

#include <algorithm>

extern "C" {
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
}
#include <pthread.h>
#include <unistd.h>
#define class class_
extern "C" {
#include <wlr/xwayland/xwayland.h>
}
#undef class

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void popup_position(Surface* s, int* x, int* y) {
  *x = 0;
  *y = 0;
  if (s->xdg == nullptr || s->xdg->role != WLR_XDG_SURFACE_ROLE_POPUP ||
      s->xdg->popup == nullptr) {
    return;
  }
  double px = 0, py = 0;
  wlr_xdg_popup_get_position(s->xdg->popup, &px, &py);
  *x = (int)px;
  *y = (int)py;
}

void send_initial_configure(Surface* s) {
  if (s->cfg_sent || s->xdg == nullptr ||
      s->xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL ||
      s->xdg->toplevel == nullptr || !s->xdg->initialized) {
    return;
  }
  s->cfg_sent = true;
  if (s->deco != nullptr) {
    wlr_xdg_toplevel_decoration_v1_set_mode(
        s->deco, WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
  }
  wlr_xdg_toplevel* tl = s->xdg->toplevel;
  wlr_xdg_toplevel_set_wm_capabilities(
      tl, WLR_XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU |
              WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE |
              WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN |
              WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE);
  toplevel_configure(s, s->cfg_w, s->cfg_h, s->cfg_max, s == s->comp->activated,
                     s->cfg_fs, s->cfg_resizing);
}

void toplevel_configure(Surface* s, int w, int h, bool maximized, bool active,
                        bool fullscreen, bool resizing) {
  s->cfg_w = w;
  s->cfg_h = h;
  s->cfg_max = maximized;
  s->cfg_fs = fullscreen;
  s->cfg_resizing = resizing;
  if (s->xdg != nullptr && s->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL &&
      s->xdg->toplevel != nullptr && s->xdg->initialized) {
    wlr_xdg_toplevel* tl = s->xdg->toplevel;
    struct wlr_xdg_toplevel_configure cfg = {};
    cfg.width = w;
    cfg.height = h;
    cfg.maximized = maximized;
    cfg.activated = active;
    cfg.fullscreen = fullscreen;
    cfg.resizing = resizing;
    if (s->deco != nullptr) {
    wlr_xdg_toplevel_decoration_v1_set_mode(
        s->deco, WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
  }
  wlr_xdg_toplevel_configure(tl, &cfg);
  } else if (s->xsurface != nullptr) {
    wlr_xwayland_surface* xs = s->xsurface;
    wlr_xwayland_surface_configure(xs, xs->x, xs->y,
                                   w > 0 ? (uint16_t)w : xs->width,
                                   h > 0 ? (uint16_t)h : xs->height);
    wlr_xwayland_surface_set_maximized(xs, maximized, maximized);
    wlr_xwayland_surface_set_fullscreen(xs, fullscreen);
    wlr_xwayland_surface_activate(xs, active);
  }
  comp_flush(s->comp);
}

static void remove_role_listeners(Surface* s) {
  wl_list_remove(&s->xdg_destroy.link);
  wl_list_remove(&s->xdg_ack.link);
  wl_list_remove(&s->xdg_new_popup.link);
  wl_list_remove(&s->xdg_ping_timeout.link);
  wl_list_remove(&s->popup_reposition.link);
  wl_list_remove(&s->popup_destroy.link);
  wl_list_remove(&s->tl_parent_set.link);
  wl_list_remove(&s->tl_title.link);
  wl_list_remove(&s->tl_app_id.link);
  wl_list_remove(&s->tl_move.link);
  wl_list_remove(&s->tl_resize.link);
  wl_list_remove(&s->tl_max.link);
  wl_list_remove(&s->tl_fs.link);
  wl_list_remove(&s->tl_min.link);
  wl_list_remove(&s->tl_menu.link);
  wl_list_remove(&s->tl_destroy.link);
  wl_list_init(&s->xdg_destroy.link);
  wl_list_init(&s->xdg_ack.link);
  wl_list_init(&s->xdg_new_popup.link);
  wl_list_init(&s->xdg_ping_timeout.link);
  wl_list_init(&s->popup_reposition.link);
  wl_list_init(&s->popup_destroy.link);
  wl_list_init(&s->tl_parent_set.link);
  wl_list_init(&s->tl_title.link);
  wl_list_init(&s->tl_app_id.link);
  wl_list_init(&s->tl_move.link);
  wl_list_init(&s->tl_resize.link);
  wl_list_init(&s->tl_max.link);
  wl_list_init(&s->tl_fs.link);
  wl_list_init(&s->tl_min.link);
  wl_list_init(&s->tl_menu.link);
  wl_list_init(&s->tl_destroy.link);
}

static void xdg_surface_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xdg_destroy);
  s->xdg = nullptr;
  remove_role_listeners(s);
}

static void xdg_ack(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, xdg_ack);
  auto* cfg = static_cast<wlr_xdg_surface_configure*>(data);
  OEvent m;
  m["serial"] = (int64_t)cfg->serial;
  emit_id(s, "configureAcked", std::move(m));
}

static void xdg_ping_timeout(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xdg_ping_timeout);
  if (s->pid > 0) kill(s->pid, SIGKILL);
}

static void tl_set_parent(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_parent_set);
  wlr_xdg_toplevel* tl = s->xdg != nullptr ? s->xdg->toplevel : nullptr;
  Surface* p = nullptr;
  if (tl != nullptr && tl->parent != nullptr) {
    p = surface_of(s->comp, tl->parent->base->surface);
  }
  s->tl_parent = p;
  OEvent m;
  m["parent"] = p != nullptr ? p->public_id : -1;
  emit_id(s, "toplevelParent", std::move(m));
}

static void tl_set_title(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_title);
  wlr_xdg_toplevel* tl = s->xdg != nullptr ? s->xdg->toplevel : nullptr;
  s->title = tl != nullptr && tl->title != nullptr ? tl->title : "";
  OEvent m;
  m["title"] = s->title;
  emit_id(s, "title", std::move(m));
}

static void tl_set_app_id(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_app_id);
  wlr_xdg_toplevel* tl = s->xdg != nullptr ? s->xdg->toplevel : nullptr;
  s->app_id = tl != nullptr && tl->app_id != nullptr ? tl->app_id : "";
  OEvent m;
  m["appId"] = s->app_id;
  emit_id(s, "appId", std::move(m));
}

static void tl_request_move(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_move);
  emit_id(s, "move");
}

static void tl_request_resize(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, tl_resize);
  auto* ev = static_cast<wlr_xdg_toplevel_resize_event*>(data);
  OEvent m;
  m["edges"] = (int64_t)ev->edges;
  emit_id(s, "resize", std::move(m));
}

static void tl_request_max(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_max);
  wlr_xdg_toplevel* tl = s->xdg != nullptr ? s->xdg->toplevel : nullptr;
  OEvent m;
  m["on"] = tl != nullptr && tl->requested.maximized;
  emit_id(s, "maximize", std::move(m));
}

static void tl_request_fs(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_fs);
  wlr_xdg_toplevel* tl = s->xdg != nullptr ? s->xdg->toplevel : nullptr;
  OEvent m;
  m["on"] = tl != nullptr && tl->requested.fullscreen;
  emit_id(s, "fullscreen", std::move(m));
}

static void tl_request_min(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_min);
  emit_id(s, "minimize");
}

static void tl_request_menu(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, tl_menu);
  auto* ev =
      static_cast<wlr_xdg_toplevel_show_window_menu_event*>(data);
  OEvent m;
  m["x"] = (int64_t)ev->x;
  m["y"] = (int64_t)ev->y;
  emit_id(s, "windowMenu", std::move(m));
}

static void tl_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, tl_destroy);
  if (s->announced) {
    emit_id(s, "toplevelClosed");
    s->announced = false;
  }
  s->role = ROLE_NONE;
  s->xdg = nullptr;
  remove_role_listeners(s);
}

void toplevel_new(OasisPrivate* c, wlr_xdg_toplevel* tl) {
  wlr_xdg_surface* xdg = tl->base;
  Surface* s = surface_of(c, xdg->surface);
  if (s == nullptr) {
    surface_new(c, xdg->surface);
    s = surface_of(c, xdg->surface);
  }
  s->xdg = xdg;
  s->role = ROLE_TOPLEVEL;
  if (s->public_id == 0) {
    s->public_id = c->next_id++;
    c->by_id[s->public_id] = s;
  }
  s->title = tl->title != nullptr ? tl->title : "";
  s->app_id = tl->app_id != nullptr ? tl->app_id : "";

  s->xdg_destroy.notify = xdg_surface_destroyed;
  wl_signal_add(&xdg->events.destroy, &s->xdg_destroy);
  s->xdg_ack.notify = xdg_ack;
  wl_signal_add(&xdg->events.ack_configure, &s->xdg_ack);
  s->xdg_ping_timeout.notify = xdg_ping_timeout;
  wl_signal_add(&xdg->events.ping_timeout, &s->xdg_ping_timeout);
  s->tl_parent_set.notify = tl_set_parent;
  wl_signal_add(&tl->events.set_parent, &s->tl_parent_set);
  s->tl_title.notify = tl_set_title;
  wl_signal_add(&tl->events.set_title, &s->tl_title);
  s->tl_app_id.notify = tl_set_app_id;
  wl_signal_add(&tl->events.set_app_id, &s->tl_app_id);
  s->tl_move.notify = tl_request_move;
  wl_signal_add(&tl->events.request_move, &s->tl_move);
  s->tl_resize.notify = tl_request_resize;
  wl_signal_add(&tl->events.request_resize, &s->tl_resize);
  s->tl_max.notify = tl_request_max;
  wl_signal_add(&tl->events.request_maximize, &s->tl_max);
  s->tl_fs.notify = tl_request_fs;
  wl_signal_add(&tl->events.request_fullscreen, &s->tl_fs);
  s->tl_min.notify = tl_request_min;
  wl_signal_add(&tl->events.request_minimize, &s->tl_min);
  s->tl_menu.notify = tl_request_menu;
  wl_signal_add(&tl->events.request_show_window_menu, &s->tl_menu);
  s->tl_destroy.notify = tl_destroyed;
  wl_signal_add(&tl->events.destroy, &s->tl_destroy);

}


static void popup_repositioned(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, popup_reposition);
  int x = 0, y = 0;
  popup_position(s, &x, &y);
  s->sx = x;
  s->sy = y;
  s->rep_sx = x;
  s->rep_sy = y;
  OEvent m;
  m["x"] = (int64_t)x;
  m["y"] = (int64_t)y;
  emit_id(s, "popupMoved", std::move(m));
}

static void popup_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, popup_destroy);
  if (s->announced) {
    emit_id(s, "popupClosed");
    s->announced = false;
  }
  s->role = ROLE_NONE;
  s->xdg = nullptr;
  remove_role_listeners(s);
}

void popup_new(OasisPrivate* c, wlr_xdg_popup* popup) {
  wlr_xdg_surface* xdg = popup->base;
  Surface* s = surface_of(c, xdg->surface);
  if (s == nullptr) {
    surface_new(c, xdg->surface);
    s = surface_of(c, xdg->surface);
  }
  Surface* parent = surface_of(c, popup->parent);
  s->xdg = xdg;
  s->role = ROLE_POPUP;
  s->announced = true;
  s->parent = parent;
  if (s->public_id == 0) {
    s->public_id = c->next_id++;
    c->by_id[s->public_id] = s;
  }
  int x = 0, y = 0;
  popup_position(s, &x, &y);
  s->sx = x;
  s->sy = y;
  s->rep_sx = x;
  s->rep_sy = y;

  s->xdg_destroy.notify = xdg_surface_destroyed;
  wl_signal_add(&xdg->events.destroy, &s->xdg_destroy);
  s->popup_reposition.notify = popup_repositioned;
  wl_signal_add(&popup->events.reposition, &s->popup_reposition);
  s->popup_destroy.notify = popup_destroyed;
  wl_signal_add(&popup->events.destroy, &s->popup_destroy);

  OEvent m;
  m["parent"] = parent != nullptr ? parent->public_id : -1;
  m["textureId"] = s->texture_id;
  m["x"] = (int64_t)x;
  m["y"] = (int64_t)y;
  emit_id(s, "popup", std::move(m));
  comp_flush(c);
}

}  // namespace oasis
