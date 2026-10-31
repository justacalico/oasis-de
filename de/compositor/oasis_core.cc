#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstdio>
#include <cstring>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

uint32_t now_ms() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return static_cast<uint32_t>(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

void comp_flush(OasisPrivate* c) {
  if (c->display != nullptr) wl_display_flush_clients(c->display);
}

void emit(OasisPrivate* c, const char* name, OEvent fields) {
  fields["event"] = name;
  c->host->sendEvent(std::move(fields));
}

void emit_id(Surface* s, const char* name, OEvent fields) {
  fields["id"] = s->public_id;
  emit(s->comp, name, std::move(fields));
}

Surface* surface_of(OasisPrivate* c, wlr_surface* wlr) {
  if (wlr == nullptr) return nullptr;
  auto it = c->by_wlr.find(wlr);
  return it != c->by_wlr.end() ? it->second : nullptr;
}

Surface* surface_by_id(OasisPrivate* c, int64_t id) {
  auto it = c->by_id.find(id);
  return it != c->by_id.end() ? it->second : nullptr;
}

// ---- host clipboard data source ------------------------------------------

static void host_source_send(wlr_data_source* wlr_source, const char* mime,
                             int32_t fd) {
  HostSource* hs = wl_container_of(wlr_source, hs, source);
  OasisPrivate* c = hs->comp;
  c->host->hostClipboardRead(mime != nullptr ? mime : "",
                             [fd](const uint8_t* data, size_t len) {
                               if (data != nullptr && len > 0) {
                                 size_t off = 0;
                                 while (off < len) {
                                   ssize_t n = write(fd, data + off, len - off);
                                   if (n <= 0) break;
                                   off += (size_t)n;
                                 }
                               }
                               close(fd);
                             });
}

static void host_source_accept(wlr_data_source*, uint32_t, const char*) {}

static void host_source_impl_destroy(wlr_data_source* wlr_source) {
  HostSource* hs = wl_container_of(wlr_source, hs, source);
  wl_list_remove(&hs->destroy.link);
  hs->comp->host_source = nullptr;
  delete hs->source;
  delete hs;
}

static const wlr_data_source_impl host_source_impl = {
    .send = host_source_send,
    .accept = host_source_accept,
    .destroy = host_source_impl_destroy,
    .dnd_drop = nullptr,
    .dnd_finish = nullptr,
    .dnd_action = nullptr,
};

void install_host_source(OasisPrivate* c) {
  c->host_mimes = c->host->hostClipboardMimes();
  if (c->host_mimes.empty() || c->seat == nullptr) {
    if (c->seat != nullptr) {
      wlr_seat_set_selection(c->seat, nullptr,
                             wl_display_next_serial(c->display));
    }
    return;
  }
  auto* hs = new HostSource();
  hs->comp = c;
  hs->source = new wlr_data_source();
  wlr_data_source_init(hs->source, &host_source_impl);
  wl_array_init(&hs->source->mime_types);
  for (const auto& m : c->host_mimes) {
    char** slot = static_cast<char**>(
        wl_array_add(&hs->source->mime_types, sizeof(char*)));
    *slot = strdup(m.c_str());
  }
  hs->destroy.notify = [](wl_listener* listener, void*) {
    HostSource* hs = wl_container_of(listener, hs, destroy);
    hs->comp->host_source = nullptr;
    wl_list_remove(&hs->destroy.link);
  };
  wl_signal_add(&hs->source->events.destroy, &hs->destroy);
  c->host_source = hs;
  wlr_seat_set_selection(c->seat, hs->source,
                         wl_display_next_serial(c->display));
}

// ---- clipboard mirror to host ---------------------------------------------

struct MirrorCtx {
  OasisPrivate* comp;
  wl_event_source* watch = nullptr;
  int fd = -1;
  std::string text;
};

static int mirror_fd_cb(int fd, uint32_t mask, void* data) {
  MirrorCtx* ctx = static_cast<MirrorCtx*>(data);
  bool done = false;
  if (mask & WL_EVENT_READABLE) {
    char buf[4096];
    ssize_t n = read(fd, buf, sizeof(buf));
    if (n > 0) {
      if (ctx->text.size() + (size_t)n <= (1 << 20)) {
        ctx->text.append(buf, n);
      } else {
        done = true;
      }
    } else {
      done = true;
    }
  }
  if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) done = true;
  if (done) {
    ctx->comp->host->hostClipboardWriteText(ctx->text);
    wl_event_source_remove(ctx->watch);
    close(ctx->fd);
    delete ctx;
  }
  return 0;
}

