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

void seat_focus(OasisPrivate* c, Surface* s) {
  if (c->kb_focus == s) return;
  c->kb_focus = s;
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
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->wlr == nullptr) return;
  if (p->ptr_focus != s) {
    p->ptr_focus = s;
    wlr_seat_pointer_notify_enter(p->seat, s->wlr, x, y);
  }
  wlr_seat_pointer_notify_motion(p->seat, now_ms(), x, y);
  wlr_seat_pointer_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::pointerExit() {
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
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->wlr == nullptr) return;
  p->touch_id = tid;
  wlr_seat_touch_notify_down(p->seat, s->wlr, now_ms(), tid, x, y);
  wlr_seat_touch_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::touchMotion(int32_t tid, double x, double y) {
  wlr_seat_touch_notify_motion(p->seat, now_ms(), tid, x, y);
  wlr_seat_touch_notify_frame(p->seat);
  comp_flush(p);
}

void OasisCore::touchUp(int32_t tid) {
  wlr_seat_touch_notify_up(p->seat, now_ms(), tid);
  wlr_seat_touch_notify_frame(p->seat);
  p->touch_id = -1;
  comp_flush(p);
}

void OasisCore::key(uint32_t code, bool pressed_key) {
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
