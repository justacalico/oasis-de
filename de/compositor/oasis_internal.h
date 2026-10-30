#ifndef OASIS_INTERNAL_H_
#define OASIS_INTERNAL_H_

#include <wayland-server-core.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include <array>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "oasis_core.h"

struct wlr_backend;
struct wlr_renderer;
struct wlr_allocator;
struct wlr_compositor;
struct wlr_subcompositor;
struct wlr_xdg_shell;
struct wlr_seat;
struct wlr_output;
struct wlr_surface;
struct wlr_xdg_surface;
struct wlr_xdg_toplevel;
struct wlr_xdg_popup;
struct wlr_xwayland;
struct wlr_xwayland_surface;
struct wlr_data_device_manager;
struct wlr_linux_dmabuf_v1;
struct wlr_viewporter;
struct wlr_fractional_scale_manager_v1;
struct wlr_idle_inhibit_manager_v1;
struct wlr_idle_inhibitor_v1;
struct wlr_cursor_shape_manager_v1;
struct wlr_presentation;
struct wlr_xdg_activation_v1;
struct wlr_text_input_manager_v3;
struct wlr_text_input_v3;
struct wlr_xdg_decoration_manager_v1;
struct wlr_xdg_toplevel_decoration_v1;
struct wlr_primary_selection_v1_device_manager;
struct wlr_keyboard;
struct wlr_data_source;
struct wlr_buffer;
struct wlr_subsurface;

namespace oasis {

enum Role { ROLE_NONE, ROLE_TOPLEVEL, ROLE_POPUP, ROLE_SUBSURFACE, ROLE_CURSOR };

struct Inhibitor {
  wl_listener destroy = {};
  wlr_idle_inhibitor_v1* inh = nullptr;
  struct Surface* surface = nullptr;
};

struct Surface {
  OasisPrivate* comp = nullptr;
  wlr_surface* wlr = nullptr;
  int64_t public_id = 0;
  Role role = ROLE_NONE;
  bool announced = false;

  wlr_xdg_surface* xdg = nullptr;
  wlr_xwayland_surface* xsurface = nullptr;
  Surface* parent = nullptr;
  Surface* tl_parent = nullptr;

  wl_listener commit = {};
  wl_listener destroy = {};
  wl_listener map = {};
  wl_listener unmap = {};
  wl_listener new_sub = {};
  wl_listener xdg_destroy = {};
  wl_listener xdg_ack = {};
  wl_listener xdg_new_popup = {};
  wl_listener xdg_ping_timeout = {};
  wl_listener popup_reposition = {};
  wl_listener popup_destroy = {};
  wl_listener tl_parent_set = {};
  wl_listener tl_title = {};
  wl_listener tl_app_id = {};
  wl_listener tl_move = {};
  wl_listener tl_resize = {};
  wl_listener tl_max = {};
  wl_listener tl_fs = {};
  wl_listener tl_min = {};
  wl_listener tl_menu = {};
  wl_listener tl_destroy = {};
  wl_listener xs_destroy = {};
  wl_listener xs_associate = {};
  wl_listener xs_dissociate = {};
  wl_listener xs_title = {};
  wl_listener xs_class = {};
  wl_listener xs_parent = {};
  wl_listener xs_request_configure = {};
  wl_listener xs_request_activate = {};
  wl_listener xs_request_move = {};
  wl_listener xs_request_resize = {};
  wl_listener xs_request_minimize = {};
  wl_listener xs_request_maximize = {};
  wl_listener xs_request_fullscreen = {};
  wl_listener xs_request_close = {};

  int tex_kind = 0;
  int64_t texture_id = -1;
  std::unique_ptr<uint8_t[]> img;
  int iw = 0, ih = 0;

  int sx = 0, sy = 0;
  int rep_sx = 0, rep_sy = 0;
  std::vector<int64_t> child_order;
  std::vector<std::array<int32_t, 4>> input_rects;
  bool input_null = true;
  bool input_reported = false;
  bool reported_inhibit = false;
  std::vector<Inhibitor*> inhibitors;

  int rep_w = 0, rep_h = -1, rep_bw = -1, rep_bh = -1;
  int rep_gx = 0, rep_gy = 0;
  double rep_vsw = -1, rep_vsh = -1;
  double rep_vsx = 0, rep_vsy = 0;
  int rep_scale = 0, rep_transform = -1;

  int rep_min_w = -1, rep_min_h = -1, rep_max_w = -1, rep_max_h = -1;
  bool cfg_sent = false;
  wlr_xdg_toplevel_decoration_v1* deco = nullptr;
  wl_listener deco_destroy = {};
  int cfg_w = 0, cfg_h = 0;
  bool cfg_max = false, cfg_fs = false, cfg_resizing = false;
  std::string title, app_id;
  pid_t pid = -1;
};

struct KillCheck {
  OasisPrivate* comp = nullptr;
  int64_t id = 0;
  int sig = 0;
  wl_event_source* timer = nullptr;
};

struct TextInputCtx {
  wlr_text_input_v3* ti = nullptr;
  OasisPrivate* comp = nullptr;
  wl_listener commit = {};
  wl_listener destroy = {};
};

struct HostSource {
  wlr_data_source* source = nullptr;
  OasisPrivate* comp = nullptr;
  wl_listener destroy = {};
};

struct OasisPrivate {
  OasisHost* host = nullptr;
  wl_display* display = nullptr;
  wl_event_loop* loop = nullptr;
  char* socket_name = nullptr;

