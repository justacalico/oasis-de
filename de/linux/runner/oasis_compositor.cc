#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "oasis_compositor.h"
#include "oasis_textures.h"

#include <unistd.h>

#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include <gtk/gtk.h>

#include "oasis_core.h"

struct _OasisCompositor {
  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  GtkWidget* view = nullptr;
  gboolean listening = FALSE;
  OasisCore* core = nullptr;
  GIOChannel* watch_channel = nullptr;
  guint watch = 0;
  guint resize_idle = 0;
  std::unordered_map<int64_t, FlTexture*> textures;
};

static FlValue* oval_to_fl(const Oval& v) {
  if (std::holds_alternative<int64_t>(v.v)) {
    return fl_value_new_int(std::get<int64_t>(v.v));
  }
  if (std::holds_alternative<double>(v.v)) {
    return fl_value_new_float(std::get<double>(v.v));
  }
  if (std::holds_alternative<bool>(v.v)) {
    return fl_value_new_bool(std::get<bool>(v.v));
  }
  if (std::holds_alternative<std::string>(v.v)) {
    return fl_value_new_string(std::get<std::string>(v.v).c_str());
  }
  if (std::holds_alternative<Oval::List>(v.v)) {
    FlValue* l = fl_value_new_list();
    for (const auto& e : std::get<Oval::List>(v.v)) {
      fl_value_append_take(l, oval_to_fl(e));
    }
    return l;
  }
  if (std::holds_alternative<Oval::Map>(v.v)) {
    FlValue* m = fl_value_new_map();
    for (const auto& kv : std::get<Oval::Map>(v.v)) {
      fl_value_set_string_take(m, kv.first.c_str(), oval_to_fl(kv.second));
    }
    return m;
  }
  return fl_value_new_null();
}

class GtkHost : public OasisHost {
 public:
  explicit GtkHost(_OasisCompositor* c) : c_(c) {}

  void sendEvent(OEvent fields) override {
    if (!c_->listening || c_->event_channel == nullptr) return;
    FlValue* m = fl_value_new_map();
    for (auto& kv : fields) {
      fl_value_set_string_take(m, kv.first.c_str(),
                               oval_to_fl(kv.second));
    }
    fl_event_channel_send(c_->event_channel, m, nullptr, nullptr);
    fl_value_unref(m);
  }

  int64_t createTexture(bool dmabuf) override {
    FlTexture* tex;
    if (dmabuf) {
      tex = FL_TEXTURE(
          g_object_new(oasis_gl_texture_get_type(), nullptr));
    } else {
      tex =
          FL_TEXTURE(g_object_new(oasis_texture_get_type(), nullptr));
    }
    fl_texture_registrar_register_texture(c_->texture_registrar, tex);
    int64_t id = fl_texture_get_id(tex);
    c_->textures[id] = tex;
    return id;
  }

  void pushPixels(int64_t id, const uint8_t* rgba, int w, int h) override {
    auto it = c_->textures.find(id);
    if (it == c_->textures.end()) return;
    oasis_texture_push(OASIS_TEXTURE(it->second), rgba,
                       (uint32_t)w, (uint32_t)h);
  }

  void pushDmabuf(int64_t id, const DmabufInfo& buf) override {
    auto it = c_->textures.find(id);
    if (it == c_->textures.end()) return;
    oasis_gl_texture_set_dmabuf(OASIS_GL_TEXTURE(it->second), buf);
  }

  void frameAvailable(int64_t id) override {
    auto it = c_->textures.find(id);
    if (it == c_->textures.end()) return;
    fl_texture_registrar_mark_texture_frame_available(
        c_->texture_registrar, it->second);
  }

  void destroyTexture(int64_t id) override {
    auto it = c_->textures.find(id);
    if (it == c_->textures.end()) return;
    fl_texture_registrar_unregister_texture(c_->texture_registrar,
                                            it->second);
    g_object_unref(it->second);
    c_->textures.erase(it);
  }

