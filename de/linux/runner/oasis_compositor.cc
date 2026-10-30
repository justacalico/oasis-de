#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "oasis_compositor.h"
#include "oasis_textures.h"

#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <unordered_set>
#include <unordered_map>
#include <vector>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gtk/gtk.h>
#include <libdrm/drm_fourcc.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include "cursor-shape-v1-server-protocol.h"
#include "fractional-scale-v1-server-protocol.h"
#include "idle-inhibit-unstable-v1-server-protocol.h"
#include "linux-dmabuf-v1-server-protocol.h"
#include "presentation-time-server-protocol.h"
#include "primary-selection-unstable-v1-server-protocol.h"
#include "text-input-unstable-v3-server-protocol.h"
#include "viewporter-server-protocol.h"
#include "xdg-activation-v1-server-protocol.h"
#include "xdg-decoration-unstable-v1-server-protocol.h"
#include "xdg-shell-server-protocol.h"


struct Surface;
extern const struct xdg_toplevel_interface toplevel_impl;
static bool is_dmabuf_buffer(wl_resource* b);
static void emit_cursor(struct _OasisCompositor* c);
static void emit_toplevel(struct _OasisCompositor* c, Surface* s);
static void send_presented(struct Surface* s);
static void sync_text_input_focus(struct _OasisCompositor* c);
static void send_primary_selection(struct _OasisCompositor* c,
                                   wl_resource* device);

struct TextInput {
  wl_resource* res;
  wl_client* client;
  OasisCompositor* client_comp = nullptr;
  struct Surface* entered = nullptr;
  bool enabled = false;
  uint32_t serial = 0;
  uint32_t cause = 0;
  uint32_t hint = 0;
  uint32_t purpose = 0;
  std::string surrounding;
  int32_t cursor_pos = 0;
  int32_t anchor = 0;
  std::array<int32_t, 4> rect{0, 0, 0, 0};
};

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
  Surface* tl_parent = nullptr;
  std::vector<Surface*> children;
  wl_client* client = nullptr;

  wl_resource* pending_buffer = nullptr;
  wl_listener pending_buffer_destroy = {};
  DmabufBuf* pending_dmabuf = nullptr;
  bool attach_requested = false;
  int pending_ox = 0;
  int pending_oy = 0;
  int pending_px = 0;
  int pending_py = 0;
  bool pending_pos_set = false;
  Surface* pending_place_sibling = nullptr;
  bool pending_place_above = false;
  bool pending_place_set = false;
  int pending_scale = 1;
  int pending_transform = 0;
  int pending_vp_w = -1;
  int pending_vp_h = -1;
  int vp_w = -1;
  int vp_h = -1;
  double pending_vp_sx = -1;
  double pending_vp_sy = -1;
  double pending_vp_sw = -1;
  double pending_vp_sh = -1;
  double vp_sx = -1;
  double vp_sy = -1;
  double vp_sw = -1;
  double vp_sh = -1;
  std::vector<wl_resource*> fractional_scales;
  std::vector<wl_resource*> viewports;
  std::vector<std::array<int32_t, 4>> pending_input;
  std::vector<std::array<int32_t, 4>> pending_opaque;
  std::vector<std::array<int32_t, 4>> pending_damage;
  std::vector<wl_resource*> idle_inhibitors;
  std::vector<wl_resource*> presentation_feedbacks;
  bool pending_input_set = false;
  bool pending_opaque_set = false;
  int buf_scale = 1;
  int transform = 0;
  std::vector<std::array<int32_t, 4>> input_region;
  bool input_null = false;
  bool pending_input_null = false;
  std::vector<std::array<int32_t, 4>> opaque_region;
  bool commit_queued = false;
  uint8_t* img = nullptr;
  int iw = 0;
  int ih = 0;
  int sx = 0;
  int sy = 0;
  bool sync = true;

  int tex_kind = 0;
  OasisTexture* texture = nullptr;
  OasisGLTexture* gl_texture = nullptr;
  DmabufBuf* dmabuf = nullptr;
  int64_t texture_id = -1;
  int64_t public_id = -1;
  std::string title;
  std::string app_id;
  std::vector<wl_resource*> frames;
  wl_resource* deco_res = nullptr;
  int deco_mode = 0;

  int geo_x = 0;
  int geo_y = 0;
  int geo_w = 0;
  int geo_h = 0;
  int pending_geo_x = 0;
  int pending_geo_y = 0;
  int pending_geo_w = 0;
  int pending_geo_h = 0;
  bool pending_geo_set = false;
  int cfg_w = 0;
  int cfg_h = 0;
  bool cfg_max = false;
  bool cfg_fs = false;
  bool cfg_resizing = false;
  bool cfg_active = false;
  bool cfg_pending = false;
  std::unordered_set<uint32_t> pending_serials;
  uint32_t acked_serial = 0;
  uint32_t grab_serial = 0;
  int rep_w = 0;
  int rep_h = 0;
  int rep_bw = 0;
  int rep_bh = 0;
  int rep_gx = 0;
  int rep_gy = 0;
  double rep_vsw = -1;
  double rep_vsh = -1;
  int min_w = 0;
  int min_h = 0;
  int max_w = 0;
  int max_h = 0;
  pid_t pid = -1;
};

struct SeatRes {
  wl_client* client;
  wl_resource* pointer = nullptr;
  wl_resource* keyboard = nullptr;
  wl_resource* touch = nullptr;
};

struct DataSource {
  OasisCompositor* comp;
  wl_client* client;
  wl_resource* res;
  std::vector<std::string> mimes;
};

struct DataDevice {
  wl_resource* res;
  wl_client* client;
  wl_resource* offer = nullptr;
};

struct DataOffer {
  wl_resource* res;
  DataSource* source;
};

struct SelectionQuery {
  OasisCompositor* comp;
  wl_resource* offer;
  wl_resource* device;
};

struct PrimarySource {
  OasisCompositor* comp;
  wl_resource* res;
  std::vector<std::string> mimes;
};

struct WriteCtx {
  int fd;
  GIOChannel* channel;
  GByteArray* data;
  gsize off;
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

struct WmBase {
  OasisCompositor* comp;
  wl_client* client;
  wl_resource* res;
  int missed = 0;
};

struct _OasisCompositor {
  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  GtkWidget* view = nullptr;
  gboolean listening = FALSE;

  wl_display* display = nullptr;
  GIOChannel* watch_channel = nullptr;
  guint watch = 0;
  char* socket_name = nullptr;

