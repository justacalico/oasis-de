#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <algorithm>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

static void inhibitor_destroyed(wl_listener* listener, void* data) {
  Inhibitor* inh = wl_container_of(listener, inh, destroy);
  Surface* s = inh->surface;
  auto& v = s->inhibitors;
  v.erase(std::remove(v.begin(), v.end(), inh), v.end());
  wl_list_remove(&inh->destroy.link);
  delete inh;
  s->comp->active_inhibitors--;
  idle_resync_inhibit(s->comp);
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
  c->active_inhibitors++;
  idle_resync_inhibit(c);
  if (s->inhibitors.size() == 1 && s->announced) {
    OEvent m;
    m["on"] = true;
    emit_id(s, "idleInhibit", std::move(m));
  }
}

static void ksi_destroyed(wl_listener* listener, void*) {
  KsInhibitor* k = wl_container_of(listener, k, destroy);
  Surface* s = k->surface;
  auto& v = s->ks_inhibitors;
  v.erase(std::remove(v.begin(), v.end(), k), v.end());
  wl_list_remove(&k->destroy.link);
  if (k->inh->active && s->announced) {
    OEvent m;
    m["on"] = false;
    emit_id(s, "shortcutsInhibit", std::move(m));
  }
  delete k;
}

static void handle_new_ksi(wl_listener* listener, void* data) {
  OasisPrivate* c = wl_container_of(listener, c, new_ksi);
  auto* wlr_inh = static_cast<wlr_keyboard_shortcuts_inhibitor_v1*>(data);
  Surface* s = surface_of(c, wlr_inh->surface);
  if (s == nullptr) return;
  auto* k = new KsInhibitor();
  k->inh = wlr_inh;
  k->surface = s;
  k->destroy.notify = ksi_destroyed;
  wl_signal_add(&wlr_inh->events.destroy, &k->destroy);
  s->ks_inhibitors.push_back(k);
  ksi_sync(s);
}

void inhibit_init(OasisPrivate* c) {
  c->new_inhibitor.notify = handle_new_inhibitor;
  wl_signal_add(&c->inhibit_mgr->events.new_inhibitor, &c->new_inhibitor);
  c->new_ksi.notify = handle_new_ksi;
  wl_signal_add(&c->ksi_mgr->events.new_inhibitor, &c->new_ksi);
}

}  // namespace oasis
