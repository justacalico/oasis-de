#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <libdrm/drm_fourcc.h>
#include <pthread.h>
#include <unistd.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

extern "C" {
#include <wlr/interfaces/wlr_buffer.h>
}

#include "oasis_internal.h"

namespace oasis {

struct PixelsBuffer {
  wlr_buffer base;
  std::vector<uint8_t> px;
};

static void pixels_buffer_destroy(wlr_buffer* wlr_buf) {
  PixelsBuffer* buf = wl_container_of(wlr_buf, buf, base);
  delete buf;
}

static bool pixels_begin_access(wlr_buffer* wlr_buf, uint32_t, void** data,
                                uint32_t* format, size_t* stride) {
  PixelsBuffer* buf = wl_container_of(wlr_buf, buf, base);
  *data = buf->px.data();
  *format = DRM_FORMAT_ABGR8888;
  *stride = (size_t)buf->base.width * 4;
  return true;
}

static const wlr_buffer_impl pixels_buffer_impl = {
    .destroy = pixels_buffer_destroy,
    .get_dmabuf = nullptr,
    .get_shm = nullptr,
    .begin_data_ptr_access = pixels_begin_access,
    .end_data_ptr_access = nullptr,
};

void capture_check(OasisOutput* o) {
  if (o == nullptr) return;
  OasisPrivate* c = o->comp;
  int w = o->width, h = o->height;
  if (w <= 0 || h <= 0) return;
  std::vector<uint8_t> px;
  if (!o->powered || !c->power_on || c->lock != nullptr) {
    px.assign((size_t)w * h * 4, 0);
  } else if (!c->host->captureOutput(px, o->x, o->y, w, h) || px.empty()) {
    return;
  }
  auto* buf = new PixelsBuffer();
  buf->px = std::move(px);
  wlr_buffer_init(&buf->base, &pixels_buffer_impl, w, h);
  wlr_output_state st;
  wlr_output_state_init(&st);
  wlr_output_state_set_buffer(&st, &buf->base);
  pixman_region32_t damage;
  pixman_region32_init_rect(&damage, 0, 0, w, h);
  wlr_output_state_set_damage(&st, &damage);
  wlr_output_commit_state(o->wlr, &st);
  wlr_output_state_finish(&st);
  pixman_region32_fini(&damage);
  wlr_buffer_drop(&buf->base);
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

}  // namespace oasis
