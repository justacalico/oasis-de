#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <wayland-server.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <cstring>

#include <pthread.h>

#include "oasis_wlr.h"

_Pragma("GCC diagnostic ignored \"-Winvalid-offsetof\"")

#include "oasis_internal.h"

namespace oasis {

// wlroots hooks EGL_KHR_debug so driver reports reach wlr_log. GTK's Wayland
// GL path calls eglSwapInterval() every time it binds a context, including
// Flutter's surfaceless contexts; each call reports EGL_BAD_SURFACE and
// would print an error line per rendered frame. Keep wlroots' filtering of
// severities and its message format but drop that one benign report.
static enum wlr_log_importance egl_msg_level(EGLint type) {
  switch (type) {
    case EGL_DEBUG_MSG_CRITICAL_KHR:
    case EGL_DEBUG_MSG_ERROR_KHR:
    case EGL_DEBUG_MSG_WARN_KHR:
      return WLR_ERROR;
    default:
      return WLR_INFO;
  }
}

static const char* egl_error_str(EGLint error) {
  switch (error) {
    case EGL_SUCCESS:
      return "EGL_SUCCESS";
    case EGL_NOT_INITIALIZED:
      return "EGL_NOT_INITIALIZED";
    case EGL_BAD_ACCESS:
      return "EGL_BAD_ACCESS";
    case EGL_BAD_ALLOC:
      return "EGL_BAD_ALLOC";
    case EGL_BAD_ATTRIBUTE:
      return "EGL_BAD_ATTRIBUTE";
    case EGL_BAD_CONTEXT:
      return "EGL_BAD_CONTEXT";
    case EGL_BAD_CONFIG:
      return "EGL_BAD_CONFIG";
    case EGL_BAD_CURRENT_SURFACE:
      return "EGL_BAD_CURRENT_SURFACE";
    case EGL_BAD_DISPLAY:
      return "EGL_BAD_DISPLAY";
    case EGL_BAD_DEVICE_EXT:
      return "EGL_BAD_DEVICE_EXT";
    case EGL_BAD_SURFACE:
      return "EGL_BAD_SURFACE";
    case EGL_BAD_MATCH:
      return "EGL_BAD_MATCH";
    case EGL_BAD_PARAMETER:
      return "EGL_BAD_PARAMETER";
    case EGL_BAD_NATIVE_PIXMAP:
      return "EGL_BAD_NATIVE_PIXMAP";
    case EGL_BAD_NATIVE_WINDOW:
      return "EGL_BAD_NATIVE_WINDOW";
    case EGL_CONTEXT_LOST:
      return "EGL_CONTEXT_LOST";
    default:
      return "unknown error";
  }
}

static void egl_debug_cb(EGLenum error, const char* command, EGLint type,
                         EGLLabelKHR, EGLLabelKHR, const char* msg) {
  if (error == EGL_BAD_SURFACE && strcmp(command, "eglSwapInterval") == 0) {
    return;
  }
  _wlr_log(egl_msg_level(type),
           "[EGL] command: %s, error: %s (0x%x), message: \"%s\"", command,
           egl_error_str(error), error, msg);
}

void install_egl_debug_filter() {
  const char* exts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if (exts == nullptr || strstr(exts, "EGL_KHR_debug") == nullptr) return;
  auto* control = reinterpret_cast<PFNEGLDEBUGMESSAGECONTROLKHRPROC>(
      eglGetProcAddress("eglDebugMessageControlKHR"));
  if (control == nullptr) return;
  static const EGLAttrib attribs[] = {
      EGL_DEBUG_MSG_CRITICAL_KHR, EGL_TRUE, EGL_DEBUG_MSG_ERROR_KHR, EGL_TRUE,
      EGL_DEBUG_MSG_WARN_KHR,     EGL_TRUE, EGL_DEBUG_MSG_INFO_KHR,  EGL_TRUE,
      EGL_NONE,
  };
  control(egl_debug_cb, attribs);
}

}  // namespace oasis