void mirror_selection_to_host(OasisPrivate* c, wlr_data_source* source) {
  if (source == nullptr || c->loop == nullptr) return;
  const char* mime = nullptr;
  {
    char** arr = static_cast<char**>(source->mime_types.data);
    size_t n = source->mime_types.size / sizeof(char*);
    for (size_t i = 0; i < n; i++) {
      if (arr[i] != nullptr &&
          strcmp(arr[i], "text/plain;charset=utf-8") == 0) {
        mime = arr[i];
      }
    }
    if (mime == nullptr) {
      for (size_t i = 0; i < n; i++) {
        if (arr[i] != nullptr && strncmp(arr[i], "text/", 5) == 0) {
          mime = arr[i];
        }
      }
    }
  }
  if (mime == nullptr) return;
  int fds[2];
  if (pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) return;
  wlr_data_source_send(source, mime, fds[1]);
  close(fds[1]);
  auto* ctx = new MirrorCtx{c, nullptr, fds[0], {}};
  ctx->watch = wl_event_loop_add_fd(c->loop, fds[0], WL_EVENT_READABLE,
                                  mirror_fd_cb, ctx);
}

// ---- keymap ------------------------------------------------------------------

void build_keymap(OasisPrivate* c) {
  c->xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (c->xkb_ctx == nullptr) return;
  xkb_rule_names names = {};
  c->kmap = xkb_keymap_new_from_names(c->xkb_ctx, &names,
                                            XKB_KEYMAP_COMPILE_NO_FLAGS);
  if (c->kmap == nullptr) {
    xkb_rule_names fallback = {"evdev", "pc105", "us", "", ""};
    c->kmap = xkb_keymap_new_from_names(c->xkb_ctx, &fallback,
                                              XKB_KEYMAP_COMPILE_NO_FLAGS);
  }
}

void send_modifiers(OasisPrivate* c) {
  if (c->vkb == nullptr) return;
  wlr_seat_keyboard_notify_modifiers(c->seat, &c->vkb->modifiers);
}

// ---- EGL debug filter ------------------------------------------------------

// wlroots hooks EGL_KHR_debug so driver reports reach wlr_log. GTK's Wayland
// GL path calls eglSwapInterval() every time it binds a context, including
// Flutter's surfaceless contexts; each call reports EGL_BAD_SURFACE and
// would print an error line per rendered frame. Keep wlroots' filtering of
// severities and its message format but drop that one benign report.
static enum wlr_log_importance egl_msg_level(EGLint type) {
  switch (type) {
    case EGL_DEBUG_MSG_CRITICAL_KHR:
    case EGL_DEBUG_MSG_ERROR_KHR:
    case EGL_DEBUG_MSG_WARN_KHR:
      return WLR_ERROR;
    default:
      return WLR_INFO;
  }
}

static const char* egl_error_str(EGLint error) {
  switch (error) {
    case EGL_SUCCESS:
      return "EGL_SUCCESS";
    case EGL_NOT_INITIALIZED:
      return "EGL_NOT_INITIALIZED";
    case EGL_BAD_ACCESS:
      return "EGL_BAD_ACCESS";
    case EGL_BAD_ALLOC:
      return "EGL_BAD_ALLOC";
    case EGL_BAD_ATTRIBUTE:
      return "EGL_BAD_ATTRIBUTE";
    case EGL_BAD_CONTEXT:
      return "EGL_BAD_CONTEXT";
    case EGL_BAD_CONFIG:
      return "EGL_BAD_CONFIG";
    case EGL_BAD_CURRENT_SURFACE:
      return "EGL_BAD_CURRENT_SURFACE";
    case EGL_BAD_DISPLAY:
      return "EGL_BAD_DISPLAY";
    case EGL_BAD_DEVICE_EXT:
      return "EGL_BAD_DEVICE_EXT";
    case EGL_BAD_SURFACE:
      return "EGL_BAD_SURFACE";
    case EGL_BAD_MATCH:
      return "EGL_BAD_MATCH";
    case EGL_BAD_PARAMETER:
      return "EGL_BAD_PARAMETER";
    case EGL_BAD_NATIVE_PIXMAP:
      return "EGL_BAD_NATIVE_PIXMAP";
    case EGL_BAD_NATIVE_WINDOW:
      return "EGL_BAD_NATIVE_WINDOW";
    case EGL_CONTEXT_LOST:
      return "EGL_CONTEXT_LOST";
    default:
      return "unknown error";
  }
}