  std::vector<Surface*> surfaces;
  std::vector<DmabufBuf*> dmabufs;
  std::unordered_map<int64_t, Surface*> by_id;
  int64_t next_id = 1;
  Surface* kb_focus = nullptr;
  uint32_t kb_enter_serial = 0;
  Surface* activated = nullptr;
  Surface* ptr_focus = nullptr;
  Surface* grab_surface = nullptr;
  int grab_buttons = 0;
  uint32_t ptr_enter_serial = 0;
  uint32_t last_button_serial = 0;
  Surface* ptr_entered = nullptr;
  wl_resource* ptr_entered_res = nullptr;
  Surface* touch_focus = nullptr;
  int touch_id = -1;
  double ptr_x = 0;
  double ptr_y = 0;
  std::vector<SeatRes> seats;
  std::set<uint32_t> pressed;
  std::vector<DataDevice*> devices;
  std::vector<DataSource*> sources;
  std::vector<DataOffer*> offers;
  std::vector<SelectionQuery*> sel_queries;
  DataSource* selection_source = nullptr;
  std::vector<WmBase*> wm_bases;
  std::vector<struct KillCheck*> kill_checks;
  guint ping_timer = 0;
  std::vector<wl_resource*> outputs;
  int out_w = 1920;
  int out_h = 1080;
  guint resize_idle = 0;
  guint config_flush = 0;
  int out_scale = 1;
  Surface* cursor_surface = nullptr;
  int cursor_hx = 0;
  int cursor_hy = 0;
  uint32_t cursor_shape = 0;
  std::vector<wl_resource*> text_inputs;
  std::vector<wl_resource*> primary_devices;
  wl_resource* primary_source = nullptr;
  std::vector<std::string> primary_mimes;
  std::unordered_set<std::string> activation_tokens;

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

static void copy_shm_region(Surface* s,
                            const uint8_t* src,
                            int stride,
                            int w,
                            uint32_t fmt,
                            int x0,
                            int y0,
                            int x1,
                            int y1) {
  for (int y = y0; y < y1; y++) {
    const uint8_t* row = src + (size_t)y * stride;
    uint8_t* dst = s->img + (size_t)y * w * 4;
    for (int x = x0; x < x1; x++) {
      uint32_t px;
      memcpy(&px, row + x * 4, 4);
      dst[x * 4 + 0] = (px >> 16) & 0xff;
      dst[x * 4 + 1] = (px >> 8) & 0xff;
      dst[x * 4 + 2] = px & 0xff;
      dst[x * 4 + 3] =
          fmt == WL_SHM_FORMAT_XRGB8888 ? 0xff : (px >> 24) & 0xff;
    }
  }
}

static void apply_buffer(Surface* s, wl_resource* buffer_res) {
  wl_shm_buffer* b = wl_shm_buffer_get(buffer_res);
  if (b == nullptr) {
    g_clear_pointer(&s->img, g_free);
    s->iw = s->ih = 0;
    s->pending_damage.clear();
    return;
  }
  int w = wl_shm_buffer_get_width(b);
  int h = wl_shm_buffer_get_height(b);
  int stride = wl_shm_buffer_get_stride(b);
  uint32_t fmt = wl_shm_buffer_get_format(b);
  if (w <= 0 || h <= 0 || w > 16384 || h > 16384 ||
      (fmt != WL_SHM_FORMAT_ARGB8888 && fmt != WL_SHM_FORMAT_XRGB8888) ||
      stride < w * 4) {
    s->pending_damage.clear();
    return;
  }
  const bool fresh = s->iw != w || s->ih != h || s->img == nullptr;
  if (fresh) {
    uint8_t* img = static_cast<uint8_t*>(g_try_malloc((size_t)w * h * 4));
    if (img == nullptr) {
      s->iw = s->ih = 0;
      s->pending_damage.clear();
      return;
    }
    g_free(s->img);
    s->img = img;
    s->iw = w;
    s->ih = h;
  }
  wl_shm_buffer_begin_access(b);
  const uint8_t* src = static_cast<const uint8_t*>(wl_shm_buffer_get_data(b));
  bool copied = false;
  if (!fresh && s->transform == 0 && !s->pending_damage.empty()) {
    for (const auto& d : s->pending_damage) {
      int x0 = std::max(d[0], 0), y0 = std::max(d[1], 0);
      int x1 = std::min(d[0] + d[2], w), y1 = std::min(d[1] + d[3], h);
      if (x0 < x1 && y0 < y1) {
        copy_shm_region(s, src, stride, w, fmt, x0, y0, x1, y1);
        copied = true;
      }
    }
  }
  if (!copied) {
    copy_shm_region(s, src, stride, w, fmt, 0, 0, w, h);
  }
  wl_shm_buffer_end_access(b);
  s->pending_damage.clear();
}

static void finish_frames(Surface* s) {
  for (wl_resource* cb : s->frames) {
    wl_callback_send_done(cb, now_ms());
    wl_resource_destroy(cb);
  }
  s->frames.clear();
}

static void emit_size(Surface* s) {
  const int scale = s->buf_scale > 0 ? s->buf_scale : 1;
  const bool swap = (s->transform & 1) != 0;
  int bw = (swap ? s->ih : s->iw) / scale;
  int bh = (swap ? s->iw : s->ih) / scale;
  int w = s->geo_w > 0 ? s->geo_w
                      : s->vp_w > 0  ? s->vp_w
                      : s->vp_sw > 0 ? (int)s->vp_sw
                                     : bw;
  int h = s->geo_h > 0 ? s->geo_h
                      : s->vp_h > 0  ? s->vp_h
                      : s->vp_sh > 0 ? (int)s->vp_sh
                                     : bh;
  if (s->rep_w == w && s->rep_h == h && s->rep_bw == s->iw &&
      s->rep_bh == s->ih && s->rep_gx == s->geo_x &&
      s->rep_gy == s->geo_y && s->rep_vsw == s->vp_sw &&
      s->rep_vsh == s->vp_sh) {
    return;
  }
  s->rep_w = w;
  s->rep_h = h;
  s->rep_bw = s->iw;
  s->rep_bh = s->ih;
  s->rep_gx = s->geo_x;
  s->rep_gy = s->geo_y;
  s->rep_vsw = s->vp_sw;
  s->rep_vsh = s->vp_sh;
  FlValue* m = new_event("size");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "w", fl_value_new_int(w));
  fl_value_set_string_take(m, "h", fl_value_new_int(h));
  fl_value_set_string_take(m, "gx", fl_value_new_int(s->geo_x));
  fl_value_set_string_take(m, "gy", fl_value_new_int(s->geo_y));
  fl_value_set_string_take(m, "bw", fl_value_new_int(s->iw));
  fl_value_set_string_take(m, "bh", fl_value_new_int(s->ih));
  fl_value_set_string_take(m, "scale", fl_value_new_int(scale));
  fl_value_set_string_take(m, "vsx", fl_value_new_float(s->vp_sx));
  fl_value_set_string_take(m, "vsy", fl_value_new_float(s->vp_sy));
  fl_value_set_string_take(m, "vsw", fl_value_new_float(s->vp_sw));
  fl_value_set_string_take(m, "vsh", fl_value_new_float(s->vp_sh));
  fl_value_set_string_take(m, "transform",
                         fl_value_new_int(s->transform));
  send_event(s->comp, m);
}

static void emit_input_region(Surface* s) {
  FlValue* m = new_event("inputRegion");
  ev_id(m, s->public_id);
  if (s->input_null) {
    fl_value_set_string_take(m, "rects", fl_value_new_null());
  } else {
    FlValue* rects = fl_value_new_list();
    for (const auto& r : s->input_region) {
      fl_value_append_take(rects, fl_value_new_int(r[0]));
      fl_value_append_take(rects, fl_value_new_int(r[1]));
      fl_value_append_take(rects, fl_value_new_int(r[2]));
      fl_value_append_take(rects, fl_value_new_int(r[3]));
    }
    fl_value_set_string_take(m, "rects", rects);
  }
  send_event(s->comp, m);
}

static void ensure_texture(Surface* s, int kind) {
  if (s->tex_kind == kind) return;
  OasisCompositor* c = s->comp;
  FlTexture* old = s->tex_kind == 1 ? FL_TEXTURE(s->texture)
                                  : FL_TEXTURE(s->gl_texture);
  if (old != nullptr) {
    fl_texture_registrar_unregister_texture(c->texture_registrar, old);
    g_object_unref(old);
    s->texture = nullptr;
    s->gl_texture = nullptr;
  }
  s->tex_kind = kind;
  s->texture_id = -1;
  FlTexture* tex;
  if (kind == 1) {
    s->texture =
        OASIS_TEXTURE(g_object_new(oasis_texture_get_type(), nullptr));
    tex = FL_TEXTURE(s->texture);
  } else {
    s->gl_texture = OASIS_GL_TEXTURE(
        g_object_new(oasis_gl_texture_get_type(), nullptr));
    tex = FL_TEXTURE(s->gl_texture);
  }
  fl_texture_registrar_register_texture(c->texture_registrar, tex);
  s->texture_id = fl_texture_get_id(tex);
  if (s->announced != SURFACE_NONE) {
    FlValue* m = new_event("texture");
    ev_id(m, s->public_id);
    fl_value_set_string_take(m, "textureId",
                             fl_value_new_int(s->texture_id));
    send_event(c, m);
  }
}

void oasis_dmabuf_ref(DmabufBuf* b) {
  if (b != nullptr) b->refs++;
}

void oasis_dmabuf_unref(DmabufBuf* b) {
  if (b == nullptr || --b->refs > 0) return;
  for (int i = 0; i < 4; i++) {
    if (b->fds[i] >= 0) close(b->fds[i]);
  }
  auto& v = b->comp->dmabufs;
  v.erase(std::remove(v.begin(), v.end(), b), v.end());
  delete b;
}

static void surface_set_dmabuf(Surface* s, DmabufBuf* db) {
  if (s->dmabuf == db) return;
  oasis_dmabuf_unref(s->dmabuf);
  s->dmabuf = db;
  oasis_dmabuf_ref(db);
}

static void pending_buffer_destroyed(wl_listener* listener, void* data) {
  _Pragma("GCC diagnostic push")
  _Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")
  Surface* s = wl_container_of(listener, s, pending_buffer_destroy);
  _Pragma("GCC diagnostic pop")
  wl_list_remove(&s->pending_buffer_destroy.link);
  wl_list_init(&s->pending_buffer_destroy.link);
  s->pending_buffer = nullptr;
}

static void set_pending_buffer(Surface* s, wl_resource* b) {
  if (s->pending_buffer == b) return;
  if (s->pending_buffer != nullptr) {
    wl_list_remove(&s->pending_buffer_destroy.link);
    wl_list_init(&s->pending_buffer_destroy.link);
  }
  s->pending_buffer = b;
  if (b != nullptr) {
    wl_resource_add_destroy_listener(b, &s->pending_buffer_destroy);
  }
}

static void surface_commit(Surface* s) {
  if (s->pending_pos_set) {
    s->sx = s->pending_px;
    s->sy = s->pending_py;
    s->pending_pos_set = false;
    if (s->announced == SURFACE_SUBSURFACE) {
      FlValue* m = new_event("subsurfaceMoved");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "x", fl_value_new_int(s->sx));
      fl_value_set_string_take(m, "y", fl_value_new_int(s->sy));
      send_event(s->comp, m);
    }
  }
  if (s->pending_place_set && s->parent != nullptr) {
    Surface* sib = s->pending_place_sibling;
    auto& ch = s->parent->children;
    ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
    auto it = std::find(ch.begin(), ch.end(), sib);
    if (it != ch.end()) {
      ch.insert(it + (s->pending_place_above ? 1 : 0), s);
    }
    s->pending_place_set = false;
    s->pending_place_sibling = nullptr;
    if (s->parent->announced != SURFACE_NONE) {
      FlValue* m = new_event("childrenReordered");
      ev_id(m, s->parent->public_id);
      FlValue* kids = fl_value_new_list();
      for (Surface* k : s->parent->children) {
        fl_value_append_take(kids, fl_value_new_int(k->public_id));
      }
      fl_value_set_string_take(m, "children", kids);
      send_event(s->comp, m);
    }
  }
  if (s->pending_geo_set) {
    s->geo_x = s->pending_geo_x;
    s->geo_y = s->pending_geo_y;
    s->geo_w = s->pending_geo_w;
    s->geo_h = s->pending_geo_h;
    s->pending_geo_set = false;
  }
  if (s->pending_ox != 0 || s->pending_oy != 0) {
    s->sx -= s->pending_ox;
    s->sy -= s->pending_oy;
    s->pending_ox = 0;
    s->pending_oy = 0;
    if (s->announced == SURFACE_POPUP ||
        s->announced == SURFACE_SUBSURFACE) {
      FlValue* m = new_event(
          s->announced == SURFACE_POPUP ? "popupMoved" : "subsurfaceMoved");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "x", fl_value_new_int(s->sx));
      fl_value_set_string_take(m, "y", fl_value_new_int(s->sy));
      send_event(s->comp, m);
    }
  }
  if (s->pending_scale > 0) {
    s->buf_scale = s->pending_scale;
    s->pending_scale = 0;
  }
  s->transform = s->pending_transform;
  s->vp_w = s->pending_vp_w;
  s->vp_h = s->pending_vp_h;
  s->vp_sx = s->pending_vp_sx;
  s->vp_sy = s->pending_vp_sy;
  s->vp_sw = s->pending_vp_sw;
  s->vp_sh = s->pending_vp_sh;
  if (s->pending_input_set) {
    s->input_region = s->pending_input;
    s->input_null = s->pending_input_null;
    s->pending_input.clear();
    s->pending_input_set = false;
    if (s->announced != SURFACE_NONE) emit_input_region(s);
  }
  if (s->pending_opaque_set) {
    s->opaque_region = s->pending_opaque;
    s->pending_opaque.clear();
    s->pending_opaque_set = false;
  }
  if (s->pending_dmabuf != nullptr) {
    DmabufBuf* db = s->pending_dmabuf;
    set_pending_buffer(s, nullptr);
    oasis_dmabuf_unref(s->pending_dmabuf);
    s->pending_dmabuf = nullptr;
    ensure_texture(s, 2);
    surface_set_dmabuf(s, db);
    g_clear_pointer(&s->img, g_free);
    s->iw = db->w;
    s->ih = db->h;
    if (s->gl_texture != nullptr) {
      oasis_gl_texture_set_dmabuf(s->gl_texture, db);
    }
  } else if (s->pending_buffer != nullptr) {
    wl_resource* b = s->pending_buffer;
    set_pending_buffer(s, nullptr);
    if (wl_shm_buffer_get(b) != nullptr) {
      ensure_texture(s, 1);
      surface_set_dmabuf(s, nullptr);
      apply_buffer(s, b);
      if (s->texture != nullptr && s->iw > 0 && s->ih > 0) {
        oasis_texture_push(s->texture, s->img, s->iw, s->ih);
      }
      wl_buffer_send_release(b);
    }
  } else if (s->attach_requested) {
    g_clear_pointer(&s->img, g_free);
    s->iw = s->ih = 0;
    s->pending_damage.clear();
    surface_set_dmabuf(s, nullptr);
  }
  s->attach_requested = false;
  if (s->announced == SURFACE_NONE && s->role == SURFACE_TOPLEVEL &&
      (s->iw > 0 || s->ih > 0 || s->dmabuf != nullptr)) {
    s->announced = SURFACE_TOPLEVEL;
    emit_toplevel(s->comp, s);
  }
  if (s->announced != SURFACE_NONE) {
    emit_size(s);
  }
  if (s->announced != SURFACE_NONE ||
      s == s->comp->cursor_surface) {
    FlTexture* tex = s->tex_kind == 1   ? FL_TEXTURE(s->texture)
                     : s->tex_kind == 2 ? FL_TEXTURE(s->gl_texture)
                                       : nullptr;
    if (tex != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(
          s->comp->texture_registrar, tex);
    }
    if (s == s->comp->cursor_surface) emit_cursor(s->comp);
  }
  finish_frames(s);
  send_presented(s);
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
  s->attach_requested = true;
  set_pending_buffer(s, buffer);
  oasis_dmabuf_unref(s->pending_dmabuf);
  s->pending_dmabuf = nullptr;
  if (buffer != nullptr && wl_shm_buffer_get(buffer) == nullptr &&
      is_dmabuf_buffer(buffer)) {
    s->pending_dmabuf =
        static_cast<DmabufBuf*>(wl_resource_get_user_data(buffer));
    oasis_dmabuf_ref(s->pending_dmabuf);
  }
  s->pending_ox = x;
  s->pending_oy = y;
}

static void surface_damage(wl_client* client,
                           wl_resource* res,
                           int32_t x,
                           int32_t y,
                           int32_t w,
                           int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s->transform != 0) {
    s->pending_damage.push_back({0, 0, INT32_MAX, INT32_MAX});
    return;
  }
  int sc = s->buf_scale > 0 ? s->buf_scale : 1;
  s->pending_damage.push_back({x * sc, y * sc, w * sc, h * sc});
}

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
                                      wl_resource* region) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_opaque_set = true;
  s->pending_opaque.clear();
  if (region != nullptr) {
    auto* r = static_cast<std::vector<std::array<int32_t, 4>>*>(
        wl_resource_get_user_data(region));
    s->pending_opaque = *r;
  }
}

static void surface_set_input_region(wl_client* client,
                                     wl_resource* res,
                                     wl_resource* region) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_input_set = true;
  s->pending_input_null = region == nullptr;
  s->pending_input.clear();
  if (region != nullptr) {
    auto* r = static_cast<std::vector<std::array<int32_t, 4>>*>(
        wl_resource_get_user_data(region));
    s->pending_input = *r;
  }
}

static void commit_children(Surface* s) {
  for (Surface* child : s->children) {
    if (child->commit_queued || child->sync) {
      child->commit_queued = false;
      surface_commit(child);
    }
    commit_children(child);
  }
}

static void surface_commit_tree(Surface* s) {
  surface_commit(s);
  commit_children(s);
}

static void surface_commit_req(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s->role == SURFACE_SUBSURFACE && s->sync &&
      s->parent != nullptr) {
    s->commit_queued = true;
    return;
  }
  surface_commit_tree(s);
}

static void surface_set_buffer_transform(wl_client* client,
                                         wl_resource* res,
                                         int32_t transform) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_transform = transform;
}

static void surface_set_buffer_scale(wl_client* client,
                                     wl_resource* res,
                                     int32_t scale) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_scale = scale;
}

static void surface_damage_buffer(wl_client* client,
                                  wl_resource* res,
                                  int32_t x,
                                  int32_t y,
                                  int32_t w,
                                  int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  s->pending_damage.push_back({x, y, w, h});
}

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

static Surface* surface_of(wl_resource* r) {
  return r != nullptr && wl_resource_instance_of(r, &wl_surface_interface,
                                                 &surface_impl)
             ? static_cast<Surface*>(wl_resource_get_user_data(r))
             : nullptr;
}

static void emit_closed(OasisCompositor* c, Surface* s) {
  const char* name = s->announced == SURFACE_POPUP
                         ? "popupClosed"
                         : s->announced == SURFACE_SUBSURFACE
                               ? "subsurfaceClosed"
                               : "toplevelClosed";
  FlValue* m = new_event(name);
  ev_id(m, s->public_id);
  send_event(c, m);
}

