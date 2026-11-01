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

OasisOutput* output_of(OasisPrivate* c, wlr_output* wlr) {
  if (wlr == nullptr) return nullptr;
  auto it = c->output_by_wlr.find(wlr);
  return it != c->output_by_wlr.end() ? it->second : nullptr;
}

OasisOutput* output_primary(OasisPrivate* c) {
  for (OasisOutput* o : c->outputs) {
    if (o->enabled && o->primary) return o;
  }
  for (OasisOutput* o : c->outputs) {
    if (o->enabled) return o;
  }
  return c->outputs.empty() ? nullptr : c->outputs.front();
}

OasisOutput* output_for_surface(Surface* s) {
  OasisPrivate* c = s->comp;
  for (OasisOutput* o : c->outputs) {
    if (o->enabled && s->outputs.count(o)) return o;
  }
  return output_primary(c);
}

static wlr_output_mode* mode_add(OasisOutput* o, int32_t w, int32_t h,
                                 int32_t refresh, bool preferred) {
  auto* m = new wlr_output_mode();
  m->width = w;
  m->height = h;
  m->refresh = refresh;
  m->preferred = preferred;
  m->picture_aspect_ratio = WLR_OUTPUT_MODE_ASPECT_RATIO_NONE;
  wl_list_insert(&o->wlr->modes, &m->link);
  o->modes.push_back(m);
  return m;
}

static void modes_clear(OasisOutput* o) {
  for (wlr_output_mode* m : o->modes) {
    wl_list_remove(&m->link);
    delete m;
  }
  o->modes.clear();
}

static bool modes_equal(OasisOutput* o,
                        const std::vector<HostOutputMode>& want) {
  if (o->modes.size() != want.size()) return false;
  for (size_t i = 0; i < want.size(); i++) {
    if (o->modes[i]->width != want[i].w ||
        o->modes[i]->height != want[i].h ||
        o->modes[i]->refresh != want[i].refresh ||
        o->modes[i]->preferred != want[i].preferred) {
      return false;
    }
  }
  return true;
}

void output_apply_state(OasisOutput* o) {
  wlr_output_state st;
  wlr_output_state_init(&st);
  wlr_output_state_set_enabled(&st, o->enabled);
  if (o->enabled && o->width > 0 && o->height > 0) {
    wlr_output_mode* mode = nullptr;
    if (!wlr_output_is_headless(o->wlr)) {
      for (wlr_output_mode* m : o->modes) {
        if (m->width == o->width && m->height == o->height &&
            std::abs(m->refresh - o->refresh) <= 1000) {
          mode = m;
          break;
        }
      }
    }
    if (mode != nullptr) {
      wlr_output_state_set_mode(&st, mode);
    } else {
      wlr_output_state_set_custom_mode(&st, o->width, o->height,
                                       o->refresh);
    }
  }
  wlr_output_commit_state(o->wlr, &st);
  wlr_output_state_finish(&st);
  o->wlr->scale = (float)o->scale;
  o->wlr->transform = (enum wl_output_transform)o->transform;
  o->wlr->phys_width = o->phys_w;
  o->wlr->phys_height = o->phys_h;
}

void outputs_layout_normalize(OasisPrivate* c) {
  int32_t min_x = 0, min_y = 0;
  bool any = false;
  for (OasisOutput* o : c->outputs) {
    if (!o->enabled) continue;
    if (!any) {
      min_x = o->x;
      min_y = o->y;
      any = true;
    } else {
      min_x = std::min(min_x, o->x);
      min_y = std::min(min_y, o->y);
    }
  }
  if (!any) return;
  if (min_x == 0 && min_y == 0) return;
  for (OasisOutput* o : c->outputs) {
    o->x -= min_x;
    o->y -= min_y;
  }
}

static void outputs_relayout(OasisPrivate* c) {
  outputs_layout_normalize(c);
  for (OasisOutput* o : c->outputs) {
    wlr_output_layout_add(c->output_layout, o->wlr, o->x, o->y);
    output_apply_state(o);
  }
}

