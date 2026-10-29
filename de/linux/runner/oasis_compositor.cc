#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "oasis_compositor.h"

#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

#include <gtk/gtk.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include "xdg-decoration-unstable-v1-server-protocol.h"
#include "xdg-shell-server-protocol.h"

#define OASIS_TYPE_TEXTURE (oasis_texture_get_type())
G_DECLARE_FINAL_TYPE(OasisTexture,
                     oasis_texture,
                     OASIS,
                     TEXTURE,
                     FlPixelBufferTexture)

struct _OasisTexture {
  FlPixelBufferTexture parent_instance;
  GMutex mutex;
  uint8_t* stage;
  uint32_t stage_w;
  uint32_t stage_h;
  uint8_t* frame;
  uint32_t frame_w;
  uint32_t frame_h;
  size_t frame_cap;
};

G_DEFINE_TYPE(OasisTexture, oasis_texture, fl_pixel_buffer_texture_get_type())

static gboolean oasis_texture_copy_pixels(FlPixelBufferTexture* texture,
                                          const uint8_t** out_buffer,
                                          uint32_t* width,
                                          uint32_t* height,
                                          GError** error) {
  OasisTexture* self = OASIS_TEXTURE(texture);
  g_mutex_lock(&self->mutex);
  size_t need = static_cast<size_t>(self->stage_w) * self->stage_h * 4;
  if (need > self->frame_cap) {
    g_free(self->frame);
    self->frame = static_cast<uint8_t*>(g_malloc(need));
    self->frame_cap = need;
  }
  memcpy(self->frame, self->stage, need);
  self->frame_w = self->stage_w;
  self->frame_h = self->stage_h;
  g_mutex_unlock(&self->mutex);
  *out_buffer = self->frame;
  *width = self->frame_w;
  *height = self->frame_h;
  return TRUE;
}

static void oasis_texture_dispose(GObject* object) {
  OasisTexture* self = OASIS_TEXTURE(object);
  g_clear_pointer(&self->stage, g_free);
  g_clear_pointer(&self->frame, g_free);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(oasis_texture_parent_class)->dispose(object);
}

static void oasis_texture_class_init(OasisTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = oasis_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      oasis_texture_copy_pixels;
}

static void oasis_texture_init(OasisTexture* self) {
  g_mutex_init(&self->mutex);
  self->stage = static_cast<uint8_t*>(g_malloc0(4));
  self->stage_w = 1;
  self->stage_h = 1;
}

static void oasis_texture_push(OasisTexture* self,
                               const uint8_t* rgba,
                               uint32_t w,
                               uint32_t h) {
  g_mutex_lock(&self->mutex);
  if (self->stage_w != w || self->stage_h != h) {
    g_free(self->stage);
    self->stage = static_cast<uint8_t*>(g_malloc((size_t)w * h * 4));
    self->stage_w = w;
    self->stage_h = h;
  }
  memcpy(self->stage, rgba, (size_t)w * h * 4);
  g_mutex_unlock(&self->mutex);
}

enum SurfaceRole {
  SURFACE_NONE,
  SURFACE_TOPLEVEL,
  SURFACE_POPUP,
  SURFACE_SUBSURFACE,
  SURFACE_CURSOR,
};

struct Surface {
  OasisCompositor* comp = nullptr;
  wl_resource* wl_surface = nullptr;
  wl_resource* xdg_surface = nullptr;
  wl_resource* role_res = nullptr;
  SurfaceRole role = SURFACE_NONE;
  SurfaceRole announced = SURFACE_NONE;
  Surface* parent = nullptr;
  std::vector<Surface*> children;
  wl_client* client = nullptr;

  wl_resource* pending_buffer = nullptr;
  int pending_ox = 0;
  int pending_oy = 0;
  uint8_t* img = nullptr;
  int iw = 0;
  int ih = 0;
  int sx = 0;
  int sy = 0;
  bool sync = true;

  OasisTexture* texture = nullptr;
  int64_t texture_id = -1;
  int64_t public_id = -1;
  std::string title;
  std::string app_id;
  std::vector<wl_resource*> frames;

  int cfg_w = 0;
  int cfg_h = 0;
  bool cfg_max = false;
  int rep_w = 0;
  int rep_h = 0;
  pid_t pid = -1;
};

struct SeatRes {
  wl_client* client;
  wl_resource* pointer = nullptr;
  wl_resource* keyboard = nullptr;
};

struct DataSource {
  OasisCompositor* comp;
  wl_resource* res;
  std::vector<std::string> mimes;
};

struct DataDevice {
  wl_resource* res;
  wl_client* client;
};

struct DataOffer {
  wl_resource* res;
};

struct Positioner {
  int w = 0;
  int h = 0;
  int arx = 0;
  int ary = 0;
  int arw = 0;
  int arh = 0;
  uint32_t anchor = XDG_POSITIONER_ANCHOR_NONE;
  uint32_t gravity = XDG_POSITIONER_GRAVITY_NONE;
  uint32_t constraint = 0;
  int offx = 0;
  int offy = 0;
};

struct ReadCtx {
  OasisCompositor* comp;
  GIOChannel* channel;
  GString* text;
};

struct _OasisCompositor {
  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean listening = FALSE;

  wl_display* display = nullptr;
  GIOChannel* watch_channel = nullptr;
  guint watch = 0;
  char* socket_name = nullptr;

  std::vector<Surface*> surfaces;
  std::unordered_map<int64_t, Surface*> by_id;
  int64_t next_id = 1;
  Surface* kb_focus = nullptr;
  Surface* ptr_focus = nullptr;
  std::vector<SeatRes> seats;
  std::set<uint32_t> pressed;
  std::vector<DataDevice*> devices;
  std::vector<DataSource*> sources;
  std::vector<DataOffer*> offers;

  char* keymap = nullptr;
  size_t keymap_len = 0;
};

static uint32_t now_ms() {
  return static_cast<uint32_t>(g_get_monotonic_time() / 1000);
}

static void comp_flush(OasisCompositor* c) {
  if (c->display) wl_display_flush_clients(c->display);
}

static void send_event(OasisCompositor* c, FlValue* map) {
  if (c->listening && c->event_channel != nullptr) {
    fl_event_channel_send(c->event_channel, map, nullptr, nullptr);
  }
  fl_value_unref(map);
}

static FlValue* new_event(const char* name) {
  FlValue* m = fl_value_new_map();
  fl_value_set_string_take(m, "event", fl_value_new_string(name));
  return m;
}

static void ev_id(FlValue* m, int64_t id) {
  fl_value_set_string_take(m, "id", fl_value_new_int(id));
}

static SeatRes* seat_for(OasisCompositor* c, wl_client* client, bool create) {
  for (auto& s : c->seats) {
    if (s.client == client) return &s;
  }
  if (!create) return nullptr;
  c->seats.push_back(SeatRes{client, nullptr, nullptr});
  return &c->seats.back();
}

static Surface* surface_root(Surface* s) {
  while (s->parent != nullptr) s = s->parent;
  return s;
}

static void flatten_push(Surface* top);

static void apply_buffer(Surface* s, wl_resource* buffer_res) {
  wl_shm_buffer* b = wl_shm_buffer_get(buffer_res);
  if (b == nullptr) {
    g_clear_pointer(&s->img, g_free);
    s->iw = s->ih = 0;
    return;
  }
  int w = wl_shm_buffer_get_width(b);
  int h = wl_shm_buffer_get_height(b);
  int stride = wl_shm_buffer_get_stride(b);
  uint32_t fmt = wl_shm_buffer_get_format(b);
  if (w <= 0 || h <= 0) return;
  if (s->iw != w || s->ih != h) {
    g_free(s->img);
    s->img = static_cast<uint8_t*>(g_malloc((size_t)w * h * 4));
    s->iw = w;
    s->ih = h;
  }
  const uint8_t* src = static_cast<const uint8_t*>(wl_shm_buffer_get_data(b));
  wl_shm_buffer_begin_access(b);
  for (int y = 0; y < h; y++) {
    const uint8_t* row = src + (size_t)y * stride;
    uint8_t* dst = s->img + (size_t)y * w * 4;
    for (int x = 0; x < w; x++) {
      uint32_t px;
      memcpy(&px, row + x * 4, 4);
      dst[x * 4 + 0] = (px >> 16) & 0xff;
      dst[x * 4 + 1] = (px >> 8) & 0xff;
      dst[x * 4 + 2] = px & 0xff;
      dst[x * 4 + 3] =
          fmt == WL_SHM_FORMAT_XRGB8888 ? 0xff : (px >> 24) & 0xff;
    }
  }
  wl_shm_buffer_end_access(b);
}