static void free_surface(Surface* s) {
  OasisCompositor* c = s->comp;
  if (s->announced != SURFACE_NONE) emit_closed(c, s);
  if (c->kb_focus == s) {
    c->kb_focus = nullptr;
    c->pressed.clear();
  }
  if (c->activated == s) c->activated = nullptr;
  if (c->ptr_focus == s) c->ptr_focus = nullptr;
  if (c->touch_focus == s) c->touch_focus = nullptr;
  if (c->grab_surface == s) {
    c->grab_surface = nullptr;
    c->grab_buttons = 0;
  }
  if (c->cursor_surface == s) {
    c->cursor_surface = nullptr;
    emit_cursor(c);
  }
  if (c->ptr_entered == s) {
    c->ptr_entered = nullptr;
    c->ptr_entered_res = nullptr;
  }
  if (s->parent != nullptr) {
    auto& ch = s->parent->children;
    ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
    s->parent = nullptr;
  }
  for (Surface* child : s->children) child->parent = nullptr;
  s->children.clear();
  FlTexture* tex = s->tex_kind == 1 ? FL_TEXTURE(s->texture)
                                    : FL_TEXTURE(s->gl_texture);
  if (tex != nullptr) {
    fl_texture_registrar_unregister_texture(c->texture_registrar, tex);
    g_object_unref(tex);
  }
  for (wl_resource* fs : s->fractional_scales) {
    wl_resource_set_user_data(fs, nullptr);
  }
  for (wl_resource* inh : s->idle_inhibitors) {
    wl_resource_set_user_data(inh, nullptr);
  }
  for (wl_resource* fb : s->presentation_feedbacks) {
    wl_resource_set_user_data(fb, nullptr);
  }
  for (wl_resource* cb : s->frames) {
    wl_resource_destroy(cb);
  }
  s->frames.clear();
  for (wl_resource* vp : s->viewports) {
    wl_resource_set_user_data(vp, nullptr);
  }
  if (s->deco_res != nullptr) {
    wl_resource_set_user_data(s->deco_res, nullptr);
  }
  if (s->xdg_surface != nullptr) {
    wl_resource_set_user_data(s->xdg_surface, nullptr);
  }
  if (s->role_res != nullptr) {
    wl_resource_set_user_data(s->role_res, nullptr);
  }
  for (Surface* x : c->surfaces) {
    if (x->parent == s) {
      if (x->role == SURFACE_POPUP && x->role_res != nullptr) {
        xdg_popup_send_popup_done(x->role_res);
      }
      x->parent = nullptr;
    }
    if (x->tl_parent == s) x->tl_parent = nullptr;
  }
  set_pending_buffer(s, nullptr);
  for (wl_resource* res : c->text_inputs) {
    TextInput* ti =
        static_cast<TextInput*>(wl_resource_get_user_data(res));
    if (ti != nullptr && ti->entered == s) ti->entered = nullptr;
  }
  c->by_id.erase(s->public_id);
  c->surfaces.erase(
      std::remove(c->surfaces.begin(), c->surfaces.end(), s),
      c->surfaces.end());
  surface_set_dmabuf(s, nullptr);
  oasis_dmabuf_unref(s->pending_dmabuf);
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

using RegionRects = std::vector<std::array<int32_t, 4>>;

static void region_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void region_add(wl_client* client,
                       wl_resource* res,
                       int32_t x,
                       int32_t y,
                       int32_t w,
                       int32_t h) {
  auto* r = static_cast<RegionRects*>(wl_resource_get_user_data(res));
  r->push_back({x, y, w, h});
}

static void region_subtract(wl_client* client,
                            wl_resource* res,
                            int32_t x,
                            int32_t y,
                            int32_t w,
                            int32_t h) {
  auto* r = static_cast<RegionRects*>(wl_resource_get_user_data(res));
  RegionRects out;
  for (const auto& a : *r) {
    int ax = a[0], ay = a[1], aw = a[2], ah = a[3];
    int ix = std::max(ax, x), iy = std::max(ay, y);
    int ix2 = std::min(ax + aw, x + w), iy2 = std::min(ay + ah, y + h);
    if (ix >= ix2 || iy >= iy2) {
      out.push_back(a);
      continue;
    }
    if (ay < iy) out.push_back({ax, ay, aw, iy - ay});
    if (ay + ah > iy2) out.push_back({ax, iy2, aw, ay + ah - iy2});
    if (ax < ix) out.push_back({ax, iy, ix - ax, iy2 - iy});
    if (ax + aw > ix2) out.push_back({ix2, iy, ax + aw - ix2, iy2 - iy});
  }
  r->swap(out);
}

static void region_res_destroyed(wl_resource* res) {
  delete static_cast<RegionRects*>(wl_resource_get_user_data(res));
}

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
  s->pending_buffer_destroy.notify = pending_buffer_destroyed;
  wl_list_init(&s->pending_buffer_destroy.link);
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
  wl_resource_set_implementation(region, &region_impl, new RegionRects(),
                                 region_res_destroyed);
}

static const struct wl_compositor_interface compositor_impl = {
    compositor_create_surface, compositor_create_region};

// wl_subsurface / wl_subcompositor

static void subsurface_destroy(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) {
    s->role = SURFACE_NONE;
    if (s->parent != nullptr) {
      auto& ch = s->parent->children;
      ch.erase(std::remove(ch.begin(), ch.end(), s), ch.end());
      s->parent = nullptr;
    }
  }
  wl_resource_destroy(res);
}

static void subsurface_set_position(wl_client* client,
                                    wl_resource* res,
                                    int32_t x,
                                    int32_t y) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->pending_px = x;
  s->pending_py = y;
  s->pending_pos_set = true;
}

static void subsurface_place_above(wl_client* client,
                                   wl_resource* res,
                                   wl_resource* sibling_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  Surface* sibling = surface_of(sibling_res);
  if (s == sibling) {
    wl_resource_post_error(res, WL_SUBSURFACE_ERROR_BAD_SURFACE,
                           "cannot place surface relative to itself");
    return;
  }
  if (sibling == nullptr || s->parent == nullptr ||
      s->parent != sibling->parent) {
    return;
  }
  s->pending_place_sibling = sibling;
  s->pending_place_above = true;
  s->pending_place_set = true;
}

static void subsurface_place_below(wl_client* client,
                                   wl_resource* res,
                                   wl_resource* sibling_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  Surface* sibling = surface_of(sibling_res);
  if (s == sibling) {
    wl_resource_post_error(res, WL_SUBSURFACE_ERROR_BAD_SURFACE,
                           "cannot place surface relative to itself");
    return;
  }
  if (sibling == nullptr || s->parent == nullptr ||
      s->parent != sibling->parent) {
    return;
  }
  s->pending_place_sibling = sibling;
  s->pending_place_above = false;
  s->pending_place_set = true;
}

static void subsurface_set_sync(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) s->sync = true;
}

static void subsurface_set_desync(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->sync = false;
  if (s->commit_queued) {
    s->commit_queued = false;
    surface_commit_tree(s);
  }
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
  Surface* s = surface_of(surface_res);
  Surface* parent = surface_of(parent_res);
  if (s == nullptr || parent == nullptr) {
    wl_resource_post_error(res, WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE,
                           "invalid surface object");
    return;
  }
  if (s->role != SURFACE_NONE) {
    wl_resource_post_error(res, WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE,
                           "surface already has a role");
    return;
  }
  for (Surface* a = parent; a != nullptr; a = a->parent) {
    if (a == s) {
      wl_resource_post_error(
          res, WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE,
          "surface cannot be a subsurface of itself or a descendant");
      return;
    }
  }
  s->role = SURFACE_SUBSURFACE;
  s->announced = SURFACE_SUBSURFACE;
  s->parent = parent;
  parent->children.push_back(s);
  s->public_id = s->comp->next_id++;
  s->comp->by_id[s->public_id] = s;
  wl_resource* sub = wl_resource_create(client, &wl_subsurface_interface,
                                        wl_resource_get_version(res), id);
  s->role_res = sub;
  wl_resource_set_implementation(sub, &subsurface_impl, s,
                                 role_res_destroyed);
  FlValue* m = new_event("subsurface");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "parent", fl_value_new_int(parent->public_id));
  fl_value_set_string_take(m, "x", fl_value_new_int(s->sx));
  fl_value_set_string_take(m, "y", fl_value_new_int(s->sy));
  send_event(s->comp, m);
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
                             wl_display_next_serial(c->display), m & ~2u, 0,
                             c->pressed.count(58) ? 2u : 0u, 0);
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
      uint32_t ser = wl_display_next_serial(c->display);
      wl_keyboard_send_enter(st->keyboard, ser, s->wl_surface, &keys);
      c->kb_enter_serial = ser;
      wl_array_release(&keys);
    }
    send_modifiers(c);
    offer_selection(c, s->client);
    for (wl_resource* dev : c->primary_devices) {
      if (wl_resource_get_client(dev) == s->client) {
        send_primary_selection(c, dev);
      }
    }
  }
  sync_text_input_focus(c);
}

static void pointer_enter(OasisCompositor* c, Surface* s, double x, double y) {
  c->ptr_x = x;
  c->ptr_y = y;
  if (c->grab_surface != nullptr) return;
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
  }
  if (st->pointer != nullptr) {
    if (c->ptr_entered != s || c->ptr_entered_res != st->pointer) {
      uint32_t ser = wl_display_next_serial(c->display);
      wl_pointer_send_enter(st->pointer, ser, s->wl_surface,
                            wl_fixed_from_double(x),
                            wl_fixed_from_double(y));
      c->ptr_enter_serial = ser;
      c->ptr_entered = s;
      c->ptr_entered_res = st->pointer;
    }
    wl_pointer_send_motion(st->pointer, now_ms(), wl_fixed_from_double(x),
                           wl_fixed_from_double(y));
    if (wl_resource_get_version(st->pointer) >=
        WL_POINTER_FRAME_SINCE_VERSION) {
      wl_pointer_send_frame(st->pointer);
    }
  }
}

static void pointer_exit(OasisCompositor* c) {
  if (c->grab_surface != nullptr || c->ptr_focus == nullptr) return;
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
  c->ptr_entered = nullptr;
  c->ptr_entered_res = nullptr;
  if (c->cursor_surface != nullptr) {
    c->cursor_surface = nullptr;
    emit_cursor(c);
  }
}

static void emit_cursor(OasisCompositor* c) {
  FlValue* m = new_event("cursor");
  Surface* s = c->cursor_surface;
  if (s == nullptr) {
    fl_value_set_string_take(m, "id", fl_value_new_int(0));
  } else {
    const int scale = s->buf_scale > 0 ? s->buf_scale : 1;
    fl_value_set_string_take(m, "id", fl_value_new_int(s->public_id));
    fl_value_set_string_take(m, "texture",
                           fl_value_new_int(s->texture_id));
    fl_value_set_string_take(m, "w", fl_value_new_int(s->iw / scale));
    fl_value_set_string_take(m, "h", fl_value_new_int(s->ih / scale));
    fl_value_set_string_take(m, "hx", fl_value_new_int(c->cursor_hx));
    fl_value_set_string_take(m, "hy", fl_value_new_int(c->cursor_hy));
  }
  send_event(c, m);
}

static void pointer_set_cursor(wl_client* client,
                               wl_resource* res,
                               uint32_t serial,
                               wl_resource* surface_res,
                               int32_t hx,
                               int32_t hy) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  c->cursor_hx = hx;
  c->cursor_hy = hy;
  if (surface_res == nullptr) {
    c->cursor_surface = nullptr;
    emit_cursor(c);
    return;
  }
  Surface* s = surface_of(surface_res);
  if (s == nullptr) return;
  if (s->role != SURFACE_NONE && s->role != SURFACE_CURSOR) {
    wl_resource_post_error(res, WL_POINTER_ERROR_ROLE,
                           "surface with a role cannot be the cursor");
    return;
  }
  if (serial != c->ptr_enter_serial &&
      serial != c->last_button_serial) {
    return;
  }
  if (c->cursor_surface != nullptr &&
      c->cursor_surface->role == SURFACE_CURSOR) {
    c->cursor_surface->role = SURFACE_NONE;
  }
  if (s->role == SURFACE_NONE) s->role = SURFACE_CURSOR;
  c->cursor_surface = s;
  emit_cursor(c);
}

static void pointer_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void pointer_res_destroyed(wl_resource* res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  for (auto& s : c->seats) {
    if (s.pointer == res) s.pointer = nullptr;
  }
  if (c->ptr_entered_res == res) c->ptr_entered_res = nullptr;
}

static const struct wl_pointer_interface pointer_impl = {
    pointer_set_cursor, pointer_release};

