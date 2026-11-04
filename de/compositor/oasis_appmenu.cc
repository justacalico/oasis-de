#include <wayland-server.h>

#include <algorithm>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

#include "appmenu-protocol.h"

namespace oasis {

static void appmenu_apply(Surface* s) {
  std::string service;
  std::string path;
  for (AppMenuLink* l : s->appmenus) {
    if (l->set) {
      service = l->service;
      path = l->path;
    }
  }
  if (service == s->menu_service && path == s->menu_path) return;
  s->menu_service = service;
  s->menu_path = path;
  if (!s->announced) return;
  OEvent m;
  m["service"] = service;
  m["path"] = path;
  emit_id(s, "appMenu", std::move(m));
}

static void appmenu_destroyed(wl_resource* res) {
  auto* link = static_cast<AppMenuLink*>(wl_resource_get_user_data(res));
  if (link == nullptr) return;
  Surface* s = link->surface;
  if (s != nullptr) {
    auto& v = s->appmenus;
    v.erase(std::remove(v.begin(), v.end(), link), v.end());
    appmenu_apply(s);
  }
  delete link;
}

static void appmenu_set_address(wl_client*, wl_resource* res,
                                const char* service_name,
                                const char* object_path) {
  auto* link = static_cast<AppMenuLink*>(wl_resource_get_user_data(res));
  if (link == nullptr || link->surface == nullptr) return;
  link->set = true;
  link->service = service_name != nullptr ? service_name : "";
  link->path = object_path != nullptr ? object_path : "";
  Surface* s = link->surface;
  auto& v = s->appmenus;
  v.erase(std::remove(v.begin(), v.end(), link), v.end());
  v.push_back(link);
  appmenu_apply(s);
}

static void appmenu_release(wl_client*, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct org_kde_kwin_appmenu_interface appmenu_impl = {
    .set_address = appmenu_set_address,
    .release = appmenu_release,
};

static void manager_create(wl_client* client, wl_resource* resource,
                           uint32_t id, wl_resource* surface_res) {
  auto* c = static_cast<OasisPrivate*>(wl_resource_get_user_data(resource));
  Surface* s =
      surface_of(c, wlr_surface_from_resource(surface_res));
  if (s == nullptr) {
    wl_resource_post_error(resource, 0, "unknown surface");
    return;
  }
  uint32_t version = wl_resource_get_version(resource);
  wl_resource* res = wl_resource_create(
      client, &org_kde_kwin_appmenu_interface, version, id);
  if (res == nullptr) {
    wl_client_post_no_memory(client);
    return;
  }
  auto* link = new AppMenuLink();
  link->surface = s;
  s->appmenus.push_back(link);
  wl_resource_set_implementation(res, &appmenu_impl, link,
                                 appmenu_destroyed);
}

static void manager_release(wl_client*, wl_resource* res) {
  wl_resource_destroy(res);
}

static const struct org_kde_kwin_appmenu_manager_interface manager_impl = {
    .create = manager_create,
    .release = manager_release,
};

static void manager_bind(wl_client* client, void* data, uint32_t version,
                         uint32_t id) {
  auto* c = static_cast<OasisPrivate*>(data);
  wl_resource* res = wl_resource_create(
      client, &org_kde_kwin_appmenu_manager_interface,
      version < 2 ? version : 2, id);
  if (res == nullptr) {
    wl_client_post_no_memory(client);
    return;
  }
  wl_resource_set_implementation(res, &manager_impl, c, nullptr);
}

void appmenu_init(OasisPrivate* c) {
  wl_global_create(c->display, &org_kde_kwin_appmenu_manager_interface, 2,
                   c, manager_bind);
}

}  // namespace oasis
