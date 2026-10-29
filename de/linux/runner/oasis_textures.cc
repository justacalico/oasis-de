#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "oasis_textures.h"

#include <cstring>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gtk/gtk.h>
#include <libdrm/drm_fourcc.h>
#include <wayland-server.h>

#include "linux-dmabuf-v1-server-protocol.h"


struct _OasisTexture {
  FlPixelBufferTexture parent_instance;
  GMutex mutex;
  uint8_t* stage;
  uint32_t stage_w;
  uint32_t stage_h;
  uint8_t* frame;
  uint32_t frame_w;
  uint32_t frame_h;
  size_t frame_cap;
};

G_DEFINE_TYPE(OasisTexture, oasis_texture, fl_pixel_buffer_texture_get_type())

static gboolean oasis_texture_copy_pixels(FlPixelBufferTexture* texture,
                                          const uint8_t** out_buffer,
                                          uint32_t* width,
                                          uint32_t* height,
                                          GError** error) {
  OasisTexture* self = OASIS_TEXTURE(texture);
  g_mutex_lock(&self->mutex);
  size_t need = static_cast<size_t>(self->stage_w) * self->stage_h * 4;
  if (need > self->frame_cap) {
    g_free(self->frame);
    self->frame = static_cast<uint8_t*>(g_malloc(need));
    self->frame_cap = need;
  }
  memcpy(self->frame, self->stage, need);
  self->frame_w = self->stage_w;
  self->frame_h = self->stage_h;
  g_mutex_unlock(&self->mutex);
  *out_buffer = self->frame;
  *width = self->frame_w;
  *height = self->frame_h;
  return TRUE;
}

static void oasis_texture_dispose(GObject* object) {
  OasisTexture* self = OASIS_TEXTURE(object);
  g_clear_pointer(&self->stage, g_free);
  g_clear_pointer(&self->frame, g_free);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(oasis_texture_parent_class)->dispose(object);
}

static void oasis_texture_class_init(OasisTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = oasis_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      oasis_texture_copy_pixels;
}

static void oasis_texture_init(OasisTexture* self) {
  g_mutex_init(&self->mutex);
  self->stage = static_cast<uint8_t*>(g_malloc0(4));
  self->stage_w = 1;
  self->stage_h = 1;
}

void oasis_texture_push(OasisTexture* self,
                               const uint8_t* rgba,
                               uint32_t w,
                               uint32_t h) {
  g_mutex_lock(&self->mutex);
  if (self->stage_w != w || self->stage_h != h) {
    g_free(self->stage);
    self->stage = static_cast<uint8_t*>(g_malloc((size_t)w * h * 4));
    self->stage_w = w;
    self->stage_h = h;
  }
  memcpy(self->stage, rgba, (size_t)w * h * 4);
  g_mutex_unlock(&self->mutex);
}



struct _OasisGLTexture {
  FlTextureGL parent_instance;
  DmabufBuf* dmabuf = nullptr;
  DmabufBuf* img_buf = nullptr;
  EGLImage image = EGL_NO_IMAGE;
  EGLDisplay img_dpy = EGL_NO_DISPLAY;
  GLuint gl_name = 0;
  uint32_t w = 0;
  uint32_t h = 0;
};

G_DEFINE_TYPE(OasisGLTexture, oasis_gl_texture, fl_texture_gl_get_type())

static EGLImage dmabuf_import(EGLDisplay dpy, DmabufBuf* b) {
  EGLAttrib attrs[64];
  int i = 0;
  attrs[i++] = EGL_WIDTH;
  attrs[i++] = b->w;
  attrs[i++] = EGL_HEIGHT;
  attrs[i++] = b->h;
  attrs[i++] = EGL_LINUX_DRM_FOURCC_EXT;
  attrs[i++] = static_cast<EGLAttrib>(b->format);
  static const EGLint fd_at[4] = {EGL_DMA_BUF_PLANE0_FD_EXT,
                                  EGL_DMA_BUF_PLANE1_FD_EXT,
                                  EGL_DMA_BUF_PLANE2_FD_EXT,
                                  EGL_DMA_BUF_PLANE3_FD_EXT};
  static const EGLint off_at[4] = {EGL_DMA_BUF_PLANE0_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE1_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE2_OFFSET_EXT,
                                   EGL_DMA_BUF_PLANE3_OFFSET_EXT};
  static const EGLint pitch_at[4] = {EGL_DMA_BUF_PLANE0_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE1_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE2_PITCH_EXT,
                                     EGL_DMA_BUF_PLANE3_PITCH_EXT};
  static const EGLint mlo_at[4] = {EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
  static const EGLint mhi_at[4] = {EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};
  int n = b->nplanes < 4 ? b->nplanes : 4;
  for (int p = 0; p < n; p++) {
    attrs[i++] = fd_at[p];
    attrs[i++] = b->fds[p];
    attrs[i++] = off_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b->offsets[p]);
    attrs[i++] = pitch_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b->strides[p]);
    attrs[i++] = mlo_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b->mods[p] & 0xffffffffu);
    attrs[i++] = mhi_at[p];
    attrs[i++] = static_cast<EGLAttrib>(b->mods[p] >> 32);
  }
  attrs[i++] = EGL_NONE;
  return eglCreateImage(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                        static_cast<EGLClientBuffer>(nullptr), attrs);
}