static void keyboard_release(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void keyboard_res_destroyed(wl_resource* res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  for (auto& s : c->seats) {
    if (s.keyboard == res) s.keyboard = nullptr;
  }
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
  wl_resource_set_implementation(p, &pointer_impl, c,
                               pointer_res_destroyed);
  SeatRes* st = seat_for(c, client, true);
  st->pointer = p;
  if (c->ptr_focus != nullptr && c->ptr_focus->client == client &&
      c->ptr_focus->wl_surface != nullptr &&
      (c->ptr_entered != c->ptr_focus || c->ptr_entered_res != p)) {
    wl_pointer_send_enter(p, wl_display_next_serial(c->display),
                          c->ptr_focus->wl_surface,
                          wl_fixed_from_double(c->ptr_x),
                          wl_fixed_from_double(c->ptr_y));
    c->ptr_entered = c->ptr_focus;
    c->ptr_entered_res = p;
  }
}

static void seat_get_keyboard(wl_client* client,
                              wl_resource* res,
                              uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* k = wl_resource_create(client, &wl_keyboard_interface,
                                      wl_resource_get_version(res), id);
  wl_resource_set_implementation(k, &keyboard_impl, c,
                               keyboard_res_destroyed);
  SeatRes* st = seat_for(c, client, true);
  st->keyboard = k;
  int fd = keymap_fd(c);
  if (fd >= 0) {
    if (c->keymap_len > 0) {
      wl_keyboard_send_keymap(k, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd,
                              c->keymap_len);
    }
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
    for (uint32_t code : c->pressed) {
      *static_cast<uint32_t*>(wl_array_add(&keys, sizeof(uint32_t))) = code;
    }
    wl_keyboard_send_enter(k, wl_display_next_serial(c->display),
                           s->wl_surface, &keys);
    wl_array_release(&keys);
    send_modifiers(c);
  }
}

static void touch_res_destroyed(wl_resource* res) {
  SeatRes* st = static_cast<SeatRes*>(wl_resource_get_user_data(res));
  if (st != nullptr) st->touch = nullptr;
}

static void seat_get_touch(wl_client* client,
                           wl_resource* res,
                           uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* t = wl_resource_create(client, &wl_touch_interface,
                                      wl_resource_get_version(res), id);
  SeatRes* st = seat_for(c, client, true);
  st->touch = t;
  wl_resource_set_implementation(t, &touch_impl, st, touch_res_destroyed);
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

static void send_output_props(OasisCompositor* c, wl_resource* res) {
  uint32_t ver = wl_resource_get_version(res);
  int phys_w = 340, phys_h = 190;
  if (c->view != nullptr && gtk_widget_get_window(c->view) != nullptr) {
    GdkDisplay* dpy = gtk_widget_get_display(c->view);
    GdkMonitor* mon = gdk_display_get_monitor_at_window(
        dpy, gtk_widget_get_window(c->view));
    if (mon != nullptr) {
      phys_w = gdk_monitor_get_width_mm(mon);
      phys_h = gdk_monitor_get_height_mm(mon);
    }
  }
  wl_output_send_geometry(res, 0, 0, phys_w, phys_h,
                          WL_OUTPUT_SUBPIXEL_UNKNOWN, "Oasis", "embedded",
                          WL_OUTPUT_TRANSFORM_NORMAL);
  if (ver >= WL_OUTPUT_MODE_SINCE_VERSION) {
    wl_output_send_mode(res, WL_OUTPUT_MODE_CURRENT, c->out_w, c->out_h,
                        60000);
  }
  if (ver >= WL_OUTPUT_SCALE_SINCE_VERSION) {
    wl_output_send_scale(res, c->out_scale);
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

static void output_res_destroyed(wl_resource* res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  auto& v = c->outputs;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
}

static void output_resend_all(OasisCompositor* c) {
  if (c->view != nullptr) {
    int scale = gtk_widget_get_scale_factor(c->view);
    c->out_scale = scale > 0 ? scale : 1;
    c->out_w = gtk_widget_get_allocated_width(c->view) * c->out_scale;
    c->out_h = gtk_widget_get_allocated_height(c->view) * c->out_scale;
  }
  if (c->out_w <= 0) c->out_w = 1920;
  if (c->out_h <= 0) c->out_h = 1080;
  for (wl_resource* res : c->outputs) {
    send_output_props(c, res);
  }
  for (Surface* s : c->surfaces) {
    for (wl_resource* fs : s->fractional_scales) {
      wp_fractional_scale_v1_send_preferred_scale(
          fs, static_cast<uint32_t>(c->out_scale) * 120);
    }
  }
  comp_flush(c);
}

static gboolean view_resized_idle(gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  c->resize_idle = 0;
  output_resend_all(c);
  return G_SOURCE_REMOVE;
}

static void view_resized(GtkWidget* widget,
                         GdkRectangle* allocation,
                         OasisCompositor* c) {
  int scale = gtk_widget_get_scale_factor(widget);
  int w = allocation->width * (scale > 0 ? scale : 1);
  int h = allocation->height * (scale > 0 ? scale : 1);
  if (w == c->out_w && h == c->out_h && scale == c->out_scale) return;
  if (c->resize_idle == 0) {
    c->resize_idle = g_idle_add(view_resized_idle, c);
  }
}

// wl_data_device family

static void offer_accept(wl_client* client,
                         wl_resource* res,
                         uint32_t serial,
                         const char* mime) {}

static DataOffer* offer_for(OasisCompositor* c, wl_resource* res) {
  for (auto* o : c->offers) {
    if (o->res == res) return o;
  }
  return nullptr;
}

static gboolean paste_write_cb(GIOChannel* ch,
                               GIOCondition cond,
                               gpointer data) {
  WriteCtx* ctx = static_cast<WriteCtx*>(data);
  if (cond & G_IO_OUT) {
    while (ctx->off < ctx->data->len) {
      ssize_t n = write(ctx->fd, ctx->data->data + ctx->off,
                        ctx->data->len - ctx->off);
      if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          return G_SOURCE_CONTINUE;
        }
        break;
      }
      ctx->off += (gsize)n;
    }
    if (ctx->off >= ctx->data->len) cond = G_IO_HUP;
  }
  if (cond & (G_IO_HUP | G_IO_ERR)) {
    close(ctx->fd);
    g_io_channel_unref(ctx->channel);
    g_byte_array_unref(ctx->data);
    delete ctx;
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

static void paste_write_start(int fd, const guint8* bytes, gsize len) {
  if (bytes == nullptr || len == 0) {
    close(fd);
    return;
  }
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
  WriteCtx* ctx = new WriteCtx;
  ctx->fd = fd;
  ctx->channel = g_io_channel_unix_new(fd);
  ctx->data = g_byte_array_sized_new(len);
  g_byte_array_append(ctx->data, bytes, len);
  ctx->off = 0;
  g_io_add_watch(ctx->channel,
                 static_cast<GIOCondition>(G_IO_OUT | G_IO_ERR | G_IO_HUP),
                 paste_write_cb, ctx);
}

static void clipboard_contents_cb(GtkClipboard* clipboard,
                                  GtkSelectionData* sel,
                                  gpointer data) {
  int fd = GPOINTER_TO_INT(data);
  const guint8* bytes = gtk_selection_data_get_data(sel);
  gint len = gtk_selection_data_get_length(sel);
  if (len <= 0) {
    close(fd);
    return;
  }
  paste_write_start(fd, bytes, (gsize)len);
}

static void offer_receive(wl_client* client,
                          wl_resource* res,
                          const char* mime,
                          int32_t fd) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  DataOffer* o = offer_for(c, res);
  if (o != nullptr && o->source != nullptr &&
      o->source->res != nullptr) {
    wl_data_source_send_send(o->source->res, mime, fd);
    close(fd);
    return;
  }
  GtkClipboard* cb =
      gtk_clipboard_get_for_display(gdk_display_get_default(),
                                    GDK_SELECTION_CLIPBOARD);
  GdkAtom atom;
  if (g_strcmp0(mime, "text/plain;charset=utf-8") == 0) {
    atom = gdk_atom_intern_static_string("UTF8_STRING");
  } else {
    atom = gdk_atom_intern(mime, FALSE);
  }
  gtk_clipboard_request_contents(cb, atom, clipboard_contents_cb,
                                 GINT_TO_POINTER(fd));
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
  for (auto* d : c->devices) {
    if (d->offer == res) d->offer = nullptr;
  }
  for (auto it = c->sel_queries.begin(); it != c->sel_queries.end();) {
    if ((*it)->offer == res) {
      it = c->sel_queries.erase(it);
    } else {
      ++it;
    }
  }
  for (auto it = c->offers.begin(); it != c->offers.end(); ++it) {
    if ((*it)->res == res) {
      delete *it;
      c->offers.erase(it);
      return;
    }
  }
}

static const char* atom_mime(const char* name) {
  if (g_strcmp0(name, "UTF8_STRING") == 0) {
    return "text/plain;charset=utf-8";
  }
  if (g_strcmp0(name, "TEXT") == 0 || g_strcmp0(name, "STRING") == 0) {
    return "text/plain";
  }
  if (name != nullptr &&
      (g_str_has_prefix(name, "text/") ||
       g_str_has_prefix(name, "image/") ||
       g_str_has_prefix(name, "application/"))) {
    return name;
  }
  return nullptr;
}

static void clipboard_targets_cb(GtkClipboard* clipboard,
                                 GdkAtom* atoms,
                                 gint n_atoms,
                                 gpointer data) {
  SelectionQuery* q = static_cast<SelectionQuery*>(data);
  OasisCompositor* c = q->comp;
  if (c == nullptr) {
    delete q;
    return;
  }
  auto it = std::find(c->sel_queries.begin(), c->sel_queries.end(), q);
  if (it != c->sel_queries.end()) {
    std::set<std::string> sent;
    for (gint i = 0; i < n_atoms; i++) {
      gchar* name = gdk_atom_name(atoms[i]);
      const char* mime = atom_mime(name);
      if (mime != nullptr && sent.insert(mime).second) {
        wl_data_offer_send_offer(q->offer, mime);
      }
      g_free(name);
    }
    wl_data_device_send_selection(q->device, q->offer);
    c->sel_queries.erase(it);
  }
  delete q;
}

static void offer_selection(OasisCompositor* c, wl_client* client) {
  DataDevice* dev = nullptr;
  for (auto* d : c->devices) {
    if (d->client == client) dev = d;
  }
  if (dev == nullptr) return;
  if (dev->offer != nullptr) {
    wl_resource_destroy(dev->offer);
  }
  wl_resource* offer = wl_resource_create(client, &wl_data_offer_interface,
                                          wl_resource_get_version(dev->res),
                                          0);
  dev->offer = offer;
  DataOffer* o = new DataOffer{offer, nullptr};
  c->offers.push_back(o);
  wl_resource_set_implementation(offer, &offer_impl, c,
                                 data_offer_destroyed);
  wl_data_device_send_data_offer(dev->res, offer);
  DataSource* sel = c->selection_source;
  if (sel != nullptr && sel->res != nullptr) {
    o->source = sel;
    for (const auto& m : sel->mimes) {
      wl_data_offer_send_offer(offer, m.c_str());
    }
    wl_data_device_send_selection(dev->res, offer);
    return;
  }
  GtkClipboard* cb =
      gtk_clipboard_get_for_display(gdk_display_get_default(),
                                    GDK_SELECTION_CLIPBOARD);
  SelectionQuery* q = new SelectionQuery{c, offer, dev->res};
  c->sel_queries.push_back(q);
  gtk_clipboard_request_targets(cb, clipboard_targets_cb, q);
}

static gboolean source_read_cb(GIOChannel* ch,
                               GIOCondition cond,
                               gpointer data) {
  ReadCtx* ctx = static_cast<ReadCtx*>(data);
  if (cond & G_IO_IN) {
    gchar buf[4096];
    gsize n = 0;
    GIOStatus st = g_io_channel_read_chars(ch, buf, sizeof(buf), &n, nullptr);
    if (n > 0) {
      if (ctx->text->len + n > (1 << 20)) {
        cond = G_IO_HUP;
      } else {
        g_string_append_len(ctx->text, buf, n);
      }
    }
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
  if (c->selection_source == ds) c->selection_source = nullptr;
  for (auto* o : c->offers) {
    if (o->source == ds) o->source = nullptr;
  }
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
                              uint32_t serial) {
  if (source != nullptr) {
    wl_data_source_send_cancelled(source);
  }
}

static void device_set_selection(wl_client* client,
                                 wl_resource* res,
                                 wl_resource* source,
                                 uint32_t serial) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  if (serial != c->kb_enter_serial) return;
  c->selection_source = nullptr;
  if (source == nullptr) return;
  for (auto* ds : c->sources) {
    if (ds->res == source) {
      c->selection_source = ds;
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
  for (auto it = c->sel_queries.begin(); it != c->sel_queries.end();) {
    if ((*it)->device == res) {
      it = c->sel_queries.erase(it);
    } else {
      ++it;
    }
  }
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
  DataSource* source = new DataSource{c, client, ds, {}};
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

static Positioner* positioner_of(wl_resource* r) {
  return r != nullptr && wl_resource_instance_of(r, &xdg_positioner_interface,
                                                 &positioner_impl)
             ? static_cast<Positioner*>(wl_resource_get_user_data(r))
             : nullptr;
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
  *out_x = x;
  *out_y = y;
}

static void send_toplevel_configure(OasisCompositor* c, Surface* s) {
  wl_array states;
  wl_array_init(&states);
  if (s->cfg_active) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_ACTIVATED;
  }
  if (s->cfg_max) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_MAXIMIZED;
  }
  if (s->cfg_fs) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_FULLSCREEN;
  }
  if (s->cfg_resizing) {
    *static_cast<uint32_t*>(wl_array_add(&states, sizeof(uint32_t))) =
        XDG_TOPLEVEL_STATE_RESIZING;
  }
  xdg_toplevel_send_configure(s->role_res, std::max(s->cfg_w, 0),
                              std::max(s->cfg_h, 0), &states);
  wl_array_release(&states);
  uint32_t ser = wl_display_next_serial(c->display);
  s->pending_serials.insert(ser);
  xdg_surface_send_configure(s->xdg_surface, ser);
}

static gboolean config_flush_idle(gpointer data) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  c->config_flush = 0;
  for (Surface* s : c->surfaces) {
    if (!s->cfg_pending) continue;
    s->cfg_pending = false;
    if (s->role_res != nullptr && s->xdg_surface != nullptr) {
      send_toplevel_configure(c, s);
    }
  }
  comp_flush(c);
  return G_SOURCE_REMOVE;
}

static void toplevel_configure(OasisCompositor* c,
                               Surface* s,
                               int w,
                               int h,
                               bool maximized,
                               bool active,
                               bool fullscreen,
                               bool resizing) {
  if (s->role_res == nullptr || s->xdg_surface == nullptr) return;
  s->cfg_w = w;
  s->cfg_h = h;
  s->cfg_max = maximized;
  s->cfg_fs = fullscreen;
  s->cfg_resizing = resizing;
  s->cfg_active = active;
  s->cfg_pending = true;
  if (c->config_flush == 0) {
    c->config_flush = g_idle_add(config_flush_idle, c);
  }
}

static void xdg_surface_destroy_req(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr && s->role != SURFACE_NONE) {
    wl_resource_post_error(res, XDG_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT,
                           "xdg_surface destroyed with a live role object");
    return;
  }
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
  fl_value_set_string_take(
      m, "parent",
      fl_value_new_int(s->tl_parent != nullptr ? s->tl_parent->public_id
                                               : -1));
  send_event(c, m);
}

static void toplevel_created(OasisCompositor* c,
                             wl_client* client,
                             wl_resource* xdg_res,
                             uint32_t id) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(xdg_res));
  if (s != nullptr && s->role != SURFACE_NONE) {
    wl_resource_post_error(xdg_res, XDG_WM_BASE_ERROR_ROLE,
                           "surface already has a role");
    return;
  }
  wl_resource* tl = wl_resource_create(client, &xdg_toplevel_interface,
                                       wl_resource_get_version(xdg_res), id);
  extern const struct xdg_toplevel_interface toplevel_impl;
  wl_resource_set_implementation(tl, &toplevel_impl, s,
                                 role_res_destroyed);
  if (s == nullptr) return;
  s->role_res = tl;
  s->role = SURFACE_TOPLEVEL;
  s->public_id = c->next_id++;
  c->by_id[s->public_id] = s;
}

static Surface* xdg_surface_of(wl_resource* r);

