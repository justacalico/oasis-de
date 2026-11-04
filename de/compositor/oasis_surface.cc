#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <unistd.h>
#include <wayland-server.h>

#include <algorithm>
#include <cstring>

#include <libdrm/drm.h>
#include <libdrm/drm_fourcc.h>
#include <pthread.h>

#include "oasis_wlr.h"

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

static void ensure_texture(Surface* s, int kind) {
  if (s->tex_kind == kind) return;
  drop_texture(s);
  s->tex_kind = kind;
  s->texture_id = s->comp->host->createTexture(kind == 2);
  s->need_full = true;
  if (s->announced) {
    OEvent m;
    m["textureId"] = s->texture_id;
    emit_id(s, "texture", std::move(m));
  }
}

// Stage a writable RGBA frame with the host. The buffer persists between
// commits, so writes may be limited to damaged rects.
static uint8_t* stage_pixels(Surface* s, int w, int h) {
  if (w != s->iw || h != s->ih) {
    s->iw = w;
    s->ih = h;
    s->need_full = true;
  }
  return s->comp->host->mapPixels(s->texture_id, w, h);
}

// The preferred readback format depends on the renderer and driver (GBM
// EGL usually reports a BGR order while surfaceless GLES tends to report
// RGBA). Normalize to RGBA bytes according to the format actually read.
// Only the region in box is touched; px is the destination for box.x1/y1
// with the given row stride.
static bool texture_read_rgba(wlr_texture* tex, uint8_t* px,
                              const pixman_box32_t& box, int stride) {
  int w = box.x2 - box.x1;
  int h = box.y2 - box.y1;
  wlr_texture_read_pixels_options opts = {
      .data = px,
      .format = wlr_texture_preferred_read_format(tex),
      .stride = (uint32_t)stride,
      .dst_x = 0,
      .dst_y = 0,
      .src_box = {box.x1, box.y1, w, h}};
  if (!wlr_texture_read_pixels(tex, &opts)) return false;
  switch (opts.format) {
    case DRM_FORMAT_ABGR8888:
      return true;
    case DRM_FORMAT_XBGR8888:
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          px[(size_t)y * stride + x * 4 + 3] = 0xff;
        }
      }
      return true;
    case DRM_FORMAT_ARGB8888:
    case DRM_FORMAT_XRGB8888: {
      const bool opaque = opts.format == DRM_FORMAT_XRGB8888;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          uint8_t* p = px + (size_t)y * stride + x * 4;
          uint8_t t = p[0];
          p[0] = p[2];
          p[2] = t;
          if (opaque) p[3] = 0xff;
        }
      }
      return true;
    }
    default:
      return false;
  }
}

// Some client buffers can't be imported by the host GL display. Render them
// through the compositor's own renderer into an allocated buffer and read
// the pixels back instead. clip limits the GPU work to the damaged region.
static bool readback_dmabuf(Surface* s, wlr_buffer* buf, uint8_t* stage,
                          int stride, const pixman_region32_t* clip,
                          pixman_box32_t* rects, int nrects) {
  OasisPrivate* c = s->comp;
  int w = buf->width, h = buf->height;
  if (c->renderer == nullptr || c->allocator == nullptr || w <= 0 || h <= 0 ||
      w > 16384 || h > 16384) {
    return false;
  }
  if (s->readback == nullptr || s->rb_w != w || s->rb_h != h) {
    if (s->rb_tex != nullptr) {
      wlr_texture_destroy(s->rb_tex);
      s->rb_tex = nullptr;
    }
    if (s->readback != nullptr) {
      wlr_buffer_drop(s->readback);
      s->readback = nullptr;
    }
    wlr_drm_format fmt = {};
    fmt.format = DRM_FORMAT_ARGB8888;
    uint64_t linear = DRM_FORMAT_MOD_LINEAR;
    fmt.modifiers = &linear;
    fmt.len = 1;
    s->readback = wlr_allocator_create_buffer(c->allocator, w, h, &fmt);
    s->rb_w = w;
    s->rb_h = h;
    if (s->readback != nullptr) {
      s->rb_tex = wlr_texture_from_buffer(c->renderer, s->readback);
    }
  }
  wlr_texture* src = wlr_texture_from_buffer(c->renderer, buf);
  if (src == nullptr || s->readback == nullptr || s->rb_tex == nullptr) {
    if (src != nullptr) wlr_texture_destroy(src);
    return false;
  }
  bool ok = false;
  wlr_render_pass* pass =
      wlr_renderer_begin_buffer_pass(c->renderer, s->readback, nullptr);
  if (pass != nullptr) {
    wlr_render_texture_options opts = {};
    opts.texture = src;
    opts.dst_box = wlr_box{0, 0, w, h};
    opts.clip = clip;
    wlr_render_pass_add_texture(pass, &opts);
    if (wlr_render_pass_submit(pass)) {
      ok = true;
      for (int i = 0; i < nrects && ok; i++) {
        pixman_box32_t& r = rects[i];
        uint8_t* dst = stage + ((size_t)r.y1 * s->iw + r.x1) * 4;
        ok = texture_read_rgba(s->rb_tex, dst, r, stride);
      }
    }
  }
  wlr_texture_destroy(src);
  return ok;
}