static void flatten_into(Surface* s, uint8_t* dst, int dw, int dh, int ox,
                         int oy) {
  if (s->img == nullptr) return;
  for (int y = 0; y < s->ih; y++) {
    int dy = oy + s->sy + y;
    if (dy < 0 || dy >= dh) continue;
    for (int x = 0; x < s->iw; x++) {
      int dx = ox + s->sx + x;
      if (dx < 0 || dx >= dw) continue;
      const uint8_t* sp = s->img + (size_t)y * s->iw * 4 + x * 4;
      uint8_t* dp = dst + (size_t)dy * dw * 4 + dx * 4;
      uint8_t a = sp[3];
      dp[0] = sp[0] + ((255 - a) * dp[0]) / 255;
      dp[1] = sp[1] + ((255 - a) * dp[1]) / 255;
      dp[2] = sp[2] + ((255 - a) * dp[2]) / 255;
      dp[3] = a + ((255 - a) * dp[3]) / 255;
    }
  }
  for (Surface* child : s->children) {
    flatten_into(child, dst, dw, dh, ox + s->sx, oy + s->sy);
  }
}

static void flatten_push(Surface* top) {
  if (top->texture == nullptr || top->iw <= 0 || top->ih <= 0) return;
  size_t size = (size_t)top->iw * top->ih * 4;
  uint8_t* flat = static_cast<uint8_t*>(g_malloc(size));
  flatten_into(top, flat, top->iw, top->ih, 0, 0);
  oasis_texture_push(top->texture, flat, top->iw, top->ih);
  g_free(flat);
  fl_texture_registrar_mark_texture_frame_available(
      top->comp->texture_registrar, FL_TEXTURE(top->texture));
}

static void finish_frames(Surface* s) {
  for (wl_resource* cb : s->frames) {
    wl_callback_send_done(cb, now_ms());
    wl_resource_destroy(cb);
  }
  s->frames.clear();
}

static void emit_size(Surface* s) {
  if (s->rep_w == s->iw && s->rep_h == s->ih) return;
  s->rep_w = s->iw;
  s->rep_h = s->ih;
  FlValue* m = new_event("size");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "w", fl_value_new_int(s->iw));
  fl_value_set_string_take(m, "h", fl_value_new_int(s->ih));
  send_event(s->comp, m);
}

static void surface_commit(Surface* s) {
  if (s->pending_buffer != nullptr) {
    apply_buffer(s, s->pending_buffer);
    s->pending_buffer = nullptr;
  }
  finish_frames(s);
  if (s->role == SURFACE_TOPLEVEL || s->role == SURFACE_POPUP) {
    emit_size(s);
    flatten_push(s);
  } else if (s->role == SURFACE_SUBSURFACE && !s->sync &&
             s->parent != nullptr) {
    flatten_push(surface_root(s->parent));
  }
}

// wl_surface

static void surface_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void surface_attach(wl_client* client,
                           wl_resource* res,
                           wl_resource* buffer,
                           int32_t x,
                           int32_t y) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_buffer = buffer;
  s->pending_ox = x;
  s->pending_oy = y;
}

static void surface_damage(wl_client* client,
                           wl_resource* res,
                           int32_t x,
                           int32_t y,
                           int32_t w,
                           int32_t h) {}

static void surface_frame(wl_client* client,
                          wl_resource* res,
                          uint32_t callback) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  wl_resource* cb = wl_resource_create(client, &wl_callback_interface, 1,
                                       callback);
  s->frames.push_back(cb);
}

static void surface_set_opaque_region(wl_client* client,
                                      wl_resource* res,
                                      wl_resource* region) {}

static void surface_set_input_region(wl_client* client,
                                     wl_resource* res,
                                     wl_resource* region) {}

static void surface_commit_req(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  surface_commit(s);
}

static void surface_set_buffer_transform(wl_client* client,
                                         wl_resource* res,
                                         int32_t transform) {}

static void surface_set_buffer_scale(wl_client* client,
                                     wl_resource* res,
                                     int32_t scale) {}

static void surface_damage_buffer(wl_client* client,
                                  wl_resource* res,
                                  int32_t x,
                                  int32_t y,
                                  int32_t w,
                                  int32_t h) {}

static void surface_offset(wl_client* client,
                           wl_resource* res,
                           int32_t x,
                           int32_t y) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_ox = x;
  s->pending_oy = y;
}

static const struct wl_surface_interface surface_impl = {
    surface_destroy,
    surface_attach,
    surface_damage,
    surface_frame,
    surface_set_opaque_region,
    surface_set_input_region,
    surface_commit_req,
    surface_set_buffer_transform,
    surface_set_buffer_scale,
    surface_damage_buffer,
    surface_offset,
};

static void emit_closed(OasisCompositor* c, Surface* s) {
  FlValue* m = new_event(s->announced == SURFACE_POPUP ? "popupClosed"
                                                     : "toplevelClosed");
  ev_id(m, s->public_id);
  send_event(c, m);
}

static void free_surface(Surface* s) {
  OasisCompositor* c = s->comp;
  if (s->announced != SURFACE_NONE) emit_closed(c, s);
  if (c->kb_focus == s) c->kb_focus = nullptr;
  if (c->ptr_focus == s) c->ptr_focus = nullptr;
  if (s->parent != nullptr) {
    auto& ch = s->parent->children;
    ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
    s->parent = nullptr;
  }
  for (Surface* child : s->children) child->parent = nullptr;
  s->children.clear();
  if (s->texture != nullptr) {
    fl_texture_registrar_unregister_texture(c->texture_registrar,
                                            FL_TEXTURE(s->texture));
    g_object_unref(s->texture);
  }
  c->by_id.erase(s->public_id);
  c->surfaces.erase(
      std::remove(c->surfaces.begin(), c->surfaces.end(), s),
      c->surfaces.end());
  g_free(s->img);
  delete s;
  comp_flush(c);
}

static void surface_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->wl_surface = nullptr;
  free_surface(s);
}

static void xdg_surface_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) s->xdg_surface = nullptr;
}

static void role_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) s->role_res = nullptr;
}

// wl_region

static void region_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void region_add(wl_client* client,
                       wl_resource* res,
                       int32_t x,
                       int32_t y,
                       int32_t w,
                       int32_t h) {}

static void region_subtract(wl_client* client,
                            wl_resource* res,
                            int32_t x,
                            int32_t y,
                            int32_t w,
                            int32_t h) {}

static const struct wl_region_interface region_impl = {
    region_destroy, region_add, region_subtract};

// wl_compositor

static void compositor_create_surface(wl_client* client,
                                      wl_resource* res,
                                      uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  Surface* s = new Surface();
  s->comp = c;
  s->client = client;
  wl_client_get_credentials(client, &s->pid, nullptr, nullptr);
  wl_resource* surf =
      wl_resource_create(client, &wl_surface_interface,
                         wl_resource_get_version(res), id);
  s->wl_surface = surf;
  wl_resource_set_implementation(surf, &surface_impl, s,
                                 surface_res_destroyed);
  c->surfaces.push_back(s);
}

static void compositor_create_region(wl_client* client,
                                     wl_resource* res,
                                     uint32_t id) {
  wl_resource* region = wl_resource_create(client, &wl_region_interface,
                                           wl_resource_get_version(res), id);
  wl_resource_set_implementation(region, &region_impl, nullptr, nullptr);
}

static const struct wl_compositor_interface compositor_impl = {
    compositor_create_surface, compositor_create_region};

// wl_subsurface / wl_subcompositor

static void subsurface_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void subsurface_set_position(wl_client* client,
                                    wl_resource* res,
                                    int32_t x,
                                    int32_t y) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->sx = x;
  s->sy = y;
}

