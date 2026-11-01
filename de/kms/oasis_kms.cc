#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <gbm.h>
#include <libdrm/drm_fourcc.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

extern "C" {
#include <libseat.h>
}

extern "C" {
#include "flutter_embedder.h"
}

#include "oasis_core.h"

static void die(const char* msg) {
  fprintf(stderr, "oasis-kms: %s\n", msg);
  exit(1);
}

// ---- minimal standard codec ------------------------------------------------

struct Cv {
  std::variant<std::monostate, bool, int64_t, double, std::string,
               std::vector<Cv>, std::map<std::string, Cv>>
      v;
};

static void cv_write(std::vector<uint8_t>& out, const Cv& v) {
  if (std::holds_alternative<std::monostate>(v.v)) {
    out.push_back(0);
  } else if (auto b = std::get_if<bool>(&v.v)) {
    out.push_back(*b ? 1 : 2);
  } else if (auto i = std::get_if<int64_t>(&v.v)) {
    if (*i >= INT32_MIN && *i <= INT32_MAX) {
      out.push_back(3);
      int32_t x = (int32_t)*i;
      out.insert(out.end(), (uint8_t*)&x, (uint8_t*)&x + 4);
    } else {
      out.push_back(4);
      out.insert(out.end(), (uint8_t*)i, (uint8_t*)i + 8);
    }
  } else if (auto d = std::get_if<double>(&v.v)) {
    out.push_back(6);
    out.insert(out.end(), (uint8_t*)d, (uint8_t*)d + 8);
  } else if (auto s = std::get_if<std::string>(&v.v)) {
    out.push_back(7);
    uint32_t n = (uint32_t)s->size();
    if (n < 254) {
      out.push_back((uint8_t)n);
    } else if (n <= 0xffff) {
      out.push_back(254);
      out.push_back(n & 0xff);
      out.push_back((n >> 8) & 0xff);
    } else {
      out.push_back(255);
      out.insert(out.end(), (uint8_t*)&n, (uint8_t*)&n + 4);
    }
    out.insert(out.end(), s->begin(), s->end());
  } else if (auto l = std::get_if<std::vector<Cv>>(&v.v)) {
    out.push_back(12);
    uint32_t n = (uint32_t)l->size();
    if (n < 254) {
      out.push_back((uint8_t)n);
    } else {
      out.push_back(255);
      out.insert(out.end(), (uint8_t*)&n, (uint8_t*)&n + 4);
    }
    for (auto& e : *l) cv_write(out, e);
  } else if (auto m = std::get_if<std::map<std::string, Cv>>(&v.v)) {
    out.push_back(13);
    uint32_t n = (uint32_t)m->size();
    if (n < 254) {
      out.push_back((uint8_t)n);
    } else {
      out.push_back(255);
      out.insert(out.end(), (uint8_t*)&n, (uint8_t*)&n + 4);
    }
    for (auto& kv : *m) {
      cv_write(out, Cv{kv.first});
      cv_write(out, kv.second);
    }
  }
}

struct Rd {
  const uint8_t* p;
  size_t left;
  uint8_t u8() { return left-- ? *p++ : 0; }
  uint32_t size() {
    uint8_t b = u8();
    if (b < 254) return b;
    if (b == 254) {
      uint32_t lo = u8(), hi = u8();
      return lo | (hi << 8);
    }
    uint32_t n = 0;
    memcpy(&n, p, 4);
    p += 4;
    left -= 4;
    return n;
  }
  Cv value() {
    uint8_t t = u8();
    Cv v;
    switch (t) {
      case 0:
        break;
      case 1:
        v.v = true;
        break;
      case 2:
        v.v = false;
        break;
      case 3: {
        int32_t x;
        memcpy(&x, p, 4);
        p += 4;
        left -= 4;
        v.v = (int64_t)x;
        break;
      }
      case 4: {
        int64_t x;
        memcpy(&x, p, 8);
        p += 8;
        left -= 8;
        v.v = x;
        break;
      }
      case 6: {
        double x;
        memcpy(&x, p, 8);
        p += 8;
        left -= 8;
        v.v = x;
        break;
      }
      case 7: {
        uint32_t n = size();
        v.v = std::string((const char*)p, n);
        p += n;
        left -= n;
        break;
      }
      case 12: {
        uint32_t n = size();
        std::vector<Cv> l;
        for (uint32_t i = 0; i < n; i++) l.push_back(value());
        v.v = std::move(l);
        break;
      }
      case 13: {
        uint32_t n = size();
        std::map<std::string, Cv> m;
        for (uint32_t i = 0; i < n; i++) {
          Cv k = value();
          Cv val = value();
          m[std::get<std::string>(k.v)] = val;
        }
        v.v = std::move(m);
        break;
      }
      default:
        break;
    }
    return v;
  }
};

struct Mc {
  std::string name;
  Cv args;
};

static Mc mc_decode(const uint8_t* data, size_t len) {
  Rd r{data, len};
  Cv v = r.value();
  Mc m;
  auto& mapp = std::get<std::map<std::string, Cv>>(v.v);
  m.name = std::get<std::string>(mapp["method"].v);
  m.args = mapp["arguments"];
  return m;
}

static std::vector<uint8_t> mc_call(const char* name, const Cv& args) {
  Cv m;
  m.v = std::map<std::string, Cv>{
      {"method", Cv{std::string(name)}}, {"arguments", args}};
  std::vector<uint8_t> out;
  cv_write(out, m);
  return out;
}

static std::vector<uint8_t> env_ok(const Cv& v) {
  std::vector<uint8_t> out{0};
  cv_write(out, v);
  return out;
}

static int64_t cv_int(const Cv& v, const char* key) {
  auto* m = std::get_if<std::map<std::string, Cv>>(&v.v);
  if (!m) return 0;
  auto it = m->find(key);
  if (it == m->end()) return 0;
  if (auto i = std::get_if<int64_t>(&it->second.v)) return *i;
  if (auto d = std::get_if<double>(&it->second.v)) return (int64_t)*d;
  return 0;
}

static double cv_dbl(const Cv& v, const char* key) {
  auto* m = std::get_if<std::map<std::string, Cv>>(&v.v);
  if (!m) return 0;
  auto it = m->find(key);
  if (it == m->end()) return 0;
  if (auto d = std::get_if<double>(&it->second.v)) return *d;
  if (auto i = std::get_if<int64_t>(&it->second.v)) return (double)*i;
  return 0;
}

static Cv oval_to_cv(const Oval& o) {
  Cv c;
  if (std::holds_alternative<int64_t>(o.v)) {
    c.v = std::get<int64_t>(o.v);
  } else if (std::holds_alternative<double>(o.v)) {
    c.v = std::get<double>(o.v);
  } else if (std::holds_alternative<bool>(o.v)) {
    c.v = std::get<bool>(o.v);
  } else if (std::holds_alternative<std::string>(o.v)) {
    c.v = std::get<std::string>(o.v);
  } else if (std::holds_alternative<Oval::List>(o.v)) {
    std::vector<Cv> l;
    for (auto& e : std::get<Oval::List>(o.v)) l.push_back(oval_to_cv(e));
    c.v = std::move(l);
  } else if (std::holds_alternative<Oval::Map>(o.v)) {
    std::map<std::string, Cv> m;
    for (auto& kv : std::get<Oval::Map>(o.v)) {
      m[kv.first] = oval_to_cv(kv.second);
    }
    c.v = std::move(m);
  }
  return c;
}

static Cv oevent_cv(const OEvent& fields) {
  std::map<std::string, Cv> m;
  for (auto& kv : fields) m[kv.first] = oval_to_cv(kv.second);
  Cv out;
  out.v = std::move(m);
  return out;
}

// ---- engine wrappers ---------------------------------------------------------

static void* eng;
static FLUTTER_API_SYMBOL(FlutterEngine) engine;
static bool (*pRun)(size_t, const FlutterRendererConfig*,
                    const FlutterProjectArgs*, void*,
                    FLUTTER_API_SYMBOL(FlutterEngine)*);
static FlutterEngineResult (*pSendPlatformMessage)(
    FLUTTER_API_SYMBOL(FlutterEngine), const FlutterPlatformMessage*);
static FlutterEngineResult (*pSendResponse)(
    FLUTTER_API_SYMBOL(FlutterEngine),
    const FlutterPlatformMessageResponseHandle*, const uint8_t*, size_t);
static uint64_t (*pGetTime)();
static FlutterEngineResult (*pSendWindowMetrics)(
    FLUTTER_API_SYMBOL(FlutterEngine), const FlutterWindowMetricsEvent*);
static FlutterEngineResult (*pSendPointer)(
    FLUTTER_API_SYMBOL(FlutterEngine), const FlutterPointerEvent*, size_t);
static FlutterEngineResult (*pSendKey)(FLUTTER_API_SYMBOL(FlutterEngine),
                                       const FlutterKeyEvent*,
                                       FlutterKeyEventCallback, void*);
