#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <libdrm/drm_fourcc.h>
#include <pthread.h>
#include <unistd.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include <wlr/interfaces/wlr_buffer.h>

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

void capture_check(OasisPrivate* c) {
  if (c->output == nullptr) return;
  std::vector<uint8_t> px;
  int w = c->out_w, h = c->out_h;
  if (!c->host->captureOutput(px, w, h) || px.empty()) return;
  auto* buf = new PixelsBuffer();
  buf->px = std::move(px);
  wlr_buffer_init(&buf->base, &pixels_buffer_impl, w, h);
  wlr_output_state st;
  wlr_output_state_init(&st);
  wlr_output_state_set_buffer(&st, &buf->base);
  pixman_region32_t damage;
  pixman_region32_init_rect(&damage, 0, 0, w, h);
  wlr_output_state_set_damage(&st, &damage);
  wlr_output_commit_state(c->output, &st);
  wlr_output_state_finish(&st);
  pixman_region32_fini(&damage);
  wlr_buffer_drop(&buf->base);
}

void output_needs_frame(wl_listener* listener, void*) {
  OasisPrivate* c = wl_container_of(listener, c, output_needs_frame);
  capture_check(c);
}

void power_mode_set(OasisPrivate* c, wlr_output* output, uint32_t mode) {
  if (output != c->output) return;
  c->power_on = mode == ZWLR_OUTPUT_POWER_V1_MODE_ON;
  OEvent m;
  m["on"] = c->power_on;
  emit(c, "outputPower", std::move(m));
}

}  // namespace oasis
