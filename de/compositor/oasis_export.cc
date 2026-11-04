#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <unistd.h>
#include <wayland-server.h>

#include <cstring>

#include <libdrm/drm.h>
#include <libdrm/drm_fourcc.h>
#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

void drop_texture(Surface* s) {
  if (s->texture_id >= 0) {
    s->comp->host->destroyTexture(s->texture_id);
    s->texture_id = -1;
  }
  s->tex_kind = 0;
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

  wlr_dmabuf_attributes attrs;
  const bool is_dmabuf = wlr_buffer_get_dmabuf(buf, &attrs);
  if (is_dmabuf && !s->dmabuf_broken && s->tex_kind == 2 &&
      s->texture_id >= 0 &&
      s->comp->host->dmabufImportFailed(s->texture_id)) {
    // The host GL display can't present this dmabuf; stop retrying the
    // import every frame and read the buffer back on the CPU instead.
    // need_full forces the held buffer through the readback path even
    // when this commit carries no new damage, so a window that has been
    // sitting on the pink no-frame placeholder recovers right away.
    s->dmabuf_broken = true;
    s->need_full = true;
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
  if (is_dmabuf) {
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

bool export_frame(Surface* s) {
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
  return acquire_ready(s) && export_buffer(s);
}

}  // namespace oasis
