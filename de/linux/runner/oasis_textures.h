#ifndef OASIS_TEXTURES_H_
#define OASIS_TEXTURES_H_

#include <flutter_linux/flutter_linux.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include "oasis_core.h"

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

void oasis_texture_push(OasisTexture* self,
                        const uint8_t* rgba,
                        uint32_t w,
                        uint32_t h);
void oasis_gl_texture_set_dmabuf(OasisGLTexture* self, const DmabufInfo& db);

#endif