static void subsurface_place_above(wl_client* client,
                                   wl_resource* res,
                                   wl_resource* sibling_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  Surface* sibling =
      static_cast<Surface*>(wl_resource_get_user_data(sibling_res));
  if (s->parent == nullptr || s->parent != sibling->parent) return;
  auto& ch = s->parent->children;
  ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
  auto it = std::find(ch.begin(), ch.end(), sibling);
  ch.insert(it + 1, s);
}

static void subsurface_place_below(wl_client* client,
                                   wl_resource* res,
                                   wl_resource* sibling_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  Surface* sibling =
      static_cast<Surface*>(wl_resource_get_user_data(sibling_res));
  if (s->parent == nullptr || s->parent != sibling->parent) return;
  auto& ch = s->parent->children;
  ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
  auto it = std::find(ch.begin(), ch.end(), sibling);
  ch.insert(it, s);
}

static void subsurface_set_sync(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->sync = true;
}

static void subsurface_set_desync(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->sync = false;
}

static const struct wl_subsurface_interface subsurface_impl = {
    subsurface_destroy,  subsurface_set_position, subsurface_place_above,
    subsurface_place_below, subsurface_set_sync,   subsurface_set_desync,
};

static void subcompositor_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void subcompositor_get_subsurface(wl_client* client,
                                         wl_resource* res,
                                         uint32_t id,
                                         wl_resource* surface_res,
                                         wl_resource* parent_res) {
  Surface* s =
      static_cast<Surface*>(wl_resource_get_user_data(surface_res));
  Surface* parent =
      static_cast<Surface*>(wl_resource_get_user_data(parent_res));
  if (s->role != SURFACE_NONE || s == parent) {
    wl_resource_post_error(res, WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE,
                           "surface already has a role");
    return;
  }
  s->role = SURFACE_SUBSURFACE;
  s->parent = parent;
  parent->children.push_back(s);
  wl_resource* sub = wl_resource_create(client, &wl_subsurface_interface,
                                        wl_resource_get_version(res), id);
  s->role_res = sub;
  wl_resource_set_implementation(sub, &subsurface_impl, s,
                                 role_res_destroyed);
}

static const struct wl_subcompositor_interface subcompositor_impl = {
    subcompositor_destroy, subcompositor_get_subsurface};

// wl_seat / wl_pointer / wl_keyboard / wl_touch

static uint32_t mods_mask(OasisCompositor* c) {
  uint32_t m = 0;
  if (c->pressed.count(42) || c->pressed.count(54)) m |= 1;
  if (c->pressed.count(58)) m |= 2;
  if (c->pressed.count(29) || c->pressed.count(97)) m |= 4;
  if (c->pressed.count(56) || c->pressed.count(100)) m |= 8;
  if (c->pressed.count(69)) m |= 16;
  if (c->pressed.count(125) || c->pressed.count(126)) m |= 64;
  if (c->pressed.count(184) || c->pressed.count(172)) m |= 128;
  return m;
}

static void send_modifiers(OasisCompositor* c) {
  if (c->kb_focus == nullptr) return;
  SeatRes* st = seat_for(c, c->kb_focus->client, false);
  if (st == nullptr || st->keyboard == nullptr) return;
  uint32_t m = mods_mask(c);
  wl_keyboard_send_modifiers(st->keyboard,
                             wl_display_next_serial(c->display), m, 0, 0, 0);
}

static void offer_selection(OasisCompositor* c, wl_client* client);

static void set_kb_focus(OasisCompositor* c, Surface* s) {
  if (c->kb_focus == s) return;
  if (c->kb_focus != nullptr) {
    SeatRes* st = seat_for(c, c->kb_focus->client, false);
    if (st != nullptr && st->keyboard != nullptr &&
        c->kb_focus->wl_surface != nullptr) {
      wl_keyboard_send_leave(st->keyboard,
                             wl_display_next_serial(c->display),
                             c->kb_focus->wl_surface);
    }
  }
  c->kb_focus = s;
  if (s != nullptr) {
    SeatRes* st = seat_for(c, s->client, false);
    if (st != nullptr && st->keyboard != nullptr) {
      wl_array keys;
      wl_array_init(&keys);
      for (uint32_t code : c->pressed) {
        *static_cast<uint32_t*>(wl_array_add(&keys, sizeof(uint32_t))) =
            code;
      }
      wl_keyboard_send_enter(st->keyboard,
                             wl_display_next_serial(c->display),
                             s->wl_surface, &keys);
      wl_array_release(&keys);
    }
    send_modifiers(c);
    offer_selection(c, s->client);
  }
}

