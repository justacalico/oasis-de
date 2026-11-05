#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

static void handle_set_cursor(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_cursor);
  auto* ev = static_cast<wlr_seat_pointer_request_set_cursor_event*>(data);
  c->cursor_hx = ev->hotspot_x;
  c->cursor_hy = ev->hotspot_y;
  Surface* s = surface_of(c, ev->surface);
  if (c->cursor_surface != nullptr &&
      c->cursor_surface->role == ROLE_CURSOR &&
      c->cursor_surface != s) {
    c->cursor_surface->role = ROLE_NONE;
  }
  if (s != nullptr && s->role == ROLE_NONE) s->role = ROLE_CURSOR;
  c->cursor_surface = s;
  c->cursor_shape = 0;
  if (s != nullptr) {
    if (s->public_id == 0) {
      s->public_id = c->next_id++;
      c->by_id[s->public_id] = s;
    }
    // Cursor surfaces are never announced, so they would otherwise stay
    // scale-blind and keep committing scale-1 buffers on HiDPI outputs.
    surface_sync_outputs(s);
  }
  emit_cursor(c);
}

static void handle_set_selection(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_selection);
  auto* ev = static_cast<wlr_seat_request_set_selection_event*>(data);
  if (ev->source == nullptr) {
    install_host_source(c);
    return;
  }
  wlr_seat_set_selection(c->seat, ev->source, ev->serial);
  mirror_selection_to_host(c, ev->source);
}

static void handle_set_primary(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_primary);
  auto* ev = static_cast<wlr_seat_request_set_primary_selection_event*>(data);
  wlr_seat_set_primary_selection(c->seat, ev->source, ev->serial);
}

static void handle_start_drag(wl_listener*, void*) {}

static void handle_request_shape(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, request_shape);
  auto* ev =
      static_cast<wlr_cursor_shape_manager_v1_request_set_shape_event*>(data);
  // A shape request replaces any client-supplied cursor surface.
  if (c->cursor_surface != nullptr &&
      c->cursor_surface->role == ROLE_CURSOR) {
    c->cursor_surface->role = ROLE_NONE;
  }
  c->cursor_surface = nullptr;
  c->cursor_shape = (uint32_t)ev->shape;
  OEvent m;
  m["shape"] = (int64_t)ev->shape;
  emit(c, "cursorShape", std::move(m));
  emit_cursor(c);
}

void seat_init(OasisPrivate* c) {
  c->seat_set_cursor.notify = handle_set_cursor;
  wl_signal_add(&c->seat->events.request_set_cursor, &c->seat_set_cursor);
  c->seat_set_selection.notify = handle_set_selection;
  wl_signal_add(&c->seat->events.request_set_selection,
                &c->seat_set_selection);
  c->seat_set_primary.notify = handle_set_primary;
  wl_signal_add(&c->seat->events.request_set_primary_selection,
                &c->seat_set_primary);
  c->seat_start_drag.notify = handle_start_drag;
  wl_signal_add(&c->seat->events.request_start_drag, &c->seat_start_drag);
  c->request_shape.notify = handle_request_shape;
  wl_signal_add(&c->cursor_shape_mgr->events.request_set_shape,
                &c->request_shape);
}

}  // namespace oasis
