#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <dlfcn.h>
#include <fcntl.h>
#include <gbm.h>
#include <libinput.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <xkbcommon/xkbcommon.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

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

static Cv oevent_cv(const OEvent& fields) {
  std::map<std::string, Cv> m;
  for (auto& kv : fields) {
    const Oval& o = kv.second;
    Cv c;
    if (std::holds_alternative<int64_t>(o.v)) c.v = std::get<int64_t>(o.v);
    else if (std::holds_alternative<double>(o.v)) c.v = std::get<double>(o.v);
    else if (std::holds_alternative<bool>(o.v)) c.v = std::get<bool>(o.v);
    else if (std::holds_alternative<std::string>(o.v))
      c.v = std::get<std::string>(o.v);
    else if (std::holds_alternative<Oval::List>(o.v)) {
      std::vector<Cv> l;
      for (auto& e : std::get<Oval::List>(o.v)) {
        OEvent wrap;
        wrap["x"] = e;
        l.push_back(oevent_cv(wrap));
      }
      c.v = std::move(l);
    }
    m[kv.first] = c;
  }
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

template <typename T>
static T sym(const char* name) {
  T f = (T)dlsym(eng, name);
  if (!f) die(name);
  return f;
}

// ---- kms state ------------------------------------------------------------------

struct Drm {
  int fd = -1;
  drmModeRes* res = nullptr;
  drmModeConnector* conn = nullptr;
  drmModeEncoder* enc = nullptr;
  drmModeCrtc* crtc = nullptr;
  drmModeModeInfo mode = {};
  uint32_t conn_id = 0, crtc_id = 0;
  gbm_device* gbm = nullptr;
  gbm_surface* surface = nullptr;
  EGLDisplay dpy = EGL_NO_DISPLAY;
  EGLContext ctx = EGL_NO_CONTEXT;
  EGLSurface esurf = EGL_NO_SURFACE;
  gbm_bo* bo = nullptr;
  gbm_bo* next_bo = nullptr;
  int width = 0, height = 0;
};

static void drm_init(Drm& d) {
  const char* nodes[] = {"/dev/dri/card1", "/dev/dri/card0", "/dev/dri/card2"};
  for (auto n : nodes) {
    d.fd = open(n, O_RDWR | O_CLOEXEC);
    if (d.fd >= 0) break;
  }
  if (d.fd < 0) die("no drm device");
  d.res = drmModeGetResources(d.fd);
  if (!d.res) die("drmModeGetResources");
  for (int i = 0; i < d.res->count_connectors; i++) {
    drmModeConnector* c = drmModeGetConnector(d.fd, d.res->connectors[i]);
    if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes > 0) {
      d.conn = c;
      break;
    }
    if (c) drmModeFreeConnector(c);
  }
  if (!d.conn) die("no connected connector");
  d.conn_id = d.conn->connector_id;
  d.mode = d.conn->modes[0];
  d.width = d.mode.hdisplay;
  d.height = d.mode.vdisplay;
  d.enc = drmModeGetEncoder(d.fd, d.conn->encoder_id);
  if (d.enc) d.crtc = drmModeGetCrtc(d.fd, d.enc->crtc_id);
  for (int i = 0; i < d.res->count_crtcs && !d.crtc; i++) {
    d.crtc = drmModeGetCrtc(d.fd, d.res->crtcs[i]);
  }
  d.crtc_id = d.crtc->crtc_id;
}