static void popup_created(OasisCompositor* c,
                          wl_client* client,
                          wl_resource* xdg_res,
                          uint32_t id,
                          wl_resource* parent_res,
                          wl_resource* pos_res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(xdg_res));
  if (s != nullptr && s->role != SURFACE_NONE) {
    wl_resource_post_error(xdg_res, XDG_WM_BASE_ERROR_ROLE,
                           "surface already has a role");
    return;
  }
  Positioner* p =
      pos_res != nullptr ? positioner_of(pos_res) : nullptr;
  if (pos_res != nullptr && p == nullptr) {
    wl_resource_post_error(xdg_res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid xdg_positioner object");
    return;
  }
  Surface* parent =
      parent_res != nullptr ? xdg_surface_of(parent_res) : nullptr;
  if (parent_res != nullptr && parent == nullptr) {
    wl_resource_post_error(xdg_res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid xdg_surface parent object");
    return;
  }
  wl_resource* pop = wl_resource_create(client, &xdg_popup_interface,
                                        wl_resource_get_version(xdg_res), id);
  extern const struct xdg_popup_interface popup_impl;
  wl_resource_set_implementation(pop, &popup_impl, s, role_res_destroyed);
  if (s == nullptr) return;
  s->role_res = pop;
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
  s->public_id = c->next_id++;
  c->by_id[s->public_id] = s;
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
                                            int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->pending_geo_x = x;
  s->pending_geo_y = y;
  s->pending_geo_w = w;
  s->pending_geo_h = h;
  s->pending_geo_set = true;
}

static void xdg_surface_ack_configure(wl_client* client,
                                      wl_resource* res,
                                      uint32_t serial) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr || s->pending_serials.erase(serial) == 0) return;
  s->acked_serial = serial;
  FlValue* m = new_event("configureAcked");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "serial", fl_value_new_int(serial));
  send_event(s->comp, m);
}

static const struct xdg_surface_interface xdg_surface_impl = {
    xdg_surface_destroy_req, xdg_surface_get_toplevel,
    xdg_surface_get_popup,    xdg_surface_set_window_geometry,
    xdg_surface_ack_configure};

static Surface* xdg_surface_of(wl_resource* r) {
  return r != nullptr && wl_resource_instance_of(r, &xdg_surface_interface,
                                                 &xdg_surface_impl)
             ? static_cast<Surface*>(wl_resource_get_user_data(r))
             : nullptr;
}

static void toplevel_destroy(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr) {
    s->role = SURFACE_NONE;
    if (s->role_res == res) s->role_res = nullptr;
    if (s->announced == SURFACE_TOPLEVEL) {
      emit_closed(s->comp, s);
      s->announced = SURFACE_NONE;
    }
  }
  wl_resource_destroy(res);
}

static void toplevel_set_parent(wl_client* client,
                                wl_resource* res,
                                wl_resource* parent) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->tl_parent =
      parent != nullptr &&
              wl_resource_instance_of(parent, &xdg_toplevel_interface,
                                      &toplevel_impl)
          ? static_cast<Surface*>(wl_resource_get_user_data(parent))
          : nullptr;
  FlValue* m = new_event("toplevelParent");
  ev_id(m, s->public_id);
  fl_value_set_string_take(
      m, "parent",
      fl_value_new_int(s->tl_parent != nullptr ? s->tl_parent->public_id
                                               : -1));
  send_event(s->comp, m);
}

static void toplevel_set_title(wl_client* client,
                               wl_resource* res,
                               const char* title) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
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
  if (s == nullptr) return;
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
                                      int32_t y) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("windowMenu");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "x", fl_value_new_int(x));
  fl_value_set_string_take(m, "y", fl_value_new_int(y));
  send_event(s->comp, m);
}

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
  if (s == nullptr) return;
  emit_simple(s, "move");
}

static void toplevel_resize(wl_client* client,
                            wl_resource* res,
                            wl_resource* seat,
                            uint32_t serial,
                            uint32_t edges) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("resize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "edges", fl_value_new_int(edges));
  send_event(s->comp, m);
}

static void toplevel_set_max_size(wl_client* client,
                                  wl_resource* res,
                                  int32_t w,
                                  int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->max_w = w;
  s->max_h = h;
  FlValue* m = new_event("maxSize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "w", fl_value_new_int(w));
  fl_value_set_string_take(m, "h", fl_value_new_int(h));
  send_event(s->comp, m);
}

static void toplevel_set_min_size(wl_client* client,
                                  wl_resource* res,
                                  int32_t w,
                                  int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->min_w = w;
  s->min_h = h;
  FlValue* m = new_event("minSize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "w", fl_value_new_int(w));
  fl_value_set_string_take(m, "h", fl_value_new_int(h));
  send_event(s->comp, m);
}

static void toplevel_set_maximized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("maximize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(TRUE));
  send_event(s->comp, m);
}

static void toplevel_unset_maximized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("maximize");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(FALSE));
  send_event(s->comp, m);
}

static void toplevel_set_fullscreen(wl_client* client,
                                    wl_resource* res,
                                    wl_resource* output) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("fullscreen");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(TRUE));
  send_event(s->comp, m);
}

static void toplevel_unset_fullscreen(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  FlValue* m = new_event("fullscreen");
  ev_id(m, s->public_id);
  fl_value_set_string_take(m, "on", fl_value_new_bool(FALSE));
  send_event(s->comp, m);
}

static void toplevel_set_minimized(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
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
  if (s != nullptr) {
    s->role = SURFACE_NONE;
    if (s->role_res == res) s->role_res = nullptr;
    if (s->announced == SURFACE_POPUP) {
      emit_closed(s->comp, s);
      s->announced = SURFACE_NONE;
    }
  }
  wl_resource_destroy(res);
}

static void popup_grab(wl_client* client,
                       wl_resource* res,
                       wl_resource* seat,
                       uint32_t serial) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->grab_serial = serial;
  set_kb_focus(s->comp, s);
}

static void popup_reposition(wl_client* client,
                             wl_resource* res,
                             wl_resource* pos_res,
                             uint32_t token) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr || s->xdg_surface == nullptr) return;
  Positioner* p = positioner_of(pos_res);
  if (p == nullptr) return;
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
  Surface* s = surface_of(surface_res);
  if (s == nullptr) {
    wl_resource_post_error(res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid wl_surface object");
    return;
  }
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
                         uint32_t serial) {
  WmBase* b = static_cast<WmBase*>(wl_resource_get_user_data(res));
  b->missed = 0;
}

static void wm_base_res_destroyed(wl_resource* res) {
  WmBase* b = static_cast<WmBase*>(wl_resource_get_user_data(res));
  auto& list = b->comp->wm_bases;
  list.erase(std::remove(list.begin(), list.end(), b), list.end());
  delete b;
}

static gboolean ping_tick(gpointer data) {
  auto* c = static_cast<OasisCompositor*>(data);
  std::vector<wl_client*> dead;
  for (WmBase* b : c->wm_bases) {
    if (++b->missed >= 3) {
      if (std::find(dead.begin(), dead.end(), b->client) == dead.end()) {
        dead.push_back(b->client);
      }
      continue;
    }
    xdg_wm_base_send_ping(b->res, wl_display_next_serial(c->display));
  }
  comp_flush(c);
  for (wl_client* client : dead) {
    wl_client_destroy(client);
  }
  return G_SOURCE_CONTINUE;
}

static const struct xdg_wm_base_interface wm_base_impl = {
    wm_base_destroy, wm_base_create_positioner, wm_base_get_xdg_surface,
    wm_base_pong};

// wp_viewporter / wp_fractional_scale_v1

static void viewport_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void viewport_set_source(wl_client* client,
                                wl_resource* res,
                                wl_fixed_t x,
                                wl_fixed_t y,
                                wl_fixed_t w,
                                wl_fixed_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->pending_vp_sx = wl_fixed_to_double(x);
  s->pending_vp_sy = wl_fixed_to_double(y);
  s->pending_vp_sw = wl_fixed_to_double(w);
  s->pending_vp_sh = wl_fixed_to_double(h);
}

static void viewport_set_destination(wl_client* client,
                                     wl_resource* res,
                                     int32_t w,
                                     int32_t h) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->pending_vp_w = w;
  s->pending_vp_h = h;
}

static const struct wp_viewport_interface viewport_impl = {
    viewport_destroy, viewport_set_source, viewport_set_destination};

static void viewport_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  auto& v = s->viewports;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
}

static void viewporter_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void viewporter_get_viewport(wl_client* client,
                                    wl_resource* res,
                                    uint32_t id,
                                    wl_resource* surface_res) {
  Surface* s = surface_of(surface_res);
  if (s == nullptr) {
    wl_resource_post_error(res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid wl_surface object");
    return;
  }
  wl_resource* vp = wl_resource_create(client, &wp_viewport_interface,
                                       wl_resource_get_version(res), id);
  s->viewports.push_back(vp);
  wl_resource_set_implementation(vp, &viewport_impl, s,
                                 viewport_res_destroyed);
}

static const struct wp_viewporter_interface viewporter_impl = {
    viewporter_destroy, viewporter_get_viewport};

static void fractional_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void fractional_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  auto& v = s->fractional_scales;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
}

static const struct wp_fractional_scale_v1_interface fractional_impl = {
    fractional_destroy};

static void fs_manager_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void fs_manager_get_fractional_scale(wl_client* client,
                                            wl_resource* res,
                                            uint32_t id,
                                            wl_resource* surface_res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  Surface* s = surface_of(surface_res);
  if (s == nullptr) {
    wl_resource_post_error(res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid wl_surface object");
    return;
  }
  wl_resource* fs =
      wl_resource_create(client, &wp_fractional_scale_v1_interface,
                         wl_resource_get_version(res), id);
  s->fractional_scales.push_back(fs);
  wl_resource_set_implementation(fs, &fractional_impl, s,
                                 fractional_res_destroyed);
  wp_fractional_scale_v1_send_preferred_scale(
      fs, static_cast<uint32_t>(c->out_scale) * 120);
}

static const struct wp_fractional_scale_manager_v1_interface
    fs_manager_impl = {fs_manager_destroy,
                       fs_manager_get_fractional_scale};

static void bind_viewporter(wl_client* client,
                            void* data,
                            uint32_t ver,
                            uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &wp_viewporter_interface, ver, id);
  wl_resource_set_implementation(res, &viewporter_impl, data, nullptr);
}

static void bind_fs_manager(wl_client* client,
                            void* data,
                            uint32_t ver,
                            uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &wp_fractional_scale_manager_v1_interface, ver, id);
  wl_resource_set_implementation(res, &fs_manager_impl, data, nullptr);
}

// zwp_idle_inhibit_v1

static void emit_idle_inhibit(Surface* s) {
  FlValue* m = new_event("idleInhibit");
  ev_id(m, s->public_id);
  fl_value_set_string_take(
      m, "on", fl_value_new_bool(!s->idle_inhibitors.empty()));
  send_event(s->comp, m);
}

static void inhibitor_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void inhibitor_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  auto& v = s->idle_inhibitors;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
  if (v.empty() && s->announced != SURFACE_NONE) emit_idle_inhibit(s);
}

static const struct zwp_idle_inhibitor_v1_interface inhibitor_impl = {
    inhibitor_destroy};

static void inhibit_manager_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void inhibit_manager_create(wl_client* client,
                                   wl_resource* res,
                                   uint32_t id,
                                   wl_resource* surface_res) {
  Surface* s = surface_of(surface_res);
  if (s == nullptr) {
    wl_resource_post_error(res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid wl_surface object");
    return;
  }
  wl_resource* inh =
      wl_resource_create(client, &zwp_idle_inhibitor_v1_interface,
                         wl_resource_get_version(res), id);
  s->idle_inhibitors.push_back(inh);
  wl_resource_set_implementation(inh, &inhibitor_impl, s,
                                 inhibitor_res_destroyed);
  if (s->idle_inhibitors.size() == 1 &&
      s->announced != SURFACE_NONE) {
    emit_idle_inhibit(s);
  }
}

static const struct zwp_idle_inhibit_manager_v1_interface
    inhibit_manager_impl = {inhibit_manager_destroy,
                            inhibit_manager_create};

static void bind_inhibit_manager(wl_client* client,
                                 void* data,
                                 uint32_t ver,
                                 uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &zwp_idle_inhibit_manager_v1_interface, ver, id);
  wl_resource_set_implementation(res, &inhibit_manager_impl, data,
                                 nullptr);
}

// wp_cursor_shape_v1

static void shape_device_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void shape_device_set_shape(wl_client* client,
                                   wl_resource* res,
                                   uint32_t serial,
                                   uint32_t shape) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  c->cursor_shape = shape;
  FlValue* m = new_event("cursorShape");
  fl_value_set_string_take(m, "shape", fl_value_new_int(shape));
  send_event(c, m);
}

static const struct wp_cursor_shape_device_v1_interface
    shape_device_impl = {shape_device_destroy, shape_device_set_shape};

static void shape_manager_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void shape_manager_get_pointer(wl_client* client,
                                      wl_resource* res,
                                      uint32_t id,
                                      wl_resource* pointer) {
  wl_resource* dev =
      wl_resource_create(client, &wp_cursor_shape_device_v1_interface,
                         wl_resource_get_version(res), id);
  wl_resource_set_implementation(dev, &shape_device_impl,
                                 wl_resource_get_user_data(res), nullptr);
}

static void shape_manager_get_tablet_tool(wl_client* client,
                                          wl_resource* res,
                                          uint32_t id,
                                          wl_resource* tablet_tool) {
  wl_resource* dev =
      wl_resource_create(client, &wp_cursor_shape_device_v1_interface,
                         wl_resource_get_version(res), id);
  wl_resource_set_implementation(dev, &shape_device_impl,
                                 wl_resource_get_user_data(res), nullptr);
}

