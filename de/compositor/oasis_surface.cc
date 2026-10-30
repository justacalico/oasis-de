#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <unistd.h>
#include <wayland-server.h>

#include <algorithm>
#include <cstring>

#include <libdrm/drm_fourcc.h>
extern "C" {
#include <wlr/render/dmabuf.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_subcompositor.h>
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

static void drop_texture(Surface* s) {
  if (s->texture_id >= 0) {
    s->comp->host->destroyTexture(s->texture_id);
    s->texture_id = -1;
  }
  s->tex_kind = 0;
}

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
  wl_list_remove(&s->deco_destroy.link);
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
  wl_list_init(&s->deco_destroy.link);
}

void free_surface(Surface* s) {
  OasisPrivate* c = s->comp;
  if (s->announced && !c->stopping) {
    const char* name = s->role == ROLE_POPUP      ? "popupClosed"
                       : s->role == ROLE_SUBSURFACE ? "subsurfaceClosed"
                                                   : "toplevelClosed";
    emit_id(s, name);
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
  drop_texture(s);
  c->by_id.erase(s->public_id);
  if (s->wlr != nullptr) c->by_wlr.erase(s->wlr);
  auto& v = c->surfaces;
  v.erase(std::remove(v.begin(), v.end(), s), v.end());
  remove_listeners(s);
  delete s;
}

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

static void emit_input_region(Surface* s) {
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
                  boxes[0].x2 - boxes[0].x1 == INT32_MAX &&
                  boxes[0].y2 - boxes[0].y1 == INT32_MAX;
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

static void ensure_texture(Surface* s, int kind) {
  if (s->tex_kind == kind) return;
  drop_texture(s);
  s->tex_kind = kind;
  s->texture_id = s->comp->host->createTexture(kind == 2);
  if (s->announced) {
    OEvent m;
    m["textureId"] = s->texture_id;
    emit_id(s, "texture", std::move(m));
  }
}

static void export_buffer(Surface* s) {
  wlr_surface* wlr = s->wlr;
  wlr_buffer* buf = wlr != nullptr ? wlr->current.buffer : nullptr;
  if (buf == nullptr) {
    s->img.reset();
    s->iw = s->ih = 0;
    return;
  }
  wlr_client_buffer* cb = wlr_client_buffer_get(buf);
  if (cb != nullptr && cb->texture != nullptr) {
    ensure_texture(s, 1);
    int w = buf->width, h = buf->height;
    if (w > 0 && h > 0 && w <= 16384 && h <= 16384) {
      if (s->iw != w || s->ih != h || s->img == nullptr) {
        s->img.reset(new (std::nothrow) uint8_t[(size_t)w * h * 4]);
        s->iw = w;
        s->ih = h;
      }
      if (s->img != nullptr) {
        wlr_texture_read_pixels_options opts = {};
        opts.data = s->img.get();
        opts.format = wlr_texture_preferred_read_format(cb->texture);
        opts.stride = (uint32_t)w * 4;
        wlr_texture_read_pixels(cb->texture, &opts);
        uint8_t* px = s->img.get();
        for (size_t i = 0; i < (size_t)w * h; i++) {
          uint8_t b = px[i * 4 + 0];
          uint8_t g = px[i * 4 + 1];
          uint8_t r = px[i * 4 + 2];
          uint8_t a = px[i * 4 + 3];
          px[i * 4 + 0] = r;
          px[i * 4 + 1] = g;
          px[i * 4 + 2] = b;
          px[i * 4 + 3] = a;
        }
        if (s->texture_id >= 0) {
          s->comp->host->pushPixels(s->texture_id, s->img.get(), w, h);
        }
      }
    }
    return;
  }
  wlr_dmabuf_attributes attrs;
  if (wlr_buffer_get_dmabuf(buf, &attrs)) {
    ensure_texture(s, 2);
    DmabufInfo info;
    info.w = attrs.width;
    info.h = attrs.height;
    info.format = attrs.format;
    info.nplanes = attrs.n_planes;
    for (int i = 0; i < attrs.n_planes && i < 4; i++) {
      info.fds[i] = fcntl(attrs.fd[i], F_DUPFD_CLOEXEC, 0);
      info.offsets[i] = attrs.offset[i];
      info.strides[i] = attrs.stride[i];
      info.mods[i] = attrs.modifier;
    }
    s->iw = info.w;
    s->ih = info.h;
    if (s->texture_id >= 0) {
      s->comp->host->pushDmabuf(s->texture_id, info);
    }
    info.close_fds();
    wlr_dmabuf_attributes_finish(&attrs);
    return;
  }
  void* data = nullptr;
  uint32_t format = 0;
  size_t stride = 0;
  if (!wlr_buffer_begin_data_ptr_access(buf, WLR_BUFFER_DATA_PTR_ACCESS_READ,
                                        &data, &format, &stride) ||
      data == nullptr || stride == 0) {
    if (data != nullptr) wlr_buffer_end_data_ptr_access(buf);
    return;
  }
  int w = buf->width;
  int h = buf->height;
  if (w <= 0 || h <= 0 || w > 16384 || h > 16384) {
    wlr_buffer_end_data_ptr_access(buf);
    return;
  }
  ensure_texture(s, 1);
  if (s->iw != w || s->ih != h || s->img == nullptr) {
    s->img.reset(new (std::nothrow) uint8_t[(size_t)w * h * 4]);
    if (s->img == nullptr) {
      wlr_buffer_end_data_ptr_access(buf);
      s->iw = s->ih = 0;
      return;
    }
    s->iw = w;
    s->ih = h;
  }
  const uint8_t* src = static_cast<const uint8_t*>(data);
  for (int y = 0; y < h; y++) {
    const uint8_t* row = src + (size_t)y * stride;
    uint8_t* dst = s->img.get() + (size_t)y * w * 4;
    for (int x = 0; x < w; x++) {
      uint32_t px;
      memcpy(&px, row + x * 4, 4);
      dst[x * 4 + 0] = (px >> 16) & 0xff;
      dst[x * 4 + 1] = (px >> 8) & 0xff;
      dst[x * 4 + 2] = px & 0xff;
      dst[x * 4 + 3] =
          format == DRM_FORMAT_XRGB8888 ? 0xff : (px >> 24) & 0xff;
    }
  }
  wlr_buffer_end_data_ptr_access(buf);
  if (s->texture_id >= 0) {
    s->comp->host->pushPixels(s->texture_id, s->img.get(), w, h);
  }
}

void send_frame_done(Surface* s) {
  wlr_surface* wlr = s->wlr;
  if (wlr == nullptr) return;
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  wlr_surface_send_frame_done(wlr, &ts);
  wlr_presentation_feedback* fb =
      wlr_presentation_surface_sampled(wlr);
  if (fb != nullptr) {
    wlr_presentation_event ev = {};
    ev.output = s->comp->output;
    ev.tv_sec = (uint64_t)ts.tv_sec;
    ev.tv_nsec = (uint32_t)ts.tv_nsec;
    ev.refresh = 16666666;
    ev.flags = 0;
    wlr_presentation_feedback_send_presented(fb, &ev);
    wlr_presentation_feedback_destroy(fb);
  }
}

void announce_toplevel(Surface* s) {
  OasisPrivate* c = s->comp;
  s->announced = true;
  OEvent m;
  m["textureId"] = s->texture_id;
  m["title"] = s->title;
  m["appId"] = s->app_id;
  m["parent"] = s->tl_parent != nullptr ? s->tl_parent->public_id : -1;
  emit_id(s, "toplevel", std::move(m));
  emit_size(s);
  wlr_surface_send_enter(s->wlr, c->output);
  wlr_fractional_scale_v1_notify_scale(s->wlr, (double)c->out_scale);
  if (!s->inhibitors.empty()) {
    OEvent im;
    im["on"] = true;
    emit_id(s, "idleInhibit", std::move(im));
  }
}

static void maybe_announce(Surface* s) {
  if (s->announced) return;
  if (s->role == ROLE_TOPLEVEL && s->wlr != nullptr && s->wlr->mapped) {
    announce_toplevel(s);
  }
}

static void check_minmax(Surface* s) {
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

static void check_child_order(Surface* s) {
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

static void check_position(Surface* s) {
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

static void surface_commit(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, commit);
  extern void send_initial_configure(Surface*);
  send_initial_configure(s);
  export_buffer(s);
  maybe_announce(s);
  if (s->announced) {
    emit_size(s);
    emit_input_region(s);
    check_minmax(s);
    check_position(s);
  }
  if (s->parent != nullptr) check_child_order(s->parent);
  if (s->texture_id >= 0 &&
      (s->announced || s == s->comp->cursor_surface)) {
    s->comp->host->frameAvailable(s->texture_id);
  }
  if (s == s->comp->cursor_surface) emit_cursor(s->comp);
  send_frame_done(s);
}

static void surface_map(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, map);
  maybe_announce(s);
}

static void surface_unmap(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, unmap);
  s->img.reset();
  s->iw = s->ih = 0;
  if (s->announced) emit_size(s);
}

static void surface_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, destroy);
  s->wlr = nullptr;
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
  emit_id(s, "subsurface", std::move(m));
  emit_size(s);
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

}  // namespace oasis