static void pointer_enter(OasisCompositor* c, Surface* s, double x, double y) {
  SeatRes* st = seat_for(c, s->client, true);
  if (c->ptr_focus != s) {
    if (c->ptr_focus != nullptr) {
      SeatRes* old = seat_for(c, c->ptr_focus->client, false);
      if (old != nullptr && old->pointer != nullptr &&
          c->ptr_focus->wl_surface != nullptr) {
        wl_pointer_send_leave(old->pointer,
                              wl_display_next_serial(c->display),
                              c->ptr_focus->wl_surface);
        if (wl_resource_get_version(old->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(old->pointer);
        }
      }
    }
    c->ptr_focus = s;
    if (st->pointer != nullptr) {
      wl_pointer_send_enter(st->pointer,
                            wl_display_next_serial(c->display),
                            s->wl_surface, wl_fixed_from_double(x),
                            wl_fixed_from_double(y));
    }
  }
  if (st->pointer != nullptr) {
    wl_pointer_send_motion(st->pointer, now_ms(), wl_fixed_from_double(x),
                           wl_fixed_from_double(y));
    if (wl_resource_get_version(st->pointer) >=
        WL_POINTER_FRAME_SINCE_VERSION) {
      wl_pointer_send_frame(st->pointer);
    }
  }
}

static void pointer_exit(OasisCompositor* c) {
  if (c->ptr_focus == nullptr) return;
  SeatRes* st = seat_for(c, c->ptr_focus->client, false);
  if (st != nullptr && st->pointer != nullptr &&
      c->ptr_focus->wl_surface != nullptr) {
    wl_pointer_send_leave(st->pointer,
                          wl_display_next_serial(c->display),
                          c->ptr_focus->wl_surface);
    if (wl_resource_get_version(st->pointer) >=
        WL_POINTER_FRAME_SINCE_VERSION) {
      wl_pointer_send_frame(st->pointer);
    }
  }
  c->ptr_focus = nullptr;
}

static void pointer_set_cursor(wl_client* client,
                               wl_resource* res,
                               uint32_t serial,
                               wl_resource* surface_res,
                               int32_t hx,
                               int32_t hy) {
  if (surface_res != nullptr) {
    Surface* s =
        static_cast<Surface*>(wl_resource_get_user_data(surface_res));
    if (s->role == SURFACE_NONE) s->role = SURFACE_CURSOR;
  }
}

static void pointer_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_pointer_interface pointer_impl = {
    pointer_set_cursor, pointer_release};

static void keyboard_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_keyboard_interface keyboard_impl = {keyboard_release};

static void touch_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_touch_interface touch_impl = {touch_release};

static int keymap_fd(OasisCompositor* c) {
  int fd = memfd_create("oasis-keymap", MFD_CLOEXEC | MFD_ALLOW_SEALING);
  if (fd < 0) {
    char* tmpl = g_strdup("/tmp/oasis-keymap-XXXXXX");
    fd = mkostemp(tmpl, O_CLOEXEC);
    unlink(tmpl);
    g_free(tmpl);
    if (fd < 0) return -1;
  }
  size_t off = 0;
  while (off < c->keymap_len) {
    ssize_t n = write(fd, c->keymap + off, c->keymap_len - off);
    if (n <= 0) break;
    off += (size_t)n;
  }
  lseek(fd, 0, SEEK_SET);
  return fd;
}

static void seat_get_pointer(wl_client* client,
                             wl_resource* res,
                             uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* p = wl_resource_create(client, &wl_pointer_interface,
                                      wl_resource_get_version(res), id);
  wl_resource_set_implementation(p, &pointer_impl, c, nullptr);
  SeatRes* st = seat_for(c, client, true);
  st->pointer = p;
}

static void seat_get_keyboard(wl_client* client,
                              wl_resource* res,
                              uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* k = wl_resource_create(client, &wl_keyboard_interface,
                                      wl_resource_get_version(res), id);
  wl_resource_set_implementation(k, &keyboard_impl, c, nullptr);
  SeatRes* st = seat_for(c, client, true);
  st->keyboard = k;
  int fd = keymap_fd(c);
  if (fd >= 0) {
    wl_keyboard_send_keymap(k, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd,
                            c->keymap_len);
    close(fd);
  }
  if (wl_resource_get_version(k) >=
      WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION) {
    wl_keyboard_send_repeat_info(k, 25, 600);
  }
  if (c->kb_focus != nullptr && c->kb_focus->client == client) {
    Surface* s = c->kb_focus;
    wl_array keys;
    wl_array_init(&keys);
    wl_keyboard_send_enter(k, wl_display_next_serial(c->display),
                           s->wl_surface, &keys);
    wl_array_release(&keys);
    send_modifiers(c);
  }
}

static void seat_get_touch(wl_client* client,
                           wl_resource* res,
                           uint32_t id) {
  wl_resource* t = wl_resource_create(client, &wl_touch_interface,
                                      wl_resource_get_version(res), id);
  wl_resource_set_implementation(t, &touch_impl, nullptr, nullptr);
}

static void seat_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_seat_interface seat_impl = {
    seat_get_pointer, seat_get_keyboard, seat_get_touch, seat_release};

// wl_output

static void output_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_output_interface output_impl = {output_release};

// wl_data_device family

static void offer_accept(wl_client* client,
                         wl_resource* res,
                         uint32_t serial,
                         const char* mime) {}

static void offer_receive(wl_client* client,
                          wl_resource* res,
                          const char* mime,
                          int32_t fd) {
  GtkClipboard* cb =
      gtk_clipboard_get_for_display(gdk_display_get_default(),
                                    GDK_SELECTION_CLIPBOARD);
  gchar* text = gtk_clipboard_wait_for_text(cb);
  if (text != nullptr) {
    size_t len = strlen(text);
    size_t off = 0;
    while (off < len) {
      ssize_t n = write(fd, text + off, len - off);
      if (n <= 0) break;
      off += (size_t)n;
    }
    g_free(text);
  }
  close(fd);
}

static void offer_destroy_req(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void offer_finish(wl_client* client, wl_resource* res) {}

static void offer_set_actions(wl_client* client,
                              wl_resource* res,
                              uint32_t dnd,
                              uint32_t preferred) {}

static const struct wl_data_offer_interface offer_impl = {
    offer_accept, offer_receive, offer_destroy_req, offer_finish,
    offer_set_actions};

static void data_offer_destroyed(wl_resource* res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  for (auto it = c->offers.begin(); it != c->offers.end(); ++it) {
    if ((*it)->res == res) {
      delete *it;
      c->offers.erase(it);
      return;
    }
  }
}

static void offer_selection(OasisCompositor* c, wl_client* client) {
  DataDevice* dev = nullptr;
  for (auto* d : c->devices) {
    if (d->client == client) dev = d;
  }
  if (dev == nullptr) return;
  wl_resource* offer = wl_resource_create(client, &wl_data_offer_interface,
                                          wl_resource_get_version(dev->res),
                                          0);
  DataOffer* o = new DataOffer{offer};
  c->offers.push_back(o);
  wl_resource_set_implementation(offer, &offer_impl, c,
                                 data_offer_destroyed);
  wl_data_device_send_data_offer(dev->res, offer);
  wl_data_offer_send_offer(offer, "text/plain");
  wl_data_offer_send_offer(offer, "text/plain;charset=utf-8");
  wl_data_device_send_selection(dev->res, offer);
}

static gboolean source_read_cb(GIOChannel* ch,
                               GIOCondition cond,
                               gpointer data) {
  ReadCtx* ctx = static_cast<ReadCtx*>(data);
  if (cond & G_IO_IN) {
    gchar buf[4096];
    gsize n = 0;
    GIOStatus st = g_io_channel_read_chars(ch, buf, sizeof(buf), &n, nullptr);
    if (n > 0) g_string_append_len(ctx->text, buf, n);
    if (st == G_IO_STATUS_ERROR) cond = G_IO_HUP;
  }
  if (cond & (G_IO_HUP | G_IO_ERR)) {
    GtkClipboard* cb =
        gtk_clipboard_get_for_display(gdk_display_get_default(),
                                      GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_text(cb, ctx->text->str, -1);
    g_io_channel_unref(ctx->channel);
    g_string_free(ctx->text, TRUE);
    delete ctx;
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

static void read_client_selection(OasisCompositor* c, DataSource* ds) {
  const char* mime = nullptr;
  for (const auto& m : ds->mimes) {
    if (m == "text/plain;charset=utf-8") mime = m.c_str();
  }
  if (mime == nullptr) {
    for (const auto& m : ds->mimes) {
      if (m.rfind("text/", 0) == 0) mime = m.c_str();
    }
  }
  if (mime == nullptr) return;
  int fds[2];
  if (pipe(fds) != 0) return;
  wl_data_source_send_send(ds->res, mime, fds[1]);
  close(fds[1]);
  GIOChannel* ch = g_io_channel_unix_new(fds[0]);
  ReadCtx* ctx = new ReadCtx{c, ch, g_string_new(nullptr)};
  g_io_add_watch(ch,
                 static_cast<GIOCondition>(G_IO_IN | G_IO_HUP | G_IO_ERR),
                 source_read_cb, ctx);
}

static void source_offer(wl_client* client,
                         wl_resource* res,
                         const char* mime) {
  DataSource* ds =
      static_cast<DataSource*>(wl_resource_get_user_data(res));
  ds->mimes.emplace_back(mime);
}

static void source_destroy_req(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void source_set_actions(wl_client* client,
                               wl_resource* res,
                               uint32_t actions) {}

static const struct wl_data_source_interface source_impl = {
    source_offer, source_destroy_req, source_set_actions};

static void data_source_destroyed(wl_resource* res) {
  DataSource* ds =
      static_cast<DataSource*>(wl_resource_get_user_data(res));
  OasisCompositor* c = ds->comp;
  c->sources.erase(
      std::remove(c->sources.begin(), c->sources.end(), ds),
      c->sources.end());
  delete ds;
}

static void device_start_drag(wl_client* client,
                              wl_resource* res,
                              wl_resource* source,
                              wl_resource* origin,
                              wl_resource* icon,
                              uint32_t serial) {}

static void device_set_selection(wl_client* client,
                                 wl_resource* res,
                                 wl_resource* source,
                                 uint32_t serial) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  if (source == nullptr) return;
  for (auto* ds : c->sources) {
    if (ds->res == source) {
      read_client_selection(c, ds);
      return;
    }
  }
}

static void device_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_data_device_interface device_impl = {
    device_start_drag, device_set_selection, device_release};

static void data_device_destroyed(wl_resource* res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  for (auto it = c->devices.begin(); it != c->devices.end(); ++it) {
    if ((*it)->res == res) {
      delete *it;
      c->devices.erase(it);
      return;
    }
  }
}

static void manager_create_data_source(wl_client* client,
                                       wl_resource* res,
                                       uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* ds =
      wl_resource_create(client, &wl_data_source_interface,
                         wl_resource_get_version(res), id);
  DataSource* source = new DataSource{c, ds, {}};
  c->sources.push_back(source);
  wl_resource_set_implementation(ds, &source_impl, source,
                                 data_source_destroyed);
}

static void manager_get_data_device(wl_client* client,
                                    wl_resource* res,
                                    uint32_t id,
                                    wl_resource* seat_res) {
  wl_resource* dev =
      wl_resource_create(client, &wl_data_device_interface,
                         wl_resource_get_version(res), id);
  DataDevice* d = new DataDevice{dev, client};
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  c->devices.push_back(d);
  wl_resource_set_implementation(dev, &device_impl, c,
                                 data_device_destroyed);
}

static const struct wl_data_device_manager_interface manager_impl = {
    manager_create_data_source, manager_get_data_device};

// xdg shell

static void positioner_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void positioner_set_size(wl_client* client,
                                wl_resource* res,
                                int32_t w,
                                int32_t h) {
  Positioner* p = static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->w = w;
  p->h = h;
}

static void positioner_set_anchor_rect(wl_client* client,
                                       wl_resource* res,
                                       int32_t x,
                                       int32_t y,
                                       int32_t w,
                                       int32_t h) {
  Positioner* p = static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->arx = x;
  p->ary = y;
  p->arw = w;
  p->arh = h;
}

static void positioner_set_anchor(wl_client* client,
                                  wl_resource* res,
                                  uint32_t anchor) {
  Positioner* p = static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->anchor = anchor;
}

static void positioner_set_gravity(wl_client* client,
                                   wl_resource* res,
                                   uint32_t gravity) {
  Positioner* p = static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->gravity = gravity;
}

static void positioner_set_constraint(wl_client* client,
                                      wl_resource* res,
                                      uint32_t constraint) {
  Positioner* p =
      static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->constraint = constraint;
}

static void positioner_set_offset(wl_client* client,
                                  wl_resource* res,
                                  int32_t x,
                                  int32_t y) {
  Positioner* p = static_cast<Positioner*>(wl_resource_get_user_data(res));
  p->offx = x;
  p->offy = y;
}

static void positioner_set_reactive(wl_client* client,
                                    wl_resource* res) {}

static void positioner_set_parent_size(wl_client* client,
                                       wl_resource* res,
                                       int32_t w,
                                       int32_t h) {}

static void positioner_set_parent_configure(wl_client* client,
                                            wl_resource* res,
                                            uint32_t serial) {}

static const struct xdg_positioner_interface positioner_impl = {
    positioner_destroy,
    positioner_set_size,
    positioner_set_anchor_rect,
    positioner_set_anchor,
    positioner_set_gravity,
    positioner_set_constraint,
    positioner_set_offset,
    positioner_set_reactive,
    positioner_set_parent_size,
    positioner_set_parent_configure,
};

static void positioner_res_destroyed(wl_resource* res) {
  delete static_cast<Positioner*>(wl_resource_get_user_data(res));
}

static void popup_position(Positioner* p, int* out_x, int* out_y) {
  int ax = p->arx;
  int ay = p->ary;
  switch (p->anchor) {
    case XDG_POSITIONER_ANCHOR_RIGHT:
    case XDG_POSITIONER_ANCHOR_TOP_RIGHT:
    case XDG_POSITIONER_ANCHOR_BOTTOM_RIGHT:
      ax += p->arw;
      break;
    case XDG_POSITIONER_ANCHOR_NONE:
      ax += p->arw / 2;
      break;
    default:
      break;
  }
  switch (p->anchor) {
    case XDG_POSITIONER_ANCHOR_BOTTOM:
    case XDG_POSITIONER_ANCHOR_BOTTOM_LEFT:
    case XDG_POSITIONER_ANCHOR_BOTTOM_RIGHT:
      ay += p->arh;
      break;
    case XDG_POSITIONER_ANCHOR_NONE:
      ay += p->arh / 2;
      break;
    default:
      break;
  }
  int x = ax;
  int y = ay;
  switch (p->gravity) {
    case XDG_POSITIONER_GRAVITY_RIGHT:
    case XDG_POSITIONER_GRAVITY_TOP_RIGHT:
    case XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT:
      x = ax - p->w;
      break;
    case XDG_POSITIONER_GRAVITY_NONE:
      x = ax - p->w / 2;
      break;
    default:
      break;
  }
  switch (p->gravity) {
    case XDG_POSITIONER_GRAVITY_BOTTOM:
    case XDG_POSITIONER_GRAVITY_BOTTOM_LEFT:
    case XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT:
      y = ay - p->h;
      break;
    case XDG_POSITIONER_GRAVITY_NONE:
      y = ay - p->h / 2;
      break;
    default:
      break;
  }
  x += p->offx;
  y += p->offy;
  if ((p->constraint & XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X) &&
      x < 0) {
    x = 0;
  }
  if ((p->constraint & XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y) &&
      y < 0) {
    y = 0;
  }
  *out_x = x;
  *out_y = y;
}

static void toplevel_configure(OasisCompositor* c,
                               Surface* s,
                               int w,
                               int h,
                               bool maximized,
                               bool active) {
  if (s->role_res == nullptr || s->xdg_surface == nullptr) return;
  s->cfg_w = w;
  s->cfg_h = h;
  s->cfg_max = maximized;
  wl_array states;
  wl_array_init(&states);
  if (active) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_ACTIVATED;
  }
  if (maximized) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_MAXIMIZED;
  }
  xdg_toplevel_send_configure(s->role_res, w, h, &states);
  wl_array_release(&states);
  xdg_surface_send_configure(s->xdg_surface,
                             wl_display_next_serial(c->display));
  comp_flush(c);
}

static void xdg_surface_destroy_req(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void emit_toplevel(OasisCompositor* c, Surface* s) {
  FlValue* m = new_event("toplevel");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "textureId",
                           fl_value_new_int(s->texture_id));
  fl_value_set_string_take(m, "title",
                           fl_value_new_string(s->title.c_str()));
  fl_value_set_string_take(m, "appId",
                           fl_value_new_string(s->app_id.c_str()));
  send_event(c, m);
}

static void toplevel_created(OasisCompositor* c,
                             wl_client* client,
                             wl_resource* xdg_res,
                             uint32_t id) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(xdg_res));
  if (s->role != SURFACE_NONE) {
    wl_resource_post_error(xdg_res, XDG_WM_BASE_ERROR_ROLE,
                           "surface already has a role");
    return;
  }
  s->role = SURFACE_TOPLEVEL;
  s->announced = SURFACE_TOPLEVEL;
  s->texture = OASIS_TEXTURE(
      g_object_new(oasis_texture_get_type(), nullptr));
  fl_texture_registrar_register_texture(c->texture_registrar,
                                        FL_TEXTURE(s->texture));
  s->texture_id = fl_texture_get_id(FL_TEXTURE(s->texture));
  s->public_id = c->next_id++;
  c->by_id[s->public_id] = s;
  wl_resource* tl = wl_resource_create(client, &xdg_toplevel_interface,
                                       wl_resource_get_version(xdg_res), id);
  s->role_res = tl;
  extern const struct xdg_toplevel_interface toplevel_impl;
  wl_resource_set_implementation(tl, &toplevel_impl, s,
                                 role_res_destroyed);
  emit_toplevel(c, s);
  wl_array states;
  wl_array_init(&states);
  xdg_toplevel_send_configure(tl, 0, 0, &states);
  wl_array_release(&states);
  xdg_surface_send_configure(s->xdg_surface,
                             wl_display_next_serial(c->display));
  comp_flush(c);
}

static void popup_created(OasisCompositor* c,
                          wl_client* client,
                          wl_resource* xdg_res,
                          uint32_t id,
                          wl_resource* parent_res,
                          wl_resource* pos_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(xdg_res));
  if (s->role != SURFACE_NONE) {
    wl_resource_post_error(xdg_res, XDG_WM_BASE_ERROR_ROLE,
                           "surface already has a role");
    return;
  }
  Positioner* p =
      pos_res != nullptr
          ? static_cast<Positioner*>(wl_resource_get_user_data(pos_res))
          : nullptr;
  Surface* parent =
      parent_res != nullptr
          ? static_cast<Surface*>(wl_resource_get_user_data(parent_res))
          : nullptr;
  s->role = SURFACE_POPUP;
  s->announced = SURFACE_POPUP;
  s->parent = parent;
  int px = 0;
  int py = 0;
  if (p != nullptr) {
    popup_position(p, &px, &py);
    s->sx = px;
    s->sy = py;
  }
  s->texture = OASIS_TEXTURE(
      g_object_new(oasis_texture_get_type(), nullptr));
  fl_texture_registrar_register_texture(c->texture_registrar,
                                        FL_TEXTURE(s->texture));
  s->texture_id = fl_texture_get_id(FL_TEXTURE(s->texture));
  s->public_id = c->next_id++;
  c->by_id[s->public_id] = s;
  wl_resource* pop = wl_resource_create(client, &xdg_popup_interface,
                                        wl_resource_get_version(xdg_res), id);
  s->role_res = pop;
  extern const struct xdg_popup_interface popup_impl;
  wl_resource_set_implementation(pop, &popup_impl, s, role_res_destroyed);
  xdg_popup_send_configure(pop, px, py, p != nullptr ? p->w : 0,
                           p != nullptr ? p->h : 0);
  xdg_surface_send_configure(s->xdg_surface,
                             wl_display_next_serial(c->display));
  FlValue* m = new_event("popup");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "parent",
                           fl_value_new_int(parent != nullptr
                                                ? parent->public_id
                                                : -1));
  fl_value_set_string_take(m, "textureId",
                           fl_value_new_int(s->texture_id));
  fl_value_set_string_take(m, "x", fl_value_new_int(px));
  fl_value_set_string_take(m, "y", fl_value_new_int(py));
  send_event(c, m);
  comp_flush(c);
}

