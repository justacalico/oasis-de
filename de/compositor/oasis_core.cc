#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <signal.h>
#include <unistd.h>
#include <wayland-server.h>

#include <algorithm>
#include <cstdlib>
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

// wlroots' default dmabuf check only accepts buffers that live on the
// compositor's DRM device, and a failed create_immed is a fatal protocol
// error. As a nested compositor the buffers may come from anywhere, so check
// importability on our own renderer instead; buffers we can't consume at all
// still get rejected so clients can fall back to shm.
static bool dmabuf_check(wlr_dmabuf_attributes* attribs, void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  if (c->renderer == nullptr) return true;
  wlr_texture* tex = wlr_texture_from_dmabuf(c->renderer, attribs);
  if (tex == nullptr) return false;
  wlr_texture_destroy(tex);
  return true;
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

static void schedule_kill_check(OasisPrivate* c, int64_t id) {
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

void OasisCore::presented(const timespec& ts, bool vsync) {
  if (p->display == nullptr) return;
  frames_presented(p, ts, vsync);
}

void OasisCore::dispatch() {
  if (p->display == nullptr) return;
  wl_event_loop_dispatch(p->loop, 0);
  wl_display_flush_clients(p->display);
}

void OasisCore::outputChanged() { outputs_sync_host(p); }

bool OasisCore::capture(std::vector<uint8_t>& rgba, int x, int y, int* w,
                        int* h) {
  if (p->host == nullptr) return false;
  return p->host->captureOutput(rgba, x, y, w, h);
}

void OasisCore::surfaceOutputs(int64_t id,
                               const std::vector<int64_t>& ids) {
  Surface* s = surface_by_id(p, id);
  if (s == nullptr) return;
  s->outputs_reported = true;
  s->outputs.clear();
  for (int64_t oid : ids) {
    for (OasisOutput* o : p->outputs) {
      if (o->public_id == oid) {
        s->outputs.insert(o);
        break;
      }
    }
  }
  surface_sync_outputs(s);
  comp_flush(p);
}

void OasisCore::configureOutput(const HostOutput& cfg) {
  outputs_apply_config(p, cfg);
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
  p->kde_deco_mgr = wlr_server_decoration_manager_create(p->display);
  wlr_server_decoration_manager_set_default_mode(
      p->kde_deco_mgr, WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
  p->viewporter = wlr_viewporter_create(p->display);
  // Explicit sync is only worth advertising when the renderer can actually
  // wait and signal DRM timelines; implicit sync is used otherwise.
  int render_fd = wlr_renderer_get_drm_fd(p->renderer);
  if (render_fd >= 0 && p->renderer->features.timeline) {
    p->syncobj_mgr =
        wlr_linux_drm_syncobj_manager_v1_create(p->display, 1, render_fd);
  }
  p->dmabuf_v1 =
      wlr_linux_dmabuf_v1_create_with_renderer(p->display, 5, p->renderer);
  if (p->dmabuf_v1 != nullptr) {
    wlr_linux_dmabuf_v1_set_check_dmabuf_callback(p->dmabuf_v1,
                                                dmabuf_check, p);
  }
  p->fs_mgr = wlr_fractional_scale_manager_v1_create(p->display, 1);
  p->inhibit_mgr = wlr_idle_inhibit_v1_create(p->display);
  p->cursor_shape_mgr = wlr_cursor_shape_manager_v1_create(p->display, 1);
  p->activation = wlr_xdg_activation_v1_create(p->display);
  p->text_input_mgr = wlr_text_input_manager_v3_create(p->display);
  p->primary_mgr = wlr_primary_selection_v1_device_manager_create(p->display);
  p->presentation =
      wlr_presentation_create(p->display, p->backend, 1);
  p->layer_shell = wlr_layer_shell_v1_create(p->display, 5);
  p->lock_mgr = wlr_session_lock_manager_v1_create(p->display);
  p->idle_notifier = wlr_idle_notifier_v1_create(p->display);
  p->capture_src_mgr =
      wlr_ext_output_image_capture_source_manager_v1_create(p->display, 1);
  p->copy_capture_mgr =
      wlr_ext_image_copy_capture_manager_v1_create(p->display, 1);
  p->power_mgr = wlr_output_power_manager_v1_create(p->display);
  p->constraints_mgr = wlr_pointer_constraints_v1_create(p->display);
  p->rel_ptr_mgr = wlr_relative_pointer_manager_v1_create(p->display);
  p->ksi_mgr = wlr_keyboard_shortcuts_inhibit_v1_create(p->display);

  keyboard_init(p);

  outputs_init(p);
  outputChanged();

  xwayland_init(p);
  surfaces_init(p);
  xdg_init(p);
  seat_init(p);
  text_input_init(p);
  decoration_init(p);
  inhibit_init(p);
  layer_init(p);
  lock_init(p);
  power_init(p);
  constraints_init(p);

  const char* name = wl_display_add_socket_auto(p->display);
  if (name == nullptr) {
    *error = "could not create wayland socket (XDG_RUNTIME_DIR set?)";
    stop();
    return false;
  }
  p->socket_name = strdup(name);

  p->ping_timer = wl_event_loop_add_timer(p->loop, ping_tick, p);
  wl_event_source_timer_update(p->ping_timer, 5000);
  idle_off_timer_start(p);
  idle_suspend_timer_start(p);
  comp_flush(p);
  return true;
}

void OasisCore::stop() {
  p->stopping = true;
  outputs_finish(p);
  if (p->ping_timer != nullptr) {
    wl_event_source_remove(p->ping_timer);
    p->ping_timer = nullptr;
  }
  if (p->idle_off_timer != nullptr) {
    wl_event_source_remove(p->idle_off_timer);
    p->idle_off_timer = nullptr;
  }
  if (p->idle_suspend_timer != nullptr) {
    wl_event_source_remove(p->idle_suspend_timer);
    p->idle_suspend_timer = nullptr;
  }
  if (p->frame_fallback != nullptr) {
    wl_event_source_remove(p->frame_fallback);
    p->frame_fallback = nullptr;
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
    if (s->acquire_waiting) {
      wlr_drm_syncobj_timeline_waiter_finish(&s->acquire_waiter);
      s->acquire_waiting = false;
    }
    if (s->exported != nullptr) {
      wlr_buffer_unlock(s->exported);
      s->exported = nullptr;
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
  keyboard_finish(p);
  free(p->socket_name);
  p->socket_name = nullptr;
  p->kb_focus = nullptr;
  p->activated = nullptr;
  p->ptr_focus = nullptr;
  p->cursor_surface = nullptr;
  p->constraint = nullptr;
  p->ptr_in_id = -1;
  p->pressed.clear();
  p->lock = nullptr;
  p->active_inhibitors = 0;
  p->power_on = true;
  p->stopping = false;
}

void OasisCore::replayEvents() {
  outputs_emit(p);
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
    } else if (s->role == ROLE_LAYER && s->layer != nullptr) {
      s->rep_anchor = -1;
      emit_layer_current(s);
    } else if (s->role == ROLE_LOCK) {
      OEvent m;
      m["textureId"] = s->texture_id;
      emit_id(s, "lockSurface", std::move(m));
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
  if (p->lock != nullptr) emit(p, "sessionLock");
  if (p->constraint != nullptr &&
      p->constraint->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) {
    Surface* s = surface_of(p, p->constraint->surface);
    if (s != nullptr && s->announced) {
      OEvent m;
      m["on"] = true;
      emit_id(s, "pointerLock", std::move(m));
    }
  }
  if (!p->power_on) {
    OEvent m;
    m["on"] = false;
    emit(p, "outputPower", std::move(m));
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
  } else if (s->role == ROLE_LAYER && s->layer != nullptr) {
    wlr_layer_surface_v1_destroy(s->layer);
    comp_flush(p);
  }
}

void OasisCore::configureLayer(int64_t id, int w, int h) {
  Surface* s = surface_by_id(p, id);
  if (s == nullptr || s->role != ROLE_LAYER || s->layer == nullptr) return;
  wlr_layer_surface_v1_configure(s->layer, w > 0 ? (uint32_t)w : 0,
                                 h > 0 ? (uint32_t)h : 0);
  comp_flush(p);
}

void OasisCore::sessionUnlock() {
  if (p->lock == nullptr) return;
  wlr_session_lock_v1_destroy(p->lock);
  comp_flush(p);
}

void OasisCore::setIdleTimeouts(int64_t displayOffMs, int64_t suspendMs) {
  p->idle_off_ms =
      displayOffMs > 0 ? static_cast<int>(displayOffMs) : 0;
  p->idle_suspend_ms = suspendMs > 0 ? static_cast<int>(suspendMs) : 0;
  idle_arm(p);
}

void OasisCore::focus(int64_t id) {
  Surface* s = surface_by_id(p, id);
  if (p->lock != nullptr) {
    seat_focus(p, s != nullptr && s->role == ROLE_LOCK ? s : nullptr);
    comp_flush(p);
    return;
  }
  bool layer_ok = s != nullptr && s->role == ROLE_LAYER &&
                  s->layer != nullptr &&
                  s->layer->current.keyboard_interactive !=
                      ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE;
  if (s != nullptr &&
      (s->role == ROLE_TOPLEVEL || s->role == ROLE_POPUP || layer_ok)) {
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
