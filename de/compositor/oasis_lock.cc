#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <pthread.h>
#include <unistd.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void idle_activity(OasisPrivate* c) {
  if (c->idle_notifier != nullptr && c->seat != nullptr) {
    wlr_idle_notifier_v1_notify_activity(c->idle_notifier, c->seat);
  }
}

void idle_resync_inhibit(OasisPrivate* c) {
  if (c->idle_notifier != nullptr) {
    wlr_idle_notifier_v1_set_inhibited(c->idle_notifier,
                                     c->active_inhibitors > 0);
  }
}

void announce_lock_surface(Surface* s) {
  OasisPrivate* c = s->comp;
  s->announced = true;
  OEvent m;
  m["textureId"] = s->texture_id;
  emit_id(s, "lockSurface", std::move(m));
  emit_size(s);
  wlr_surface_send_enter(s->wlr, c->output);
  wlr_fractional_scale_v1_notify_scale(s->wlr, (double)c->out_scale);
  comp_flush(c);
}

static void lock_surf_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, lock_surf_destroy);
  s->lock_surface = nullptr;
  wl_list_remove(&s->lock_surf_destroy.link);
  wl_list_init(&s->lock_surf_destroy.link);
}

void lock_surface_new(OasisPrivate* c,
                      wlr_session_lock_surface_v1* lock_surface) {
  if (lock_surface->output == nullptr) lock_surface->output = c->output;
  Surface* s = surface_of(c, lock_surface->surface);
  if (s == nullptr) {
    surface_new(c, lock_surface->surface);
    s = surface_of(c, lock_surface->surface);
  }
  s->lock_surface = lock_surface;
  s->role = ROLE_LOCK;
  if (s->public_id == 0) {
    s->public_id = c->next_id++;
    c->by_id[s->public_id] = s;
  }
  s->lock_surf_destroy.notify = lock_surf_destroyed;
  wl_signal_add(&lock_surface->events.destroy, &s->lock_surf_destroy);
  wlr_session_lock_surface_v1_configure(lock_surface, c->out_w, c->out_h);
  comp_flush(c);
}

static void session_done(OasisPrivate* c) {
  wl_list_remove(&c->lock_new_surface.link);
  wl_list_remove(&c->lock_unlock.link);
  wl_list_remove(&c->lock_destroy.link);
  wl_list_init(&c->lock_new_surface.link);
  wl_list_init(&c->lock_unlock.link);
  wl_list_init(&c->lock_destroy.link);
  c->lock = nullptr;
  if (!c->stopping) emit(c, "sessionUnlock");
}

static void lock_unlocked(wl_listener* listener, void*) {
  OasisPrivate* c = wl_container_of(listener, c, lock_unlock);
  session_done(c);
}

static void lock_destroyed(wl_listener* listener, void*) {
  OasisPrivate* c = wl_container_of(listener, c, lock_destroy);
  session_done(c);
}

static void lock_new_surface(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, lock_new_surface);
  lock_surface_new(c, static_cast<wlr_session_lock_surface_v1*>(data));
}

void session_lock_new(OasisPrivate* c, wlr_session_lock_v1* lock) {
  if (c->lock != nullptr) {
    wlr_session_lock_v1_destroy(lock);
    return;
  }
  c->lock = lock;
  c->lock_new_surface.notify = lock_new_surface;
  wl_signal_add(&lock->events.new_surface, &c->lock_new_surface);
  c->lock_unlock.notify = lock_unlocked;
  wl_signal_add(&lock->events.unlock, &c->lock_unlock);
  c->lock_destroy.notify = lock_destroyed;
  wl_signal_add(&lock->events.destroy, &c->lock_destroy);
  seat_focus(c, nullptr);
  emit(c, "sessionLock");
  wlr_session_lock_v1_send_locked(lock);
  comp_flush(c);
}

}  // namespace oasis