static void xdg_surface_get_toplevel(wl_client* client,
                                   wl_resource* res,
                                   uint32_t id) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  toplevel_created(s->comp, client, res, id);
}

static void xdg_surface_get_popup(wl_client* client,
                                  wl_resource* res,
                                  uint32_t id,
                                  wl_resource* parent,
                                  wl_resource* positioner) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  popup_created(s->comp, client, res, id, parent, positioner);
}

static void xdg_surface_set_window_geometry(wl_client* client,
                                            wl_resource* res,
                                            int32_t x,
                                            int32_t y,
                                            int32_t w,
                                            int32_t h) {}

static void xdg_surface_ack_configure(wl_client* client,
                                      wl_resource* res,
                                      uint32_t serial) {}

static const struct xdg_surface_interface xdg_surface_impl = {
    xdg_surface_destroy_req, xdg_surface_get_toplevel,
    xdg_surface_get_popup,    xdg_surface_set_window_geometry,
    xdg_surface_ack_configure};

static void toplevel_destroy(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) s->role = SURFACE_NONE;
  wl_resource_destroy(res);
}

static void toplevel_set_parent(wl_client* client,
                                wl_resource* res,
                                wl_resource* parent) {}

static void toplevel_set_title(wl_client* client,
                               wl_resource* res,
                               const char* title) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->title = title != nullptr ? title : "";
  FlValue* m = new_event("title");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "title",
                           fl_value_new_string(s->title.c_str()));
  send_event(s->comp, m);
}

