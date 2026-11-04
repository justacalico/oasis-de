#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <algorithm>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void remove_listeners(Surface* s) {
  wl_list_remove(&s->commit.link);
  wl_list_remove(&s->destroy.link);
  wl_list_remove(&s->map.link);
  wl_list_remove(&s->unmap.link);
  wl_list_remove(&s->new_sub.link);
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
  wl_list_remove(&s->xs_destroy.link);
  wl_list_remove(&s->xs_associate.link);
  wl_list_remove(&s->xs_dissociate.link);
  wl_list_remove(&s->xs_title.link);
  wl_list_remove(&s->xs_class.link);
  wl_list_remove(&s->xs_parent.link);
  wl_list_remove(&s->xs_request_configure.link);
  wl_list_remove(&s->xs_request_activate.link);
  wl_list_remove(&s->xs_request_move.link);
  wl_list_remove(&s->xs_request_resize.link);
  wl_list_remove(&s->xs_request_minimize.link);
  wl_list_remove(&s->xs_request_maximize.link);
  wl_list_remove(&s->xs_request_fullscreen.link);
  wl_list_remove(&s->xs_request_close.link);
  wl_list_remove(&s->layer_destroy.link);
  wl_list_remove(&s->layer_new_popup.link);
  wl_list_remove(&s->lock_surf_destroy.link);
  wl_list_remove(&s->deco_destroy.link);
  wl_list_remove(&s->deco_request.link);
  wl_list_remove(&s->kde_mode.link);
  wl_list_remove(&s->kde_destroy.link);
  wl_list_remove(&s->xs_decorations.link);
}

void init_surface_listeners(Surface* s) {
  wl_list_init(&s->commit.link);
  wl_list_init(&s->destroy.link);
  wl_list_init(&s->map.link);
  wl_list_init(&s->unmap.link);
  wl_list_init(&s->new_sub.link);
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
  wl_list_init(&s->xs_destroy.link);
  wl_list_init(&s->xs_associate.link);
  wl_list_init(&s->xs_dissociate.link);
  wl_list_init(&s->xs_title.link);
  wl_list_init(&s->xs_class.link);
  wl_list_init(&s->xs_parent.link);
  wl_list_init(&s->xs_request_configure.link);
  wl_list_init(&s->xs_request_activate.link);
  wl_list_init(&s->xs_request_move.link);
  wl_list_init(&s->xs_request_resize.link);
  wl_list_init(&s->xs_request_minimize.link);
  wl_list_init(&s->xs_request_maximize.link);
  wl_list_init(&s->xs_request_fullscreen.link);
  wl_list_init(&s->xs_request_close.link);
  wl_list_init(&s->layer_destroy.link);
  wl_list_init(&s->layer_new_popup.link);
  wl_list_init(&s->lock_surf_destroy.link);
  wl_list_init(&s->deco_destroy.link);
  wl_list_init(&s->deco_request.link);
  wl_list_init(&s->kde_mode.link);
  wl_list_init(&s->kde_destroy.link);
  wl_list_init(&s->xs_decorations.link);
}

void free_surface(Surface* s) {
  OasisPrivate* c = s->comp;
  if (s->announced && !c->stopping) {
    if (s->role == ROLE_POPUP) {
      emit_id(s, "popupClosed");
    } else if (s->role == ROLE_SUBSURFACE) {
      emit_id(s, "subsurfaceClosed");
    } else if (s->role == ROLE_LAYER) {
      emit_id(s, "layerClosed");
    } else if (s->role == ROLE_LOCK) {
      emit_id(s, "lockSurfaceClosed");
    } else {
      emit_id(s, "toplevelClosed");
    }
  }
  s->announced = false;
  if (c->kb_focus == s) c->kb_focus = nullptr;
  if (c->activated == s) c->activated = nullptr;
  if (c->ptr_focus == s) c->ptr_focus = nullptr;
  if (c->cursor_surface == s) {
    c->cursor_surface = nullptr;
    emit_cursor(c);
  }
  for (Surface* x : c->surfaces) {
    if (x->parent == s) x->parent = nullptr;
    if (x->tl_parent == s) x->tl_parent = nullptr;
  }
  for (Inhibitor* inh : s->inhibitors) {
    wl_list_remove(&inh->destroy.link);
    delete inh;
  }
  s->inhibitors.clear();
  for (KsInhibitor* k : s->ks_inhibitors) {
    wl_list_remove(&k->destroy.link);
    delete k;
  }
  s->ks_inhibitors.clear();
  if (s->rb_tex != nullptr) wlr_texture_destroy(s->rb_tex);
  if (s->readback != nullptr) wlr_buffer_drop(s->readback);
  if (s->acquire_waiting) {
    wlr_drm_syncobj_timeline_waiter_finish(&s->acquire_waiter);
    s->acquire_waiting = false;
  }
  if (s->exported != nullptr) {
    wlr_buffer_unlock(s->exported);
    s->exported = nullptr;
  }
  if (s->frame_pending) {
    s->frame_pending = false;
    if (c->pending_frames > 0) c->pending_frames--;
  }
  drop_texture(s);
  c->by_id.erase(s->public_id);
  if (s->wlr != nullptr) c->by_wlr.erase(s->wlr);
  if (s->xsurface != nullptr) {
    c->by_xsurface.erase(s->xsurface);
    s->xsurface = nullptr;
  }
  auto& v = c->surfaces;
  v.erase(std::remove(v.begin(), v.end(), s), v.end());
  remove_listeners(s);
  delete s;
}