static void egl_debug_cb(EGLenum error, const char* command, EGLint type,
                         EGLLabelKHR, EGLLabelKHR, const char* msg) {
  if (error == EGL_BAD_SURFACE && strcmp(command, "eglSwapInterval") == 0) {
    return;
  }
  _wlr_log(egl_msg_level(type),
           "[EGL] command: %s, error: %s (0x%x), message: \"%s\"", command,
           egl_error_str(error), error, msg);
}

static void install_egl_debug_filter() {
  const char* exts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if (exts == nullptr || strstr(exts, "EGL_KHR_debug") == nullptr) return;
  auto* control = reinterpret_cast<PFNEGLDEBUGMESSAGECONTROLKHRPROC>(
      eglGetProcAddress("eglDebugMessageControlKHR"));
  if (control == nullptr) return;
  static const EGLAttrib attribs[] = {
      EGL_DEBUG_MSG_CRITICAL_KHR, EGL_TRUE, EGL_DEBUG_MSG_ERROR_KHR, EGL_TRUE,
      EGL_DEBUG_MSG_WARN_KHR,     EGL_TRUE, EGL_DEBUG_MSG_INFO_KHR,  EGL_TRUE,
      EGL_NONE,
  };
  control(egl_debug_cb, attribs);
}

// ---- text input -----------------------------------------------------------------

void sync_text_input_focus(OasisPrivate* c) {
  if (c->text_input_mgr == nullptr) return;
  wl_client* focus_client = nullptr;
  if (c->kb_focus != nullptr && c->kb_focus->wlr != nullptr) {
    focus_client = wl_resource_get_client(c->kb_focus->wlr->resource);
  }
  wlr_surface* want =
      c->kb_focus != nullptr ? c->kb_focus->wlr : nullptr;
  wlr_text_input_v3* ti;
  wl_list_for_each(ti, &c->text_input_mgr->text_inputs, link) {
    wl_client* tc = wl_resource_get_client(ti->resource);
    wlr_surface* target = tc == focus_client ? want : nullptr;
    if (ti->focused_surface == target) continue;
    if (ti->focused_surface != nullptr) {
      wlr_text_input_v3_send_leave(ti);
    }
    if (target != nullptr) {
      wlr_text_input_v3_send_enter(ti, target);
    }
  }
}

static void ti_commit(wl_listener* listener, void*) {
  TextInputCtx* ctx = wl_container_of(listener, ctx, commit);
  wlr_text_input_v3_send_done(ctx->ti);
}

static void ti_destroy(wl_listener* listener, void*) {
  TextInputCtx* ctx = wl_container_of(listener, ctx, destroy);
  auto& v = ctx->comp->text_inputs;
  v.erase(std::remove(v.begin(), v.end(), ctx), v.end());
  wl_list_remove(&ctx->commit.link);
  wl_list_remove(&ctx->destroy.link);
  delete ctx;
}

static void handle_new_text_input(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_text_input);
  auto* ti = static_cast<wlr_text_input_v3*>(data);
  auto* ctx = new TextInputCtx();
  ctx->ti = ti;
  ctx->comp = c;
  ctx->commit.notify = ti_commit;
  wl_signal_add(&ti->events.commit, &ctx->commit);
  ctx->destroy.notify = ti_destroy;
  wl_signal_add(&ti->events.destroy, &ctx->destroy);
  c->text_inputs.push_back(ctx);
  sync_text_input_focus(c);
}

// ---- seat signals -----------------------------------------------------------------

static void handle_set_cursor(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_cursor);
  auto* ev = static_cast<wlr_seat_pointer_request_set_cursor_event*>(data);
  c->cursor_hx = ev->hotspot_x;
  c->cursor_hy = ev->hotspot_y;
  Surface* s = surface_of(c, ev->surface);
  if (c->cursor_surface != nullptr &&
      c->cursor_surface->role == ROLE_CURSOR &&
      c->cursor_surface != s) {
    c->cursor_surface->role = ROLE_NONE;
  }
  if (s != nullptr && s->role == ROLE_NONE) s->role = ROLE_CURSOR;
  c->cursor_surface = s;
  emit_cursor(c);
}