static gboolean oasis_gl_texture_populate(FlTextureGL* texture,
                                          uint32_t* target,
                                          uint32_t* name,
                                          uint32_t* width,
                                          uint32_t* height,
                                          GError** error) {
  OasisGLTexture* self = OASIS_GL_TEXTURE(texture);
  EGLDisplay dpy = eglGetCurrentDisplay();
  if (self->dmabuf == nullptr || dpy == EGL_NO_DISPLAY ||
      eglGetCurrentContext() == EGL_NO_CONTEXT) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "no dmabuf or no egl context");
    return FALSE;
  }
  if (self->gl_name == 0) glGenTextures(1, &self->gl_name);
  if (self->img_buf != self->dmabuf) {
    if (self->image != EGL_NO_IMAGE && self->img_dpy != EGL_NO_DISPLAY) {
      eglDestroyImage(self->img_dpy, self->image);
    }
    self->image = EGL_NO_IMAGE;
    if (self->img_buf != nullptr) {
      oasis_dmabuf_unref(self->img_buf);
      self->img_buf = nullptr;
    }
    self->image = dmabuf_import(dpy, self->dmabuf);
    self->img_dpy = dpy;
    if (self->image == EGL_NO_IMAGE) {
      g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                  "dmabuf import failed");
      return FALSE;
    }
    self->img_buf = self->dmabuf;
    oasis_dmabuf_ref(self->img_buf);
  }
  static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target = nullptr;
  if (image_target == nullptr) {
    image_target = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
        eglGetProcAddress("glEGLImageTargetTexture2DOES"));
  }
  if (image_target == nullptr) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "glEGLImageTargetTexture2DOES unavailable");
    return FALSE;
  }
  glBindTexture(GL_TEXTURE_2D, self->gl_name);
  image_target(GL_TEXTURE_2D, self->image);
  *target = GL_TEXTURE_2D;
  *name = self->gl_name;
  *width = self->w;
  *height = self->h;
  return TRUE;
}

void oasis_gl_texture_set_dmabuf(OasisGLTexture* self, DmabufBuf* db) {
  if (self->dmabuf == db) return;
  if (self->dmabuf != nullptr) oasis_dmabuf_unref(self->dmabuf);
  self->dmabuf = db;
  if (db != nullptr) {
    oasis_dmabuf_ref(db);
    self->w = static_cast<uint32_t>(db->w);
    self->h = static_cast<uint32_t>(db->h);
  }
}

static void oasis_gl_texture_dispose(GObject* object) {
  OasisGLTexture* self = OASIS_GL_TEXTURE(object);
  if (self->image != EGL_NO_IMAGE && self->img_dpy != EGL_NO_DISPLAY) {
    eglDestroyImage(self->img_dpy, self->image);
    self->image = EGL_NO_IMAGE;
  }
  oasis_dmabuf_unref(self->img_buf);
  self->img_buf = nullptr;
  oasis_dmabuf_unref(self->dmabuf);
  self->dmabuf = nullptr;
  G_OBJECT_CLASS(oasis_gl_texture_parent_class)->dispose(object);
}

static void oasis_gl_texture_class_init(OasisGLTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = oasis_gl_texture_dispose;
  FL_TEXTURE_GL_CLASS(klass)->populate = oasis_gl_texture_populate;
}

static void oasis_gl_texture_init(OasisGLTexture* self) {}
