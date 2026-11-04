#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void emit_cursor(OasisPrivate* c) {
  OEvent m;
  Surface* s = c->cursor_surface;
  if (s == nullptr || s->texture_id < 0) {
    m["id"] = (int64_t)0;
  } else {
    int scale = s->wlr != nullptr && s->wlr->current.scale > 0
                    ? s->wlr->current.scale
                    : 1;
    m["id"] = s->public_id;
    m["texture"] = s->texture_id;
    m["w"] = (int64_t)(s->iw / scale);
    m["h"] = (int64_t)(s->ih / scale);
    m["hx"] = (int64_t)c->cursor_hx;
    m["hy"] = (int64_t)c->cursor_hy;
  }
  emit(c, "cursor", std::move(m));
}

void emit_size(Surface* s) {
  wlr_surface* wlr = s->wlr;
  int scale = 1, transform = 0, bw = 0, bh = 0;
  double vsx = -1, vsy = -1, vsw = -1, vsh = -1;
  int vp_dw = -1, vp_dh = -1;
  int gx = s->rep_gx, gy = s->rep_gy, gw = 0, gh = 0;
  if (wlr != nullptr) {
    wlr_surface_state* st = &wlr->current;
    scale = st->scale > 0 ? st->scale : 1;
    transform = (int)st->transform;
    bw = st->buffer_width;
    bh = st->buffer_height;
    if (st->viewport.has_src) {
      vsx = st->viewport.src.x;
      vsy = st->viewport.src.y;
      vsw = st->viewport.src.width;
      vsh = st->viewport.src.height;
    }
    if (st->viewport.has_dst) {
      vp_dw = st->viewport.dst_width;
      vp_dh = st->viewport.dst_height;
    }
  }
  if (s->xdg != nullptr) {
    gx = s->xdg->current.geometry.x;
    gy = s->xdg->current.geometry.y;
    gw = s->xdg->current.geometry.width;
    gh = s->xdg->current.geometry.height;
  }
  const bool swap = (transform & 1) != 0;
  int lw = swap ? bh / scale : bw / scale;
  int lh = swap ? bw / scale : bh / scale;
  int w = gw > 0   ? gw
          : vp_dw > 0 ? vp_dw
          : vsw > 0   ? (int)vsw
                      : lw;
  int h = gh > 0   ? gh
          : vp_dh > 0 ? vp_dh
          : vsh > 0   ? (int)vsh
                      : lh;
  if (w == s->rep_w && h == s->rep_h && bw == s->rep_bw &&
      bh == s->rep_bh && gx == s->rep_gx && gy == s->rep_gy &&
      vsw == s->rep_vsw && vsh == s->rep_vsh && scale == s->rep_scale &&
      transform == s->rep_transform) {
    return;
  }
  s->rep_w = w;
  s->rep_h = h;
  s->rep_bw = bw;
  s->rep_bh = bh;
  s->rep_gx = gx;
  s->rep_gy = gy;
  s->rep_vsw = vsw;
  s->rep_vsh = vsh;
  s->rep_scale = scale;
  s->rep_transform = transform;
  OEvent m;
  m["w"] = (int64_t)w;
  m["h"] = (int64_t)h;
  m["gx"] = (int64_t)gx;
  m["gy"] = (int64_t)gy;
  m["bw"] = (int64_t)bw;
  m["bh"] = (int64_t)bh;
  m["scale"] = (int64_t)scale;
  m["vsx"] = vsx;
  m["vsy"] = vsy;
  m["vsw"] = vsw;
  m["vsh"] = vsh;
  m["transform"] = (int64_t)transform;
  emit_id(s, "size", std::move(m));
}