static FlutterEngineResult (*pRegisterTexture)(FLUTTER_API_SYMBOL(FlutterEngine),
                                               int64_t);
static FlutterEngineResult (*pUnregisterTexture)(
    FLUTTER_API_SYMBOL(FlutterEngine), int64_t);
static FlutterEngineResult (*pMarkFrameAvailable)(
    FLUTTER_API_SYMBOL(FlutterEngine), int64_t);
static FlutterEngineResult (*pUpdateSemantics)(
    FLUTTER_API_SYMBOL(FlutterEngine), const FlutterSemanticsUpdate2*);
static FlutterEngineResult (*pRunTask)(FLUTTER_API_SYMBOL(FlutterEngine),
                                       const FlutterTask*);
static FlutterEngineResult (*pDeinit)(FLUTTER_API_SYMBOL(FlutterEngine));
static FlutterEngineResult (*pPostRenderTask)(
    FLUTTER_API_SYMBOL(FlutterEngine), VoidCallback, void*);

template <typename T>
static T sym(const char* name) {
  T f = (T)dlsym(eng, name);
  if (!f) die(name);
  return f;
}

// ---- kms state ------------------------------------------------------------------

struct Head {
  drmModeConnector* conn = nullptr;
  drmModeCrtc* crtc = nullptr;
  uint32_t conn_id = 0, crtc_id = 0;
  std::string name;
  int x = 0, y = 0;
  drmModeModeInfo mode = {};
  bool enabled = true;
};

struct Drm {
  int fd = -1;
  drmModeRes* res = nullptr;
  std::vector<Head> heads;
  gbm_device* gbm = nullptr;
  gbm_surface* surface = nullptr;
  EGLDisplay dpy = EGL_NO_DISPLAY;
  EGLConfig cfg = nullptr;
  EGLContext ctx = EGL_NO_CONTEXT;
  EGLSurface esurf = EGL_NO_SURFACE;
  gbm_bo* bo = nullptr;
  gbm_bo* stale_bo = nullptr;
  int pending_flips = 0;
  std::unordered_map<uint32_t, uint32_t> fbs;
  int width = 0, height = 0;
};

static void layout_bounds(Drm& d, int& w, int& h) {
  w = 0;
  h = 0;
  for (auto& hd : d.heads) {
    if (!hd.enabled) continue;
    w = std::max(w, hd.x + (int)hd.mode.hdisplay);
    h = std::max(h, hd.y + (int)hd.mode.vdisplay);
  }
  if (w <= 0) w = 1920;
  if (h <= 0) h = 1080;
}

static void heads_free(Drm& d) {
  for (auto& hd : d.heads) {
    if (hd.conn != nullptr) drmModeFreeConnector(hd.conn);
    if (hd.crtc != nullptr) drmModeFreeCrtc(hd.crtc);
  }
  d.heads.clear();
}

static std::string connector_name(const drmModeConnector* c) {
  const char* t = drmModeGetConnectorTypeName(c->connector_type);
  char buf[64];
  snprintf(buf, sizeof(buf), "%s-%d", t != nullptr ? t : "Unknown",
           c->connector_type_id);
  return buf;
}

static uint32_t pick_crtc(Drm& d, drmModeConnector* conn,
                          std::set<uint32_t>& used) {
  drmModeEncoder* enc = conn->encoder_id != 0
                            ? drmModeGetEncoder(d.fd, conn->encoder_id)
                            : nullptr;
  uint32_t id = enc != nullptr ? enc->crtc_id : 0;
  if (id != 0 && !used.count(id)) {
    used.insert(id);
    drmModeFreeEncoder(enc);
    return id;
  }
  if (enc != nullptr) drmModeFreeEncoder(enc);
  for (int e = 0; e < conn->count_encoders; e++) {
    drmModeEncoder* cand = drmModeGetEncoder(d.fd, conn->encoders[e]);
    if (cand == nullptr) continue;
    for (int ci = 0; ci < d.res->count_crtcs; ci++) {
      if (!(cand->possible_crtcs & (1u << ci))) continue;
      uint32_t cid = d.res->crtcs[ci];
      if (used.count(cid)) continue;
      used.insert(cid);
      drmModeFreeEncoder(cand);
      return cid;
    }
    drmModeFreeEncoder(cand);
  }
  return 0;
}

static void heads_scan(Drm& d) {
  std::unordered_map<uint32_t, std::pair<int, int>> old_pos;
  for (auto& hd : d.heads) {
    old_pos[hd.conn_id] = {hd.x, hd.y};
  }
  heads_free(d);
  if (d.res != nullptr) drmModeFreeResources(d.res);
  d.res = drmModeGetResources(d.fd);
  if (d.res == nullptr) return;
  std::set<uint32_t> used_crtcs;
  int next_x = 0;
  for (int i = 0; i < d.res->count_connectors; i++) {
    drmModeConnector* conn =
        drmModeGetConnector(d.fd, d.res->connectors[i]);
    if (conn == nullptr) continue;
    if (conn->connection != DRM_MODE_CONNECTED || conn->count_modes == 0) {
      drmModeFreeConnector(conn);
      continue;
    }
    Head hd;
    hd.conn = conn;
    hd.conn_id = conn->connector_id;
    hd.name = connector_name(conn);
    hd.mode = conn->modes[0];
    for (int m = 0; m < conn->count_modes; m++) {
      if (conn->modes[m].type & DRM_MODE_TYPE_PREFERRED) {
        hd.mode = conn->modes[m];
        break;
      }
    }
    hd.crtc_id = pick_crtc(d, conn, used_crtcs);
    if (hd.crtc_id != 0) {
      hd.crtc = drmModeGetCrtc(d.fd, hd.crtc_id);
    }
    auto it = old_pos.find(hd.conn_id);
    if (it != old_pos.end()) {
      hd.x = it->second.first;
      hd.y = it->second.second;
    } else {
      hd.x = next_x;
    }
    next_x = std::max(next_x, hd.x + (int)hd.mode.hdisplay);
    d.heads.push_back(hd);
  }
}

static bool heads_hotplugged(Drm& d) {
  drmModeRes* res = drmModeGetResources(d.fd);
  if (res == nullptr) return false;
  bool changed = false;
  int connected_count = 0;
  for (int i = 0; i < res->count_connectors && !changed; i++) {
    drmModeConnector* conn =
        drmModeGetConnector(d.fd, res->connectors[i]);
    if (conn == nullptr) continue;
    bool connected = conn->connection == DRM_MODE_CONNECTED &&
                     conn->count_modes > 0;
    if (connected) {
      connected_count++;
      bool have = false;
      for (auto& hd : d.heads) {
        if (hd.conn_id == conn->connector_id) have = true;
      }
      changed = !have;
    }
    drmModeFreeConnector(conn);
  }
  changed = changed || connected_count != (int)d.heads.size();
  drmModeFreeResources(res);
  return changed;
}

static const drmModeModeInfo* head_find_mode(Head& hd, int w, int h,
                                             int refresh_mhz) {
  const drmModeModeInfo* best = nullptr;
  for (int i = 0; i < hd.conn->count_modes; i++) {
    const auto& m = hd.conn->modes[i];
    if ((int)m.hdisplay != w || (int)m.vdisplay != h) continue;
    if (refresh_mhz > 0 &&
        std::abs((int)m.vrefresh * 1000 - refresh_mhz) > 1000) {
      continue;
    }
    best = &m;
    if (refresh_mhz > 0) break;
  }
  return best;
}

// ---- seat --------------------------------------------------------------------
//
// Device nodes under /dev/dri and /dev/input are root-owned and typically
// not readable by the session user. libseat acquires fds through logind or
// seatd, which is also what grants drm master; without it the shell would
// present but open() of every evdev node fails and input is silently dead.

static libseat* g_seat = nullptr;
static bool g_seat_active = false;
static std::unordered_map<int, int> g_seat_devs;

static void seat_enable(libseat*, void*) { g_seat_active = true; }
static void seat_disable(libseat* seat, void*) {
  g_seat_active = false;
  libseat_disable_seat(seat);
}
static libseat_seat_listener g_seat_listener = {
    .enable_seat = seat_enable,
    .disable_seat = seat_disable,
};

static void seat_init() {
  g_seat = libseat_open_seat(&g_seat_listener, nullptr);
  if (g_seat == nullptr) return;
  for (int i = 0; i < 20 && !g_seat_active; i++) {
    libseat_dispatch(g_seat, 50);
  }
}

static int seat_dev_open(const char* path, int flags) {
  if (g_seat != nullptr) {
    int fd = -1;
    int id = libseat_open_device(g_seat, path, &fd);
    if (id >= 0 && fd >= 0) {
      g_seat_devs[fd] = id;
      return fd;
    }
  }
  return open(path, flags | O_CLOEXEC);
}

// libseat_close_device also closes the fd for seat-opened devices.
static void seat_dev_close(int fd) {
  auto it = g_seat_devs.find(fd);
  if (it == g_seat_devs.end()) {
    close(fd);
    return;
  }
  if (g_seat != nullptr) libseat_close_device(g_seat, it->second);
  g_seat_devs.erase(it);
}