// The buffer went to the host. Keep it locked so the client can't get a
// release event and recycle it out from under us; returns false when the
// frame was skipped entirely.
static bool note_exported(Surface* s, wlr_buffer* buf) {
  if (s->exported == buf) return true;
  wlr_buffer* locked = wlr_buffer_lock(buf);
  if (locked == nullptr) return false;
  if (s->exported != nullptr) wlr_buffer_unlock(s->exported);
  s->exported = locked;
  return true;
}

// Buffers the renderer already imported (shm and friendlier dmabufs)
// fall back to a GPU readback through the compositor's own context.
static bool readback_texture(Surface* s, wlr_texture* tex, int w, int h,
                             pixman_box32_t* rects, int nrects) {
  if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return false;
  uint8_t* stage = stage_pixels(s, w, h);
  if (stage == nullptr) return false;
  bool ok = true;
  for (int i = 0; i < nrects && ok; i++) {
    pixman_box32_t& r = rects[i];
    uint8_t* dst = stage + ((size_t)r.y1 * w + r.x1) * 4;
    ok = texture_read_rgba(tex, dst, r, w * 4);
  }
  s->comp->host->unmapPixels(s->texture_id);
  return ok;
}

static bool export_buffer(Surface* s) {
  wlr_surface* wlr = s->wlr;
  wlr_buffer* buf = wlr != nullptr ? wlr->current.buffer : nullptr;
  if (buf == nullptr) {
    // wlroots folds commits whose buffer can be damage-applied straight
    // into the existing client texture and consumes current.buffer in
    // the process, so shm clients only ever hand us one buffer. The new
    // pixels then live in the surface's texture; a null-attach (unmap)
    // commit instead leaves wlr->buffer NULL.
    if (wlr == nullptr || wlr->buffer == nullptr ||
        !(wlr->current.committed & WLR_SURFACE_STATE_BUFFER)) {
      return false;
    }
    wlr_texture* tex = wlr_surface_get_texture(wlr);
    if (tex == nullptr) return false;
    if (s->iw != tex->width || s->ih != tex->height) s->need_full = true;
    ensure_texture(s, 1);
    pixman_region32_t full_region;
    pixman_region32_init_rect(&full_region, 0, 0, tex->width, tex->height);
    const pixman_region32_t* damage =
        s->need_full ? &full_region : &wlr->buffer_damage;
    int nrects = 0;
    pixman_box32_t* rects = pixman_region32_rectangles(
        const_cast<pixman_region32_t*>(damage), &nrects);
    if (nrects == 0) {
      pixman_region32_fini(&full_region);
      return false;
    }
    s->need_full = false;
    bool pushed = readback_texture(s, tex, tex->width, tex->height, rects,
                                   nrects);
    pixman_region32_fini(&full_region);
    return pushed;
  }

  // A commit that re-attaches the displayed buffer without damage carries
  // no new pixels; skip the whole export. Damage is read from
  // surface->buffer_damage rather than current.buffer_damage: wlroots
  // already folds wl_surface.damage() (surface coords) into the former,
  // while the latter only carries wl_surface.damage_buffer() calls.
  if (buf == s->exported && !s->need_full &&
      pixman_region32_empty(&wlr->buffer_damage)) {
    return false;
  }
  if (s->iw != buf->width || s->ih != buf->height) {
    s->need_full = true;
  }
  pixman_region32_t full_region;
  pixman_region32_init_rect(&full_region, 0, 0, buf->width, buf->height);
  const pixman_region32_t* damage =
      s->need_full ? &full_region : &wlr->buffer_damage;
  int nrects = 0;
  pixman_box32_t* rects = pixman_region32_rectangles(
      const_cast<pixman_region32_t*>(damage), &nrects);
  if (nrects == 0) {
    pixman_region32_fini(&full_region);
    return false;
  }
  if (!note_exported(s, buf)) {
    pixman_region32_fini(&full_region);
    return false;
  }
  s->need_full = false;

  bool pushed = false;
  // Zero-copy path first: dmabuf buffers can be handed to the host as an
  // EGL image instead of being read back through the CPU.
  wlr_dmabuf_attributes attrs;
  if (wlr_buffer_get_dmabuf(buf, &attrs)) {
    if (!s->dmabuf_broken && s->tex_kind == 2 && s->texture_id >= 0 &&
        s->comp->host->dmabufImportFailed(s->texture_id)) {
      // The host GL display can't present this dmabuf; stop retrying the
      // import every frame and read the buffer back on the CPU instead.
      s->dmabuf_broken = true;
    }
    if (!s->dmabuf_broken) {
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
        pushed = true;
      }
      info.close_fds();
    } else {
      ensure_texture(s, 1);
      uint8_t* stage = stage_pixels(s, buf->width, buf->height);
      if (stage != nullptr) {
        pushed =
            readback_dmabuf(s, buf, stage, s->iw * 4, damage, rects, nrects);
        s->comp->host->unmapPixels(s->texture_id);
      }
    }
    pixman_region32_fini(&full_region);
    return pushed;
  }
  wlr_client_buffer* cb = wlr_client_buffer_get(buf);
  if (cb != nullptr && cb->texture != nullptr) {
    ensure_texture(s, 1);
    pushed = readback_texture(s, cb->texture, buf->width, buf->height,
                              rects, nrects);
    pixman_region32_fini(&full_region);
    return pushed;
  }
  void* data = nullptr;
  uint32_t format = 0;
  size_t stride = 0;
  if (!wlr_buffer_begin_data_ptr_access(buf, WLR_BUFFER_DATA_PTR_ACCESS_READ,
                                        &data, &format, &stride) ||
      data == nullptr || stride == 0) {
    if (data != nullptr) wlr_buffer_end_data_ptr_access(buf);
    pixman_region32_fini(&full_region);
    return false;
  }
  int w = buf->width;
  int h = buf->height;
  if (w <= 0 || h <= 0 || w > 16384 || h > 16384) {
    wlr_buffer_end_data_ptr_access(buf);
    pixman_region32_fini(&full_region);
    return false;
  }
  ensure_texture(s, 1);
  uint8_t* stage = stage_pixels(s, w, h);
  if (stage == nullptr) {
    wlr_buffer_end_data_ptr_access(buf);
    pixman_region32_fini(&full_region);
    return false;
  }
  const uint8_t* src = static_cast<const uint8_t*>(data);
  for (int i = 0; i < nrects; i++) {
    pixman_box32_t& r = rects[i];
    for (int y = r.y1; y < r.y2; y++) {
      const uint8_t* row = src + (size_t)y * stride + (size_t)r.x1 * 4;
      uint8_t* dst = stage + ((size_t)y * w + r.x1) * 4;
      for (int x = r.x1; x < r.x2; x++) {
        uint32_t px;
        memcpy(&px, row + (x - r.x1) * 4, 4);
        dst[(x - r.x1) * 4 + 0] = (px >> 16) & 0xff;
        dst[(x - r.x1) * 4 + 1] = (px >> 8) & 0xff;
        dst[(x - r.x1) * 4 + 2] = px & 0xff;
        dst[(x - r.x1) * 4 + 3] =
            format == DRM_FORMAT_XRGB8888 ? 0xff : (px >> 24) & 0xff;
      }
    }
  }
  wlr_buffer_end_data_ptr_access(buf);
  s->comp->host->unmapPixels(s->texture_id);
  pixman_region32_fini(&full_region);
  return true;
}