static std::vector<HostOutput> outputs_host_report(OasisPrivate* c) {
  std::vector<HostOutput> out;
  for (OasisOutput* o : c->outputs) {
    HostOutput h;
    h.name = o->name;
    h.description = o->description;
    h.enabled = o->enabled;
    h.primary = o->primary;
    h.x = o->x;
    h.y = o->y;
    h.w = o->width;
    h.h = o->height;
    h.refresh = o->refresh;
    h.scale = o->scale;
    h.transform = o->transform;
    h.phys_w = o->phys_w;
    h.phys_h = o->phys_h;
    for (wlr_output_mode* m : o->modes) {
      h.modes.push_back({m->width, m->height, m->refresh, m->preferred});
    }
    out.push_back(std::move(h));
  }
  return out;
}

void outputs_manager_push(OasisPrivate* c) {
  if (c->output_mgr == nullptr) return;
  wlr_output_configuration_v1* config = wlr_output_configuration_v1_create();
  if (config == nullptr) return;
  for (OasisOutput* o : c->outputs) {
    wlr_output_configuration_head_v1* head =
        wlr_output_configuration_head_v1_create(config, o->wlr);
    if (head == nullptr) continue;
    head->state.x = o->x;
    head->state.y = o->y;
    head->state.enabled = o->enabled;
    head->state.scale = (float)o->scale;
    head->state.transform = (enum wl_output_transform)o->transform;
  }
  wlr_output_manager_v1_set_configuration(c->output_mgr, config);
}

void outputs_emit(OasisPrivate* c) {
  Oval::List list;
  for (OasisOutput* o : c->outputs) {
    Oval::Map m;
    m["id"] = o->public_id;
    m["name"] = o->name;
    m["desc"] = o->description;
    m["enabled"] = o->enabled;
    m["primary"] = o->primary;
    m["powered"] = o->powered;
    m["x"] = (int64_t)o->x;
    m["y"] = (int64_t)o->y;
    m["w"] = (int64_t)o->width;
    m["h"] = (int64_t)o->height;
    m["scale"] = o->scale;
    m["refresh"] = (int64_t)o->refresh;
    m["transform"] = (int64_t)o->transform;
    m["physW"] = (int64_t)o->phys_w;
    m["physH"] = (int64_t)o->phys_h;
    Oval::List modes;
    for (wlr_output_mode* mo : o->modes) {
      Oval::Map mm;
      mm["w"] = (int64_t)mo->width;
      mm["h"] = (int64_t)mo->height;
      mm["refresh"] = (int64_t)mo->refresh;
      mm["preferred"] = mo->preferred;
      modes.emplace_back(std::move(mm));
    }
    m["modes"] = std::move(modes);
    list.emplace_back(std::move(m));
  }
  OEvent e;
  e["list"] = std::move(list);
  emit(c, "outputs", std::move(e));
}

static std::unordered_set<OasisOutput*> surface_wanted(Surface* s) {
  OasisPrivate* c = s->comp;
  std::unordered_set<OasisOutput*> want;
  if (s->outputs_reported) {
    for (OasisOutput* o : s->outputs) {
      if (o->enabled) want.insert(o);
    }
    return want;
  }
  wlr_output* pinned = nullptr;
  if (s->role == ROLE_LAYER && s->layer != nullptr) {
    pinned = s->layer->output;
  } else if (s->role == ROLE_LOCK && s->lock_surface != nullptr) {
    pinned = s->lock_surface->output;
  }
  OasisOutput* po = output_of(c, pinned);
  if (po != nullptr) {
    if (po->enabled) want.insert(po);
    return want;
  }
  for (OasisOutput* o : c->outputs) {
    if (o->enabled) want.insert(o);
  }
  return want;
}

