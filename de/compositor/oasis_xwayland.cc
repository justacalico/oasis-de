#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <signal.h>
#include <wayland-server.h>

#include <algorithm>

#include <pthread.h>
#include <unistd.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

static void xs_sync_props(Surface* s) {
  wlr_xwayland_surface* xs = s->xsurface;
  if (xs == nullptr) return;
  s->title = xs->title != nullptr ? xs->title : "";
  if (xs->class_ != nullptr) {
    s->app_id = xs->class_;
  } else if (xs->instance != nullptr) {
    s->app_id = xs->instance;
  }
}

static void xs_emit_prop(Surface* s, const char* event,
                         const std::string& value) {
  OEvent m;
  m[event] = value;
  emit_id(s, event, std::move(m));
}

static void xs_free(Surface* s) {
  OasisPrivate* c = s->comp;
  if (s->xsurface != nullptr) {
    c->by_xsurface.erase(s->xsurface);
    s->xsurface = nullptr;
  }
  s->wlr = nullptr;
  free_surface(s);
}

static void xs_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_destroy);
  xs_free(s);
}

static void xs_dissociated(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_dissociate);
  if (s->wlr != nullptr) {
    s->comp->by_wlr.erase(s->wlr);
    s->wlr = nullptr;
  }
}

static void xs_associated(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_associate);
  wlr_xwayland_surface* xs = s->xsurface;
  if (xs == nullptr || xs->surface == nullptr) return;
  wlr_surface* wlr = xs->surface;
  Surface* auto_s = surface_of(s->comp, wlr);
  if (auto_s != nullptr && auto_s != s) {
    auto_s->announced = false;
    auto_s->comp->by_wlr.erase(wlr);
    auto_s->wlr = nullptr;
    remove_listeners(auto_s);
    auto& v = auto_s->comp->surfaces;
    v.erase(std::remove(v.begin(), v.end(), auto_s), v.end());
    auto_s->comp->by_id.erase(auto_s->public_id);
    delete auto_s;
  }
  attach_wlr(s, wlr);
}

static void xs_request_configure(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, xs_request_configure);
  auto* ev = static_cast<wlr_xwayland_surface_configure_event*>(data);
  if (s->xsurface != nullptr) {
    wlr_xwayland_surface_configure(s->xsurface, ev->x, ev->y, ev->width,
                                   ev->height);
  }
}

static void xs_request_activate(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_request_activate);
  if (s->announced) emit_id(s, "activate");
}

static void xs_request_move(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_request_move);
  if (s->announced) emit_id(s, "move");
}

static void xs_request_resize(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, xs_request_resize);
  auto* ev = static_cast<wlr_xwayland_resize_event*>(data);
  if (!s->announced) return;
  OEvent m;
  m["edges"] = (int64_t)ev->edges;
  emit_id(s, "resize", std::move(m));
}

static void xs_request_minimize(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_request_minimize);
  if (s->announced) emit_id(s, "minimize");
}

static void xs_request_maximize(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_request_maximize);
  if (!s->announced || s->xsurface == nullptr) return;
  OEvent m;
  m["on"] = s->xsurface->maximized_horz && s->xsurface->maximized_vert;
  emit_id(s, "maximize", std::move(m));
}

static void xs_request_fullscreen(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_request_fullscreen);
  if (!s->announced || s->xsurface == nullptr) return;
  OEvent m;
  m["on"] = s->xsurface->fullscreen;
  emit_id(s, "fullscreen", std::move(m));
}

static void xs_set_title(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_title);
  xs_sync_props(s);
  if (s->announced) xs_emit_prop(s, "title", s->title);
}

static void xs_set_class(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_class);
  xs_sync_props(s);
  if (s->announced) xs_emit_prop(s, "appId", s->app_id);
}

static void xs_set_parent(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, xs_parent);
  wlr_xwayland_surface* xs = s->xsurface;
  Surface* p = nullptr;
  if (xs != nullptr && xs->parent != nullptr) {
    auto it = s->comp->by_xsurface.find(xs->parent);
    if (it != s->comp->by_xsurface.end()) p = it->second;
  }
  s->tl_parent = p;
  if (!s->announced) return;
  OEvent m;
  m["parent"] = p != nullptr ? p->public_id : -1;
  emit_id(s, "toplevelParent", std::move(m));
}

void xwayland_new_surface(OasisPrivate* c, wlr_xwayland_surface* xs) {
  auto* s = new Surface();
  s->comp = c;
  s->xsurface = xs;
  s->role = ROLE_TOPLEVEL;
  s->public_id = c->next_id++;
  s->pid = xs->pid;
  init_surface_listeners(s);
  c->by_id[s->public_id] = s;
  c->by_xsurface[xs] = s;
  c->surfaces.push_back(s);
  xs_sync_props(s);
  if (xs->parent != nullptr) {
    auto it = c->by_xsurface.find(xs->parent);
    if (it != c->by_xsurface.end()) s->tl_parent = it->second;
  }

  s->xs_destroy.notify = xs_destroyed;
  wl_signal_add(&xs->events.destroy, &s->xs_destroy);
  s->xs_associate.notify = xs_associated;
  wl_signal_add(&xs->events.associate, &s->xs_associate);
  s->xs_dissociate.notify = xs_dissociated;
  wl_signal_add(&xs->events.dissociate, &s->xs_dissociate);
  s->xs_title.notify = xs_set_title;
  wl_signal_add(&xs->events.set_title, &s->xs_title);
  s->xs_class.notify = xs_set_class;
  wl_signal_add(&xs->events.set_class, &s->xs_class);
  s->xs_parent.notify = xs_set_parent;
  wl_signal_add(&xs->events.set_parent, &s->xs_parent);
  s->xs_request_configure.notify = xs_request_configure;
  wl_signal_add(&xs->events.request_configure, &s->xs_request_configure);
  s->xs_request_activate.notify = xs_request_activate;
  wl_signal_add(&xs->events.request_activate, &s->xs_request_activate);
  s->xs_request_move.notify = xs_request_move;
  wl_signal_add(&xs->events.request_move, &s->xs_request_move);
  s->xs_request_resize.notify = xs_request_resize;
  wl_signal_add(&xs->events.request_resize, &s->xs_request_resize);
  s->xs_request_minimize.notify = xs_request_minimize;
  wl_signal_add(&xs->events.request_minimize, &s->xs_request_minimize);
  s->xs_request_maximize.notify = xs_request_maximize;
  wl_signal_add(&xs->events.request_maximize, &s->xs_request_maximize);
  s->xs_request_fullscreen.notify = xs_request_fullscreen;
  wl_signal_add(&xs->events.request_fullscreen,
                &s->xs_request_fullscreen);
}

}  // namespace oasis
