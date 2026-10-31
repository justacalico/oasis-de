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

void constraint_drop(OasisPrivate* c) {
  if (c->constraint == nullptr) return;
  Surface* s = surface_of(c, c->constraint->surface);
  bool locked = c->constraint->type == WLR_POINTER_CONSTRAINT_V1_LOCKED;
  wl_list_remove(&c->constraint_destroy.link);
  wl_list_init(&c->constraint_destroy.link);
  wlr_pointer_constraint_v1_send_deactivated(c->constraint);
  c->constraint = nullptr;
  if (locked && s != nullptr && s->announced) {
    OEvent m;
    m["on"] = false;
    emit_id(s, "pointerLock", std::move(m));
  }
}

void constraint_activate(OasisPrivate* c, Surface* s, double sx, double sy) {
  if (c->constraints_mgr == nullptr || s == nullptr || s->wlr == nullptr) {
    return;
  }
  auto* con = wlr_pointer_constraints_v1_constraint_for_surface(
      c->constraints_mgr, s->wlr, c->seat);
  if (con == c->constraint) return;
  constraint_drop(c);
  if (con == nullptr) return;
  c->constraint = con;
  c->constraint_destroy.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, constraint_destroy);
    auto* con = static_cast<wlr_pointer_constraint_v1*>(data);
    Surface* s = surface_of(c, con->surface);
    if (con->type == WLR_POINTER_CONSTRAINT_V1_LOCKED && s != nullptr &&
        s->announced) {
      OEvent m;
      m["on"] = false;
      emit_id(s, "pointerLock", std::move(m));
    }
    c->constraint = nullptr;
    wl_list_remove(&listener->link);
    wl_list_init(&listener->link);
  };
  wl_signal_add(&con->events.destroy, &c->constraint_destroy);
  wlr_pointer_constraint_v1_send_activated(con);
  if (con->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) {
    c->lock_sx = sx;
    c->lock_sy = sy;
    if (s->announced) {
      OEvent m;
      m["on"] = true;
      emit_id(s, "pointerLock", std::move(m));
    }
  }
}

void ksi_sync(Surface* s) {
  bool focused = s->comp->kb_focus == s;
  for (KsInhibitor* k : s->ks_inhibitors) {
    if (focused == k->inh->active) continue;
    if (focused) {
      wlr_keyboard_shortcuts_inhibitor_v1_activate(k->inh);
    } else {
      wlr_keyboard_shortcuts_inhibitor_v1_deactivate(k->inh);
    }
    if (s->announced) {
      OEvent m;
      m["on"] = focused;
      emit_id(s, "shortcutsInhibit", std::move(m));
    }
  }
}

void seat_focus(OasisPrivate* c, Surface* s) {
  if (c->kb_focus == s) return;
  Surface* old = c->kb_focus;
  c->kb_focus = s;
  if (old != nullptr) ksi_sync(old);
  if (s != nullptr) ksi_sync(s);
  if (s == nullptr || s->wlr == nullptr) {
    wlr_seat_keyboard_notify_clear_focus(c->seat);
    sync_text_input_focus(c);
    return;
  }
  std::vector<uint32_t> keys(c->pressed.begin(), c->pressed.end());
  wlr_seat_keyboard_notify_enter(
      c->seat, s->wlr, keys.data(), keys.size(),
      c->vkb != nullptr ? &c->vkb->modifiers : nullptr);
  if (s->xsurface != nullptr) {
    wlr_xwayland_surface_activate(s->xsurface, true);
  }
  sync_text_input_focus(c);
}

}  // namespace oasis

using namespace oasis;