static void toplevel_set_app_id(wl_client* client,
                                wl_resource* res,
                                const char* app_id) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->app_id = app_id != nullptr ? app_id : "";
  FlValue* m = new_event("appId");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "appId",
                           fl_value_new_string(s->app_id.c_str()));
  send_event(s->comp, m);
}

static void toplevel_show_window_menu(wl_client* client,
                                      wl_resource* res,
                                      wl_resource* seat,
                                      uint32_t serial,
                                      int32_t x,
                                      int32_t y) {}

static void emit_simple(Surface* s, const char* name) {
  FlValue* m = new_event(name);
  ev_id(m, s->public_id);
  send_event(s->comp, m);
}

static void toplevel_move(wl_client* client,
                          wl_resource* res,
                          wl_resource* seat,
                          uint32_t serial) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  emit_simple(s, "move");
}

static void toplevel_resize(wl_client* client,
                            wl_resource* res,
                            wl_resource* seat,
                            uint32_t serial,
                            uint32_t edges) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  FlValue* m = new_event("resize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "edges", fl_value_new_int(edges));
  send_event(s->comp, m);
}

static void toplevel_set_max_size(wl_client* client,
                                  wl_resource* res,
                                  int32_t w,
                                  int32_t h) {}

static void toplevel_set_min_size(wl_client* client,
                                  wl_resource* res,
                                  int32_t w,
                                  int32_t h) {}

static void toplevel_set_maximized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  FlValue* m = new_event("maximize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(TRUE));
  send_event(s->comp, m);
}

static void toplevel_unset_maximized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  FlValue* m = new_event("maximize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(FALSE));
  send_event(s->comp, m);
}

static void toplevel_set_fullscreen(wl_client* client,
                                    wl_resource* res,
                                    wl_resource* output) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  FlValue* m = new_event("fullscreen");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(TRUE));
  send_event(s->comp, m);
}

static void toplevel_unset_fullscreen(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  FlValue* m = new_event("fullscreen");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(FALSE));
  send_event(s->comp, m);
}

static void toplevel_set_minimized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  emit_simple(s, "minimize");
}

const struct xdg_toplevel_interface toplevel_impl = {
    toplevel_destroy,          toplevel_set_parent,
    toplevel_set_title,        toplevel_set_app_id,
    toplevel_show_window_menu, toplevel_move,
    toplevel_resize,           toplevel_set_max_size,
    toplevel_set_min_size,     toplevel_set_maximized,
    toplevel_unset_maximized,  toplevel_set_fullscreen,
    toplevel_unset_fullscreen, toplevel_set_minimized,
};

static void popup_destroy(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) s->role = SURFACE_NONE;
  wl_resource_destroy(res);
}

static void popup_grab(wl_client* client,
                       wl_resource* res,
                       wl_resource* seat,
                       uint32_t serial) {}

static void popup_reposition(wl_client* client,
                             wl_resource* res,
                             wl_resource* pos_res,
                             uint32_t token) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  Positioner* p =
      static_cast<Positioner*>(wl_resource_get_user_data(pos_res));
  int x = 0;
  int y = 0;
  popup_position(p, &x, &y);
  s->sx = x;
  s->sy = y;
  xdg_popup_send_repositioned(res, token);
  xdg_popup_send_configure(res, x, y, p->w, p->h);
  xdg_surface_send_configure(s->xdg_surface,
                             wl_display_next_serial(s->comp->display));
  FlValue* m = new_event("popupMoved");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "x", fl_value_new_int(x));
  fl_value_set_string_take(m, "y", fl_value_new_int(y));
  send_event(s->comp, m);
}

const struct xdg_popup_interface popup_impl = {
    popup_destroy, popup_grab, popup_reposition};

static void wm_base_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void wm_base_create_positioner(wl_client* client,
                                     wl_resource* res,
                                     uint32_t id) {
  wl_resource* pos =
      wl_resource_create(client, &xdg_positioner_interface,
                         wl_resource_get_version(res), id);
  Positioner* p = new Positioner();
  wl_resource_set_implementation(pos, &positioner_impl, p,
                                 positioner_res_destroyed);
}

static void wm_base_get_xdg_surface(wl_client* client,
                                  wl_resource* res,
                                  uint32_t id,
                                  wl_resource* surface_res) {
  Surface* s =
      static_cast<Surface*>(wl_resource_get_user_data(surface_res));
  if (s->xdg_surface != nullptr) {
    wl_resource_post_error(res, XDG_WM_BASE_ERROR_ROLE,
                           "surface already has xdg_surface");
    return;
  }
  wl_resource* xs = wl_resource_create(client, &xdg_surface_interface,
                                       wl_resource_get_version(res), id);
  s->xdg_surface = xs;
  wl_resource_set_implementation(xs, &xdg_surface_impl, s,
                                 xdg_surface_res_destroyed);
}

static void wm_base_pong(wl_client* client,
                         wl_resource* res,
                         uint32_t serial) {}

static const struct xdg_wm_base_interface wm_base_impl = {
    wm_base_destroy, wm_base_create_positioner, wm_base_get_xdg_surface,
    wm_base_pong};

// xdg decoration

static void deco_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void deco_set_mode(wl_client* client,
                          wl_resource* res,
                          uint32_t mode) {}

static void deco_unset_mode(wl_client* client, wl_resource* res) {}

static const struct zxdg_toplevel_decoration_v1_interface deco_impl = {
    deco_destroy, deco_set_mode, deco_unset_mode};