void emit_input_region(Surface* s) {
  wlr_surface* wlr = s->wlr;
  if (wlr == nullptr) return;
  std::vector<std::array<int32_t, 4>> rects;
  pixman_region32_t* input = &wlr->current.input;
  int n = 0;
  pixman_box32_t* boxes = pixman_region32_rectangles(input, &n);
  for (int i = 0; i < n; i++) {
    rects.push_back({boxes[i].x1, boxes[i].y1, boxes[i].x2 - boxes[i].x1,
                     boxes[i].y2 - boxes[i].y1});
  }
  bool infinite = n == 1 && boxes[0].x1 == INT32_MIN &&
                  boxes[0].y1 == INT32_MIN &&
                  boxes[0].x2 == INT32_MAX &&
                  boxes[0].y2 == INT32_MAX;
  OEvent m;
  if (infinite) {
    if (s->input_reported && s->input_null) return;
    s->input_null = true;
    m["rects"] = Oval();
  } else {
    if (s->input_reported && s->input_rects == rects && !s->input_null) {
      return;
    }
    s->input_null = false;
    s->input_rects = rects;
    Oval::List list;
    for (auto& r : rects) {
      for (int i = 0; i < 4; i++) list.emplace_back((int64_t)r[i]);
    }
    m["rects"] = std::move(list);
  }
  s->input_reported = true;
  emit_id(s, "inputRegion", std::move(m));
}

void check_minmax(Surface* s) {
  if (s->xdg == nullptr || s->xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL ||
      s->xdg->toplevel == nullptr) {
    return;
  }
  wlr_xdg_toplevel* tl = s->xdg->toplevel;
  if (tl->current.min_width != s->rep_min_w ||
      tl->current.min_height != s->rep_min_h) {
    s->rep_min_w = tl->current.min_width;
    s->rep_min_h = tl->current.min_height;
    OEvent m;
    m["w"] = (int64_t)tl->current.min_width;
    m["h"] = (int64_t)tl->current.min_height;
    emit_id(s, "minSize", std::move(m));
  }
  if (tl->current.max_width != s->rep_max_w ||
      tl->current.max_height != s->rep_max_h) {
    s->rep_max_w = tl->current.max_width;
    s->rep_max_h = tl->current.max_height;
    OEvent m;
    m["w"] = (int64_t)tl->current.max_width;
    m["h"] = (int64_t)tl->current.max_height;
    emit_id(s, "maxSize", std::move(m));
  }
}

void check_child_order(Surface* s) {
  wlr_surface* wlr = s->wlr;
  if (wlr == nullptr) return;
  std::vector<int64_t> order;
  wlr_subsurface* sub;
  wl_list_for_each(sub, &wlr->current.subsurfaces_below,
                   current.link) {
    Surface* cs = surface_of(s->comp, sub->surface);
    if (cs != nullptr) order.push_back(cs->public_id);
  }
  wl_list_for_each(sub, &wlr->current.subsurfaces_above,
                   current.link) {
    Surface* cs = surface_of(s->comp, sub->surface);
    if (cs != nullptr) order.push_back(cs->public_id);
  }
  if (order == s->child_order) return;
  s->child_order = order;
  OEvent m;
  Oval::List kids;
  for (int64_t id : order) kids.emplace_back(id);
  m["children"] = std::move(kids);
  emit_id(s, "childrenReordered", std::move(m));
}

void check_position(Surface* s) {
  int x = 0, y = 0;
  if (s->role == ROLE_SUBSURFACE) {
    wlr_subsurface* sub =
        s->wlr != nullptr ? wlr_subsurface_try_from_wlr_surface(s->wlr)
                          : nullptr;
    if (sub == nullptr) return;
    x = sub->current.x;
    y = sub->current.y;
  } else if (s->role == ROLE_POPUP) {
    popup_position(s, &x, &y);
  } else {
    return;
  }
  if (x == s->rep_sx && y == s->rep_sy) return;
  s->rep_sx = s->sx = x;
  s->rep_sy = s->sy = y;
  OEvent m;
  m["x"] = (int64_t)x;
  m["y"] = (int64_t)y;
  emit_id(s, s->role == ROLE_POPUP ? "popupMoved" : "subsurfaceMoved",
          std::move(m));
}

}  // namespace oasis