  void outputMetrics(int& w, int& h, int& scale, int& phys_w,
                     int& phys_h) override {
    scale = 1;
    w = 1280;
    h = 720;
    phys_w = 340;
    phys_h = 190;
    if (c_->view == nullptr) return;
    scale = gtk_widget_get_scale_factor(c_->view);
    w = gtk_widget_get_allocated_width(c_->view) * scale;
    h = gtk_widget_get_allocated_height(c_->view) * scale;
    if (gtk_widget_get_window(c_->view) != nullptr) {
      GdkDisplay* dpy = gtk_widget_get_display(c_->view);
      GdkMonitor* mon = gdk_display_get_monitor_at_window(
          dpy, gtk_widget_get_window(c_->view));
      if (mon != nullptr) {
        phys_w = gdk_monitor_get_width_mm(mon);
        phys_h = gdk_monitor_get_height_mm(mon);
      }
    }
  }

  std::vector<std::string> hostClipboardMimes() override {
    std::vector<std::string> out;
    GtkClipboard* cb = gtk_clipboard_get_for_display(
        gdk_display_get_default(), GDK_SELECTION_CLIPBOARD);
    GdkAtom* atoms = nullptr;
    gint n = 0;
    if (!gtk_clipboard_wait_for_targets(cb, &atoms, &n)) return out;
    for (gint i = 0; i < n; i++) {
      gchar* name = gdk_atom_name(atoms[i]);
      if (g_strcmp0(name, "UTF8_STRING") == 0) {
        out.emplace_back("text/plain;charset=utf-8");
      } else if (g_strcmp0(name, "TEXT") == 0 ||
                 g_strcmp0(name, "STRING") == 0) {
        out.emplace_back("text/plain");
      } else if (name != nullptr &&
                 (g_str_has_prefix(name, "text/") ||
                  g_str_has_prefix(name, "image/") ||
                  g_str_has_prefix(name, "application/"))) {
        out.emplace_back(name);
      }
      g_free(name);
    }
    g_free(atoms);
    return out;
  }

  void hostClipboardRead(
      const std::string& mime,
      std::function<void(const uint8_t*, size_t)> done) override {
    GtkClipboard* cb = gtk_clipboard_get_for_display(
        gdk_display_get_default(), GDK_SELECTION_CLIPBOARD);
    GdkAtom atom;
    if (mime == "text/plain;charset=utf-8") {
      atom = gdk_atom_intern_static_string("UTF8_STRING");
    } else {
      atom = gdk_atom_intern(mime.c_str(), FALSE);
    }
    auto* cb_copy =
        new std::function<void(const uint8_t*, size_t)>(std::move(done));
    gtk_clipboard_request_contents(
        cb, atom,
        [](GtkClipboard*, GtkSelectionData* sel, gpointer data) {
          auto* fn =
              static_cast<std::function<void(const uint8_t*, size_t)>*>(
                  data);
          const guint8* bytes = gtk_selection_data_get_data(sel);
          gint len = gtk_selection_data_get_length(sel);
          (*fn)(bytes, len > 0 ? (size_t)len : 0);
          delete fn;
        },
        cb_copy);
  }

  void hostClipboardWriteText(const std::string& text) override {
    GtkClipboard* cb = gtk_clipboard_get_for_display(
        gdk_display_get_default(), GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_text(cb, text.c_str(), -1);
  }

 private:
  _OasisCompositor* c_;
};

static gboolean watch_cb(GIOChannel*, GIOCondition cond, gpointer data) {
  auto* c = static_cast<_OasisCompositor*>(data);
  if (cond & (G_IO_ERR | G_IO_HUP)) return G_SOURCE_REMOVE;
  c->core->dispatch();
  return G_SOURCE_CONTINUE;
}

static gboolean view_resized_idle(gpointer data) {
  auto* c = static_cast<_OasisCompositor*>(data);
  c->resize_idle = 0;
  c->core->outputChanged();
  return G_SOURCE_REMOVE;
}

static void view_resized(GtkWidget*, GdkRectangle*, _OasisCompositor* c) {
  if (c->resize_idle == 0) {
    c->resize_idle = g_idle_add(view_resized_idle, c);
  }
}

static void launch_reap(GPid pid, gint, gpointer) { g_spawn_close_pid(pid); }

static void spawn_child(gchar** argv, gchar** env) {
  g_autoptr(GError) err = nullptr;
  GPid pid = 0;
  if (!g_spawn_async(g_get_home_dir(), argv, env,
                     static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH |
                                              G_SPAWN_DO_NOT_REAP_CHILD),
                     nullptr, nullptr, &pid, &err)) {
    g_warning("oasis: failed to launch %s: %s", argv[0],
              err != nullptr ? err->message : "unknown error");
    return;
  }
  g_child_watch_add(pid, launch_reap, nullptr);
}