static void deco_manager_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void deco_manager_get_decoration(wl_client* client,
                                        wl_resource* res,
                                        uint32_t id,
                                        wl_resource* toplevel) {
  wl_resource* deco =
      wl_resource_create(client, &zxdg_toplevel_decoration_v1_interface,
                         wl_resource_get_version(res), id);
  wl_resource_set_implementation(deco, &deco_impl, nullptr, nullptr);
  zxdg_toplevel_decoration_v1_send_configure(
      deco, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static const struct zxdg_decoration_manager_v1_interface deco_manager_impl =
    {deco_manager_destroy, deco_manager_get_decoration};

// global binds

static void bind_compositor(wl_client* client,
                            void* data,
                            uint32_t ver,
                            uint32_t id) {
  wl_resource* res = wl_resource_create(client, &wl_compositor_interface,
                                        ver, id);
  wl_resource_set_implementation(res, &compositor_impl, data, nullptr);
}

static void bind_subcompositor(wl_client* client,
                               void* data,
                               uint32_t ver,
                               uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &wl_subcompositor_interface, ver, id);
  wl_resource_set_implementation(res, &subcompositor_impl, data, nullptr);
}

static void bind_seat(wl_client* client,
                      void* data,
                      uint32_t ver,
                      uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &wl_seat_interface, ver, id);
  wl_resource_set_implementation(res, &seat_impl, data, nullptr);
  wl_seat_send_capabilities(
      res, WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD);
  if (ver >= WL_SEAT_NAME_SINCE_VERSION) {
    wl_seat_send_name(res, "oasis-seat0");
  }
}

static void bind_output(wl_client* client,
                        void* data,
                        uint32_t ver,
                        uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &wl_output_interface, ver, id);
  wl_resource_set_implementation(res, &output_impl, data, nullptr);
  wl_output_send_geometry(res, 0, 0, 340, 190, WL_OUTPUT_SUBPIXEL_NONE,
                          "Oasis", "embedded", WL_OUTPUT_TRANSFORM_NORMAL);
  if (ver >= WL_OUTPUT_MODE_SINCE_VERSION) {
    wl_output_send_mode(res, WL_OUTPUT_MODE_CURRENT, 1920, 1080, 60000);
  }
  if (ver >= WL_OUTPUT_SCALE_SINCE_VERSION) {
    wl_output_send_scale(res, 1);
  }
  if (ver >= WL_OUTPUT_NAME_SINCE_VERSION) {
    wl_output_send_name(res, "oasis-embedded");
  }
  if (ver >= WL_OUTPUT_DESCRIPTION_SINCE_VERSION) {
    wl_output_send_description(res, "Oasis embedded output");
  }
  if (ver >= WL_OUTPUT_DONE_SINCE_VERSION) {
    wl_output_send_done(res);
  }
}

static void bind_data_device_manager(wl_client* client,
                                     void* data,
                                     uint32_t ver,
                                     uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &wl_data_device_manager_interface, ver, id);
  wl_resource_set_implementation(res, &manager_impl, data, nullptr);
}

static void bind_wm_base(wl_client* client,
                         void* data,
                         uint32_t ver,
                         uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &xdg_wm_base_interface, ver, id);
  wl_resource_set_implementation(res, &wm_base_impl, data, nullptr);
}

static void bind_deco_manager(wl_client* client,
                              void* data,
                              uint32_t ver,
                              uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &zxdg_decoration_manager_v1_interface,
                         ver, id);
  wl_resource_set_implementation(res, &deco_manager_impl, data, nullptr);
}

// display lifecycle

static gboolean display_fd_cb(GIOChannel* ch,
                              GIOCondition cond,
                              gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  if (cond & (G_IO_ERR | G_IO_HUP)) return G_SOURCE_REMOVE;
  wl_event_loop* loop = wl_display_get_event_loop(c->display);
  wl_event_loop_dispatch(loop, 0);
  wl_display_flush_clients(c->display);
  return G_SOURCE_CONTINUE;
}

static void build_keymap(OasisCompositor* c) {
  xkb_context* ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (ctx == nullptr) return;
  xkb_rule_names names = {};
  xkb_keymap* km =
      xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
  if (km == nullptr) {
    xkb_rule_names fallback = {"evdev", "pc105", "us", "", ""};
    km = xkb_keymap_new_from_names(ctx, &fallback,
                                   XKB_KEYMAP_COMPILE_NO_FLAGS);
  }
  if (km != nullptr) {
    c->keymap =
        xkb_keymap_get_as_string(km, XKB_KEYMAP_FORMAT_TEXT_V1);
    c->keymap_len = c->keymap != nullptr ? strlen(c->keymap) + 1 : 0;
    xkb_keymap_unref(km);
  }
  xkb_context_unref(ctx);
}

static bool display_start(OasisCompositor* c, GError** error) {
  if (c->display != nullptr) return true;
  c->display = wl_display_create();
  if (c->display == nullptr) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "wl_display_create failed");
    return false;
  }
  build_keymap(c);
  wl_display_init_shm(c->display);
  wl_display_add_shm_format(c->display, WL_SHM_FORMAT_ARGB8888);
  wl_display_add_shm_format(c->display, WL_SHM_FORMAT_XRGB8888);
  wl_global_create(c->display, &wl_compositor_interface, 5, c,
                   bind_compositor);
  wl_global_create(c->display, &wl_subcompositor_interface, 1, c,
                   bind_subcompositor);
  wl_global_create(c->display, &wl_seat_interface, 5, c, bind_seat);
  wl_global_create(c->display, &wl_output_interface, 4, c, bind_output);
  wl_global_create(c->display, &wl_data_device_manager_interface, 3, c,
                   bind_data_device_manager);
  wl_global_create(c->display, &xdg_wm_base_interface, 3, c, bind_wm_base);
  wl_global_create(c->display, &zxdg_decoration_manager_v1_interface, 1,
                   c, bind_deco_manager);
  const char* name = wl_display_add_socket_auto(c->display);
  if (name == nullptr) {
    wl_display_destroy(c->display);
    c->display = nullptr;
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "could not create wayland socket (XDG_RUNTIME_DIR set?)");
    return false;
  }
  c->socket_name = g_strdup(name);
  int fd = wl_event_loop_get_fd(wl_display_get_event_loop(c->display));
  c->watch_channel = g_io_channel_unix_new(fd);
  c->watch = g_io_add_watch(
      c->watch_channel,
      static_cast<GIOCondition>(G_IO_IN | G_IO_ERR | G_IO_HUP),
      display_fd_cb, c);
  return true;
}

// spawn

static void launch_app(OasisCompositor* c, FlValue* args) {
  if (c->socket_name == nullptr) return;
  FlValue* list = fl_value_lookup_string(args, "argv");
  if (list == nullptr || fl_value_get_type(list) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(list) == 0) {
    return;
  }
  g_autoptr(GPtrArray) argv = g_ptr_array_new();
  for (size_t i = 0; i < fl_value_get_length(list); i++) {
    FlValue* v = fl_value_get_list_value(list, i);
    if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
      g_ptr_array_add(argv, const_cast<char*>(fl_value_get_string(v)));
    }
  }
  if (argv->len == 0) return;
  g_ptr_array_add(argv, nullptr);
  g_auto(GStrv) env = g_get_environ();
  env = g_environ_setenv(env, "WAYLAND_DISPLAY", c->socket_name, TRUE);
  env = g_environ_setenv(env, "GDK_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "GSK_RENDERER", "cairo", TRUE);
  env = g_environ_setenv(env, "GTK_CSD", "0", TRUE);
  env = g_environ_setenv(env, "QT_QPA_PLATFORM", "wayland", TRUE);
  env = g_environ_setenv(env, "QT_WAYLAND_CLIENT_BUFFER_INTEGRATION",
                         "shm", TRUE);
  env = g_environ_setenv(env, "QT_WAYLAND_DISABLE_WINDOWDECORATION", "1",
                         TRUE);
  env = g_environ_setenv(env, "SDL_VIDEODRIVER", "wayland", TRUE);
  env = g_environ_setenv(env, "XDG_SESSION_TYPE", "wayland", TRUE);
  env = g_environ_setenv(env, "MOZ_ENABLE_WAYLAND", "1", TRUE);
  env = g_environ_setenv(env, "WINIT_UNIX_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "CLUTTER_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "ECORE_EVAS_ENGINE", "wayland_shm", TRUE);
  env = g_environ_setenv(env, "ELM_ENGINE", "wayland_shm", TRUE);
  g_spawn_async(nullptr,
                reinterpret_cast<gchar**>(argv->pdata), env,
                static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH),
                nullptr, nullptr, nullptr, nullptr);
}