static void drm_init(Drm& d) {
  const char* nodes[] = {"/dev/dri/card1", "/dev/dri/card0", "/dev/dri/card2"};
  for (auto n : nodes) {
    d.fd = seat_dev_open(n, O_RDWR);
    if (d.fd >= 0) break;
  }
  if (d.fd < 0) die("no drm device");
  drmSetMaster(d.fd);
  heads_scan(d);
  if (d.heads.empty()) die("no connected connector");
  layout_bounds(d, d.width, d.height);
}

static void gbm_surface_new(Drm& d) {
  d.surface = gbm_surface_create(d.gbm, d.width, d.height,
                                 GBM_FORMAT_XRGB8888,
                                 GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
  if (!d.surface) die("gbm surface");
  const EGLint surf_attrs[] = {EGL_NONE};
  d.esurf = eglCreateWindowSurface(d.dpy, d.cfg, d.surface, surf_attrs);
  if (d.esurf == EGL_NO_SURFACE) die("egl surface");
}

static void gbm_resize(Drm& d, int w, int h) {
  if (d.esurf != EGL_NO_SURFACE) {
    eglMakeCurrent(d.dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(d.dpy, d.esurf);
    d.esurf = EGL_NO_SURFACE;
  }
  if (d.surface != nullptr) {
    gbm_surface_destroy(d.surface);
    d.surface = nullptr;
  }
  d.bo = nullptr;
  d.stale_bo = nullptr;
  d.pending_flips = 0;
  d.width = w;
  d.height = h;
  gbm_surface_new(d);
  eglMakeCurrent(d.dpy, d.esurf, d.esurf, d.ctx);
}

static void gbm_init(Drm& d) {
  d.gbm = gbm_create_device(d.fd);
  if (!d.gbm) die("gbm device");
  const EGLAttrib dpy_attrs[] = {EGL_NONE};
  d.dpy = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, d.gbm, dpy_attrs);
  eglInitialize(d.dpy, nullptr, nullptr);
  eglBindAPI(EGL_OPENGL_ES_API);
  const EGLint cfg_attrs[] = {EGL_SURFACE_TYPE,
                              EGL_WINDOW_BIT,
                              EGL_RENDERABLE_TYPE,
                              EGL_OPENGL_ES2_BIT,
                              EGL_RED_SIZE,
                              8,
                              EGL_GREEN_SIZE,
                              8,
                              EGL_BLUE_SIZE,
                              8,
                              EGL_ALPHA_SIZE,
                              0,
                              EGL_NONE};
  EGLint ncfg = 0;
  eglChooseConfig(d.dpy, cfg_attrs, &d.cfg, 1, &ncfg);
  const EGLint ctx_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  d.ctx = eglCreateContext(d.dpy, d.cfg, EGL_NO_CONTEXT, ctx_attrs);
  gbm_surface_new(d);
}

static uint32_t bo_fb(Drm& d, gbm_bo* bo) {
  uint32_t handle = gbm_bo_get_handle(bo).u32;
  auto it = d.fbs.find(handle);
  if (it != d.fbs.end()) return it->second;
  uint32_t stride = gbm_bo_get_stride(bo);
  uint32_t fb = 0;
  drmModeAddFB(d.fd, d.width, d.height, 24, 32, stride, handle, &fb);
  d.fbs[handle] = fb;
  return fb;
}

static void release_stale(Drm& d) {
  if (d.stale_bo == nullptr) return;
  gbm_surface_release_buffer(d.surface, d.stale_bo);
  d.stale_bo = nullptr;
}

static void on_flip(int, unsigned, unsigned, unsigned, void* data) {
  auto* d = static_cast<Drm*>(data);
  if (d->pending_flips > 0) d->pending_flips--;
  if (d->pending_flips == 0) release_stale(*d);
}

static void drm_present(Drm& d) {
  eglSwapBuffers(d.dpy, d.esurf);
  gbm_bo* next = gbm_surface_lock_front_buffer(d.surface);
  if (!next) return;
  uint32_t fb = bo_fb(d, next);
  int flips = 0;
  for (auto& hd : d.heads) {
    if (!hd.enabled || hd.crtc_id == 0) continue;
    int ret = drmModePageFlip(d.fd, hd.crtc_id, fb,
                              DRM_MODE_PAGE_FLIP_EVENT, &d);
    if (ret != 0) {
      drmModeSetCrtc(d.fd, hd.crtc_id, fb, hd.x, hd.y, &hd.conn_id, 1,
                     &hd.mode);
    } else {
      flips++;
    }
  }
  if (d.bo != nullptr) {
    if (d.pending_flips == 0) {
      gbm_surface_release_buffer(d.surface, d.bo);
    } else {
      release_stale(d);
      d.stale_bo = d.bo;
    }
  }
  d.pending_flips += flips;
  d.bo = next;
}

// ---- embedder glue ---------------------------------------------------------------

static Drm g_drm;
static OasisCore* g_core = nullptr;

static void send_metrics() {
  FlutterWindowMetricsEvent wm = {};
  wm.struct_size = sizeof(wm);
  wm.width = g_drm.width;
  wm.height = g_drm.height;
  wm.pixel_ratio = 1.0;
  pSendWindowMetrics(engine, &wm);
}

// ---- external textures ------------------------------------------------------
//
// The compositor hands each client buffer to the engine as an external
// texture. There is a single EGL context and it belongs to the raster
// thread, so the platform thread never touches GL here: pushPixels and
// pushDmabuf only stage data under g_tex_mu, and every glGenTextures,
// upload, EGL import and delete happens inside the engine's texture frame
// callback (or another task posted to the render thread). Doing the GL
// work on the platform thread raced the rasterizer, made eglMakeCurrent
// fail with EGL_BAD_ACCESS, and corrupted textures of unrelated surfaces.

#ifndef GL_RGBA8
#define GL_RGBA8 0x8058
#endif

struct KmsTex {
  bool is_dmabuf = false;
  GLuint name = 0;
  int w = 0, h = 0;
  EGLImage image = EGL_NO_IMAGE;
  bool failed = false;

  std::vector<uint8_t> pixels;
  int pix_w = 0, pix_h = 0;
  bool pix_dirty = false;
  DmabufInfo dmabuf;
  bool dmabuf_dirty = false;

  ~KmsTex() { dmabuf.close_fds(); }
};

static std::mutex g_tex_mu;
static std::unordered_map<int64_t, std::shared_ptr<KmsTex>> g_textures;
static std::vector<std::shared_ptr<KmsTex>> g_dead_tex;
static int64_t g_next_tex = 1;

static void kms_tex_collect();
static struct {
  int fd = -1;
  libinput* li = nullptr;
  udev* ud = nullptr;
  xkb_context* xkb = nullptr;
  xkb_keymap* map = nullptr;
  xkb_state* state = nullptr;
} g_input;

static bool eng_make_current(void*) {
  return eglMakeCurrent(g_drm.dpy, g_drm.esurf, g_drm.esurf, g_drm.ctx) ==
         EGL_TRUE;
}
static bool eng_clear_current(void*) {
  return eglMakeCurrent(g_drm.dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT) == EGL_TRUE;
}
static bool eng_present(void*) {
  // Switched to another VT: the seat controller has paused our devices,
  // so swaps and page flips would only fail against a dead master.
  if (g_seat != nullptr && !g_seat_active) return true;
  {
    std::lock_guard<std::mutex> lk(g_tex_mu);
    kms_tex_collect();
  }
  drm_present(g_drm);
  return true;
}
static uint32_t eng_fbo(void*) { return 0; }
static bool eng_resource(void*) {
  return eglMakeCurrent(g_drm.dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        g_drm.ctx) == EGL_TRUE;
}
static void* eng_proc(void*, const char* name) {
  return (void*)eglGetProcAddress(name);
}

static EGLImage kms_dmabuf_image(const DmabufInfo& b) {
  EGLAttrib attrs[64];
  int i = 0;
  attrs[i++] = EGL_WIDTH;
  attrs[i++] = b.w;
  attrs[i++] = EGL_HEIGHT;
  attrs[i++] = b.h;
  attrs[i++] = EGL_LINUX_DRM_FOURCC_EXT;
  attrs[i++] = static_cast<EGLAttrib>(b.format);
  static const EGLint fd_at[4] = {EGL_DMA_BUF_PLANE0_FD_EXT,
                                  EGL_DMA_BUF_PLANE1_FD_EXT,
                                  EGL_DMA_BUF_PLANE2_FD_EXT,
                                  EGL_DMA_BUF_PLANE3_FD_EXT};
  static const EGLint off_at[4] = {EGL_DMA_BUF_PLANE0_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE1_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE2_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE3_OFFSET_EXT};
  static const EGLint pitch_at[4] = {EGL_DMA_BUF_PLANE0_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE1_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE2_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE3_PITCH_EXT};
  static const EGLint mlo_at[4] = {EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
  static const EGLint mhi_at[4] = {EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};
  int n = b.nplanes < 4 ? b.nplanes : 4;
  for (int p = 0; p < n; p++) {
    attrs[i++] = fd_at[p];
    attrs[i++] = b.fds[p];
    attrs[i++] = off_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b.offsets[p]);
    attrs[i++] = pitch_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b.strides[p]);
    if (b.mods[p] != DRM_FORMAT_MOD_INVALID) {
      attrs[i++] = mlo_at[p];
      attrs[i++] = static_cast<EGLAttrib>(b.mods[p] & 0xffffffffu);
      attrs[i++] = mhi_at[p];
      attrs[i++] = static_cast<EGLAttrib>(b.mods[p] >> 32);
    }
  }
  attrs[i++] = EGL_NONE;
  return eglCreateImage(g_drm.dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                        static_cast<EGLClientBuffer>(nullptr), attrs);
}