// wp_presentation_feedback "kind" bit advertised when the timestamp comes
// from a real vblank rather than an estimate.
static constexpr uint32_t kPresentVsync = 0x1;

void send_frame_done(Surface* s, const timespec& ts, bool vsync) {
  s->frame_pending = false;
  if (s->comp->pending_frames > 0) s->comp->pending_frames--;
  wlr_surface* wlr = s->wlr;
  if (wlr == nullptr) return;
  wlr_surface_send_frame_done(wlr, &ts);
  wlr_presentation_feedback* fb = wlr_presentation_surface_sampled(wlr);
  if (fb != nullptr) {
    OasisOutput* o = output_for_surface(s);
    wlr_presentation_event ev = {};
    ev.output = o != nullptr ? o->wlr : nullptr;
    ev.tv_sec = (uint64_t)ts.tv_sec;
    ev.tv_nsec = (uint32_t)ts.tv_nsec;
    ev.refresh =
        o != nullptr && o->refresh > 0 ? (uint32_t)(1000000000000ULL / o->refresh)
                                     : 16666666;
    ev.flags = vsync ? kPresentVsync : 0;
    wlr_presentation_feedback_send_presented(fb, &ev);
    wlr_presentation_feedback_destroy(fb);
  }
}

void frames_presented(OasisPrivate* c, const timespec& ts, bool vsync) {
  if (c->pending_frames <= 0) return;
  for (Surface* s : c->surfaces) {
    if (s->frame_pending) send_frame_done(s, ts, vsync);
  }
  wl_display_flush_clients(c->display);
}