static void launch_app(_OasisCompositor* c, FlValue* args) {
  if (c->core->socketName() == nullptr) return;
  FlValue* list = fl_value_lookup_string(args, "argv");
  if (list == nullptr || fl_value_get_type(list) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(list) == 0) {
    return;
  }
  g_autoptr(GPtrArray) argv = g_ptr_array_new();
  for (size_t i = 0; i < fl_value_get_length(list); i++) {
    FlValue* v = fl_value_get_list_value(list, i);
    if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
      g_ptr_array_add(argv, const_cast<char*>(fl_value_get_string(v)));
    }
  }
  if (argv->len == 0) return;
  g_ptr_array_add(argv, nullptr);
  g_auto(GStrv) env = g_get_environ();
  env = g_environ_unsetenv(env, "DISPLAY");
  env = g_environ_unsetenv(env, "XAUTHORITY");
  env = g_environ_setenv(env, "WAYLAND_DISPLAY", c->core->socketName(),
                       TRUE);
  if (c->core->xwaylandDisplay() != nullptr) {
    env = g_environ_setenv(env, "DISPLAY", c->core->xwaylandDisplay(),
                         TRUE);
  }
  env = g_environ_setenv(env, "GDK_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "GTK_CSD", "0", TRUE);
  env = g_environ_setenv(env, "QT_QPA_PLATFORM", "wayland", TRUE);
  env = g_environ_setenv(env, "QT_WAYLAND_DISABLE_WINDOWDECORATION", "1",
                       TRUE);
  env = g_environ_setenv(env, "SDL_VIDEODRIVER", "wayland", TRUE);
  env = g_environ_setenv(env, "XDG_SESSION_TYPE", "wayland", TRUE);
  env = g_environ_setenv(env, "XDG_CURRENT_DESKTOP", "oasis", TRUE);
  env = g_environ_setenv(env, "XDG_SESSION_DESKTOP", "oasis", TRUE);
  env = g_environ_setenv(env, "MOZ_ENABLE_WAYLAND", "1", TRUE);
  env = g_environ_setenv(env, "WINIT_UNIX_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "CLUTTER_BACKEND", "wayland", TRUE);
  env = g_environ_setenv(env, "ECORE_EVAS_ENGINE", "wayland_shm", TRUE);
  env = g_environ_setenv(env, "ELM_ENGINE", "wayland_shm", TRUE);
  if (g_find_program_in_path("systemd-run") != nullptr) {
    g_autoptr(GPtrArray) scoped = g_ptr_array_new();
    g_ptr_array_add(scoped, const_cast<char*>("systemd-run"));
    g_ptr_array_add(scoped, const_cast<char*>("--user"));
    g_ptr_array_add(scoped, const_cast<char*>("--scope"));
    g_ptr_array_add(scoped, const_cast<char*>("--quiet"));
    g_ptr_array_add(scoped, const_cast<char*>("--collect"));
    g_ptr_array_add(scoped, const_cast<char*>("--"));
    for (guint i = 0; i + 1 < argv->len; i++) {
      g_ptr_array_add(scoped, argv->pdata[i]);
    }
    g_ptr_array_add(scoped, nullptr);
    spawn_child(reinterpret_cast<gchar**>(scoped->pdata), env);
    return;
  }
  spawn_child(reinterpret_cast<gchar**>(argv->pdata), env);
}

static int64_t arg_int(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr ? fl_value_get_int(v) : 0;
}

static double arg_double(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr ? fl_value_get_float(v) : 0;
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer data) {
  auto* c = static_cast<_OasisCompositor*>(data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(name, "start") == 0) {
    std::string error;
    if (!c->core->start(&error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "start-failed", error.c_str(), nullptr));
    } else {
      if (c->watch == 0) {
        int fd = c->core->fd();
        c->watch_channel = g_io_channel_unix_new(fd);
        c->watch = g_io_add_watch(
            c->watch_channel,
            static_cast<GIOCondition>(G_IO_IN | G_IO_ERR | G_IO_HUP),
            watch_cb, c);
      }
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(
          m, "socket", fl_value_new_string(c->core->socketName()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    }
  } else if (g_strcmp0(name, "launch") == 0) {
    launch_app(c, args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "configure") == 0) {
    c->core->configure(arg_int(args, "id"), (int)arg_int(args, "w"),
                       (int)arg_int(args, "h"),
                       arg_int(args, "maximized") != 0,
                       arg_int(args, "fullscreen") != 0,
                       arg_int(args, "resizing") != 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "close") == 0) {
    c->core->closeSurface(arg_int(args, "id"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "focus") == 0) {
    c->core->focus(arg_int(args, "id"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerMotion") == 0) {
    c->core->pointerMotion(arg_int(args, "id"), arg_double(args, "x"),
                           arg_double(args, "y"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerExit") == 0) {
    c->core->pointerExit();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerButton") == 0) {
    c->core->pointerButton((uint32_t)arg_int(args, "button"),
                           arg_int(args, "state") == 1);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerAxis") == 0) {
    c->core->pointerAxis(arg_double(args, "dx"), arg_double(args, "dy"),
                         (uint32_t)arg_int(args, "src"),
                         (int32_t)arg_int(args, "discrete"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "pointerAxisStop") == 0) {
    c->core->pointerAxisStop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchDown") == 0) {
    c->core->touchDown(arg_int(args, "id"), (int32_t)arg_int(args, "tid"),
                       arg_double(args, "x"), arg_double(args, "y"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchMotion") == 0) {
    c->core->touchMotion((int32_t)arg_int(args, "tid"),
                         arg_double(args, "x"), arg_double(args, "y"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "touchUp") == 0) {
    c->core->touchUp((int32_t)arg_int(args, "tid"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "key") == 0) {
    c->core->key((uint32_t)arg_int(args, "code"),
                 arg_int(args, "state") == 1);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "stop") == 0) {
    if (c->watch != 0) g_source_remove(c->watch);
    c->watch = 0;
    if (c->watch_channel != nullptr) {
      g_io_channel_unref(c->watch_channel);
      c->watch_channel = nullptr;
    }
    c->core->stop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static FlMethodErrorResponse* listen_cb(FlEventChannel*, FlValue*,
                                        gpointer data) {
  auto* c = static_cast<_OasisCompositor*>(data);
  c->listening = TRUE;
  c->core->replayEvents();
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel*, FlValue*,
                                        gpointer data) {
  auto* c = static_cast<_OasisCompositor*>(data);
  c->listening = FALSE;
  return nullptr;
}

OasisCompositor* oasis_compositor_new(FlPluginRegistrar* registrar,
                                      FlView* view) {
  auto* c = new _OasisCompositor();
  c->registrar = registrar;
  c->view = GTK_WIDGET(view);
  FlEngine* engine = fl_view_get_engine(view);
  c->texture_registrar = fl_engine_get_texture_registrar(engine);
  g_signal_connect(view, "size-allocate", G_CALLBACK(view_resized), c);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  c->method_channel = fl_method_channel_new(messenger, "oasis/wayland",
                                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(c->method_channel,
                                            method_call_cb, c, nullptr);
  g_autoptr(FlStandardMethodCodec) msg_codec =
      fl_standard_method_codec_new();
  c->event_channel = fl_event_channel_new(messenger, "oasis/wayland/events",
                                          FL_METHOD_CODEC(msg_codec));
  fl_event_channel_set_stream_handlers(c->event_channel, listen_cb,
                                       cancel_cb, c, nullptr);
  c->core = new OasisCore(new GtkHost(c));
  return c;
}

void oasis_compositor_free(OasisCompositor* c) {
  if (c == nullptr) return;
  if (c->watch != 0) g_source_remove(c->watch);
  if (c->resize_idle != 0) g_source_remove(c->resize_idle);
  if (c->view != nullptr) {
    g_signal_handlers_disconnect_by_data(c->view, c);
  }
  if (c->watch_channel != nullptr) g_io_channel_unref(c->watch_channel);
  for (auto& kv : c->textures) {
    g_object_unref(kv.second);
  }
  delete c->core;
  g_clear_object(&c->method_channel);
  g_clear_object(&c->event_channel);
  delete c;
}