static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC kms_image_target() {
  static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC fn = nullptr;
  if (fn == nullptr) {
    fn = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
        eglGetProcAddress("glEGLImageTargetTexture2DOES"));
  }
  return fn;
}

// Runs on the raster thread with g_tex_mu held.
static void kms_tex_collect() {
  for (auto& t : g_dead_tex) {
    if (t->image != EGL_NO_IMAGE) {
      eglDestroyImage(g_drm.dpy, t->image);
      t->image = EGL_NO_IMAGE;
    }
    if (t->name != 0) {
      glDeleteTextures(1, &t->name);
      t->name = 0;
    }
  }
  g_dead_tex.clear();
}

// Runs on the raster thread with g_tex_mu held. Returns true once the
// texture has content the engine can sample.
static bool kms_tex_acquire(KmsTex* t) {
  if (t->name == 0) {
    glGenTextures(1, &t->name);
    if (t->name == 0) return false;
    glBindTexture(GL_TEXTURE_2D, t->name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  }
  if (t->is_dmabuf) {
    if (t->dmabuf_dirty) {
      t->dmabuf_dirty = false;
      if (t->image != EGL_NO_IMAGE) {
        eglDestroyImage(g_drm.dpy, t->image);
        t->image = EGL_NO_IMAGE;
      }
      EGLImage img = kms_dmabuf_image(t->dmabuf);
      auto target = kms_image_target();
      glBindTexture(GL_TEXTURE_2D, t->name);
      if (img != EGL_NO_IMAGE && target != nullptr) {
        target(GL_TEXTURE_2D, img);
      }
      // Multi-plane/YUV formats generally refuse a TEXTURE_2D binding;
      // latch the failure so the core falls back to a CPU readback.
      if (img == EGL_NO_IMAGE || target == nullptr ||
          glGetError() != GL_NO_ERROR) {
        if (img != EGL_NO_IMAGE) eglDestroyImage(g_drm.dpy, img);
        t->failed = true;
        return false;
      }
      t->image = img;
      t->w = t->dmabuf.w;
      t->h = t->dmabuf.h;
    }
    return t->image != EGL_NO_IMAGE;
  }
  if (t->pix_dirty && t->pix_w > 0 && t->pix_h > 0) {
    t->pix_dirty = false;
    glBindTexture(GL_TEXTURE_2D, t->name);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (t->w == t->pix_w && t->h == t->pix_h) {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, t->pix_w, t->pix_h, GL_RGBA,
                      GL_UNSIGNED_BYTE, t->pixels.data());
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, t->pix_w, t->pix_h, 0,
                   GL_RGBA, GL_UNSIGNED_BYTE, t->pixels.data());
      t->w = t->pix_w;
      t->h = t->pix_h;
    }
  }
  return t->w > 0 && t->h > 0;
}

static bool eng_texture(void*, int64_t id, size_t, size_t,
                        FlutterOpenGLTexture* tex) {
  if (eglGetCurrentContext() == EGL_NO_CONTEXT &&
      !eng_resource(nullptr) && !eng_make_current(nullptr)) {
    return false;
  }
  std::lock_guard<std::mutex> lk(g_tex_mu);
  kms_tex_collect();
  auto it = g_textures.find(id);
  if (it == g_textures.end()) return false;
  KmsTex* t = it->second.get();
  GLint prev_tex = 0, prev_unpack = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &prev_unpack);
  bool ok = kms_tex_acquire(t);
  glPixelStorei(GL_UNPACK_ALIGNMENT, prev_unpack);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex);
  if (!ok) return false;
  tex->target = GL_TEXTURE_2D;
  tex->name = t->name;
  tex->format = GL_RGBA8;
  tex->width = (size_t)t->w;
  tex->height = (size_t)t->h;
  return true;
}

// ---- render-thread jobs -------------------------------------------------------
//
// Anything that needs the GL context but originates on the platform
// thread (screen capture, output resize) runs as a render-thread task so
// it is serialized with the engine's own context use.

struct RasterJob {
  std::mutex mu;
  std::condition_variable cv;
  bool done = false;
  std::function<void()> fn;
};

static bool run_on_raster(std::function<void()> fn) {
  auto job = std::make_shared<RasterJob>();
  job->fn = std::move(fn);
  // The task holds a reference so a wait timeout can't free the job out
  // from under a callback that has not run yet.
  auto* holder = new std::shared_ptr<RasterJob>(job);
  FlutterEngineResult res = pPostRenderTask(
      engine,
      [](void* ud) {
        auto* j = static_cast<std::shared_ptr<RasterJob>*>(ud);
        (*j)->fn();
        {
          std::lock_guard<std::mutex> lk((*j)->mu);
          (*j)->done = true;
        }
        (*j)->cv.notify_one();
        delete j;
      },
      holder);
  if (res != kSuccess) {
    delete holder;
    return false;
  }
  std::unique_lock<std::mutex> lk(job->mu);
  return job->cv.wait_for(lk, std::chrono::seconds(5),
                          [&] { return job->done; });
}

static bool g_events_listening = false;

class KmsHost : public OasisHost {
 public:
  void sendEvent(OEvent fields) override {
    if (!g_events_listening) return;
    Cv c = oevent_cv(fields);
    std::vector<uint8_t> payload = env_ok(c);
    FlutterPlatformMessage msg = {};
    msg.struct_size = sizeof(msg);
    msg.channel = "oasis/wayland/events";
    msg.message = payload.data();
    msg.message_size = payload.size();
    pSendPlatformMessage(engine, &msg);
  }
  int64_t createTexture(bool dmabuf) override {
    int64_t id = g_next_tex++;
    auto t = std::make_shared<KmsTex>();
    t->is_dmabuf = dmabuf;
    {
      std::lock_guard<std::mutex> lk(g_tex_mu);
      g_textures[id] = std::move(t);
    }
    pRegisterTexture(engine, id);
    return id;
  }
  void pushPixels(int64_t id, const uint8_t* rgba, int w,
                  int h) override {
    if (w <= 0 || h <= 0) return;
    std::lock_guard<std::mutex> lk(g_tex_mu);
    auto it = g_textures.find(id);
    if (it == g_textures.end()) return;
    KmsTex* t = it->second.get();
    t->pixels.assign(rgba, rgba + (size_t)w * h * 4);
    t->pix_w = w;
    t->pix_h = h;
    t->pix_dirty = true;
  }
  void pushDmabuf(int64_t id, const DmabufInfo& buf) override {
    std::lock_guard<std::mutex> lk(g_tex_mu);
    auto it = g_textures.find(id);
    if (it == g_textures.end()) return;
    KmsTex* t = it->second.get();
    t->dmabuf.close_fds();
    t->dmabuf = buf;
    for (int i = 0; i < 4; i++) {
      if (t->dmabuf.fds[i] >= 0) {
        t->dmabuf.fds[i] =
            fcntl(t->dmabuf.fds[i], F_DUPFD_CLOEXEC, 0);
      }
    }
    t->dmabuf_dirty = true;
  }
  bool dmabufImportFailed(int64_t id) override {
    std::lock_guard<std::mutex> lk(g_tex_mu);
    auto it = g_textures.find(id);
    return it != g_textures.end() && it->second->failed;
  }
  void frameAvailable(int64_t id) override {
    pMarkFrameAvailable(engine, id);
  }
  void destroyTexture(int64_t id) override {
    {
      std::lock_guard<std::mutex> lk(g_tex_mu);
      auto it = g_textures.find(id);
      if (it == g_textures.end()) return;
      g_dead_tex.push_back(std::move(it->second));
      g_textures.erase(it);
    }
    pUnregisterTexture(engine, id);
  }
  std::vector<HostOutput> outputs() override {
    std::vector<HostOutput> out;
    bool first = true;
    for (auto& hd : g_drm.heads) {
      HostOutput o;
      o.name = hd.name;
      o.description = hd.name + " display";
      o.enabled = hd.enabled;
      o.primary = first;
      o.x = hd.x;
      o.y = hd.y;
      o.w = hd.mode.hdisplay;
      o.h = hd.mode.vdisplay;
      o.refresh = hd.mode.vrefresh * 1000;
      o.scale = 1;
      o.phys_w = hd.conn != nullptr ? (int)hd.conn->mmWidth : 0;
      o.phys_h = hd.conn != nullptr ? (int)hd.conn->mmHeight : 0;
      if (hd.conn != nullptr) {
        for (int i = 0; i < hd.conn->count_modes; i++) {
          const auto& m = hd.conn->modes[i];
          o.modes.push_back({(int32_t)m.hdisplay, (int32_t)m.vdisplay,
                             (int32_t)m.vrefresh * 1000,
                             (m.type & DRM_MODE_TYPE_PREFERRED) != 0});
        }
      }
      out.push_back(std::move(o));
      first = false;
    }
    return out;
  }

