#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <time.h>
#include <wayland-server.h>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

// wp_presentation_feedback "kind" bit advertised when the timestamp comes
// from a real vblank rather than an estimate.
static constexpr uint32_t kPresentVsync = 0x1;

void send_frame_done(Surface* s, const timespec& ts, bool vsync) {
  s->frame_pending = false;
  if (s->comp->pending_frames > 0) s->comp->pending_frames--;
  wlr_surface* wlr = s->wlr;
  if (wlr == nullptr) return;
  wlr_surface_send_frame_done(wlr, &ts);
  wlr_presentation_feedback* fb = wlr_presentation_surface_sampled(wlr);
  if (fb != nullptr) {
    OasisOutput* o = output_for_surface(s);
    wlr_presentation_event ev = {};
    ev.output = o != nullptr ? o->wlr : nullptr;
    ev.tv_sec = (uint64_t)ts.tv_sec;
    ev.tv_nsec = (uint32_t)ts.tv_nsec;
    ev.refresh =
        o != nullptr && o->refresh > 0 ? (uint32_t)(1000000000000ULL / o->refresh)
                                     : 16666666;
    ev.flags = vsync ? kPresentVsync : 0;
    wlr_presentation_feedback_send_presented(fb, &ev);
    wlr_presentation_feedback_destroy(fb);
  }
}

void frames_presented(OasisPrivate* c, const timespec& ts, bool vsync) {
  if (c->pending_frames <= 0) return;
  for (Surface* s : c->surfaces) {
    if (s->frame_pending) send_frame_done(s, ts, vsync);
  }
  wl_display_flush_clients(c->display);
}

// When the host stops painting (minimized shell, blank screen, stalled
// driver) clients still need frame callbacks or they wedge. Flush strays
// after a couple of missed frames.
static constexpr int kFrameFallbackMs = 40;

static int frame_fallback_cb(void* data) {
  auto* c = static_cast<OasisPrivate*>(data);
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  frames_presented(c, ts, false);
  if (c->pending_frames > 0) {
    wl_event_source_timer_update(c->frame_fallback, kFrameFallbackMs);
  }
  return 0;
}

void frame_pending_add(Surface* s) {
  OasisPrivate* c = s->comp;
  if (s->frame_pending) return;
  s->frame_pending = true;
  c->pending_frames++;
  if (c->frame_fallback == nullptr) {
    c->frame_fallback =
        wl_event_loop_add_timer(c->loop, frame_fallback_cb, c);
  }
  if (c->frame_fallback != nullptr) {
    wl_event_source_timer_update(c->frame_fallback, kFrameFallbackMs);
  }
}

}  // namespace oasis