void announce_toplevel(Surface* s) {
  s->announced = true;
  OEvent m;
  m["textureId"] = s->texture_id;
  m["title"] = s->title;
  m["appId"] = s->app_id;
  m["parent"] = s->tl_parent != nullptr ? s->tl_parent->public_id : -1;
  emit_id(s, "toplevel", std::move(m));
  emit_size(s);
  surface_sync_outputs(s);
  if (!s->inhibitors.empty()) {
    OEvent im;
    im["on"] = true;
    emit_id(s, "idleInhibit", std::move(im));
  }
  for (KsInhibitor* k : s->ks_inhibitors) {
    if (k->inh->active) {
      OEvent im;
      im["on"] = true;
      emit_id(s, "shortcutsInhibit", std::move(im));
      break;
    }
  }
}

static void maybe_announce(Surface* s) {
  if (s->announced || s->wlr == nullptr || !s->wlr->mapped) return;
  if (s->role == ROLE_TOPLEVEL) {
    announce_toplevel(s);
  } else if (s->role == ROLE_LAYER) {
    announce_layer(s);
  } else if (s->role == ROLE_LOCK) {
    announce_lock_surface(s);
  }
}

static void surface_commit(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, commit);
  send_initial_configure(s);
  frame_pending_add(s);
  bool exported = export_frame(s);
  maybe_announce(s);
  if (s->announced) {
    emit_size(s);
    emit_decoration(s);
    emit_input_region(s);
    check_minmax(s);
    check_position(s);
    if (s->role == ROLE_LAYER && s->layer != nullptr) {
      emit_layer_current(s);
    }
  }
  if (s->parent != nullptr) check_child_order(s->parent);
  if (exported && s->texture_id >= 0 &&
      (s->announced || s == s->comp->cursor_surface)) {
    s->comp->host->frameAvailable(s->texture_id);
  }
  if (s == s->comp->cursor_surface) emit_cursor(s->comp);
}

static void surface_map(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, map);
  maybe_announce(s);
}

static void surface_unmap(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, unmap);
  s->iw = s->ih = 0;
  s->need_full = true;
  if (s->exported != nullptr) {
    wlr_buffer_unlock(s->exported);
    s->exported = nullptr;
  }
  if (s->announced) emit_size(s);
}

static void surface_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, destroy);
  if (s->wlr != nullptr) {
    s->comp->by_wlr.erase(s->wlr);
    s->wlr = nullptr;
  }
  free_surface(s);
}

static void surface_new_sub(wl_listener* listener, void* data) {
  Surface* parent = wl_container_of(listener, parent, new_sub);
  auto* sub = static_cast<wlr_subsurface*>(data);
  Surface* s = surface_of(parent->comp, sub->surface);
  if (s == nullptr) return;
  Surface* ps = surface_of(parent->comp, sub->parent);
  s->role = ROLE_SUBSURFACE;
  s->announced = true;
  s->parent = ps;
  if (s->public_id == 0) {
    s->public_id = parent->comp->next_id++;
    parent->comp->by_id[s->public_id] = s;
  }
  s->sx = sub->current.x;
  s->sy = sub->current.y;
  s->rep_sx = s->sx;
  s->rep_sy = s->sy;
  OEvent m;
  m["parent"] = ps != nullptr ? ps->public_id : -1;
  m["x"] = (int64_t)s->sx;
  m["y"] = (int64_t)s->sy;
  m["textureId"] = s->texture_id;
  emit_id(s, "subsurface", std::move(m));
  emit_size(s);
}

// Xwayland surfaces can lose their wl_surface on dissociate and get a new
// one on the next map. Leaving the listeners linked on the old surface
// means a later attach_wlr inserts the same wl_listener nodes into a
// second signal list, which corrupts both lists.
void detach_wlr(Surface* s) {
  if (s->wlr == nullptr) return;
  s->comp->by_wlr.erase(s->wlr);
  s->wlr = nullptr;
  wl_list_remove(&s->commit.link);
  wl_list_init(&s->commit.link);
  wl_list_remove(&s->destroy.link);
  wl_list_init(&s->destroy.link);
  wl_list_remove(&s->map.link);
  wl_list_init(&s->map.link);
  wl_list_remove(&s->unmap.link);
  wl_list_init(&s->unmap.link);
  wl_list_remove(&s->new_sub.link);
  wl_list_init(&s->new_sub.link);
}

void attach_wlr(Surface* s, wlr_surface* wlr) {
  s->wlr = wlr;
  s->comp->by_wlr[wlr] = s;
  wl_client_get_credentials(wl_resource_get_client(wlr->resource),
                            &s->pid, nullptr, nullptr);
  s->commit.notify = surface_commit;
  wl_signal_add(&wlr->events.commit, &s->commit);
  s->map.notify = surface_map;
  wl_signal_add(&wlr->events.map, &s->map);
  s->unmap.notify = surface_unmap;
  wl_signal_add(&wlr->events.unmap, &s->unmap);
  s->destroy.notify = surface_destroyed;
  wl_signal_add(&wlr->events.destroy, &s->destroy);
  s->new_sub.notify = surface_new_sub;
  wl_signal_add(&wlr->events.new_subsurface, &s->new_sub);
}

void surface_new(OasisPrivate* c, wlr_surface* wlr) {
  if (c->by_wlr.count(wlr)) return;
  auto* s = new Surface();
  s->comp = c;
  init_surface_listeners(s);
  attach_wlr(s, wlr);
  c->surfaces.push_back(s);
}

void surfaces_init(OasisPrivate* c) {
  c->new_surface.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, new_surface);
    surface_new(c, static_cast<wlr_surface*>(data));
  };
  wl_signal_add(&c->compositor->events.new_surface, &c->new_surface);
}

}  // namespace oasis
