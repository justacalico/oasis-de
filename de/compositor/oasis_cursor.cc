#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <algorithm>
#include <cstring>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

// The compositor does not track pointer position in layout space, so a
// shape cursor is rendered for the densest output the pointer could be
// on; the shell then draws it at its logical size like every other
// surface.
static double cursor_output_scale(OasisPrivate* c) {
  double scale = 0;
  for (OasisOutput* o : c->outputs) {
    if (o->enabled) scale = std::max(scale, o->scale);
  }
  if (scale <= 0) {
    OasisOutput* p = output_primary(c);
    scale = p != nullptr ? p->scale : 1;
  }
  return scale > 0 ? scale : 1;
}

void cursor_init(OasisPrivate* c) {
  c->xcursor_mgr = wlr_xcursor_manager_create(nullptr, 24);
}

void cursor_finish(OasisPrivate* c) {
  if (c->cursor_tex >= 0) {
    c->host->destroyTexture(c->cursor_tex);
    c->cursor_tex = -1;
  }
  if (c->xcursor_mgr != nullptr) {
    wlr_xcursor_manager_destroy(c->xcursor_mgr);
    c->xcursor_mgr = nullptr;
  }
}

// Stages the themed image for c->cursor_shape into the shared cursor
// texture and fills m with the event fields the shell needs to draw it.
bool cursor_shape_event(OasisPrivate* c, OEvent& m) {
  if (c->xcursor_mgr == nullptr || c->host == nullptr) return false;
  double scale = cursor_output_scale(c);
  wlr_xcursor_manager_load(c->xcursor_mgr, (float)scale);
  const char* name = nullptr;
  if (c->cursor_shape <=
      (uint32_t)WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_ALL_RESIZE) {
    name = wlr_cursor_shape_v1_name(
        (enum wp_cursor_shape_device_v1_shape)c->cursor_shape);
  }
  wlr_xcursor* xc = name != nullptr
                        ? wlr_xcursor_manager_get_xcursor(c->xcursor_mgr,
                                                          name, (float)scale)
                        : nullptr;
  if (xc == nullptr) {
    xc = wlr_xcursor_manager_get_xcursor(c->xcursor_mgr, "left_ptr",
                                         (float)scale);
  }
  if (xc == nullptr || xc->image_count == 0) return false;
  wlr_xcursor_image* img = xc->images[0];
  if (c->cursor_tex < 0) {
    c->cursor_tex = c->host->createTexture(false);
    if (c->cursor_tex < 0) return false;
  }
  uint8_t* stage = c->host->mapPixels(
      c->cursor_tex, (int)img->width, (int)img->height);
  if (stage == nullptr) return false;
  const uint8_t* src = img->buffer;
  size_t n = (size_t)img->width * img->height;
  for (size_t i = 0; i < n; i++) {
    stage[i * 4 + 0] = src[i * 4 + 2];
    stage[i * 4 + 1] = src[i * 4 + 1];
    stage[i * 4 + 2] = src[i * 4 + 0];
    stage[i * 4 + 3] = src[i * 4 + 3];
  }
  c->host->unmapPixels(c->cursor_tex);
  c->host->frameAvailable(c->cursor_tex);
  m["id"] = (int64_t)-1;
  m["texture"] = c->cursor_tex;
  m["w"] = img->width / scale;
  m["h"] = img->height / scale;
  m["hx"] = img->hotspot_x / scale;
  m["hy"] = img->hotspot_y / scale;
  return true;
}

}  // namespace oasis