static const struct wp_cursor_shape_manager_v1_interface
    shape_manager_impl = {shape_manager_destroy,
                          shape_manager_get_pointer,
                          shape_manager_get_tablet_tool};

static void bind_shape_manager(wl_client* client,
                               void* data,
                               uint32_t ver,
                               uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &wp_cursor_shape_manager_v1_interface, ver, id);
  wl_resource_set_implementation(res, &shape_manager_impl, data, nullptr);
}

// wp_presentation

static void presentation_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void feedback_res_destroyed(wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  auto& v = s->presentation_feedbacks;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
}

static void presentation_feedback(wl_client* client,
                                  wl_resource* res,
                                  wl_resource* surface_res,
                                  uint32_t callback) {
  Surface* s = surface_of(surface_res);
  if (s == nullptr) {
    wl_resource_post_error(res, WL_DISPLAY_ERROR_INVALID_OBJECT,
                           "invalid wl_surface object");
    return;
  }
  wl_resource* fb =
      wl_resource_create(client, &wp_presentation_feedback_interface,
                         wl_resource_get_version(res), callback);
  s->presentation_feedbacks.push_back(fb);
  wl_resource_set_implementation(fb, nullptr, s,
                                 feedback_res_destroyed);
}

static const struct wp_presentation_interface presentation_impl = {
    presentation_destroy, presentation_feedback};

static void send_presented(Surface* s) {
  if (s->presentation_feedbacks.empty()) return;
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  for (wl_resource* fb : s->presentation_feedbacks) {
    wp_presentation_feedback_send_presented(
        fb, static_cast<uint32_t>(ts.tv_sec >> 32),
        static_cast<uint32_t>(ts.tv_sec & 0xffffffffu),
        static_cast<uint32_t>(ts.tv_nsec), 16666666, 0, 0, 0);
    wl_resource_destroy(fb);
  }
  s->presentation_feedbacks.clear();
}

static void bind_presentation(wl_client* client,
                              void* data,
                              uint32_t ver,
                              uint32_t id) {
  wl_resource* res =
      wl_resource_create(client, &wp_presentation_interface, ver, id);
  wl_resource_set_implementation(res, &presentation_impl, data, nullptr);
  wp_presentation_send_clock_id(res, CLOCK_MONOTONIC);
}

// xdg_activation_v1

struct ActivationToken {
  OasisCompositor* c;
  wl_client* client;
  Surface* surface;
  uint32_t serial;
  bool has_serial;
};

static void activation_token_res_destroyed(wl_resource* res) {
  delete static_cast<ActivationToken*>(wl_resource_get_user_data(res));
}

static void activation_token_destroy(wl_client* client,
                                     wl_resource* res) {
  wl_resource_destroy(res);
}

static void activation_token_set_serial(wl_client* client,
                                        wl_resource* res,
                                        uint32_t serial,
                                        wl_resource* seat) {
  ActivationToken* t =
      static_cast<ActivationToken*>(wl_resource_get_user_data(res));
  if (seat == nullptr ||
      !wl_resource_instance_of(seat, &wl_seat_interface, &seat_impl) ||
      wl_resource_get_client(seat) != client) {
    return;
  }
  t->serial = serial;
  t->has_serial = true;
}

static void activation_token_set_app_id(wl_client* client,
                                        wl_resource* res,
                                        const char* app_id) {}

static void activation_token_set_surface(wl_client* client,
                                         wl_resource* res,
                                         wl_resource* surface) {
  ActivationToken* t =
      static_cast<ActivationToken*>(wl_resource_get_user_data(res));
  Surface* s = surface_of(surface);
  if (s == nullptr || s->client != client) return;
  t->surface = s;
}

static void activation_token_commit(wl_client* client,
                                    wl_resource* res) {
  ActivationToken* t =
      static_cast<ActivationToken*>(wl_resource_get_user_data(res));
  if (!t->has_serial && t->surface == nullptr) {
    wl_resource_destroy(res);
    return;
  }
  char token[17];
  snprintf(token, sizeof(token), "%08x%08x", (unsigned)rand(),
           (unsigned)now_ms());
  t->c->activation_tokens.insert(token);
  xdg_activation_token_v1_send_done(res, token);
  wl_resource_destroy(res);
}

static const struct xdg_activation_token_v1_interface
    activation_token_impl = {
        activation_token_set_serial,
        activation_token_set_app_id,
        activation_token_set_surface,
        activation_token_commit,
        activation_token_destroy};

static void activation_manager_destroy(wl_client* client,
                                       wl_resource* res) {
  wl_resource_destroy(res);
}

static void activation_manager_get_token(wl_client* client,
                                         wl_resource* res,
                                         uint32_t id) {
  wl_resource* tok =
      wl_resource_create(client, &xdg_activation_token_v1_interface,
                         wl_resource_get_version(res), id);
  ActivationToken* t = new ActivationToken{
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res)),
      client,
      nullptr,
      0,
      false};
  wl_resource_set_implementation(tok, &activation_token_impl, t,
                                 activation_token_res_destroyed);
}

static void activation_manager_activate(wl_client* client,
                                        wl_resource* res,
                                        const char* token,
                                        wl_resource* surface_res) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  Surface* s = surface_of(surface_res);
  if (s == nullptr || s->announced != SURFACE_TOPLEVEL) return;
  if (s->client != client) return;
  if (c->activation_tokens.erase(token) == 0) return;
  FlValue* m = new_event("activate");
  ev_id(m, s->public_id);
  send_event(c, m);
}

static const struct xdg_activation_v1_interface activation_manager_impl =
    {activation_manager_destroy, activation_manager_get_token,
     activation_manager_activate};

static void bind_activation_manager(wl_client* client,
                                    void* data,
                                    uint32_t ver,
                                    uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &xdg_activation_v1_interface, ver, id);
  wl_resource_set_implementation(res, &activation_manager_impl, data,
                                 nullptr);
}

// zwp_text_input_v3

static void text_input_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void text_input_res_destroyed(wl_resource* res) {
  TextInput* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  auto& v = ti->client_comp->text_inputs;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
  delete ti;
}

static void text_input_enable(wl_client* client, wl_resource* res) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->enabled = true;
}

static void text_input_disable(wl_client* client, wl_resource* res) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->enabled = false;
}

static void text_input_set_surrounding(wl_client* client,
                                       wl_resource* res,
                                       const char* text,
                                       int32_t cursor,
                                       int32_t anchor) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->surrounding = text != nullptr ? text : "";
  ti->cursor_pos = cursor;
  ti->anchor = anchor;
}

static void text_input_set_cause(wl_client* client,
                                 wl_resource* res,
                                 uint32_t cause) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->cause = cause;
}

static void text_input_set_content_type(wl_client* client,
                                        wl_resource* res,
                                        uint32_t hint,
                                        uint32_t purpose) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->hint = hint;
  ti->purpose = purpose;
}

static void text_input_set_rect(wl_client* client,
                                wl_resource* res,
                                int32_t x,
                                int32_t y,
                                int32_t w,
                                int32_t h) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  ti->rect = {x, y, w, h};
}

static void text_input_commit(wl_client* client, wl_resource* res) {
  auto* ti = static_cast<TextInput*>(wl_resource_get_user_data(res));
  zwp_text_input_v3_send_done(res, ti->serial++);
}

static const struct zwp_text_input_v3_interface text_input_impl = {
    text_input_destroy,
    text_input_enable,
    text_input_disable,
    text_input_set_surrounding,
    text_input_set_cause,
    text_input_set_content_type,
    text_input_set_rect,
    text_input_commit};

static void text_input_manager_destroy(wl_client* client,
                                       wl_resource* res) {
  wl_resource_destroy(res);
}

static void text_input_manager_get(wl_client* client,
                                   wl_resource* res,
                                   uint32_t id,
                                   wl_resource* seat) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* ti_res =
      wl_resource_create(client, &zwp_text_input_v3_interface,
                         wl_resource_get_version(res), id);
  auto* ti = new TextInput{ti_res, client};
  ti->client_comp = c;
  c->text_inputs.push_back(ti_res);
  wl_resource_set_implementation(ti_res, &text_input_impl, ti,
                                 text_input_res_destroyed);
  sync_text_input_focus(c);
}

static const struct zwp_text_input_manager_v3_interface
    text_input_manager_impl = {text_input_manager_destroy,
                               text_input_manager_get};

static void bind_text_input_manager(wl_client* client,
                                    void* data,
                                    uint32_t ver,
                                    uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &zwp_text_input_manager_v3_interface, ver, id);
  wl_resource_set_implementation(res, &text_input_manager_impl, data,
                                 nullptr);
}

static void sync_text_input_focus(OasisCompositor* c) {
  wl_client* focus_client =
      c->kb_focus != nullptr ? c->kb_focus->client : nullptr;
  for (wl_resource* res : c->text_inputs) {
    TextInput* ti =
        static_cast<TextInput*>(wl_resource_get_user_data(res));
    Surface* want = ti->client == focus_client ? c->kb_focus : nullptr;
    if (ti->entered == want) continue;
    if (ti->entered != nullptr && ti->entered->wl_surface != nullptr) {
      zwp_text_input_v3_send_leave(res, ti->entered->wl_surface);
    }
    ti->entered = nullptr;
    if (want != nullptr && want->wl_surface != nullptr) {
      zwp_text_input_v3_send_enter(res, want->wl_surface);
      ti->entered = want;
    }
  }
}

// zwp_primary_selection_v1

static void primary_source_offer(wl_client* client,
                                 wl_resource* res,
                                 const char* mime) {
  auto* ps =
      static_cast<PrimarySource*>(wl_resource_get_user_data(res));
  if (mime != nullptr) ps->mimes.push_back(mime);
}

static void primary_source_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void primary_source_res_destroyed(wl_resource* res) {
  auto* ps =
      static_cast<PrimarySource*>(wl_resource_get_user_data(res));
  if (ps->comp->primary_source == res) {
    ps->comp->primary_source = nullptr;
    ps->comp->primary_mimes.clear();
  }
  delete ps;
}

static const struct zwp_primary_selection_source_v1_interface
    primary_source_impl = {primary_source_offer,
                           primary_source_destroy};

static void primary_offer_receive(wl_client* client,
                                  wl_resource* res,
                                  const char* mime,
                                  int32_t fd) {
  auto* data = static_cast<OasisCompositor*>(
      wl_resource_get_user_data(res));
  if (data->primary_source != nullptr) {
    zwp_primary_selection_source_v1_send_send(
        data->primary_source, mime != nullptr ? mime : "", fd);
  }
  close(fd);
}

static void primary_offer_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct zwp_primary_selection_offer_v1_interface
    primary_offer_impl = {primary_offer_receive,
                          primary_offer_destroy};

static void primary_device_res_destroyed(wl_resource* res) {
  auto* c = static_cast<OasisCompositor*>(
      wl_resource_get_user_data(res));
  auto& v = c->primary_devices;
  v.erase(std::remove(v.begin(), v.end(), res), v.end());
}

static void send_primary_selection(OasisCompositor* c,
                                   wl_resource* device) {
  if (c->primary_source == nullptr || c->primary_mimes.empty()) {
    zwp_primary_selection_device_v1_send_selection(device, nullptr);
    return;
  }
  wl_resource* offer = wl_resource_create(
      wl_resource_get_client(device),
      &zwp_primary_selection_offer_v1_interface,
      wl_resource_get_version(device), 0);
  wl_resource_set_implementation(offer, &primary_offer_impl, c,
                                 nullptr);
  zwp_primary_selection_device_v1_send_data_offer(device, offer);
  for (const auto& mime : c->primary_mimes) {
    zwp_primary_selection_offer_v1_send_offer(offer, mime.c_str());
  }
  zwp_primary_selection_device_v1_send_selection(device, offer);
}

static void primary_device_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void primary_device_set_selection(wl_client* client,
                                         wl_resource* res,
                                         wl_resource* source,
                                         uint32_t serial) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  if (serial != c->kb_enter_serial) return;
  c->primary_source = source;
  c->primary_mimes.clear();
  if (source != nullptr) {
    PrimarySource* ps =
        wl_resource_instance_of(
            source, &zwp_primary_selection_source_v1_interface,
            &primary_source_impl)
            ? static_cast<PrimarySource*>(
                  wl_resource_get_user_data(source))
            : nullptr;
    if (ps == nullptr) c->primary_source = nullptr;
    c->primary_mimes = ps != nullptr ? ps->mimes
                                     : std::vector<std::string>{};
  }
  for (wl_resource* dev : c->primary_devices) {
    send_primary_selection(c, dev);
  }
}

static const struct zwp_primary_selection_device_v1_interface
    primary_device_impl = {primary_device_set_selection,
                           primary_device_destroy};

static void primary_manager_destroy(wl_client* client,
                                    wl_resource* res) {
  wl_resource_destroy(res);
}

static void primary_manager_create_source(wl_client* client,
                                          wl_resource* res,
                                          uint32_t id) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* source = wl_resource_create(
      client, &zwp_primary_selection_source_v1_interface,
      wl_resource_get_version(res), id);
  wl_resource_set_implementation(source, &primary_source_impl,
                                 new PrimarySource{c, source, {}},
                                 primary_source_res_destroyed);
}

static void primary_manager_get_device(wl_client* client,
                                       wl_resource* res,
                                       uint32_t id,
                                       wl_resource* seat) {
  OasisCompositor* c =
      static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* dev = wl_resource_create(
      client, &zwp_primary_selection_device_v1_interface,
      wl_resource_get_version(res), id);
  c->primary_devices.push_back(dev);
  wl_resource_set_implementation(dev, &primary_device_impl, c,
                                 primary_device_res_destroyed);
}