  wlr_backend* backend = nullptr;
  wlr_renderer* renderer = nullptr;
  wlr_allocator* allocator = nullptr;
  wlr_compositor* compositor = nullptr;
  wlr_subcompositor* subcompositor = nullptr;
  wlr_xdg_shell* xdg_shell = nullptr;
  wlr_seat* seat = nullptr;
  wlr_output* output = nullptr;
  wlr_xwayland* xwayland = nullptr;
  wlr_presentation* presentation = nullptr;
  wlr_xdg_activation_v1* activation = nullptr;
  wlr_text_input_manager_v3* text_input_mgr = nullptr;
  wlr_xdg_decoration_manager_v1* deco_mgr = nullptr;
  wlr_cursor_shape_manager_v1* cursor_shape_mgr = nullptr;
  wlr_idle_inhibit_manager_v1* inhibit_mgr = nullptr;
  wlr_fractional_scale_manager_v1* fs_mgr = nullptr;
  wlr_viewporter* viewporter = nullptr;
  wlr_linux_dmabuf_v1* dmabuf_v1 = nullptr;
  wlr_data_device_manager* data_device_mgr = nullptr;
  wlr_primary_selection_v1_device_manager* primary_mgr = nullptr;

  wlr_keyboard* vkb = nullptr;
  xkb_context* xkb_ctx = nullptr;
  xkb_keymap* xkb_keymap = nullptr;
  xkb_state* xkb_state = nullptr;

  wl_listener new_surface = {};
  wl_listener new_toplevel = {};
  wl_listener new_popup = {};
  wl_listener xwayland_ready = {};
  wl_listener xwayland_new_surface = {};
  wl_listener xwayland_destroy = {};
  wl_listener seat_set_cursor = {};
  wl_listener seat_set_selection = {};
  wl_listener seat_set_primary = {};
  wl_listener seat_start_drag = {};
  wl_listener request_activate = {};
  wl_listener new_text_input = {};
  wl_listener new_decoration = {};
  wl_listener request_shape = {};
  wl_listener new_inhibitor = {};
  wl_listener kb_key = {};
  wl_listener kb_mods = {};

  std::vector<Surface*> surfaces;
  std::unordered_map<int64_t, Surface*> by_id;
  std::unordered_map<wlr_surface*, Surface*> by_wlr;
  std::unordered_map<wlr_xwayland_surface*, Surface*> by_xsurface;
  std::vector<TextInputCtx*> text_inputs;
  int64_t next_id = 1;
  Surface* kb_focus = nullptr;
  Surface* activated = nullptr;
  Surface* ptr_focus = nullptr;
  Surface* cursor_surface = nullptr;
  int cursor_hx = 0, cursor_hy = 0;
  uint32_t last_button_serial = 0;
  std::set<uint32_t> pressed;
  int32_t touch_id = -1;

  int out_w = 1920, out_h = 1080, out_scale = 1;
  int phys_w = 340, phys_h = 190;

  wl_event_source* ping_timer = nullptr;
  std::vector<KillCheck*> kill_checks;

  HostSource* host_source = nullptr;
  std::vector<std::string> host_mimes;
  std::string xwayland_display;
  bool stopping = false;
};

Surface* surface_of(OasisPrivate* c, wlr_surface* wlr);
Surface* surface_by_id(OasisPrivate* c, int64_t id);
void emit(OasisPrivate* c, const char* name, OEvent fields = {});
void emit_id(Surface* s, const char* name, OEvent fields = {});
void emit_size(Surface* s);
void emit_cursor(OasisPrivate* c);
void free_surface(Surface* s);
void remove_listeners(Surface* s);
void announce_toplevel(Surface* s);
void send_frame_done(Surface* s);
void sync_text_input_focus(OasisPrivate* c);
void seat_focus(OasisPrivate* c, Surface* s);
void toplevel_configure(Surface* s, int w, int h, bool maximized, bool active,
                        bool fullscreen, bool resizing);
void popup_position(Surface* s, int* x, int* y);
void mirror_selection_to_host(OasisPrivate* c, wlr_data_source* source);
void install_host_source(OasisPrivate* c);
void surface_new(OasisPrivate* c, wlr_surface* wlr);
void init_surface_listeners(Surface* s);
void attach_wlr(Surface* s, wlr_surface* wlr);
void toplevel_new(OasisPrivate* c, wlr_xdg_toplevel* toplevel);
void popup_new(OasisPrivate* c, wlr_xdg_popup* popup);
void xwayland_new_surface(OasisPrivate* c, wlr_xwayland_surface* xsurface);
uint32_t now_ms();
void build_keymap(OasisPrivate* c);
void send_modifiers(OasisPrivate* c);
void comp_flush(OasisPrivate* c);

}  // namespace oasis

#endif