static void handle_set_selection(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_selection);
  auto* ev = static_cast<wlr_seat_request_set_selection_event*>(data);
  if (ev->source == nullptr) {
    install_host_source(c);
    return;
  }
  wlr_seat_set_selection(c->seat, ev->source, ev->serial);
  mirror_selection_to_host(c, ev->source);
}

static void handle_set_primary(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, seat_set_primary);
  auto* ev = static_cast<wlr_seat_request_set_primary_selection_event*>(data);
  wlr_seat_set_primary_selection(c->seat, ev->source, ev->serial);
}

static void handle_start_drag(wl_listener*, void*) {}

// ---- misc manager signals ------------------------------------------------------------

static void handle_request_shape(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, request_shape);
  auto* ev =
      static_cast<wlr_cursor_shape_manager_v1_request_set_shape_event*>(data);
  OEvent m;
  m["shape"] = (int64_t)ev->shape;
  emit(c, "cursorShape", std::move(m));
}

static void inhibitor_destroyed(wl_listener* listener, void* data) {
  Inhibitor* inh = wl_container_of(listener, inh, destroy);
  Surface* s = inh->surface;
  auto& v = s->inhibitors;
  v.erase(std::remove(v.begin(), v.end(), inh), v.end());
  wl_list_remove(&inh->destroy.link);
  delete inh;
  if (s->announced) {
    OEvent m;
    m["on"] = !s->inhibitors.empty();
    emit_id(s, "idleInhibit", std::move(m));
  }
}

static void handle_new_inhibitor(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_inhibitor);
  auto* wlr_inh = static_cast<wlr_idle_inhibitor_v1*>(data);
  Surface* s = surface_of(c, wlr_inh->surface);
  if (s == nullptr) return;
  auto* inh = new Inhibitor();
  inh->inh = wlr_inh;
  inh->surface = s;
  inh->destroy.notify = inhibitor_destroyed;
  wl_signal_add(&wlr_inh->events.destroy, &inh->destroy);
  s->inhibitors.push_back(inh);
  if (s->inhibitors.size() == 1 && s->announced) {
    OEvent m;
    m["on"] = true;
    emit_id(s, "idleInhibit", std::move(m));
  }
}

static void deco_destroyed(wl_listener* listener, void*) {
  Surface* s = wl_container_of(listener, s, deco_destroy);
  s->deco = nullptr;
  wl_list_remove(&listener->link);
  wl_list_init(&listener->link);
}

static void handle_new_decoration(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_decoration);
  auto* deco = static_cast<wlr_xdg_toplevel_decoration_v1*>(data);
  Surface* s = surface_of(c, deco->toplevel->base->surface);
  if (s == nullptr) return;
  s->deco = deco;
  s->deco_destroy.notify = deco_destroyed;
  wl_signal_add(&deco->events.destroy, &s->deco_destroy);
  if (s->xdg != nullptr && s->xdg->initialized) {
    wlr_xdg_toplevel_decoration_v1_set_mode(
        deco, WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
  }
}

static void handle_request_activate(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, request_activate);
  auto* ev = static_cast<wlr_xdg_activation_v1_request_activate_event*>(data);
  Surface* s = surface_of(c, ev->surface);
  if (s == nullptr || !s->announced || s->role != ROLE_TOPLEVEL) return;
  emit_id(s, "activate");
}

// ---- virtual keyboard -----------------------------------------------------------------

static const wlr_keyboard_impl vkb_impl = {.name = "oasis-virtual",
                                           .led_update = nullptr};

static void handle_kb_key(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, kb_key);
  auto* ev = static_cast<wlr_keyboard_key_event*>(data);
  wlr_seat_keyboard_notify_key(c->seat, ev->time_msec, ev->keycode,
                               ev->state);
}

static void handle_kb_mods(wl_listener* listener, void*) {
  OasisPrivate* c = wl_container_of(listener, c, kb_mods);
  wlr_seat_keyboard_notify_modifiers(c->seat, &c->vkb->modifiers);
}

// ---- output -----------------------------------------------------------------------------