static Surface* surface_by_id(OasisCompositor* c, FlValue* args) {
  FlValue* v = fl_value_lookup_string(args, "id");
  if (v == nullptr) return nullptr;
  auto it = c->by_id.find(fl_value_get_int(v));
  return it != c->by_id.end() ? it->second : nullptr;
}

static int64_t arg_int(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr ? fl_value_get_int(v) : 0;
}

static double arg_double(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr ? fl_value_get_float(v) : 0;
}

struct KillCheck {
  OasisCompositor* comp;
  int64_t id;
};

static gboolean kill_check(gpointer data) {
  KillCheck* k = static_cast<KillCheck*>(data);
  auto it = k->comp->by_id.find(k->id);
  if (it != k->comp->by_id.end() && it->second->pid > 0) {
    kill(it->second->pid, SIGTERM);
  }
  delete k;
  return G_SOURCE_REMOVE;
}

// method channel

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* call,
                           gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(name, "start") == 0) {
    g_autoptr(GError) error = nullptr;
    if (!display_start(c, &error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "start-failed", error->message, nullptr));
    } else {
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "socket",
                               fl_value_new_string(c->socket_name));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    }
  } else if (g_strcmp0(name, "launch") == 0) {
    launch_app(c, args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "configure") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr && s->role == SURFACE_TOPLEVEL) {
      toplevel_configure(c, s, (int)arg_int(args, "w"),
                         (int)arg_int(args, "h"),
                         arg_int(args, "maximized") != 0, true);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "close") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr) {
      if (s->role == SURFACE_TOPLEVEL && s->role_res != nullptr) {
        xdg_toplevel_send_close(s->role_res);
        comp_flush(c);
        g_timeout_add(2500, kill_check, new KillCheck{c, s->public_id});
      } else if (s->role == SURFACE_POPUP && s->role_res != nullptr) {
        xdg_popup_send_popup_done(s->role_res);
        comp_flush(c);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "focus") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr && (s->role == SURFACE_TOPLEVEL ||
                         s->role == SURFACE_POPUP)) {
      set_kb_focus(c, s);
      if (s->role == SURFACE_TOPLEVEL) {
        toplevel_configure(c, s, s->cfg_w, s->cfg_h, s->cfg_max, true);
      }
    } else {
      set_kb_focus(c, nullptr);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerMotion") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr) {
      pointer_enter(c, s, arg_double(args, "x"), arg_double(args, "y"));
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerExit") == 0) {
    pointer_exit(c);
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerButton") == 0) {
    if (c->ptr_focus != nullptr) {
      SeatRes* st = seat_for(c, c->ptr_focus->client, false);
      if (st != nullptr && st->pointer != nullptr) {
        wl_pointer_send_button(st->pointer,
                               wl_display_next_serial(c->display),
                               now_ms(), (uint32_t)arg_int(args, "button"),
                               (uint32_t)arg_int(args, "state"));
        if (wl_resource_get_version(st->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(st->pointer);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerAxis") == 0) {
    if (c->ptr_focus != nullptr) {
      SeatRes* st = seat_for(c, c->ptr_focus->client, false);
      if (st != nullptr && st->pointer != nullptr) {
        double dx = arg_double(args, "dx");
        double dy = arg_double(args, "dy");
        uint32_t t = now_ms();
        if (dx != 0) {
          wl_pointer_send_axis(st->pointer, t,
                               WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                               wl_fixed_from_double(dx));
        }
        if (dy != 0) {
          wl_pointer_send_axis(st->pointer, t,
                               WL_POINTER_AXIS_VERTICAL_SCROLL,
                               wl_fixed_from_double(dy));
        }
        if (wl_resource_get_version(st->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(st->pointer);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "key") == 0) {
    uint32_t code = (uint32_t)arg_int(args, "code");
    uint32_t state = (uint32_t)arg_int(args, "state");
    uint32_t before = mods_mask(c);
    if (state == WL_KEYBOARD_KEY_STATE_PRESSED) {
      c->pressed.insert(code);
    } else {
      c->pressed.erase(code);
    }
    if (c->kb_focus != nullptr) {
      SeatRes* st = seat_for(c, c->kb_focus->client, false);
      if (st != nullptr && st->keyboard != nullptr) {
        wl_keyboard_send_key(st->keyboard,
                             wl_display_next_serial(c->display), now_ms(),
                             code, state);
        if (mods_mask(c) != before) send_modifiers(c);
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "stop") == 0) {
    if (c->watch != 0) g_source_remove(c->watch);
    c->watch = 0;
    if (c->watch_channel != nullptr) {
      g_io_channel_unref(c->watch_channel);
      c->watch_channel = nullptr;
    }
    if (c->display != nullptr) {
      wl_display_destroy_clients(c->display);
      wl_display_destroy(c->display);
      c->display = nullptr;
    }
    g_clear_pointer(&c->socket_name, g_free);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void replay_state(OasisCompositor* c) {
  for (Surface* s : c->surfaces) {
    if (s->announced == SURFACE_NONE) continue;
    if (s->announced == SURFACE_TOPLEVEL) {
      FlValue* m = new_event("toplevel");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "textureId",
                               fl_value_new_int(s->texture_id));
      fl_value_set_string_take(m, "title",
                               fl_value_new_string(s->title.c_str()));
      fl_value_set_string_take(
          m, "appId", fl_value_new_string(s->app_id.c_str()));
      send_event(c, m);
    } else if (s->announced == SURFACE_POPUP) {
      FlValue* m = new_event("popup");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "parent",
                               fl_value_new_int(s->parent != nullptr
                                                    ? s->parent->public_id
                                                    : -1));
      fl_value_set_string_take(m, "textureId",
                               fl_value_new_int(s->texture_id));
      fl_value_set_string_take(m, "x", fl_value_new_int(s->sx));
      fl_value_set_string_take(m, "y", fl_value_new_int(s->sy));
      send_event(c, m);
    }
    s->rep_w = 0;
    s->rep_h = -1;
    emit_size(s);
  }
}

static FlMethodErrorResponse* listen_cb(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  c->listening = TRUE;
  replay_state(c);
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  c->listening = FALSE;
  return nullptr;
}

OasisCompositor* oasis_compositor_new(FlPluginRegistrar* registrar,
                                        FlView* view) {
  OasisCompositor* c = new OasisCompositor();
  c->registrar = registrar;
  FlEngine* engine = fl_view_get_engine(view);
  c->texture_registrar = fl_engine_get_texture_registrar(engine);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  c->method_channel = fl_method_channel_new(messenger, "oasis/wayland",
                                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(c->method_channel,
                                            method_call_cb, c, nullptr);
  g_autoptr(FlStandardMethodCodec) msg_codec =
      fl_standard_method_codec_new();
  c->event_channel = fl_event_channel_new(messenger, "oasis/wayland/events",
                                        FL_METHOD_CODEC(msg_codec));
  fl_event_channel_set_stream_handlers(c->event_channel, listen_cb,
                                       cancel_cb, c, nullptr);
  return c;
}

void oasis_compositor_free(OasisCompositor* c) {
  if (c == nullptr) return;
  if (c->watch != 0) g_source_remove(c->watch);
  if (c->watch_channel != nullptr) g_io_channel_unref(c->watch_channel);
  if (c->display != nullptr) {
    wl_display_destroy_clients(c->display);
    wl_display_destroy(c->display);
  }
  for (Surface* s : c->surfaces) {
    if (s->texture != nullptr) g_object_unref(s->texture);
    g_free(s->img);
    delete s;
  }
  for (DataSource* ds : c->sources) delete ds;
  for (DataOffer* o : c->offers) delete o;
  for (DataDevice* d : c->devices) delete d;
  g_free(c->keymap);
  g_free(c->socket_name);
  g_clear_object(&c->method_channel);
  g_clear_object(&c->event_channel);
  delete c;
}