void surface_sync_outputs(Surface* s) {
  if (s->wlr == nullptr) return;
  auto want = surface_wanted(s);
  for (OasisOutput* o : s->outputs) {
    if (!want.count(o)) wlr_surface_send_leave(s->wlr, o->wlr);
  }
  for (OasisOutput* o : want) {
    if (!s->outputs.count(o)) wlr_surface_send_enter(s->wlr, o->wlr);
  }
  s->outputs = std::move(want);
  double scale = surface_preferred_scale(s);
  if (scale != s->entered_scale) {
    s->entered_scale = scale;
    wlr_fractional_scale_v1_notify_scale(s->wlr, scale);
  }
}

double surface_preferred_scale(Surface* s) {
  double scale = 0;
  for (OasisOutput* o : s->outputs) {
    scale = std::max(scale, o->scale);
  }
  if (scale <= 0) {
    OasisOutput* p = output_primary(s->comp);
    scale = p != nullptr ? p->scale : 1;
  }
  return scale;
}

void output_notify_surfaces(OasisPrivate* c) {
  for (Surface* s : c->surfaces) {
    if (s->announced) surface_sync_outputs(s);
  }
}

static void outputs_reconfigure_locks(OasisPrivate* c) {
  for (Surface* s : c->surfaces) {
    if (s->role != ROLE_LOCK || s->lock_surface == nullptr) continue;
    OasisOutput* o = output_of(c, s->lock_surface->output);
    if (o == nullptr) o = output_primary(c);
    if (o != nullptr && o->enabled) {
      wlr_session_lock_surface_v1_configure(s->lock_surface, o->width,
                                            o->height);
    }
  }
}

static void outputs_changed(OasisPrivate* c, bool client_driven) {
  outputs_relayout(c);
  output_notify_surfaces(c);
  outputs_reconfigure_locks(c);
  outputs_manager_push(c);
  outputs_emit(c);
  if (client_driven) {
    c->host->applyOutputs(outputs_host_report(c));
  }
  comp_flush(c);
}

void outputs_apply_config(OasisPrivate* c, const HostOutput& cfg) {
  auto it = c->output_by_name.find(cfg.name);
  if (it == c->output_by_name.end()) return;
  OasisOutput* o = it->second;
  o->enabled = cfg.enabled;
  if (cfg.w > 0 && cfg.h > 0) {
    o->width = cfg.w;
    o->height = cfg.h;
    if (cfg.refresh > 0) o->refresh = cfg.refresh;
  }
  if (cfg.scale > 0) o->scale = cfg.scale;
  if (cfg.transform >= 0 && cfg.transform <= 7) {
    o->transform = cfg.transform;
  }
  o->x = cfg.x;
  o->y = cfg.y;
  outputs_changed(c, true);
}

// ---- output lifecycle -------------------------------------------------------

static void output_destroyed(wl_listener* listener, void*) {
  OasisOutput* o = wl_container_of(listener, o, destroy);
  OasisPrivate* c = o->comp;
  wlr_output_layout_remove(c->output_layout, o->wlr);
  c->output_by_wlr.erase(o->wlr);
  c->output_by_name.erase(o->name);
  auto& v = c->outputs;
  v.erase(std::remove(v.begin(), v.end(), o), v.end());
  for (Surface* s : c->surfaces) {
    if (!s->outputs.erase(o)) continue;
    if (!c->stopping) surface_sync_outputs(s);
  }
  for (Surface* s : c->surfaces) {
    if (s->layer != nullptr && s->layer->output == o->wlr) {
      s->layer->output = nullptr;
    }
    if (s->lock_surface != nullptr && s->lock_surface->output == o->wlr) {
      s->lock_surface->output = nullptr;
    }
  }
  modes_clear(o);
  wl_list_remove(&o->destroy.link);
  wl_list_remove(&o->needs_frame.link);
  bool was_primary = o->primary;
  delete o;
  if (was_primary) {
    for (OasisOutput* rest : c->outputs) {
      if (rest->enabled) {
        rest->primary = true;
        break;
      }
    }
  }
  if (!c->stopping) {
    output_notify_surfaces(c);
    outputs_manager_push(c);
    outputs_emit(c);
    comp_flush(c);
  }
}

