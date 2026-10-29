#ifndef OASIS_TEXTURES_H_
#define OASIS_TEXTURES_H_

#include <flutter_linux/flutter_linux.h>
#include <wayland-server.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

#define OASIS_TYPE_TEXTURE (oasis_texture_get_type())
G_DECLARE_FINAL_TYPE(OasisTexture,
                     oasis_texture,
                     OASIS,
                     TEXTURE,
                     FlPixelBufferTexture)

#define OASIS_TYPE_GL_TEXTURE (oasis_gl_texture_get_type())
G_DECLARE_FINAL_TYPE(OasisGLTexture,
                     oasis_gl_texture,
                     OASIS,
                     GL_TEXTURE,
                     FlTextureGL)

#include "oasis_compositor.h"

struct DmabufBuf {
  OasisCompositor* comp = nullptr;
  wl_resource* res = nullptr;
  int w = 0;
  int h = 0;
  uint32_t format = 0;
  int nplanes = 0;
  int fds[4] = {-1, -1, -1, -1};
  uint32_t offsets[4] = {0, 0, 0, 0};
  uint32_t strides[4] = {0, 0, 0, 0};
  uint64_t mods[4] = {0, 0, 0, 0};
};

void oasis_texture_push(OasisTexture* self,
                        const uint8_t* rgba,
                        uint32_t w,
                        uint32_t h);
void oasis_gl_texture_set_dmabuf(OasisGLTexture* self, DmabufBuf* db);

#endif