static const struct zwp_primary_selection_device_manager_v1_interface
    primary_manager_impl = {primary_manager_create_source,
                            primary_manager_get_device,
                            primary_manager_destroy};

static void bind_primary_manager(wl_client* client,
                                 void* data,
                                 uint32_t ver,
                                 uint32_t id) {
  wl_resource* res = wl_resource_create(
      client, &zwp_primary_selection_device_manager_v1_interface, ver,
      id);
  wl_resource_set_implementation(res, &primary_manager_impl, data,
                                 nullptr);
}

// xdg decoration

static void deco_destroy(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s != nullptr && s->deco_res == res) s->deco_res = nullptr;
  wl_resource_destroy(res);
}

static void deco_set_mode(wl_client* client,
                          wl_resource* res,
                          uint32_t mode) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  if (mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ||
      mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE) {
    s->deco_mode = (int)mode;
  }
  zxdg_toplevel_decoration_v1_send_configure(
      res, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static void deco_unset_mode(wl_client* client, wl_resource* res) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(res));
  if (s == nullptr) return;
  s->deco_mode = 0;
  zxdg_toplevel_decoration_v1_send_configure(
      res, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static const struct zxdg_toplevel_decoration_v1_interface deco_impl = {
    deco_destroy, deco_set_mode, deco_unset_mode};

static void deco_manager_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void deco_manager_get_decoration(wl_client* client,
                                        wl_resource* res,
                                        uint32_t id,
                                        wl_resource* toplevel) {
  Surface* s = static_cast<Surface*>(wl_resource_get_user_data(toplevel));
  if (s == nullptr) return;
  if (s->deco_res != nullptr) {
    wl_resource_post_error(
        res, ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ALREADY_CONSTRUCTED,
        "toplevel already has a decoration object");
    return;
  }
  wl_resource* deco =
      wl_resource_create(client, &zxdg_toplevel_decoration_v1_interface,
                         wl_resource_get_version(res), id);
  wl_resource_set_implementation(deco, &deco_impl, s, nullptr);
  s->deco_res = deco;
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
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  wl_resource* res =
      wl_resource_create(client, &wl_output_interface, ver, id);
  c->outputs.push_back(res);
  wl_resource_set_implementation(res, &output_impl, c,
                                 output_res_destroyed);
  send_output_props(c, res);
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
  auto* b = new WmBase{static_cast<OasisCompositor*>(data), client, res, 0};
  static_cast<OasisCompositor*>(data)->wm_bases.push_back(b);
  wl_resource_set_implementation(res, &wm_base_impl, b,
                                 wm_base_res_destroyed);
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

// zwp_linux_dmabuf_v1

struct DmabufParams {
  OasisCompositor* comp = nullptr;
  wl_resource* res = nullptr;
  DmabufBuf pending;
};

static void dmabuf_params_cleanup(DmabufParams* p) {
  for (int i = 0; i < 4; i++) {
    if (p->pending.fds[i] >= 0) close(p->pending.fds[i]);
  }
  delete p;
}

static void dmabuf_params_res_destroyed(wl_resource* res) {
  dmabuf_params_cleanup(
      static_cast<DmabufParams*>(wl_resource_get_user_data(res)));
}

static void dmabuf_buf_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct wl_buffer_interface dmabuf_buf_impl = {
    dmabuf_buf_destroy};

static bool is_dmabuf_buffer(wl_resource* b) {
  return wl_resource_instance_of(b, &wl_buffer_interface,
                                 &dmabuf_buf_impl) != 0;
}

static void dmabuf_buf_res_destroyed(wl_resource* res) {
  DmabufBuf* b = static_cast<DmabufBuf*>(wl_resource_get_user_data(res));
  b->res = nullptr;
  b->destroyed = true;
  oasis_dmabuf_unref(b);
}

static wl_resource* dmabuf_make_buffer(DmabufParams* p,
                                       uint32_t id,
                                       int w,
                                       int h,
                                       uint32_t format,
                                       uint32_t flags) {
  DmabufBuf* b = new DmabufBuf();
  b->comp = p->comp;
  b->w = w;
  b->h = h;
  b->format = format;
  b->nplanes = p->pending.nplanes;
  for (int i = 0; i < 4; i++) {
    b->fds[i] = p->pending.fds[i];
    b->offsets[i] = p->pending.offsets[i];
    b->strides[i] = p->pending.strides[i];
    b->mods[i] = p->pending.mods[i];
    p->pending.fds[i] = -1;
  }
  wl_resource* res = wl_resource_create(
      wl_resource_get_client(p->res), &wl_buffer_interface, 1, id);
  b->res = res;
  wl_resource_set_implementation(res, &dmabuf_buf_impl, b,
                                 dmabuf_buf_res_destroyed);
  p->comp->dmabufs.push_back(b);
  return res;
}

static void dmabuf_params_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void dmabuf_params_add(wl_client* client,
                              wl_resource* res,
                              int32_t fd,
                              uint32_t plane,
                              uint32_t offset,
                              uint32_t stride,
                              uint32_t mod_hi,
                              uint32_t mod_lo) {
  DmabufParams* p =
      static_cast<DmabufParams*>(wl_resource_get_user_data(res));
  if (plane >= 4 || p->pending.fds[plane] >= 0) {
    wl_resource_post_error(res, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
                           "plane already added");
    return;
  }
  int dupfd = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  if (dupfd < 0) {
    wl_resource_post_error(res, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_FORMAT,
                           "fd dup failed");
    return;
  }
  p->pending.fds[plane] = dupfd;
  p->pending.offsets[plane] = offset;
  p->pending.strides[plane] = stride;
  p->pending.mods[plane] =
      (static_cast<uint64_t>(mod_hi) << 32) | mod_lo;
  if (static_cast<int>(plane) >= p->pending.nplanes) {
    p->pending.nplanes = plane + 1;
  }
}

static bool dmabuf_params_ready(DmabufParams* p, int w, int h) {
  return w > 0 && h > 0 && p->pending.nplanes > 0 &&
         p->pending.fds[0] >= 0;
}

static void dmabuf_params_create(wl_client* client,
                                 wl_resource* res,
                                 int32_t w,
                                 int32_t h,
                                 uint32_t format,
                                 uint32_t flags) {
  DmabufParams* p =
      static_cast<DmabufParams*>(wl_resource_get_user_data(res));
  if (!dmabuf_params_ready(p, w, h)) {
    zwp_linux_buffer_params_v1_send_failed(res);
    return;
  }
  wl_resource* b = dmabuf_make_buffer(p, 0, w, h, format, flags);
  zwp_linux_buffer_params_v1_send_created(res, b);
}

static void dmabuf_params_create_immed(wl_client* client,
                                       wl_resource* res,
                                       uint32_t buffer_id,
                                       int32_t w,
                                       int32_t h,
                                       uint32_t format,
                                       uint32_t flags) {
  DmabufParams* p =
      static_cast<DmabufParams*>(wl_resource_get_user_data(res));
  if (!dmabuf_params_ready(p, w, h)) {
    wl_resource_post_error(res, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE,
                           "incomplete dmabuf params");
    return;
  }
  dmabuf_make_buffer(p, buffer_id, w, h, format, flags);
}

#ifdef ZWP_LINUX_BUFFER_PARAMS_V1_SET_SAMPLING_DEVICE_SINCE_VERSION
static void dmabuf_params_set_sampling(wl_client* client,
                                       wl_resource* res,
                                       wl_array* device_fd) {}
#endif

static const struct zwp_linux_buffer_params_v1_interface
    dmabuf_params_impl = {
        dmabuf_params_destroy,
        dmabuf_params_add,
        dmabuf_params_create,
        dmabuf_params_create_immed,
#ifdef ZWP_LINUX_BUFFER_PARAMS_V1_SET_SAMPLING_DEVICE_SINCE_VERSION
        dmabuf_params_set_sampling,
#endif
};

static void dmabuf_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static void dmabuf_create_params(wl_client* client,
                                 wl_resource* res,
                                 uint32_t params_id) {
  DmabufParams* p = new DmabufParams();
  p->comp = static_cast<OasisCompositor*>(wl_resource_get_user_data(res));
  wl_resource* pr = wl_resource_create(
      client, &zwp_linux_buffer_params_v1_interface,
      wl_resource_get_version(res), params_id);
  p->res = pr;
  wl_resource_set_implementation(pr, &dmabuf_params_impl, p,
                                 dmabuf_params_res_destroyed);
}

static void dmabuf_feedback_destroy(wl_client* client, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct zwp_linux_dmabuf_feedback_v1_interface
    dmabuf_feedback_impl = {dmabuf_feedback_destroy};

static const uint32_t dmabuf_fmts[] = {
    DRM_FORMAT_ARGB8888, DRM_FORMAT_XRGB8888,
    DRM_FORMAT_ABGR8888, DRM_FORMAT_XBGR8888,
    DRM_FORMAT_RGB565,
};

static dev_t dmabuf_render_dev() {
  for (int i = 128; i < 144; i++) {
    char path[32];
    snprintf(path, sizeof(path), "/dev/dri/renderD%d", i);
    struct stat st;
    if (stat(path, &st) == 0) return st.st_rdev;
  }
  for (int i = 0; i < 16; i++) {
    char path[32];
    snprintf(path, sizeof(path), "/dev/dri/card%d", i);
    struct stat st;
    if (stat(path, &st) == 0) return st.st_rdev;
  }
  return 0;
}

static void dmabuf_send_feedback(wl_resource* f) {
  int fd = memfd_create("oasis-dmabuf",
                        MFD_CLOEXEC | MFD_ALLOW_SEALING);
  if (fd < 0) return;
  wl_array indices;
  wl_array_init(&indices);
  size_t count = sizeof(dmabuf_fmts) / sizeof(dmabuf_fmts[0]);
  for (size_t i = 0; i < count; i++) {
    struct {
      uint32_t format;
      uint32_t pad;
      uint64_t modifier;
    } entry = {dmabuf_fmts[i], 0, 0};
    if (write(fd, &entry, sizeof(entry)) ==
        static_cast<ssize_t>(sizeof(entry))) {
      uint32_t idx = static_cast<uint32_t>(i);
      uint32_t* slot =
          static_cast<uint32_t*>(wl_array_add(&indices, sizeof(idx)));
      if (slot != nullptr) *slot = idx;
    }
  }
  zwp_linux_dmabuf_feedback_v1_send_format_table(
      f, fd, static_cast<uint32_t>(indices.size * 4));
  close(fd);
  dev_t dev = dmabuf_render_dev();
  wl_array da;
  wl_array_init(&da);
  void* slot = wl_array_add(&da, sizeof(dev));
  if (slot == nullptr) {
    wl_array_release(&da);
    wl_array_release(&indices);
    return;
  }
  memcpy(da.data, &dev, sizeof(dev));
  zwp_linux_dmabuf_feedback_v1_send_main_device(f, &da);
  zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(f, &da);
  zwp_linux_dmabuf_feedback_v1_send_tranche_flags(f, 0);
  zwp_linux_dmabuf_feedback_v1_send_tranche_formats(f, &indices);
  zwp_linux_dmabuf_feedback_v1_send_tranche_done(f);
  zwp_linux_dmabuf_feedback_v1_send_done(f);
  wl_array_release(&da);
  wl_array_release(&indices);
}

static void dmabuf_get_default_feedback(wl_client* client,
                                        wl_resource* res,
                                        uint32_t id) {
  wl_resource* f =
      wl_resource_create(client, &zwp_linux_dmabuf_feedback_v1_interface,
                         wl_resource_get_version(res), id);
  wl_resource_set_implementation(f, &dmabuf_feedback_impl, nullptr,
                                 nullptr);
  dmabuf_send_feedback(f);
}

static void dmabuf_get_surface_feedback(wl_client* client,
                                        wl_resource* res,
                                        uint32_t id,
                                        wl_resource* surface) {
  dmabuf_get_default_feedback(client, res, id);
}

static const struct zwp_linux_dmabuf_v1_interface dmabuf_impl = {
    dmabuf_destroy, dmabuf_create_params, dmabuf_get_default_feedback,
    dmabuf_get_surface_feedback};

static void bind_dmabuf(wl_client* client,
                        void* data,
                        uint32_t ver,
                        uint32_t id) {
  OasisCompositor* c = static_cast<OasisCompositor*>(data);
  wl_resource* res = wl_resource_create(
      client, &zwp_linux_dmabuf_v1_interface, ver < 4 ? ver : 4, id);
  wl_resource_set_implementation(res, &dmabuf_impl, c, nullptr);
  if (ver < 4) {
    for (uint32_t f : dmabuf_fmts) {
      zwp_linux_dmabuf_v1_send_format(res, f);
      if (ver >= 3) {
        zwp_linux_dmabuf_v1_send_modifier(res, f, 0, 0);
      }
    }
  }
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
  wl_global_create(c->display, &zwp_linux_dmabuf_v1_interface, 4, c,
                   bind_dmabuf);
  wl_global_create(c->display, &wp_viewporter_interface, 1, c,
                   bind_viewporter);
  wl_global_create(c->display,
                   &wp_fractional_scale_manager_v1_interface, 1, c,
                   bind_fs_manager);
  wl_global_create(c->display,
                   &zwp_idle_inhibit_manager_v1_interface, 1, c,
                   bind_inhibit_manager);
  wl_global_create(c->display,
                   &wp_cursor_shape_manager_v1_interface, 2, c,
                   bind_shape_manager);
  wl_global_create(c->display, &wp_presentation_interface, 1, c,
                   bind_presentation);
  wl_global_create(c->display, &xdg_activation_v1_interface, 1, c,
                   bind_activation_manager);
  wl_global_create(c->display,
                   &zwp_text_input_manager_v3_interface, 1, c,
                   bind_text_input_manager);
  wl_global_create(
      c->display, &zwp_primary_selection_device_manager_v1_interface,
      1, c, bind_primary_manager);
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
  c->ping_timer = g_timeout_add_seconds(5, ping_tick, c);
  return true;
}

// spawn

static void launch_reap(GPid pid, gint status, gpointer data) {
  g_spawn_close_pid(pid);
}

static void spawn_child(gchar** argv, gchar** env) {
  g_autoptr(GError) err = nullptr;
  GPid pid = 0;
  if (!g_spawn_async(g_get_home_dir(), argv, env,
                     static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH |
                                              G_SPAWN_DO_NOT_REAP_CHILD),
                     nullptr, nullptr, &pid, &err)) {
    g_warning("oasis: failed to launch %s: %s", argv[0],
              err != nullptr ? err->message : "unknown error");
    return;
  }
  g_child_watch_add(pid, launch_reap, nullptr);
}

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
  env = g_environ_unsetenv(env, "DISPLAY");
  env = g_environ_unsetenv(env, "XAUTHORITY");
  env = g_environ_setenv(env, "WAYLAND_DISPLAY", c->socket_name, TRUE);
  env = g_environ_setenv(env, "GDK_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "GTK_CSD", "0", TRUE);
  env = g_environ_setenv(env, "QT_QPA_PLATFORM", "wayland", TRUE);
  env = g_environ_setenv(env, "QT_WAYLAND_DISABLE_WINDOWDECORATION", "1",
                         TRUE);
  env = g_environ_setenv(env, "SDL_VIDEODRIVER", "wayland", TRUE);
  env = g_environ_setenv(env, "XDG_SESSION_TYPE", "wayland", TRUE);
  env = g_environ_setenv(env, "XDG_CURRENT_DESKTOP", "oasis", TRUE);
  env = g_environ_setenv(env, "XDG_SESSION_DESKTOP", "oasis", TRUE);
  env = g_environ_setenv(env, "MOZ_ENABLE_WAYLAND", "1", TRUE);
  env = g_environ_setenv(env, "WINIT_UNIX_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "CLUTTER_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "ECORE_EVAS_ENGINE", "wayland_shm", TRUE);
  env = g_environ_setenv(env, "ELM_ENGINE", "wayland_shm", TRUE);
  if (g_find_program_in_path("systemd-run") != nullptr) {
    g_autoptr(GPtrArray) scoped = g_ptr_array_new();
    g_ptr_array_add(scoped, const_cast<char*>("systemd-run"));
    g_ptr_array_add(scoped, const_cast<char*>("--user"));
    g_ptr_array_add(scoped, const_cast<char*>("--scope"));
    g_ptr_array_add(scoped, const_cast<char*>("--quiet"));
    g_ptr_array_add(scoped, const_cast<char*>("--collect"));
    g_ptr_array_add(scoped, const_cast<char*>("--"));
    for (guint i = 0; i + 1 < argv->len; i++) {
      g_ptr_array_add(scoped, argv->pdata[i]);
    }
    g_ptr_array_add(scoped, nullptr);
    spawn_child(reinterpret_cast<gchar**>(scoped->pdata), env);
    return;
  }
  spawn_child(reinterpret_cast<gchar**>(argv->pdata), env);
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
  int sig;
  guint source = 0;
};

static gboolean kill_check(gpointer data) {
  KillCheck* k = static_cast<KillCheck*>(data);
  auto it = k->comp->by_id.find(k->id);
  if (it != k->comp->by_id.end() && it->second->pid > 0) {
    kill(it->second->pid, k->sig);
    if (k->sig == SIGTERM) {
      k->sig = SIGKILL;
      k->source = g_timeout_add(2500, kill_check, k);
      return G_SOURCE_REMOVE;
    }
  }
  k->comp->kill_checks.erase(
      std::remove(k->comp->kill_checks.begin(),
                  k->comp->kill_checks.end(), k),
      k->comp->kill_checks.end());
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
                         arg_int(args, "maximized") != 0,
                         s == c->activated,
                         arg_int(args, "fullscreen") != 0,
                         arg_int(args, "resizing") != 0);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "close") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr) {
      if (s->role == SURFACE_TOPLEVEL && s->role_res != nullptr) {
        xdg_toplevel_send_close(s->role_res);
        comp_flush(c);
        KillCheck* k = new KillCheck{c, s->public_id, SIGTERM};
        k->source = g_timeout_add(5000, kill_check, k);
        c->kill_checks.push_back(k);
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
      if (s->role == SURFACE_TOPLEVEL && c->activated != s) {
        if (c->activated != nullptr &&
            c->activated->role == SURFACE_TOPLEVEL) {
          toplevel_configure(c, c->activated, c->activated->cfg_w,
                             c->activated->cfg_h, c->activated->cfg_max,
                             false, c->activated->cfg_fs,
                             c->activated->cfg_resizing);
        }
        toplevel_configure(c, s, s->cfg_w, s->cfg_h, s->cfg_max, true,
                           s->cfg_fs, s->cfg_resizing);
        c->activated = s;
      }
    } else {
      set_kb_focus(c, nullptr);
      if (c->activated != nullptr &&
          c->activated->role == SURFACE_TOPLEVEL) {
        toplevel_configure(c, c->activated, c->activated->cfg_w,
                           c->activated->cfg_h, c->activated->cfg_max,
                           false, c->activated->cfg_fs,
                           c->activated->cfg_resizing);
        c->activated = nullptr;
      }
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
    uint32_t state = (uint32_t)arg_int(args, "state");
    uint32_t button = (uint32_t)arg_int(args, "button");
    if (state == 1 && c->grab_buttons == 0) {
      c->grab_surface = c->ptr_focus;
    }
    Surface* target =
        c->grab_surface != nullptr ? c->grab_surface : c->ptr_focus;
    if (target != nullptr) {
      SeatRes* st = seat_for(c, target->client, false);
      if (st != nullptr && st->pointer != nullptr) {
        uint32_t ser = wl_display_next_serial(c->display);
        wl_pointer_send_button(st->pointer, ser, now_ms(), button, state);
        if (state == 1) c->last_button_serial = ser;
        if (wl_resource_get_version(st->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(st->pointer);
        }
      }
    }
    if (state == 1) {
      c->grab_buttons++;
    } else if (c->grab_buttons > 0 && --c->grab_buttons == 0) {
      c->grab_surface = nullptr;
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerAxis") == 0) {
    if (c->ptr_focus != nullptr) {
      SeatRes* st = seat_for(c, c->ptr_focus->client, false);
      if (st != nullptr && st->pointer != nullptr) {
        double dx = arg_double(args, "dx");
        double dy = arg_double(args, "dy");
        uint32_t src = (uint32_t)arg_int(args, "src");
        uint32_t discrete = (uint32_t)arg_int(args, "discrete");
        uint32_t t = now_ms();
        bool v5 = wl_resource_get_version(st->pointer) >=
                  WL_POINTER_AXIS_SOURCE_SINCE_VERSION;
        if (v5) {
          wl_pointer_send_axis_source(
              st->pointer, static_cast<wl_pointer_axis_source>(src));
        }
        if (dx != 0) {
          wl_pointer_send_axis(st->pointer, t,
                               WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                               wl_fixed_from_double(dx));
          if (v5 && discrete != 0) {
            wl_pointer_send_axis_discrete(
                st->pointer, WL_POINTER_AXIS_HORIZONTAL_SCROLL, discrete);
          }
        }
        if (dy != 0) {
          wl_pointer_send_axis(st->pointer, t,
                               WL_POINTER_AXIS_VERTICAL_SCROLL,
                               wl_fixed_from_double(dy));
          if (v5 && discrete != 0) {
            wl_pointer_send_axis_discrete(
                st->pointer, WL_POINTER_AXIS_VERTICAL_SCROLL, discrete);
          }
        }
        if (wl_resource_get_version(st->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(st->pointer);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerAxisStop") == 0) {
    if (c->ptr_focus != nullptr) {
      SeatRes* st = seat_for(c, c->ptr_focus->client, false);
      if (st != nullptr && st->pointer != nullptr &&
          wl_resource_get_version(st->pointer) >=
              WL_POINTER_AXIS_SOURCE_SINCE_VERSION) {
        uint32_t t = now_ms();
        wl_pointer_send_axis_stop(st->pointer, t,
                                  WL_POINTER_AXIS_HORIZONTAL_SCROLL);
        wl_pointer_send_axis_stop(st->pointer, t,
                                  WL_POINTER_AXIS_VERTICAL_SCROLL);
        if (wl_resource_get_version(st->pointer) >=
            WL_POINTER_FRAME_SINCE_VERSION) {
          wl_pointer_send_frame(st->pointer);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchDown") == 0) {
    Surface* s = surface_by_id(c, args);
    if (s != nullptr && s->wl_surface != nullptr) {
      SeatRes* st = seat_for(c, s->client, true);
      if (st != nullptr && st->touch != nullptr) {
        c->touch_focus = s;
        c->touch_id = (int)arg_int(args, "tid");
        wl_touch_send_down(st->touch,
                           wl_display_next_serial(c->display), now_ms(),
                           s->wl_surface, (int32_t)c->touch_id,
                           wl_fixed_from_double(arg_double(args, "x")),
                           wl_fixed_from_double(arg_double(args, "y")));
        if (wl_resource_get_version(st->touch) >=
            WL_TOUCH_FRAME_SINCE_VERSION) {
          wl_touch_send_frame(st->touch);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchMotion") == 0) {
    if (c->touch_focus != nullptr) {
      SeatRes* st = seat_for(c, c->touch_focus->client, false);
      if (st != nullptr && st->touch != nullptr) {
        wl_touch_send_motion(st->touch, now_ms(), (int32_t)c->touch_id,
                             wl_fixed_from_double(arg_double(args, "x")),
                             wl_fixed_from_double(arg_double(args, "y")));
        if (wl_resource_get_version(st->touch) >=
            WL_TOUCH_FRAME_SINCE_VERSION) {
          wl_touch_send_frame(st->touch);
        }
      }
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchUp") == 0) {
    if (c->touch_focus != nullptr) {
      SeatRes* st = seat_for(c, c->touch_focus->client, false);
      if (st != nullptr && st->touch != nullptr) {
        wl_touch_send_up(st->touch,
                         wl_display_next_serial(c->display), now_ms(),
                         (int32_t)c->touch_id);
        if (wl_resource_get_version(st->touch) >=
            WL_TOUCH_FRAME_SINCE_VERSION) {
          wl_touch_send_frame(st->touch);
        }
      }
      c->touch_focus = nullptr;
    }
    comp_flush(c);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "key") == 0) {
    uint32_t code = (uint32_t)arg_int(args, "code");
    uint32_t state = (uint32_t)arg_int(args, "state");
    if (state > WL_KEYBOARD_KEY_STATE_RELEASED) {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalidArgs", "bad key state", nullptr));
    } else {
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
      response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (g_strcmp0(name, "stop") == 0) {
    if (c->ping_timer != 0) g_source_remove(c->ping_timer);
    c->ping_timer = 0;
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
      fl_value_set_string_take(
          m, "parent",
          fl_value_new_int(s->tl_parent != nullptr
                               ? s->tl_parent->public_id
                               : -1));
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
    } else if (s->announced == SURFACE_SUBSURFACE) {
      FlValue* m = new_event("subsurface");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "parent",
                               fl_value_new_int(s->parent != nullptr
                                                    ? s->parent->public_id
                                                    : -1));
      fl_value_set_string_take(m, "x", fl_value_new_int(s->sx));
      fl_value_set_string_take(m, "y", fl_value_new_int(s->sy));
      send_event(c, m);
    }
    if (s->tex_kind != 0) {
      FlValue* m = new_event("texture");
      ev_id(m, s->public_id);
      fl_value_set_string_take(m, "textureId",
                               fl_value_new_int(s->texture_id));
      send_event(c, m);
    }
    s->rep_w = 0;
    s->rep_h = -1;
    s->rep_bw = -1;
    s->rep_bh = -1;
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
  c->view = GTK_WIDGET(view);
  FlEngine* engine = fl_view_get_engine(view);
  c->texture_registrar = fl_engine_get_texture_registrar(engine);
  g_signal_connect(view, "size-allocate", G_CALLBACK(view_resized), c);
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
  if (c->ping_timer != 0) g_source_remove(c->ping_timer);
  if (c->resize_idle != 0) g_source_remove(c->resize_idle);
  if (c->config_flush != 0) g_source_remove(c->config_flush);
  for (KillCheck* k : c->kill_checks) {
    g_source_remove(k->source);
    delete k;
  }
  c->kill_checks.clear();
  for (auto* q : c->sel_queries) {
    q->comp = nullptr;
  }
  if (c->view != nullptr) {
    g_signal_handlers_disconnect_by_data(c->view, c);
  }
  if (c->watch_channel != nullptr) g_io_channel_unref(c->watch_channel);
  if (c->display != nullptr) {
    wl_display_destroy_clients(c->display);
    wl_display_destroy(c->display);
  }
  for (Surface* s : c->surfaces) {
    if (s->texture != nullptr) g_object_unref(s->texture);
    if (s->gl_texture != nullptr) g_object_unref(s->gl_texture);
    surface_set_dmabuf(s, nullptr);
    oasis_dmabuf_unref(s->pending_dmabuf);
    g_free(s->img);
    delete s;
  }
  while (!c->dmabufs.empty()) {
    oasis_dmabuf_unref(c->dmabufs.back());
  }
  for (DataSource* ds : c->sources) delete ds;
  for (DataOffer* o : c->offers) delete o;
  for (DataDevice* d : c->devices) delete d;
  for (SelectionQuery* q : c->sel_queries) delete q;
  g_free(c->keymap);
  g_free(c->socket_name);
  g_clear_object(&c->method_channel);
  g_clear_object(&c->event_channel);
  delete c;
}
