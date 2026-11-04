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

void idle_arm(OasisPrivate* c) {
  if (c->idle_off_timer != nullptr) {
    if (c->power_on && c->active_inhibitors == 0 && c->idle_off_ms > 0) {
      wl_event_source_timer_update(c->idle_off_timer, c->idle_off_ms);
    } else {
      wl_event_source_timer_update(c->idle_off_timer, 0);
    }
  }
  if (c->idle_suspend_timer != nullptr) {
    if (c->active_inhibitors == 0 && c->idle_suspend_ms > 0) {
      wl_event_source_timer_update(c->idle_suspend_timer,
                                   c->idle_suspend_ms);
    } else {
      wl_event_source_timer_update(c->idle_suspend_timer, 0);
    }
  }
}

void output_power_set(OasisPrivate* c, bool on) {
  if (c->power_on == on) return;
  c->power_on = on;
  OEvent m;
  m["on"] = on;
  emit(c, "outputPower", std::move(m));
}

void idle_activity(OasisPrivate* c) {
  if (c->display == nullptr) return;
  if (c->idle_notifier != nullptr && c->seat != nullptr) {
    wlr_idle_notifier_v1_notify_activity(c->idle_notifier, c->seat);
  }
  output_power_set(c, true);
  idle_arm(c);
}

bool idle_wake(OasisPrivate* c) {
  const bool was_off = !c->power_on;
  idle_activity(c);
  return was_off;
}

void idle_resync_inhibit(OasisPrivate* c) {
  if (c->idle_notifier != nullptr) {
    wlr_idle_notifier_v1_set_inhibited(c->idle_notifier,
                                     c->active_inhibitors > 0);
  }
  idle_arm(c);
}

static int idle_off(void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  output_power_set(c, false);
  idle_arm(c);
  return 0;
}

void idle_off_timer_start(OasisPrivate* c) {
  c->idle_off_timer = wl_event_loop_add_timer(c->loop, idle_off, c);
  idle_arm(c);
}

static int idle_suspend(void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  emit(c, "idleSuspend");
  comp_flush(c);
  idle_arm(c);
  return 0;
}

void idle_suspend_timer_start(OasisPrivate* c) {
  c->idle_suspend_timer =
      wl_event_loop_add_timer(c->loop, idle_suspend, c);
  idle_arm(c);
}

void announce_lock_surface(Surface* s) {
  s->announced = true;
  OEvent m;
  m["textureId"] = s->texture_id;
  emit_id(s, "lockSurface", std::move(m));
  emit_size(s);
  surface_sync_outputs(s);
  comp_flush(s->comp);
}

static void lock_surf_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, lock_surf_destroy);
  s->lock_surface = nullptr;
  wl_list_remove(&s->lock_surf_destroy.link);
  wl_list_init(&s->lock_surf_destroy.link);
  if (s->announced && s->role == ROLE_LOCK) {
    emit_id(s, "lockSurfaceClosed");
    s->announced = false;
    s->role = ROLE_NONE;
  }
}

void lock_surface_new(OasisPrivate* c,
                      wlr_session_lock_surface_v1* lock_surface) {
  if (lock_surface->output == nullptr) {
    OasisOutput* p = output_primary(c);
    if (p != nullptr) lock_surface->output = p->wlr;
  }
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
  OasisOutput* o = output_of(c, lock_surface->output);
  if (o == nullptr) o = output_primary(c);
  wlr_session_lock_surface_v1_configure(
      lock_surface, o != nullptr ? o->width : 1920,
      o != nullptr ? o->height : 1080);
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
  wlr_seat_pointer_notify_clear_focus(c->seat);
  c->ptr_focus = nullptr;
  c->ptr_in_id = -1;
  emit(c, "sessionLock");
  wlr_session_lock_v1_send_locked(lock);
  comp_flush(c);
}

void lock_init(OasisPrivate* c) {
  c->new_lock.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, new_lock);
    session_lock_new(c, static_cast<wlr_session_lock_v1*>(data));
  };
  wl_signal_add(&c->lock_mgr->events.new_lock, &c->new_lock);
}

void power_mode_set(OasisPrivate* c, wlr_output* output, uint32_t mode) {
  OasisOutput* o = output_of(c, output);
  if (o == nullptr) return;
  bool on = mode == ZWLR_OUTPUT_POWER_V1_MODE_ON;
  if (o->powered == on) return;
  o->powered = on;
  bool any = false;
  for (OasisOutput* x : c->outputs) {
    if (x->powered) any = true;
  }
  output_power_set(c, any);
}

void power_init(OasisPrivate* c) {
  c->power_set_mode.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, power_set_mode);
    auto* ev =
        static_cast<wlr_output_power_v1_set_mode_event*>(data);
    power_mode_set(c, ev->output, (uint32_t)ev->mode);
  };
  wl_signal_add(&c->power_mgr->events.set_mode, &c->power_set_mode);
}

}  // namespace oasis