static void output_frame_needed(wl_listener* listener, void*) {
  OasisOutput* o = wl_container_of(listener, o, needs_frame);
  capture_check(o);
}

static OasisOutput* output_track(OasisPrivate* c, wlr_output* wlr) {
  auto* o = new OasisOutput();
  o->comp = c;
  o->wlr = wlr;
  o->public_id = c->next_output_id++;
  o->width = wlr->width > 0 ? wlr->width : 1920;
  o->height = wlr->height > 0 ? wlr->height : 1080;
  o->refresh = wlr->refresh > 0 ? wlr->refresh : 60000;
  c->outputs.push_back(o);
  c->output_by_wlr[wlr] = o;
  o->destroy.notify = output_destroyed;
  wl_signal_add(&wlr->events.destroy, &o->destroy);
  o->needs_frame.notify = output_frame_needed;
  wl_signal_add(&wlr->events.needs_frame, &o->needs_frame);
  return o;
}

static void handle_new_output(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, backend_new_output);
  auto* wlr = static_cast<wlr_output*>(data);
  if (output_of(c, wlr) == nullptr) {
    output_track(c, wlr);
    if (!c->stopping) {
      output_notify_surfaces(c);
      outputs_manager_push(c);
      outputs_emit(c);
      comp_flush(c);
    }
  }
}

static void output_fill(OasisOutput* o, const HostOutput& h) {
  o->name = h.name;
  o->description = h.description;
  o->enabled = h.enabled;
  o->primary = h.primary;
  o->x = h.x;
  o->y = h.y;
  const HostOutputMode* preferred = nullptr;
  for (const auto& m : h.modes) {
    if (m.preferred) {
      preferred = &m;
      break;
    }
  }
  if (h.w > 0 && h.h > 0) {
    o->width = h.w;
    o->height = h.h;
  } else if (preferred != nullptr) {
    o->width = preferred->w;
    o->height = preferred->h;
  }
  if (h.refresh > 0) {
    o->refresh = h.refresh;
  } else if (preferred != nullptr) {
    o->refresh = preferred->refresh;
  }
  if (h.scale > 0) o->scale = h.scale;
  if (h.transform >= 0 && h.transform <= 7) o->transform = h.transform;
  o->phys_w = h.phys_w;
  o->phys_h = h.phys_h;
  if (o->wlr->name == nullptr || strcmp(o->wlr->name, h.name.c_str()) != 0) {
    wlr_output_set_name(o->wlr, h.name.c_str());
  }
  wlr_output_set_description(
      o->wlr, h.description.empty() ? h.name.c_str() : h.description.c_str());
}

void outputs_sync_host(OasisPrivate* c) {
  auto want = c->host->outputs();
  if (want.empty()) {
    HostOutput fallback;
    fallback.name = "oasis-embedded";
    fallback.description = "Oasis embedded output";
    fallback.primary = true;
    fallback.w = 1920;
    fallback.h = 1080;
    want.push_back(std::move(fallback));
  }
  bool any_primary = false;
  for (const auto& h : want) any_primary |= h.primary;
  if (!any_primary) want.front().primary = true;

  std::unordered_set<std::string> keep;
  for (const HostOutput& h : want) {
    if (h.name.empty()) continue;
    keep.insert(h.name);
    OasisOutput* o = nullptr;
    bool created = false;
    auto it = c->output_by_name.find(h.name);
    if (it != c->output_by_name.end()) {
      o = it->second;
    } else {
      wlr_output* wlr = wlr_headless_add_output(
          c->backend, h.w > 0 ? (unsigned)h.w : 1920,
          h.h > 0 ? (unsigned)h.h : 1080);
      if (wlr == nullptr) continue;
      o = output_of(c, wlr);
      if (o == nullptr) o = output_track(c, wlr);
      wlr_output_init_render(o->wlr, c->allocator, c->renderer);
      created = true;
    }
    bool modes_stale = !modes_equal(o, h.modes);
    output_fill(o, h);
    c->output_by_name[o->name] = o;
    if (modes_stale) {
      modes_clear(o);
      for (const HostOutputMode& m : h.modes) {
        mode_add(o, m.w, m.h, m.refresh, m.preferred);
      }
      if (o->modes.empty()) {
        mode_add(o, o->width, o->height, o->refresh, true);
      }
    }
    if (created) wlr_output_create_global(o->wlr, c->display);
  }
  std::vector<OasisOutput*> dead;
  for (OasisOutput* o : c->outputs) {
    if (!keep.count(o->name)) dead.push_back(o);
  }
  for (OasisOutput* o : dead) {
    wlr_output_destroy(o->wlr);
  }
  bool primary_ok = false;
  for (OasisOutput* o : c->outputs) {
    if (o->enabled && o->primary) primary_ok = true;
  }
  if (!primary_ok) {
    OasisOutput* p = output_primary(c);
    if (p != nullptr) p->primary = true;
  }
  outputs_changed(c, false);
}