// When the host stops painting (minimized shell, blank screen, stalled
// driver) clients still need frame callbacks or they wedge. Flush strays
// after a couple of missed frames.
static constexpr int kFrameFallbackMs = 40;

static int frame_fallback_cb(void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  frames_presented(c, ts, false);
  if (c->pending_frames > 0) {
    wl_event_source_timer_update(c->frame_fallback, kFrameFallbackMs);
  }
  return 0;
}

void frame_pending_add(Surface* s) {
  OasisPrivate* c = s->comp;
  if (s->frame_pending) return;
  s->frame_pending = true;
  c->pending_frames++;
  if (c->frame_fallback == nullptr) {
    c->frame_fallback =
        wl_event_loop_add_timer(c->loop, frame_fallback_cb, c);
  }
  if (c->frame_fallback != nullptr) {
    wl_event_source_timer_update(c->frame_fallback, kFrameFallbackMs);
  }
}

// linux-drm-syncobj: a commit may carry an acquire fence that isn't
// signalled yet. Buffer sampling has to wait, so park the export and let
// the timeline waiter run it once the fence fires.
static void acquire_ready_cb(wlr_drm_syncobj_timeline_waiter* waiter) {
  Surface* s = wl_container_of(waiter, s, acquire_waiter);
  // The waiter stays registered after firing; finish it here or every
  // deferred commit leaks an eventfd until the fd table fills up.
  wlr_drm_syncobj_timeline_waiter_finish(&s->acquire_waiter);
  s->acquire_waiting = false;
  if (export_buffer(s) && s->texture_id >= 0 &&
      (s->announced || s == s->comp->cursor_surface)) {
    s->comp->host->frameAvailable(s->texture_id);
  }
  wl_display_flush_clients(s->comp->display);
}

static bool acquire_ready(Surface* s) {
  if (s->wlr == nullptr) return true;
  wlr_linux_drm_syncobj_surface_v1_state* st =
      wlr_linux_drm_syncobj_v1_get_surface_state(s->wlr);
  if (st == nullptr || st->acquire_timeline == nullptr) return true;
  bool ready = false;
  if (wlr_drm_syncobj_timeline_check(st->acquire_timeline, st->acquire_point,
                                     DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT,
                                     &ready) &&
      ready) {
    return true;
  }
  // DRM_IOCTL_SYNCOBJ_EVENTFD accepts only 0 or WAIT_AVAILABLE;
  // wait-before-submit is built into the ioctl, so 0 still fires once an
  // unsubmitted point materializes and is then signalled.
  if (wlr_drm_syncobj_timeline_waiter_init(
          &s->acquire_waiter, st->acquire_timeline, st->acquire_point, 0,
          s->comp->loop, acquire_ready_cb)) {
    s->acquire_waiting = true;
    return false;
  }
  // No waiter available; degrade to sampling right away rather than
  // dropping the frame.
  return true;
}

void emit_decoration(Surface* s) {
  if (!s->announced || s->role != ROLE_TOPLEVEL) return;
  int mode = 2;
  if (s->xsurface != nullptr) {
    if (s->xsurface->decorations !=
        WLR_XWAYLAND_SURFACE_DECORATIONS_ALL) {
      mode = 1;
    }
  } else if (s->deco != nullptr && s->deco->scheduled_mode != 0) {
    mode = (int)s->deco->scheduled_mode;
  } else if (s->kde_deco != nullptr && s->kde_deco->mode != 0) {
    mode = (int)s->kde_deco->mode;
  }
  if (mode == s->rep_deco) return;
  s->rep_deco = mode;
  OEvent m;
  m["mode"] = (int64_t)mode;
  emit_id(s, "decoration", std::move(m));
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
  frame_pending_add(s);
  // linux-drm-syncobj: drop the previous buffer's release point once we
  // are done with it, then gate the export on this commit's acquire fence.
  wlr_linux_drm_syncobj_surface_v1_state* syncst =
      s->wlr != nullptr
          ? wlr_linux_drm_syncobj_v1_get_surface_state(s->wlr)
          : nullptr;
  if (syncst != nullptr && s->wlr->current.buffer != nullptr) {
    wlr_linux_drm_syncobj_v1_state_signal_release_with_buffer(
        syncst, s->wlr->current.buffer);
  }
  if (s->acquire_waiting) {
    wlr_drm_syncobj_timeline_waiter_finish(&s->acquire_waiter);
    s->acquire_waiting = false;
  }
  bool exported = acquire_ready(s) && export_buffer(s);
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