static void output_apply(OasisPrivate* c) {
  if (c->output == nullptr) return;
  wlr_output_state st;
  wlr_output_state_init(&st);
  wlr_output_state_set_enabled(&st, true);
  wlr_output_state_set_custom_mode(&st, c->out_w, c->out_h, 60000);
  wlr_output_state_set_scale(&st, (float)c->out_scale);
  wlr_output_commit_state(c->output, &st);
  wlr_output_state_finish(&st);
  c->output->phys_width = c->phys_w;
  c->output->phys_height = c->phys_h;
}

static void output_notify_surfaces(OasisPrivate* c) {
  for (Surface* s : c->surfaces) {
    if (s->wlr != nullptr && s->announced) {
      wlr_surface_send_enter(s->wlr, c->output);
      wlr_fractional_scale_v1_notify_scale(s->wlr, (double)c->out_scale);
    }
  }
  comp_flush(c);
}

// ---- timers ----------------------------------------------------------------------------

static int ping_tick(void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  for (Surface* s : c->surfaces) {
    if (s->xdg != nullptr && s->xdg->initialized && s->announced &&
        s->role == ROLE_TOPLEVEL) {
      wlr_xdg_surface_ping(s->xdg);
    }
  }
  comp_flush(c);
  wl_event_source_timer_update(c->ping_timer, 5000);
  return 0;
}

static int kill_check(void* data) {
  auto* k = static_cast<KillCheck*>(data);
  OasisPrivate* c = k->comp;
  Surface* s = surface_by_id(c, k->id);
  if (s != nullptr && s->pid > 0) {
    kill(s->pid, k->sig);
    if (k->sig == SIGTERM) {
      k->sig = SIGKILL;
      wl_event_source_timer_update(k->timer, 2500);
      return 0;
    }
  }
  auto& v = c->kill_checks;
  v.erase(std::remove(v.begin(), v.end(), k), v.end());
  wl_event_source_remove(k->timer);
  delete k;
  return 0;
}

void schedule_kill_check(OasisPrivate* c, int64_t id) {
  auto* k = new KillCheck();
  k->comp = c;
  k->id = id;
  k->sig = SIGTERM;
  k->timer = wl_event_loop_add_timer(c->loop, kill_check, k);
  wl_event_source_timer_update(k->timer, 5000);
  c->kill_checks.push_back(k);
}

}  // namespace oasis

using namespace oasis;

OasisCore::OasisCore(OasisHost* host) {
  p = new OasisPrivate();
  p->host = host;
}

OasisCore::~OasisCore() {
  stop();
  delete p;
}

bool OasisCore::running() const { return p->display != nullptr; }
const char* OasisCore::socketName() const { return p->socket_name; }
const char* OasisCore::xwaylandDisplay() const {
  return p->xwayland_display.empty() ? nullptr : p->xwayland_display.c_str();
}

int OasisCore::fd() const {
  if (p->loop == nullptr) return -1;
  return wl_event_loop_get_fd(p->loop);
}

void OasisCore::dispatch() {
  if (p->display == nullptr) return;
  wl_event_loop_dispatch(p->loop, 0);
  wl_display_flush_clients(p->display);
}

void OasisCore::outputChanged() {
  int w = 0, h = 0, scale = 1, pw = 340, ph = 190;
  p->host->outputMetrics(w, h, scale, pw, ph);
  p->out_w = w > 0 ? w : 1920;
  p->out_h = h > 0 ? h : 1080;
  p->out_scale = scale > 0 ? scale : 1;
  p->phys_w = pw > 0 ? pw : 340;
  p->phys_h = ph > 0 ? ph : 190;
  output_apply(p);
  output_notify_surfaces(p);
}

