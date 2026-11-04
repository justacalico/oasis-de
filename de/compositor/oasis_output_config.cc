#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <cstring>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

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

void outputs_changed(OasisPrivate* c, bool client_driven) {
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

void outputs_sync_host(OasisPrivate* c) {
  // The host can report output changes before the compositor starts.
  if (c->backend == nullptr) return;
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
  int unnamed = 0;
  for (const HostOutput& h : want) {
    HostOutput host = h;
    // A nameless host output must still become a wl_output; clients
    // like Qt fall back to a placeholder screen when none exist.
    if (host.name.empty()) {
      host.name = "oasis-" + std::to_string(++unnamed);
    }
    keep.insert(host.name);
    OasisOutput* o = nullptr;
    bool created = false;
    auto it = c->output_by_name.find(host.name);
    if (it != c->output_by_name.end() && it->second->name == host.name) {
      o = it->second;
    } else {
      wlr_output* wlr = wlr_headless_add_output(
          c->backend, host.w > 0 ? (unsigned)host.w : 1920,
          host.h > 0 ? (unsigned)host.h : 1080);
      if (wlr == nullptr) continue;
      o = output_of(c, wlr);
      if (o == nullptr) o = output_track(c, wlr);
      wlr_output_init_render(o->wlr, c->allocator, c->renderer);
      created = true;
    }
    bool modes_stale = !modes_equal(o, host.modes);
    output_fill(o, host);
    c->output_by_name[o->name] = o;
    if (modes_stale) {
      modes_clear(o);
      for (const HostOutputMode& m : host.modes) {
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

void output_manager_init(OasisPrivate* c) {
  if (c->output_mgr == nullptr) return;
  c->output_config_apply.notify = handle_output_config_apply;
  wl_signal_add(&c->output_mgr->events.apply, &c->output_config_apply);
  c->output_config_test.notify = handle_output_config_test;
  wl_signal_add(&c->output_mgr->events.test, &c->output_config_test);
}

}  // namespace oasis