static void gbm_init(Drm& d) {
  d.gbm = gbm_create_device(d.fd);
  if (!d.gbm) die("gbm device");
  d.surface = gbm_surface_create(d.gbm, d.width, d.height,
                                 GBM_FORMAT_XRGB8888,
                                 GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
  if (!d.surface) die("gbm surface");
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
  EGLConfig cfg;
  EGLint ncfg = 0;
  eglChooseConfig(d.dpy, cfg_attrs, &cfg, 1, &ncfg);
  const EGLint ctx_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  d.ctx = eglCreateContext(d.dpy, cfg, EGL_NO_CONTEXT, ctx_attrs);
  const EGLint surf_attrs[] = {EGL_NONE};
  d.esurf = eglCreateWindowSurface(d.dpy, cfg, d.surface, surf_attrs);
}

static uint32_t bo_fb(Drm& d, gbm_bo* bo) {
  uint32_t handle = gbm_bo_get_handle(bo).u32;
  uint32_t stride = gbm_bo_get_stride(bo);
  uint32_t fb = 0;
  drmModeAddFB(d.fd, d.width, d.height, 24, 32, stride, handle, &fb);
  return fb;
}

static void drm_present(Drm& d) {
  eglSwapBuffers(d.dpy, d.esurf);
  gbm_bo* next = gbm_surface_lock_front_buffer(d.surface);
  if (!next) return;
  uint32_t fb = bo_fb(d, next);
  int ret = drmModePageFlip(d.fd, d.crtc_id, fb, DRM_MODE_PAGE_FLIP_EVENT,
                          &d);
  if (ret != 0) {
    drmModeSetCrtc(d.fd, d.crtc_id, fb, 0, 0, &d.conn_id, 1, &d.mode);
    gbm_surface_release_buffer(d.surface, next);
    return;
  }
  d.next_bo = next;
}

// ---- embedder glue ---------------------------------------------------------------

static Drm g_drm;
static OasisCore* g_core = nullptr;
static std::unordered_map<int64_t, GLuint> g_textures;
static int64_t g_next_tex = 1;
static struct {
  int fd = -1;
  libinput* li = nullptr;
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
static bool eng_texture(void*, int64_t id, size_t w, size_t h,
                        FlutterOpenGLTexture* tex) {
  auto it = g_textures.find(id);
  if (it == g_textures.end()) return false;
  tex->target = GL_TEXTURE_2D;
  tex->name = it->second;
  return true;
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
  int64_t createTexture(bool) override {
    int64_t id = g_next_tex++;
    GLuint tex = 0;
    eng_make_current(nullptr);
    glGenTextures(1, &tex);
    g_textures[id] = tex;
    pRegisterTexture(engine, id);
    return id;
  }
  void pushPixels(int64_t id, const uint8_t* rgba, int w, int h) override {
    auto it = g_textures.find(id);
    if (it == g_textures.end()) return;
    eng_make_current(nullptr);
    glBindTexture(GL_TEXTURE_2D, it->second);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, rgba);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  }
  void pushDmabuf(int64_t, const DmabufInfo&) override {}
  void frameAvailable(int64_t id) override {
    pMarkFrameAvailable(engine, id);
  }
  void destroyTexture(int64_t id) override {
    auto it = g_textures.find(id);
    if (it == g_textures.end()) return;
    pUnregisterTexture(engine, id);
    eng_make_current(nullptr);
    glDeleteTextures(1, &it->second);
    g_textures.erase(it);
  }
  void outputMetrics(int& w, int& h, int& scale, int& pw,
                     int& ph) override {
    w = g_drm.width;
    h = g_drm.height;
    scale = 1;
    pw = 340;
    ph = 190;
  }
  std::vector<std::string> hostClipboardMimes() override { return {}; }
  void hostClipboardRead(
      const std::string&,
      std::function<void(const uint8_t*, size_t)> done) override {
    done(nullptr, 0);
  }
  void hostClipboardWriteText(const std::string&) override {}
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
  } else if (n == "configure") {
    g_core->configure(cv_int(mc.args, "id"), (int)cv_int(mc.args, "w"),
                      (int)cv_int(mc.args, "h"), cv_int(mc.args, "maximized"),
                      cv_int(mc.args, "fullscreen"),
                      cv_int(mc.args, "resizing"));
    platform_reply(h, Cv{std::monostate{}});
  } else if (n == "close") {
    g_core->closeSurface(cv_int(mc.args, "id"));
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
  return open(path, flags);
}
static void input_close(int fd, void*) { close(fd); }
static const libinput_interface input_iface = {.open_restricted = input_open,
                                               .close_restricted = input_close};

static void input_init() {
  g_input.li = libinput_path_create_context(&input_iface, nullptr);
  const char* devs[] = {"/dev/input/event0", "/dev/input/event1",
                        "/dev/input/event2", "/dev/input/event3"};
  for (auto d : devs) libinput_path_add_device(g_input.li, d);
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
  ev.buttons = buttons;
  pSendPointer(engine, &ev, 1);
}

static double g_px = 0, g_py = 0;
static int64_t g_buttons = 0;

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
      if (libinput_event_pointer_get_button_state(pe) ==
          LIBINPUT_BUTTON_STATE_PRESSED) {
        g_buttons |= bit;
        send_pointer(g_px, g_py, kDown, g_buttons);
      } else {
        send_pointer(g_px, g_py, kUp, g_buttons);
        g_buttons &= ~bit;
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
      FlutterKeyEvent fev = {};
      fev.struct_size = sizeof(fev);
      fev.timestamp = pGetTime();
      fev.type = down ? kFlutterKeyEventTypeDown : kFlutterKeyEventTypeUp;
      fev.physical = code + 8;
      fev.logical = code + 8;
      pSendKey(engine, &fev, nullptr, nullptr);
    }
    libinput_event_destroy(ev);
  }
}

// ---- task runner ----------------------------------------------------------------

static FlutterTask g_task = {};

int main(int argc, char** argv) {
  const char* bundle = argc > 1 ? argv[1] : "./bundle";
  std::string assets = std::string(bundle) + "/data/flutter_assets";
  std::string icu = std::string(bundle) + "/data/icudtl.dat";

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
        g_task = task;
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

  if (pRun(FLUTTER_ENGINE_VERSION, &rc, &args, nullptr, &engine) !=
      kSuccess) {
    die("FlutterEngineRun failed");
  }

  FlutterWindowMetricsEvent wm = {};
  wm.struct_size = sizeof(wm);
  wm.width = g_drm.width;
  wm.height = g_drm.height;
  wm.pixel_ratio = 1.0;
  pSendWindowMetrics(engine, &wm);

  g_core = new OasisCore(new KmsHost());
  input_init();

  int wlfd = -1;
  while (true) {
    pollfd fds[4] = {};
    int nf = 0;
    fds[nf++] = {g_input.fd, POLLIN, 0};
    if (wlfd < 0 && g_core->running()) wlfd = g_core->fd();
    if (!g_core->running()) wlfd = -1;
    if (wlfd >= 0) fds[nf++] = {wlfd, POLLIN, 0};
    int ret = poll(fds, nf, 50);
    if (g_task.runner != 0) {
      FlutterTask t = g_task;
      g_task = {};
      pRunTask(engine, &t);
    }
    if (ret <= 0) continue;
    for (int i = 0; i < nf; i++) {
      if (fds[i].fd == g_input.fd && (fds[i].revents & POLLIN)) {
        input_dispatch();
      } else if (fds[i].fd == wlfd && (fds[i].revents & POLLIN)) {
        g_core->dispatch();
      }
    }
  }
  return 0;
}
