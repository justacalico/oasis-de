#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include <cstdlib>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

static xkb_keymap* compile_keymap(xkb_context* ctx,
                                  const xkb_rule_names* names) {
#ifdef OASIS_XKB_NAMES2
  // libxkbcommon 1.11+ compiles to the extended v2 text format by default;
  // its serialization marks some virtual modifiers with explicit bindings
  // ("Hyper=0x4000,ScrollLock=0x8000") that Xwayland's xkbcomp rejects as
  // multiply defined. Compiling in v1 keeps the keymap served to Wayland
  // clients and Xwayland in the classic format.
  return xkb_keymap_new_from_names2(ctx, names, XKB_KEYMAP_FORMAT_TEXT_V1,
                                    XKB_KEYMAP_COMPILE_NO_FLAGS);
#else
  return xkb_keymap_new_from_names(ctx, names, XKB_KEYMAP_COMPILE_NO_FLAGS);
#endif
}

void build_keymap(OasisPrivate* c) {
  c->xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (c->xkb_ctx == nullptr) return;
  xkb_rule_names names = {};
  c->kmap = compile_keymap(c->xkb_ctx, &names);
  if (c->kmap == nullptr) {
    xkb_rule_names fallback = {"evdev", "pc105", "us", "", ""};
    c->kmap = compile_keymap(c->xkb_ctx, &fallback);
  }
}

void send_modifiers(OasisPrivate* c) {
  if (c->vkb == nullptr) return;
  wlr_seat_keyboard_notify_modifiers(c->seat, &c->vkb->modifiers);
}

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

void keyboard_init(OasisPrivate* c) {
  c->vkb = static_cast<wlr_keyboard*>(calloc(1, sizeof(wlr_keyboard)));
  wlr_keyboard_init(c->vkb, &vkb_impl, "oasis-virtual");
  if (c->kmap != nullptr) {
    wlr_keyboard_set_keymap(c->vkb, c->kmap);
  }
  wlr_keyboard_set_repeat_info(c->vkb, 25, 600);
  wlr_seat_set_keyboard(c->seat, c->vkb);
  c->kb_key.notify = handle_kb_key;
  wl_signal_add(&c->vkb->events.key, &c->kb_key);
  c->kb_mods.notify = handle_kb_mods;
  wl_signal_add(&c->vkb->events.modifiers, &c->kb_mods);
}

void keyboard_finish(OasisPrivate* c) {
  if (c->vkb != nullptr) {
    wl_list_remove(&c->kb_key.link);
    wl_list_remove(&c->kb_mods.link);
    wlr_keyboard_finish(c->vkb);
    free(c->vkb);
    c->vkb = nullptr;
  }
  if (c->kstate != nullptr) {
    xkb_state_unref(c->kstate);
    c->kstate = nullptr;
  }
  if (c->kmap != nullptr) {
    xkb_keymap_unref(c->kmap);
    c->kmap = nullptr;
  }
  if (c->xkb_ctx != nullptr) {
    xkb_context_unref(c->xkb_ctx);
    c->xkb_ctx = nullptr;
  }
}

}  // namespace oasis
