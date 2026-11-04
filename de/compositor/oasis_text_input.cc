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

void text_input_init(OasisPrivate* c) {
  c->new_text_input.notify = handle_new_text_input;
  wl_signal_add(&c->text_input_mgr->events.new_text_input,
                &c->new_text_input);
}

}  // namespace oasis