  void applyOutputs(const std::vector<HostOutput>& want) override {
    bool reprogram = false;
    for (const auto& w : want) {
      for (auto& hd : g_drm.heads) {
        if (hd.name != w.name) continue;
        bool changed = false;
        if (hd.enabled != w.enabled) {
          hd.enabled = w.enabled;
          changed = true;
        }
        if (w.enabled) {
          if (hd.x != w.x || hd.y != w.y) {
            hd.x = w.x;
            hd.y = w.y;
            changed = true;
          }
          const drmModeModeInfo* m =
              head_find_mode(hd, w.w, w.h, w.refresh);
          if (m != nullptr &&
              (hd.mode.hdisplay != m->hdisplay ||
               hd.mode.vdisplay != m->vdisplay ||
               hd.mode.vrefresh != m->vrefresh)) {
            hd.mode = *m;
            changed = true;
          }
        }
        if (!changed || hd.crtc_id == 0) continue;
        reprogram = true;
        if (!hd.enabled) {
          drmModeSetCrtc(g_drm.fd, hd.crtc_id, 0, 0, 0, nullptr, 0,
                         nullptr);
        } else if (g_drm.bo != nullptr) {
          drmModeSetCrtc(g_drm.fd, hd.crtc_id, bo_fb(g_drm, g_drm.bo),
                         hd.x, hd.y, &hd.conn_id, 1, &hd.mode);
        }
      }
    }
    if (!reprogram) return;
    int nw = 0, nh = 0;
    layout_bounds(g_drm, nw, nh);
    if (nw != g_drm.width || nh != g_drm.height) {
      run_on_raster([nw, nh] { gbm_resize(g_drm, nw, nh); });
      send_metrics();
    }
  }
  std::vector<std::string> hostClipboardMimes() override { return {}; }
  void hostClipboardRead(
      const std::string&,
      std::function<void(const uint8_t*, size_t)> done) override {
    done(nullptr, 0);
  }
  void hostClipboardWriteText(const std::string&) override {}
  bool captureOutput(std::vector<uint8_t>& rgba, int x, int y, int w,
                     int h) override {
    if (w <= 0 || h <= 0) return false;
    std::vector<uint8_t> out;
    bool ok = run_on_raster([x, y, w, h, &out] {
      eng_make_current(nullptr);
      out.resize((size_t)w * h * 4);
      GLint prev_pack = 0;
      glGetIntegerv(GL_PACK_ALIGNMENT, &prev_pack);
      glPixelStorei(GL_PACK_ALIGNMENT, 4);
      glReadPixels(x, g_drm.height - y - h, w, h, GL_RGBA,
                   GL_UNSIGNED_BYTE, out.data());
      glPixelStorei(GL_PACK_ALIGNMENT, prev_pack);
      size_t row_bytes = (size_t)w * 4;
      std::vector<uint8_t> row(row_bytes);
      for (int yy = 0; yy < h / 2; yy++) {
        uint8_t* top = out.data() + (size_t)yy * row_bytes;
        uint8_t* bottom = out.data() + (size_t)(h - 1 - yy) * row_bytes;
        memcpy(row.data(), top, row_bytes);
        memcpy(top, bottom, row_bytes);
        memcpy(bottom, row.data(), row_bytes);
      }
    });
    if (!ok) return false;
    rgba = std::move(out);
    return true;
  }
};

struct PendingReply {
  const FlutterPlatformMessageResponseHandle* handle;
};

static void platform_reply(const FlutterPlatformMessageResponseHandle* h,
                           const Cv& v) {
  std::vector<uint8_t> payload = env_ok(v);
  FlutterPlatformMessageResponseHandle* hh =
      const_cast<FlutterPlatformMessageResponseHandle*>(h);
  FlutterPlatformMessage msg = {};
  msg.struct_size = sizeof(msg);
  msg.channel = nullptr;
  pSendResponse(engine, hh, payload.data(), payload.size());
}

static void launch_app(const std::vector<std::string>& argv) {
  pid_t pid = fork();
  if (pid != 0) return;
  setsid();
  setenv("WAYLAND_DISPLAY", g_core->socketName(), 1);
  if (g_core->xwaylandDisplay() != nullptr) {
    setenv("DISPLAY", g_core->xwaylandDisplay(), 1);
  } else {
    unsetenv("DISPLAY");
  }
  unsetenv("XAUTHORITY");
  setenv("GDK_BACKEND", "wayland", 1);
  setenv("GTK_CSD", "0", 1);
  setenv("QT_QPA_PLATFORM", "wayland", 1);
  setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);
  setenv("SDL_VIDEODRIVER", "wayland", 1);
  setenv("XDG_SESSION_TYPE", "wayland", 1);
  setenv("MOZ_ENABLE_WAYLAND", "1", 1);
  setenv("WINIT_UNIX_BACKEND", "wayland", 1);
  std::vector<char*> cargv;
  for (const auto& s : argv) cargv.push_back(const_cast<char*>(s.c_str()));
  cargv.push_back(nullptr);
  execvp(cargv[0], cargv.data());
  _exit(127);
}

