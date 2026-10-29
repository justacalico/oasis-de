#ifndef OASIS_COMPOSITOR_H_
#define OASIS_COMPOSITOR_H_

#include <flutter_linux/flutter_linux.h>

typedef struct _OasisCompositor OasisCompositor;

OasisCompositor* oasis_compositor_new(FlPluginRegistrar* registrar, FlView* view);
void oasis_compositor_free(OasisCompositor* compositor);

#endif  // OASIS_COMPOSITOR_H_