bool OasisCore::start(std::string* error) {
  if (p->display != nullptr) return true;

  wlr_log_init(WLR_ERROR, nullptr);

  p->display = wl_display_create();
  if (p->display == nullptr) {
    *error = "wl_display_create failed";
    return false;
  }
  p->loop = wl_display_get_event_loop(p->display);

  build_keymap(p);

  p->backend = wlr_headless_backend_create(p->loop);
  if (p->backend == nullptr) {
    *error = "headless backend create failed (no render node?)";
    wl_display_destroy(p->display);
    p->display = nullptr;
    return false;
  }
  p->renderer = wlr_renderer_autocreate(p->backend);
  if (p->renderer == nullptr) {
    *error = "renderer create failed";
    wlr_backend_destroy(p->backend);
    wl_display_destroy(p->display);
    p->display = nullptr;
    return false;
  }
  wlr_renderer_init_wl_display(p->renderer, p->display);
  install_egl_debug_filter();
  p->allocator = wlr_allocator_autocreate(p->backend, p->renderer);

  p->compositor = wlr_compositor_create(p->display, 6, p->renderer);
  p->subcompositor = wlr_subcompositor_create(p->display);
  p->data_device_mgr = wlr_data_device_manager_create(p->display);
  p->seat = wlr_seat_create(p->display, "oasis-seat0");
  wlr_seat_set_capabilities(p->seat, WL_SEAT_CAPABILITY_POINTER |
                                          WL_SEAT_CAPABILITY_KEYBOARD |
                                          WL_SEAT_CAPABILITY_TOUCH);
  p->xdg_shell = wlr_xdg_shell_create(p->display, 6);
  p->deco_mgr = wlr_xdg_decoration_manager_v1_create(p->display);
  p->viewporter = wlr_viewporter_create(p->display);
  p->fs_mgr = wlr_fractional_scale_manager_v1_create(p->display, 1);
  p->inhibit_mgr = wlr_idle_inhibit_v1_create(p->display);
  p->cursor_shape_mgr = wlr_cursor_shape_manager_v1_create(p->display, 1);
  p->activation = wlr_xdg_activation_v1_create(p->display);
  p->text_input_mgr = wlr_text_input_manager_v3_create(p->display);
  p->primary_mgr = wlr_primary_selection_v1_device_manager_create(p->display);
  p->presentation =
      wlr_presentation_create(p->display, p->backend, 1);

  p->vkb = static_cast<wlr_keyboard*>(calloc(1, sizeof(wlr_keyboard)));
  wlr_keyboard_init(p->vkb, &vkb_impl, "oasis-virtual");
  if (p->kmap != nullptr) {
    wlr_keyboard_set_keymap(p->vkb, p->kmap);
  }
  wlr_keyboard_set_repeat_info(p->vkb, 25, 600);
  wlr_seat_set_keyboard(p->seat, p->vkb);
  p->kb_key.notify = handle_kb_key;
  wl_signal_add(&p->vkb->events.key, &p->kb_key);
  p->kb_mods.notify = handle_kb_mods;
  wl_signal_add(&p->vkb->events.modifiers, &p->kb_mods);

  p->output = wlr_headless_add_output(p->backend, p->out_w, p->out_h);
  wlr_output_set_name(p->output, "oasis-embedded");
  wlr_output_set_description(p->output, "Oasis embedded output");
  wlr_output_init_render(p->output, p->allocator, p->renderer);
  wlr_output_create_global(p->output, p->display);
  outputChanged();

  p->xwayland = wlr_xwayland_create(p->display, p->compositor, false);
  if (p->xwayland != nullptr) {
    p->xwayland_ready.notify = [](wl_listener* listener, void*) {
      OasisPrivate* c = wl_container_of(listener, c, xwayland_ready);
      if (c->xwayland != nullptr && c->xwayland->display_name != nullptr) {
        c->xwayland_display = c->xwayland->display_name;
      }
      wlr_xwayland_set_seat(c->xwayland, c->seat);
    };
    wl_signal_add(&p->xwayland->events.ready, &p->xwayland_ready);
    p->xwayland_new_surface.notify = [](wl_listener* listener, void* data) {
      OasisPrivate* c = wl_container_of(listener, c, xwayland_new_surface);
      xwayland_new_surface(c, static_cast<wlr_xwayland_surface*>(data));
    };
    wl_signal_add(&p->xwayland->events.new_surface,
                  &p->xwayland_new_surface);
    p->xwayland_destroy.notify = [](wl_listener* listener, void*) {
      OasisPrivate* c = wl_container_of(listener, c, xwayland_destroy);
      c->xwayland = nullptr;
      c->xwayland_display.clear();
      wl_list_remove(&listener->link);
      wl_list_init(&listener->link);
      wl_list_remove(&c->xwayland_ready.link);
      wl_list_init(&c->xwayland_ready.link);
      wl_list_remove(&c->xwayland_new_surface.link);
      wl_list_init(&c->xwayland_new_surface.link);
    };
    wl_signal_add(&p->xwayland->events.destroy, &p->xwayland_destroy);
  }

  p->new_surface.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, new_surface);
    surface_new(c, static_cast<wlr_surface*>(data));
  };
  wl_signal_add(&p->compositor->events.new_surface, &p->new_surface);
  p->new_toplevel.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, new_toplevel);
    toplevel_new(c, static_cast<wlr_xdg_toplevel*>(data));
  };
  wl_signal_add(&p->xdg_shell->events.new_toplevel, &p->new_toplevel);
  p->new_popup.notify = [](wl_listener* listener, void* data) {
    OasisPrivate* c = wl_container_of(listener, c, new_popup);
    popup_new(c, static_cast<wlr_xdg_popup*>(data));
  };
  wl_signal_add(&p->xdg_shell->events.new_popup, &p->new_popup);

  p->seat_set_cursor.notify = handle_set_cursor;
  wl_signal_add(&p->seat->events.request_set_cursor, &p->seat_set_cursor);
  p->seat_set_selection.notify = handle_set_selection;
  wl_signal_add(&p->seat->events.request_set_selection,
                &p->seat_set_selection);
  p->seat_set_primary.notify = handle_set_primary;
  wl_signal_add(&p->seat->events.request_set_primary_selection,
                &p->seat_set_primary);
  p->seat_start_drag.notify = handle_start_drag;
  wl_signal_add(&p->seat->events.request_start_drag, &p->seat_start_drag);
  p->request_activate.notify = handle_request_activate;
  wl_signal_add(&p->activation->events.request_activate,
                &p->request_activate);
  p->new_text_input.notify = handle_new_text_input;
  wl_signal_add(&p->text_input_mgr->events.new_text_input,
                &p->new_text_input);
  p->new_decoration.notify = handle_new_decoration;
  wl_signal_add(&p->deco_mgr->events.new_toplevel_decoration,
                &p->new_decoration);
  p->request_shape.notify = handle_request_shape;
  wl_signal_add(&p->cursor_shape_mgr->events.request_set_shape,
                &p->request_shape);
  p->new_inhibitor.notify = handle_new_inhibitor;
  wl_signal_add(&p->inhibit_mgr->events.new_inhibitor, &p->new_inhibitor);

  const char* name = wl_display_add_socket_auto(p->display);
  if (name == nullptr) {
    *error = "could not create wayland socket (XDG_RUNTIME_DIR set?)";
    stop();
    return false;
  }
  p->socket_name = strdup(name);

  p->ping_timer = wl_event_loop_add_timer(p->loop, ping_tick, p);
  wl_event_source_timer_update(p->ping_timer, 5000);
  comp_flush(p);
  return true;
}

