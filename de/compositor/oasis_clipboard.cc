#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <unistd.h>
#include <wayland-server.h>

#include <cstring>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

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

}  // namespace oasis