void OasisCore::pointerMotion(int64_t id, double x, double y) {
  if (idle_wake(p)) return;
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->wlr == nullptr) return;
  if (p->lock != nullptr && s->role != ROLE_LOCK) return;
  if (p->constraint != nullptr && s->wlr != p->constraint->surface) {
    s = surface_of(p, p->constraint->surface);
    if (s == nullptr || s->wlr == nullptr) {
      constraint_drop(p);
      return;
    }
  }
  double dx = 0, dy = 0;
  if (p->ptr_in_id == id) {
    dx = x - p->ptr_in_x;
    dy = y - p->ptr_in_y;
  }
  p->ptr_in_id = id;
  p->ptr_in_x = x;
  p->ptr_in_y = y;
  if (p->constraint == nullptr) constraint_activate(p, s, x, y);
  if (p->ptr_focus != s) {
    p->ptr_focus = s;
    wlr_seat_pointer_notify_enter(p->seat, s->wlr, x, y);
  }
  if ((dx != 0 || dy != 0) && p->rel_ptr_mgr != nullptr) {
    wlr_relative_pointer_manager_v1_send_relative_motion(
        p->rel_ptr_mgr, p->seat, (uint64_t)now_ms() * 1000, dx, dy, dx, dy);
  }
  if (p->constraint != nullptr &&
      p->constraint->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) {
    wlr_seat_pointer_notify_motion(p->seat, now_ms(), p->lock_sx,
                                   p->lock_sy);
  } else {
    if (p->constraint != nullptr) {
      auto* b = pixman_region32_extents(&p->constraint->region);
      if (b->x2 > b->x1 && b->y2 > b->y1) {
        if (x < b->x1) x = b->x1;
        if (x > b->x2 - 1) x = b->x2 - 1;
        if (y < b->y1) y = b->y1;
        if (y > b->y2 - 1) y = b->y2 - 1;
      }
    }
    wlr_seat_pointer_notify_motion(p->seat, now_ms(), x, y);
  }
  wlr_seat_pointer_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::pointerExit() {
  p->ptr_in_id = -1;
  if (p->constraint != nullptr) return;
  wlr_seat_pointer_notify_clear_focus(p->seat);
  p->ptr_focus = nullptr;
  if (p->cursor_surface != nullptr) {
    if (p->cursor_surface->role == ROLE_CURSOR) {
      p->cursor_surface->role = ROLE_NONE;
    }
    p->cursor_surface = nullptr;
    emit_cursor(p);
  }
  comp_flush(p);
}

void OasisCore::pointerButton(uint32_t button, bool pressed) {
  if (idle_wake(p)) return;
  uint32_t serial = wlr_seat_pointer_notify_button(
      p->seat, now_ms(), button,
      pressed ? WL_POINTER_BUTTON_STATE_PRESSED
              : WL_POINTER_BUTTON_STATE_RELEASED);
  if (pressed && serial != 0) p->last_button_serial = serial;
  wlr_seat_pointer_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::pointerAxis(double dx, double dy, uint32_t source,
                                  int32_t discrete) {
  if (idle_wake(p)) return;
  auto src = static_cast<wl_pointer_axis_source>(source);
  if (dx != 0) {
    wlr_seat_pointer_notify_axis(
        p->seat, now_ms(), WL_POINTER_AXIS_HORIZONTAL_SCROLL, dx, discrete,
        src, WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
  }
  if (dy != 0) {
    wlr_seat_pointer_notify_axis(
        p->seat, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, dy, discrete,
        src, WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
  }
  wlr_seat_pointer_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::pointerAxisStop() {
  wlr_seat_pointer_notify_axis(
      p->seat, now_ms(), WL_POINTER_AXIS_HORIZONTAL_SCROLL, 0, 0,
      WL_POINTER_AXIS_SOURCE_CONTINUOUS,
      WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
  wlr_seat_pointer_notify_axis(
      p->seat, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, 0, 0,
      WL_POINTER_AXIS_SOURCE_CONTINUOUS,
      WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
  wlr_seat_pointer_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::touchDown(int64_t id, int32_t tid, double x, double y) {
  if (idle_wake(p)) return;
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->wlr == nullptr) return;
  if (p->lock != nullptr && s->role != ROLE_LOCK) return;
  p->touch_id = tid;
  wlr_seat_touch_notify_down(p->seat, s->wlr, now_ms(), tid, x, y);
  wlr_seat_touch_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::touchMotion(int32_t tid, double x, double y) {
  if (idle_wake(p)) return;
  wlr_seat_touch_notify_motion(p->seat, now_ms(), tid, x, y);
  wlr_seat_touch_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::touchUp(int32_t tid) {
  if (idle_wake(p)) return;
  wlr_seat_touch_notify_up(p->seat, now_ms(), tid);
  wlr_seat_touch_notify_frame(p->seat);
  p->touch_id = -1;
  comp_flush(p);
}

void OasisCore::activity() { idle_activity(p); }

void OasisCore::key(uint32_t code, bool pressed_key) {
  if (idle_wake(p)) return;
  if (p->vkb == nullptr) return;
  if (pressed_key) {
    p->pressed.insert(code);
  } else {
    p->pressed.erase(code);
  }
  wlr_keyboard_key_event ev = {};
  ev.time_msec = now_ms();
  ev.keycode = code;
  ev.state = pressed_key ? WL_KEYBOARD_KEY_STATE_PRESSED
                         : WL_KEYBOARD_KEY_STATE_RELEASED;
  ev.update_state = true;
  wlr_keyboard_notify_key(p->vkb, &ev);
  comp_flush(p);
}