void OasisCore::stop() {
  p->stopping = true;
  if (p->ping_timer != nullptr) {
    wl_event_source_remove(p->ping_timer);
    p->ping_timer = nullptr;
  }
  for (KillCheck* k : p->kill_checks) {
    if (k->timer != nullptr) wl_event_source_remove(k->timer);
    delete k;
  }
  p->kill_checks.clear();
  for (TextInputCtx* ctx : p->text_inputs) {
    wl_list_remove(&ctx->commit.link);
    wl_list_remove(&ctx->destroy.link);
    delete ctx;
  }
  p->text_inputs.clear();
  for (Surface* s : p->surfaces) {
    s->announced = false;
    remove_listeners(s);
    for (Inhibitor* inh : s->inhibitors) {
      wl_list_remove(&inh->destroy.link);
      delete inh;
    }
    s->inhibitors.clear();
    delete s;
  }
  p->surfaces.clear();
  p->by_id.clear();
  p->by_wlr.clear();
  if (p->display != nullptr) {
    wl_display_destroy_clients(p->display);
    if (p->xwayland != nullptr) {
      wlr_xwayland_destroy(p->xwayland);
      p->xwayland = nullptr;
    }
    wl_display_destroy(p->display);
    p->display = nullptr;
  }
  if (p->vkb != nullptr) {
    wl_list_remove(&p->kb_key.link);
    wl_list_remove(&p->kb_mods.link);
    wlr_keyboard_finish(p->vkb);
    free(p->vkb);
    p->vkb = nullptr;
  }
  if (p->kstate != nullptr) {
    xkb_state_unref(p->kstate);
    p->kstate = nullptr;
  }
  if (p->kmap != nullptr) {
    xkb_keymap_unref(p->kmap);
    p->kmap = nullptr;
  }
  if (p->xkb_ctx != nullptr) {
    xkb_context_unref(p->xkb_ctx);
    p->xkb_ctx = nullptr;
  }
  free(p->socket_name);
  p->socket_name = nullptr;
  p->kb_focus = nullptr;
  p->activated = nullptr;
  p->ptr_focus = nullptr;
  p->cursor_surface = nullptr;
  p->pressed.clear();
  p->stopping = false;
}