static void handle_method(const Mc& mc,
                          const FlutterPlatformMessageResponseHandle* h) {
  const std::string& n = mc.name;
  if (n == "start") {
    std::string err;
    if (!g_core->start(&err)) {
      std::vector<uint8_t> p{1};
      cv_write(p, Cv{std::string("start-failed")});
      cv_write(p, Cv{err});
      cv_write(p, Cv{std::monostate{}});
      pSendResponse(engine, h, p.data(), p.size());
      return;
    }
    Cv socket;
    socket.v = std::map<std::string, Cv>{
        {"socket", Cv{std::string(g_core->socketName())}}};
    platform_reply(h, socket);
  } else if (n == "stop") {
    g_core->stop();
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "launch") {
    std::vector<std::string> spawn;
    if (auto* args = std::get_if<std::map<std::string, Cv>>(&mc.args.v)) {
      auto it = args->find("argv");
      if (it != args->end()) {
        if (auto* l = std::get_if<std::vector<Cv>>(&it->second.v)) {
          for (auto& e : *l) {
            if (auto* s = std::get_if<std::string>(&e.v)) {
              spawn.push_back(*s);
            }
          }
        }
      }
    }
    if (!spawn.empty() && g_core->socketName() != nullptr) {
      launch_app(spawn);
    }
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "configure") {
    g_core->configure(cv_int(mc.args, "id"), (int)cv_int(mc.args, "w"),
                      (int)cv_int(mc.args, "h"), cv_int(mc.args, "maximized"),
                      cv_int(mc.args, "fullscreen"),
                      cv_int(mc.args, "resizing"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "configureLayer") {
    g_core->configureLayer(cv_int(mc.args, "id"), (int)cv_int(mc.args, "w"),
                           (int)cv_int(mc.args, "h"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "surfaceOutputs") {
    auto* args = std::get_if<std::map<std::string, Cv>>(&mc.args.v);
    std::vector<int64_t> ids;
    if (args != nullptr) {
      auto it = args->find("outputs");
      if (it != args->end()) {
        if (auto* l = std::get_if<std::vector<Cv>>(&it->second.v)) {
          for (auto& e : *l) {
            if (auto* i = std::get_if<int64_t>(&e.v)) ids.push_back(*i);
          }
        }
      }
    }
    g_core->surfaceOutputs(cv_int(mc.args, "id"), ids);
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "configureOutput") {
    HostOutput cfg;
    auto* args = std::get_if<std::map<std::string, Cv>>(&mc.args.v);
    if (args != nullptr) {
      auto it = args->find("name");
      if (it != args->end()) {
        if (auto* s = std::get_if<std::string>(&it->second.v)) {
          cfg.name = *s;
        }
      }
    }
    cfg.enabled = cv_int(mc.args, "enabled") != 0;
    cfg.x = (int32_t)cv_int(mc.args, "x");
    cfg.y = (int32_t)cv_int(mc.args, "y");
    cfg.w = (int32_t)cv_int(mc.args, "w");
    cfg.h = (int32_t)cv_int(mc.args, "h");
    cfg.refresh = (int32_t)cv_int(mc.args, "refresh");
    cfg.scale = cv_dbl(mc.args, "scale");
    cfg.transform = (int32_t)cv_int(mc.args, "transform");
    g_core->configureOutput(cfg);
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "close") {
    g_core->closeSurface(cv_int(mc.args, "id"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "sessionUnlock") {
    g_core->sessionUnlock();
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "activity") {
    g_core->activity();
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "idleTimeouts") {
    g_core->setIdleTimeouts(cv_int(mc.args, "displayOff"),
                            cv_int(mc.args, "suspend"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "focus") {
    g_core->focus(cv_int(mc.args, "id"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "pointerMotion") {
    g_core->pointerMotion(cv_int(mc.args, "id"), cv_dbl(mc.args, "x"),
                          cv_dbl(mc.args, "y"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "pointerExit") {
    g_core->pointerExit();
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "pointerButton") {
    g_core->pointerButton((uint32_t)cv_int(mc.args, "button"),
                          cv_int(mc.args, "state") == 1);
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "pointerAxis") {
    g_core->pointerAxis(cv_dbl(mc.args, "dx"), cv_dbl(mc.args, "dy"),
                        (uint32_t)cv_int(mc.args, "src"),
                        (int32_t)cv_int(mc.args, "discrete"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "pointerAxisStop") {
    g_core->pointerAxisStop();
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "touchDown") {
    g_core->touchDown(cv_int(mc.args, "id"), (int32_t)cv_int(mc.args, "tid"),
                      cv_dbl(mc.args, "x"), cv_dbl(mc.args, "y"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "touchMotion") {
    g_core->touchMotion((int32_t)cv_int(mc.args, "tid"), cv_dbl(mc.args, "x"),
                        cv_dbl(mc.args, "y"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "touchUp") {
    g_core->touchUp((int32_t)cv_int(mc.args, "tid"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "key") {
    g_core->key((uint32_t)cv_int(mc.args, "code"),
                cv_int(mc.args, "state") == 1);
    platform_reply(h, Cv{std::monostate{}});
  } else {
    pSendResponse(engine, h, nullptr, 0);
  }
}

static void platform_message_cb(const FlutterPlatformMessage* msg, void*) {
  if (msg->channel == nullptr) return;
  std::string ch(msg->channel);
  Mc mc = mc_decode(msg->message, msg->message_size);
  if (ch == "oasis/wayland") {
    handle_method(mc, msg->response_handle);
  } else if (ch == "oasis/wayland/events") {
    if (mc.name == "listen") {
      g_events_listening = true;
      g_core->replayEvents();
    } else {
      g_events_listening = false;
    }
    platform_reply(msg->response_handle, Cv{std::monostate{}});
  } else {
    pSendResponse(engine, msg->response_handle, nullptr, 0);
  }
}

// ---- input ----------------------------------------------------------------

static int input_open(const char* path, int flags, void*) {
  return seat_dev_open(path, flags);
}
static void input_close(int fd, void*) { seat_dev_close(fd); }
static const libinput_interface input_iface = {.open_restricted = input_open,
                                               .close_restricted = input_close};

static void input_init() {
  const char* seat = g_seat != nullptr ? libseat_seat_name(g_seat)
                                       : getenv("XDG_SEAT");
  if (seat == nullptr) seat = "seat0";
  g_input.ud = udev_new();
  if (g_input.ud != nullptr) {
    g_input.li = libinput_udev_create_context(&input_iface, nullptr,
                                              g_input.ud);
    if (g_input.li != nullptr &&
        libinput_udev_assign_seat(g_input.li, seat) != 0) {
      libinput_unref(g_input.li);
      g_input.li = nullptr;
    }
  }
  if (g_input.li == nullptr) {
    g_input.li = libinput_path_create_context(&input_iface, nullptr);
    if (DIR* dir = opendir("/dev/input")) {
      while (dirent* de = readdir(dir)) {
        if (strncmp(de->d_name, "event", 5) != 0) continue;
        char path[64];
        snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
        libinput_path_add_device(g_input.li, path);
      }
      closedir(dir);
    }
  }
  g_input.fd = libinput_get_fd(g_input.li);
  g_input.xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  xkb_rule_names names = {};
  g_input.map =
      xkb_keymap_new_from_names(g_input.xkb, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
  if (g_input.map) g_input.state = xkb_state_new(g_input.map);
}

static void send_pointer(double x, double y, int64_t phase, int64_t buttons) {
  FlutterPointerEvent ev = {};
  ev.struct_size = sizeof(ev);
  ev.phase = (FlutterPointerPhase)phase;
  ev.timestamp = pGetTime();
  ev.x = x;
  ev.y = y;
  ev.device = 0;
  ev.signal_kind = kFlutterPointerSignalKindNone;
  ev.device_kind = kFlutterPointerDeviceKindMouse;
  ev.buttons = buttons;
  pSendPointer(engine, &ev, 1);
}

static double g_px = 0, g_py = 0;
static int64_t g_buttons = 0;

// evdev -> USB HID usage. Keyboard-page entries produce a physical of
// 0x00070000|usage, consumer-page entries 0x000c0000|usage. Keys missing from
// both tables fall back to a private page (0x0e) holding the xkb keycode,
// which the Dart side decodes straight back into an evdev code.
static const struct {
  uint16_t ev;
  uint16_t hid;
} kHidKbd[] = {
    {1, 0x29},   {2, 0x1e},   {3, 0x1f},   {4, 0x20},   {5, 0x21},
    {6, 0x22},   {7, 0x23},   {8, 0x24},   {9, 0x25},   {10, 0x26},
    {11, 0x27},  {12, 0x2d},  {13, 0x2e},  {14, 0x2a},  {15, 0x2b},
    {16, 0x14},  {17, 0x1a},  {18, 0x08},  {19, 0x15},  {20, 0x17},
    {21, 0x1c},  {22, 0x18},  {23, 0x0c},  {24, 0x12},  {25, 0x13},
    {26, 0x2f},  {27, 0x30},  {28, 0x28},  {29, 0xe0},  {30, 0x04},
    {31, 0x16},  {32, 0x07},  {33, 0x09},  {34, 0x0a},  {35, 0x0b},
    {36, 0x0d},  {37, 0x0e},  {38, 0x0f},  {39, 0x33},  {40, 0x34},
    {41, 0x35},  {42, 0xe1},  {43, 0x31},  {44, 0x1d},  {45, 0x1b},
    {46, 0x06},  {47, 0x19},  {48, 0x05},  {49, 0x11},  {50, 0x10},
    {51, 0x36},  {52, 0x37},  {53, 0x38},  {54, 0xe5},  {55, 0x55},
    {56, 0xe2},  {57, 0x2c},  {58, 0x39},  {59, 0x3a},  {60, 0x3b},
    {61, 0x3c},  {62, 0x3d},  {63, 0x3e},  {64, 0x3f},  {65, 0x40},
    {66, 0x41},  {67, 0x42},  {68, 0x43},  {69, 0x53},  {70, 0x47},
    {71, 0x5f},  {72, 0x60},  {73, 0x61},  {74, 0x56},  {75, 0x5c},
    {76, 0x5d},  {77, 0x5e},  {78, 0x57},  {79, 0x59},  {80, 0x5a},
    {81, 0x5b},  {82, 0x62},  {83, 0x63},  {86, 0x64},  {87, 0x44},
    {88, 0x45},  {96, 0x58},  {97, 0xe4},  {98, 0x54},  {99, 0x46},
    {100, 0xe6}, {102, 0x4a}, {103, 0x52}, {104, 0x4b}, {105, 0x50},
    {106, 0x4f}, {107, 0x4d}, {108, 0x51}, {109, 0x4e}, {110, 0x49},
    {111, 0x4c}, {117, 0x67}, {119, 0x48}, {127, 0x65}, {148, 0x80},
    {149, 0x81}, {150, 0x82}, {152, 0x84}, {153, 0x83},
    {174, 0x8c}, {181, 0x8f}, {183, 0x68}, {184, 0x69}, {185, 0x6a},
    {186, 0x6b}, {187, 0x6c}, {188, 0x6d}, {189, 0x6e}, {190, 0x6f},
    {191, 0x70}, {192, 0x71}, {193, 0x72}, {194, 0x73}, {208, 0x8a},
    {224, 0x8b}, {226, 0x89},
};

static const struct {
  uint16_t ev;
  uint16_t hid;
} kHidCons[] = {
    {113, 0xe2}, {114, 0xea}, {115, 0xe9}, {116, 0x30},  {128, 0x226},
    {140, 0x192}, {151, 0x196}, {155, 0x18a}, {156, 0x22a}, {158, 0x224},
    {159, 0x225}, {163, 0xb5}, {164, 0xcd}, {165, 0xb6},  {166, 0xb7},
    {172, 0x223}, {217, 0x221},
};

static uint64_t key_physical(uint32_t code) {
  for (const auto& m : kHidKbd) {
    if (m.ev == code) return 0x00070000 | m.hid;
  }
  for (const auto& m : kHidCons) {
    if (m.ev == code) return 0x000c0000 | m.hid;
  }
  return 0x000e0000 | (code + 8);
}

// Maps a key's level-0 keysym to a LogicalKeyboardKey id: printable keys use
// their Unicode value, named keys use the unprintable/modifier planes.
static uint64_t key_logical(uint32_t code) {
  xkb_keysym_t sym = XKB_KEY_NoSymbol;
  if (g_input.map != nullptr) {
    const xkb_keysym_t* syms = nullptr;
    if (xkb_keymap_key_get_syms_by_level(g_input.map, code + 8, 0, 0,
                                         &syms) > 0) {
      sym = syms[0];
    }
  }
  if (sym != XKB_KEY_NoSymbol) {
    if (sym >= XKB_KEY_KP_0 && sym <= XKB_KEY_KP_9) {
      return 0x00200000230 + (sym - XKB_KEY_KP_0);
    }
    if (sym >= XKB_KEY_F1 && sym <= XKB_KEY_F24) {
      return 0x00100000801 + (sym - XKB_KEY_F1);
    }
    switch (sym) {
      case XKB_KEY_BackSpace: return 0x00100000008;
      case XKB_KEY_Tab: return 0x00100000009;
      case XKB_KEY_Return: return 0x0010000000d;
      case XKB_KEY_Escape: return 0x0010000001b;
      case XKB_KEY_Delete: return 0x0010000007f;
      case XKB_KEY_Insert: return 0x00100000407;
      case XKB_KEY_Home: return 0x00100000306;
      case XKB_KEY_End: return 0x00100000305;
      case XKB_KEY_Page_Up: return 0x00100000308;
      case XKB_KEY_Page_Down: return 0x00100000307;
      case XKB_KEY_Left: return 0x00100000302;
      case XKB_KEY_Up: return 0x00100000304;
      case XKB_KEY_Right: return 0x00100000303;
      case XKB_KEY_Down: return 0x00100000301;
      case XKB_KEY_Caps_Lock: return 0x00100000104;
      case XKB_KEY_Num_Lock: return 0x0010000010a;
      case XKB_KEY_Scroll_Lock: return 0x0010000010c;
      case XKB_KEY_ISO_Level3_Shift: return 0x00100000103;
      case XKB_KEY_Menu: return 0x00100000505;
      case XKB_KEY_Print: return 0x00100000608;
      case XKB_KEY_Pause: return 0x00100000509;
      case XKB_KEY_Shift_L: return 0x00200000102;
      case XKB_KEY_Shift_R: return 0x00200000103;
      case XKB_KEY_Control_L: return 0x00200000100;
      case XKB_KEY_Control_R: return 0x00200000101;
      case XKB_KEY_Alt_L: return 0x00200000104;
      case XKB_KEY_Alt_R: return 0x00200000105;
      case XKB_KEY_Meta_L:
      case XKB_KEY_Super_L:
      case XKB_KEY_Hyper_L: return 0x00200000106;
      case XKB_KEY_Meta_R:
      case XKB_KEY_Super_R:
      case XKB_KEY_Hyper_R: return 0x00200000107;
      case XKB_KEY_KP_Enter: return 0x0020000020d;
      case XKB_KEY_KP_Multiply: return 0x0020000022a;
      case XKB_KEY_KP_Add: return 0x0020000022b;
      case XKB_KEY_KP_Separator: return 0x0020000022c;
      case XKB_KEY_KP_Subtract: return 0x0020000022d;
      case XKB_KEY_KP_Decimal:
      case XKB_KEY_KP_Delete: return 0x0020000022e;
      case XKB_KEY_KP_Divide: return 0x0020000022f;
      case XKB_KEY_KP_Equal: return 0x0020000023d;
      case XKB_KEY_KP_Insert: return 0x00200000230;
      case XKB_KEY_KP_End: return 0x00200000231;
      case XKB_KEY_KP_Down: return 0x00200000232;
      case XKB_KEY_KP_Next: return 0x00200000233;
      case XKB_KEY_KP_Left: return 0x00200000234;
      case XKB_KEY_KP_Begin: return 0x00200000235;
      case XKB_KEY_KP_Right: return 0x00200000236;
      case XKB_KEY_KP_Home: return 0x00200000237;
      case XKB_KEY_KP_Up: return 0x00200000238;
      case XKB_KEY_KP_Prior: return 0x00200000239;
      case XKB_KEY_XF86AudioLowerVolume: return 0x00100000a0f;
      case XKB_KEY_XF86AudioRaiseVolume: return 0x00100000a10;
      case XKB_KEY_XF86AudioMute: return 0x00100000a11;
      case XKB_KEY_XF86AudioPlay: return 0x00100000d2f;
      case XKB_KEY_XF86AudioPause: return 0x00100000d2e;
      case XKB_KEY_XF86AudioPrev: return 0x00100000a09;
      case XKB_KEY_XF86AudioNext: return 0x00100000a08;
      case XKB_KEY_XF86AudioStop: return 0x00100000a07;
      case XKB_KEY_XF86MonBrightnessDown: return 0x00100000601;
      case XKB_KEY_XF86MonBrightnessUp: return 0x00100000602;
      case XKB_KEY_XF86Sleep: return 0x00200000002;
      case XKB_KEY_XF86WakeUp: return 0x0010000060b;
      case XKB_KEY_XF86Back: return 0x00100000c01;
      case XKB_KEY_XF86Forward: return 0x00100000c03;
      case XKB_KEY_XF86Search: return 0x00100000c06;
      case XKB_KEY_XF86HomePage: return 0x00100000c04;
      case XKB_KEY_XF86Mail: return 0x00100000b03;
      case XKB_KEY_XF86WWW: return 0x00100000b09;
      default: break;
    }
    uint32_t cp = xkb_keysym_to_utf32(sym);
    if (cp != 0) return cp;
  }
  return 0x00100000001;
}

static void input_dispatch() {
  libinput_dispatch(g_input.li);
  libinput_event* ev;
  while ((ev = libinput_get_event(g_input.li)) != nullptr) {
    auto type = libinput_event_get_type(ev);
    if (type == LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE) {
      auto* pe = libinput_event_get_pointer_event(ev);
      g_px = libinput_event_pointer_get_absolute_x_transformed(pe, g_drm.width);
      g_py = libinput_event_pointer_get_absolute_y_transformed(pe,
                                                               g_drm.height);
      send_pointer(g_px, g_py,
                   g_buttons ? kMove : kHover, g_buttons);
    } else if (type == LIBINPUT_EVENT_POINTER_MOTION) {
      auto* pe = libinput_event_get_pointer_event(ev);
      g_px += libinput_event_pointer_get_dx(pe);
      g_py += libinput_event_pointer_get_dy(pe);
      send_pointer(g_px, g_py, g_buttons ? kMove : kHover, g_buttons);
    } else if (type == LIBINPUT_EVENT_POINTER_BUTTON) {
      auto* pe = libinput_event_get_pointer_event(ev);
      uint32_t b = libinput_event_pointer_get_button(pe);
      int64_t bit = 0;
      if (b == BTN_LEFT) bit = kFlutterPointerButtonMousePrimary;
      else if (b == BTN_RIGHT) bit = kFlutterPointerButtonMouseSecondary;
      else if (b == BTN_MIDDLE) bit = kFlutterPointerButtonMouseMiddle;
      else if (b == BTN_SIDE) bit = kFlutterPointerButtonMouseBack;
      else if (b == BTN_EXTRA) bit = kFlutterPointerButtonMouseForward;
      if (bit != 0) {
        bool was_down = g_buttons != 0;
        if (libinput_event_pointer_get_button_state(pe) ==
            LIBINPUT_BUTTON_STATE_PRESSED) {
          g_buttons |= bit;
        } else {
          g_buttons &= ~bit;
        }
        send_pointer(g_px, g_py,
                     g_buttons == 0 ? kUp : was_down ? kMove : kDown,
                     g_buttons);
      }
    } else if (type == LIBINPUT_EVENT_POINTER_SCROLL_WHEEL ||
               type == LIBINPUT_EVENT_POINTER_SCROLL_FINGER ||
               type == LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS) {
      auto* pe = libinput_event_get_pointer_event(ev);
      FlutterPointerEvent sev = {};
      sev.struct_size = sizeof(sev);
      sev.phase = g_buttons ? kMove : kHover;
      sev.timestamp = pGetTime();
      sev.x = g_px;
      sev.y = g_py;
      sev.device = 0;
      sev.signal_kind = kFlutterPointerSignalKindScroll;
      sev.device_kind = kFlutterPointerDeviceKindMouse;
      sev.scroll_delta_x = libinput_event_pointer_get_scroll_value(
          pe, LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL);
      sev.scroll_delta_y = -libinput_event_pointer_get_scroll_value(
          pe, LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
      sev.buttons = g_buttons;
      pSendPointer(engine, &sev, 1);
    } else if (type == LIBINPUT_EVENT_KEYBOARD_KEY) {
      auto* ke = libinput_event_get_keyboard_event(ev);
      uint32_t code = libinput_event_keyboard_get_key(ke);
      bool down = libinput_event_keyboard_get_key_state(ke) ==
                  LIBINPUT_KEY_STATE_PRESSED;
      if (g_input.state) {
        xkb_state_update_key(g_input.state, code + 8,
                             down ? XKB_KEY_DOWN : XKB_KEY_UP);
      }
      // With a managed seat the console keyboard runs in K_OFF, so the
      // kernel never interprets Ctrl+Alt+Fn. The keymap hands us
      // XF86Switch_VT_n keysyms instead and switching is our job.
      bool vt_switch = false;
      if (down && g_seat != nullptr && g_input.state != nullptr) {
        xkb_keysym_t sym =
            xkb_state_key_get_one_sym(g_input.state, code + 8);
        if (sym >= XKB_KEY_XF86Switch_VT_1 &&
            sym <= XKB_KEY_XF86Switch_VT_12) {
          libseat_switch_session(g_seat,
                                 sym - XKB_KEY_XF86Switch_VT_1 + 1);
          vt_switch = true;
        }
      }
      if (vt_switch) {
        libinput_event_destroy(ev);
        continue;
      }
      FlutterKeyEvent fev = {};
      fev.struct_size = sizeof(fev);
      fev.timestamp = pGetTime();
      fev.type = down ? kFlutterKeyEventTypeDown : kFlutterKeyEventTypeUp;
      fev.physical = key_physical(code);
      fev.logical = key_logical(code);
      fev.device_type = kFlutterKeyEventDeviceTypeKeyboard;
      char utf8[32];
      if (down && g_input.state != nullptr &&
          xkb_state_key_get_utf8(g_input.state, code + 8, utf8,
                                 sizeof(utf8)) > 0) {
        fev.character = utf8;
      }
      pSendKey(engine, &fev, nullptr, nullptr);
    }
    libinput_event_destroy(ev);
  }
}

// ---- task runner ----------------------------------------------------------------

static std::mutex g_task_mu;
static std::deque<FlutterTask> g_tasks;
static int g_wake_fd = -1;

static void post_flutter_task(FlutterTask task) {
  {
    std::lock_guard<std::mutex> lk(g_task_mu);
    g_tasks.push_back(task);
  }
  if (g_wake_fd >= 0) {
    const uint64_t one = 1;
    ssize_t unused = write(g_wake_fd, &one, sizeof(one));
    (void)unused;
  }
}

static void run_flutter_tasks() {
  for (;;) {
    FlutterTask t;
    {
      std::lock_guard<std::mutex> lk(g_task_mu);
      if (g_tasks.empty()) return;
      t = g_tasks.front();
      g_tasks.pop_front();
    }
    pRunTask(engine, &t);
  }
}

int main(int argc, char** argv) {
  const char* bundle = argc > 1 ? argv[1] : "./bundle";
  std::string assets = std::string(bundle) + "/data/flutter_assets";
  std::string icu = std::string(bundle) + "/data/icudtl.dat";

  signal(SIGCHLD, SIG_IGN);
  seat_init();
  drm_init(g_drm);
  gbm_init(g_drm);
  eng_make_current(nullptr);

  const char* eng_path = getenv("OASIS_ENGINE");
  if (!eng_path) eng_path = "libflutter_engine.so";
  eng = dlopen(eng_path, RTLD_NOW | RTLD_GLOBAL);
  if (!eng) die(dlerror());
  pRun = sym<decltype(pRun)>("FlutterEngineRun");
  pSendPlatformMessage = sym<decltype(pSendPlatformMessage)>(
      "FlutterEngineSendPlatformMessage");
  pSendResponse = sym<decltype(pSendResponse)>(
      "FlutterEngineSendPlatformMessageResponse");
  pGetTime = sym<decltype(pGetTime)>("FlutterEngineGetCurrentTime");
  pSendWindowMetrics = sym<decltype(pSendWindowMetrics)>(
      "FlutterEngineSendWindowMetricsEvent");
  pSendPointer =
      sym<decltype(pSendPointer)>("FlutterEngineSendPointerEvent");
  pSendKey = sym<decltype(pSendKey)>("FlutterEngineSendKeyEvent");
  pRegisterTexture = sym<decltype(pRegisterTexture)>(
      "FlutterEngineRegisterExternalTexture");
  pUnregisterTexture = sym<decltype(pUnregisterTexture)>(
      "FlutterEngineUnregisterExternalTexture");
  pMarkFrameAvailable = sym<decltype(pMarkFrameAvailable)>(
      "FlutterEngineMarkExternalTextureFrameAvailable");
  pRunTask = sym<decltype(pRunTask)>("FlutterEngineRunTask");
  pDeinit = sym<decltype(pDeinit)>("FlutterEngineDeinitialize");
  pPostRenderTask = sym<decltype(pPostRenderTask)>(
      "FlutterEnginePostRenderThreadTask");

  FlutterRendererConfig rc = {};
  rc.type = kOpenGL;
  rc.open_gl.struct_size = sizeof(rc.open_gl);
  rc.open_gl.make_current = eng_make_current;
  rc.open_gl.clear_current = eng_clear_current;
  rc.open_gl.present = eng_present;
  rc.open_gl.fbo_callback = eng_fbo;
  rc.open_gl.make_resource_current = eng_resource;
  rc.open_gl.gl_proc_resolver = eng_proc;
  rc.open_gl.gl_external_texture_frame_callback = eng_texture;

  static FlutterTaskRunnerDescription task_desc = {};
  task_desc.struct_size = sizeof(task_desc);
  task_desc.user_data = nullptr;
  task_desc.runs_task_on_current_thread_callback =
      [](void*) { return false; };
  task_desc.post_task_callback =
      [](FlutterTask task, uint64_t, void*) {
        post_flutter_task(task);
      };
  task_desc.identifier = 1;
  static FlutterCustomTaskRunners runners = {};
  runners.struct_size = sizeof(runners);
  runners.platform_task_runner = &task_desc;

  FlutterProjectArgs args = {};
  args.struct_size = sizeof(args);
  args.assets_path = assets.c_str();
  args.icu_data_path = icu.c_str();
  args.platform_message_callback = platform_message_cb;
  args.custom_task_runners = &runners;

  g_wake_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
  if (g_wake_fd < 0) die("eventfd");

  if (pRun(FLUTTER_ENGINE_VERSION, &rc, &args, nullptr, &engine) !=
      kSuccess) {
    die("FlutterEngineRun failed");
  }

  send_metrics();

  g_core = new OasisCore(new KmsHost());
  input_init();

  drmEventContext evctx = {};
  evctx.version = 2;
  evctx.page_flip_handler = on_flip;

  int wlfd = -1;
  int seatfd = g_seat != nullptr ? libseat_get_fd(g_seat) : -1;
  int rescans = 0;
  while (true) {
    pollfd fds[5] = {};
    int nf = 0;
    fds[nf++] = {g_input.fd, POLLIN, 0};
    fds[nf++] = {g_drm.fd, POLLIN, 0};
    fds[nf++] = {g_wake_fd, POLLIN, 0};
    if (seatfd >= 0) fds[nf++] = {seatfd, POLLIN, 0};
    if (wlfd < 0 && g_core->running()) wlfd = g_core->fd();
    if (!g_core->running()) wlfd = -1;
    if (wlfd >= 0) fds[nf++] = {wlfd, POLLIN, 0};
    int ret = poll(fds, nf, 50);
    run_flutter_tasks();
    if (++rescans >= 20) {
      rescans = 0;
      if (heads_hotplugged(g_drm)) {
        heads_scan(g_drm);
        int nw = 0, nh = 0;
        layout_bounds(g_drm, nw, nh);
        if (nw != g_drm.width || nh != g_drm.height) {
          run_on_raster([nw, nh] { gbm_resize(g_drm, nw, nh); });
          send_metrics();
        }
        if (g_core->running()) g_core->outputChanged();
      }
    }
    if (ret <= 0) continue;
    for (int i = 0; i < nf; i++) {
      if (fds[i].fd == g_input.fd && (fds[i].revents & POLLIN)) {
        input_dispatch();
      } else if (fds[i].fd == g_drm.fd && (fds[i].revents & POLLIN)) {
        drmHandleEvent(g_drm.fd, &evctx);
      } else if (fds[i].fd == g_wake_fd && (fds[i].revents & POLLIN)) {
        uint64_t n;
        ssize_t unused = read(g_wake_fd, &n, sizeof(n));
        (void)unused;
      } else if (fds[i].fd == seatfd && (fds[i].revents & POLLIN)) {
        libseat_dispatch(g_seat, 0);
      } else if (fds[i].fd == wlfd && (fds[i].revents & POLLIN)) {
        g_core->dispatch();
      }
    }
  }
  return 0;
}
