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

static void emit_layer_state(Surface* s,
                             const wlr_layer_surface_v1_state& st) {
  wlr_layer_surface_v1* ls = s->layer;
  const char* ns = ls->namespace_ != nullptr ? ls->namespace_ : "";
  if ((int)st.anchor == s->rep_anchor && st.exclusive_zone == s->rep_exclusive &&
      (int)st.exclusive_edge == s->rep_edge &&
      (int)st.keyboard_interactive == s->rep_kb &&
      (int)st.layer == s->rep_layer && st.margin.top == s->rep_mt &&
      st.margin.right == s->rep_mr && st.margin.bottom == s->rep_mb &&
      st.margin.left == s->rep_ml &&
      (int)st.desired_width == s->rep_dw &&
      (int)st.desired_height == s->rep_dh && ns == s->rep_ns) {
    return;
  }
  s->rep_anchor = st.anchor;
  s->rep_exclusive = st.exclusive_zone;
  s->rep_edge = st.exclusive_edge;
  s->rep_kb = st.keyboard_interactive;
  s->rep_layer = st.layer;
  s->rep_mt = st.margin.top;
  s->rep_mr = st.margin.right;
  s->rep_mb = st.margin.bottom;
  s->rep_ml = st.margin.left;
  s->rep_dw = st.desired_width;
  s->rep_dh = st.desired_height;
  s->rep_ns = ns;
  OEvent m;
  m["textureId"] = s->texture_id;
  m["ns"] = s->rep_ns;
  m["layer"] = (int64_t)s->rep_layer;
  m["anchor"] = (int64_t)s->rep_anchor;
  m["exclusive"] = (int64_t)s->rep_exclusive;
  m["edge"] = (int64_t)s->rep_edge;
  m["kb"] = (int64_t)s->rep_kb;
  m["mt"] = (int64_t)s->rep_mt;
  m["mr"] = (int64_t)s->rep_mr;
  m["mb"] = (int64_t)s->rep_mb;
  m["ml"] = (int64_t)s->rep_ml;
  m["dw"] = (int64_t)s->rep_dw;
  m["dh"] = (int64_t)s->rep_dh;
  emit_id(s, "layer", std::move(m));
}

void emit_layer_pending(Surface* s) {
  emit_layer_state(s, s->layer->pending);
}

void emit_layer_current(Surface* s) {
  emit_layer_state(s, s->layer->current);
}

static void layer_surface_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, layer_destroy);
  s->layer = nullptr;
  wl_list_remove(&s->layer_destroy.link);
  wl_list_remove(&s->layer_new_popup.link);
  wl_list_init(&s->layer_destroy.link);
  wl_list_init(&s->layer_new_popup.link);
}

static void layer_new_popup_handler(wl_listener* listener, void* data) {
  Surface* s = wl_container_of(listener, s, layer_new_popup);
  popup_new(s->comp, static_cast<wlr_xdg_popup*>(data));
}

void announce_layer(Surface* s) {
  OasisPrivate* c = s->comp;
  s->announced = true;
  s->rep_anchor = -1;
  emit_layer_current(s);
  emit_size(s);
  wlr_surface_send_enter(s->wlr, c->output);
  wlr_fractional_scale_v1_notify_scale(s->wlr, (double)c->out_scale);
  comp_flush(c);
}

void layer_new(OasisPrivate* c, wlr_layer_surface_v1* ls) {
  if (ls->output == nullptr) ls->output = c->output;
  Surface* s = surface_of(c, ls->surface);
  if (s == nullptr) {
    surface_new(c, ls->surface);
    s = surface_of(c, ls->surface);
  }
  s->layer = ls;
  s->role = ROLE_LAYER;
  if (s->public_id == 0) {
    s->public_id = c->next_id++;
    c->by_id[s->public_id] = s;
  }
  s->layer_destroy.notify = layer_surface_destroyed;
  wl_signal_add(&ls->events.destroy, &s->layer_destroy);
  s->layer_new_popup.notify = layer_new_popup_handler;
  wl_signal_add(&ls->events.new_popup, &s->layer_new_popup);
  emit_layer_pending(s);
}

}  // namespace oasis