void OasisCore::replayEvents() {
  for (Surface* s : p->surfaces) {
    if (!s->announced) continue;
    if (s->role == ROLE_TOPLEVEL) {
      OEvent m;
      m["textureId"] = s->texture_id;
      m["title"] = s->title;
      m["appId"] = s->app_id;
      m["parent"] = s->tl_parent != nullptr ? s->tl_parent->public_id : -1;
      emit_id(s, "toplevel", std::move(m));
    } else if (s->role == ROLE_POPUP) {
      OEvent m;
      m["parent"] = s->parent != nullptr ? s->parent->public_id : -1;
      m["textureId"] = s->texture_id;
      m["x"] = s->sx;
      m["y"] = s->sy;
      emit_id(s, "popup", std::move(m));
    } else if (s->role == ROLE_SUBSURFACE) {
      OEvent m;
      m["parent"] = s->parent != nullptr ? s->parent->public_id : -1;
      m["x"] = s->sx;
      m["y"] = s->sy;
      emit_id(s, "subsurface", std::move(m));
    }
    if (s->tex_kind != 0) {
      OEvent m;
      m["textureId"] = s->texture_id;
      emit_id(s, "texture", std::move(m));
    }
    s->rep_w = 0;
    s->rep_h = -1;
    s->rep_bw = -1;
    s->rep_bh = -1;
    emit_size(s);
  }
  emit_cursor(p);
}

void OasisCore::configure(int64_t id, int w, int h, bool maximized,
                                bool fullscreen, bool resizing) {
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->role != ROLE_TOPLEVEL) return;
  toplevel_configure(s, w, h, maximized, s == p->activated, fullscreen,
                     resizing);
}

void OasisCore::closeSurface(int64_t id) {
  Surface* s = surface_by_id(p, id);
  if (s == nullptr) return;
  if (s->role == ROLE_TOPLEVEL) {
    if (s->xdg != nullptr) {
      wlr_xdg_toplevel_send_close(s->xdg->toplevel);
    } else if (s->xsurface != nullptr) {
      wlr_xwayland_surface_close(s->xsurface);
    }
    comp_flush(p);
    if (s->pid > 0) schedule_kill_check(p, s->public_id);
  } else if (s->role == ROLE_POPUP && s->xdg != nullptr) {
    wlr_xdg_popup_destroy(s->xdg->popup);
    comp_flush(p);
  }
}

void OasisCore::focus(int64_t id) {
  Surface* s = surface_by_id(p, id);
  if (s != nullptr &&
      (s->role == ROLE_TOPLEVEL || s->role == ROLE_POPUP)) {
    seat_focus(p, s);
    if (s->role == ROLE_TOPLEVEL && p->activated != s) {
      if (p->activated != nullptr && p->activated->role == ROLE_TOPLEVEL) {
        toplevel_configure(p->activated, p->activated->cfg_w,
                           p->activated->cfg_h, p->activated->cfg_max, false,
                           p->activated->cfg_fs, p->activated->cfg_resizing);
      }
      toplevel_configure(s, s->cfg_w, s->cfg_h, s->cfg_max, true, s->cfg_fs,
                         s->cfg_resizing);
      p->activated = s;
    }
  } else {
    seat_focus(p, nullptr);
    if (p->activated != nullptr && p->activated->role == ROLE_TOPLEVEL) {
      toplevel_configure(p->activated, p->activated->cfg_w,
                         p->activated->cfg_h, p->activated->cfg_max, false,
                         p->activated->cfg_fs, p->activated->cfg_resizing);
      p->activated = nullptr;
    }
  }
  comp_flush(p);
}