// ---- zwlr_output_manager_v1 ---------------------------------------------------

static void output_config_apply(OasisPrivate* c,
                              wlr_output_configuration_v1* config,
                              bool apply) {
  if (!apply) {
    wlr_output_configuration_v1_send_succeeded(config);
    return;
  }
  wlr_output_configuration_head_v1* head;
  wl_list_for_each(head, &config->heads, link) {
    OasisOutput* o = output_of(c, head->state.output);
    if (o == nullptr) continue;
    const auto& st = head->state;
    o->enabled = st.enabled;
    if (st.enabled) {
      if (st.mode != nullptr) {
        o->width = st.mode->width;
        o->height = st.mode->height;
        o->refresh = st.mode->refresh;
      } else if (st.custom_mode.width > 0 && st.custom_mode.height > 0) {
        o->width = st.custom_mode.width;
        o->height = st.custom_mode.height;
        if (st.custom_mode.refresh > 0) {
          o->refresh = st.custom_mode.refresh;
        }
      }
      o->x = st.x;
      o->y = st.y;
      if (st.scale > 0) o->scale = st.scale;
      o->transform = (int32_t)st.transform;
    }
  }
  wlr_output_configuration_v1_send_succeeded(config);
  outputs_changed(c, true);
}

static void handle_output_config_apply(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, output_config_apply);
  output_config_apply(c, static_cast<wlr_output_configuration_v1*>(data),
                      true);
}

static void handle_output_config_test(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, output_config_test);
  output_config_apply(c, static_cast<wlr_output_configuration_v1*>(data),
                      false);
}

void outputs_init(OasisPrivate* c) {
  c->output_layout = wlr_output_layout_create(c->display);
  c->output_mgr = wlr_output_manager_v1_create(c->display);
  c->backend_new_output.notify = handle_new_output;
  wl_signal_add(&c->backend->events.new_output, &c->backend_new_output);
  if (c->output_mgr != nullptr) {
    c->output_config_apply.notify = handle_output_config_apply;
    wl_signal_add(&c->output_mgr->events.apply, &c->output_config_apply);
    c->output_config_test.notify = handle_output_config_test;
    wl_signal_add(&c->output_mgr->events.test, &c->output_config_test);
  }
  wlr_backend_start(c->backend);
  c->outputs_inited = true;
}

void outputs_finish(OasisPrivate* c) {
  if (!c->outputs_inited) return;
  c->outputs_inited = false;
  wl_list_remove(&c->backend_new_output.link);
  wl_list_init(&c->backend_new_output.link);
  if (c->output_mgr != nullptr) {
    wl_list_remove(&c->output_config_apply.link);
    wl_list_remove(&c->output_config_test.link);
    wl_list_init(&c->output_config_apply.link);
    wl_list_init(&c->output_config_test.link);
  }
  while (!c->outputs.empty()) {
    wlr_output_destroy(c->outputs.front()->wlr);
  }
  if (c->output_layout != nullptr) {
    wlr_output_layout_destroy(c->output_layout);
    c->output_layout = nullptr;
  }
  c->output_mgr = nullptr;
}

}  // namespace oasis
