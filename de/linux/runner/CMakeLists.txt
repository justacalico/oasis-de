cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.

pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET
  wayland-server
  xkbcommon
  egl
  glesv2
  libdrm
  pixman-1
)

# xkb_keymap_new_from_names2 appeared in libxkbcommon 1.11.
pkg_check_modules(XKB_NAMES2 QUIET xkbcommon>=1.11)

pkg_check_modules(WLROOTS REQUIRED IMPORTED_TARGET
  wlroots-0.20
)

# wlroots does not install generated protocol headers; compositors must
# produce them from the wlr-protocols XML definitions (wlr-protocols-devel).
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
pkg_get_variable(WLR_PROTOCOLS_DIR wlr-protocols pkgdatadir)
if(NOT WLR_PROTOCOLS_DIR)
  set(WLR_PROTOCOLS_DIR "/usr/share/wlr-protocols")
endif()

set(PROTOCOL_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/protocols")
file(MAKE_DIRECTORY "${PROTOCOL_GEN_DIR}")
set(PROTOCOL_HEADERS "")
foreach(proto
    wlr-layer-shell-unstable-v1
    wlr-output-power-management-unstable-v1)
  set(xml "${WLR_PROTOCOLS_DIR}/unstable/${proto}.xml")
  set(header "${PROTOCOL_GEN_DIR}/${proto}-protocol.h")
  add_custom_command(
    OUTPUT "${header}"
    COMMAND "${WAYLAND_SCANNER}" server-header "${xml}" "${header}"
    DEPENDS "${xml}"
    VERBATIM)
  list(APPEND PROTOCOL_HEADERS "${header}")
endforeach()
add_custom_target(wlr_protocols_gen DEPENDS ${PROTOCOL_HEADERS})

set(COMPOSITOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../compositor")

set(APPMENU_XML "${COMPOSITOR_DIR}/protocols/appmenu.xml")
add_custom_command(
  OUTPUT "${PROTOCOL_GEN_DIR}/appmenu-protocol.h"
         "${PROTOCOL_GEN_DIR}/appmenu-protocol.c"
  COMMAND "${WAYLAND_SCANNER}" server-header "${APPMENU_XML}"
          "${PROTOCOL_GEN_DIR}/appmenu-protocol.h"
  COMMAND "${WAYLAND_SCANNER}" private-code "${APPMENU_XML}"
          "${PROTOCOL_GEN_DIR}/appmenu-protocol.c"
  DEPENDS "${APPMENU_XML}"
  VERBATIM)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "oasis_compositor.cc"
  "oasis_textures.cc"
  "${PROTOCOL_GEN_DIR}/appmenu-protocol.c"
  "${COMPOSITOR_DIR}/oasis_appmenu.cc"
  "${COMPOSITOR_DIR}/oasis_capture.cc"
  "${COMPOSITOR_DIR}/oasis_clipboard.cc"
  "${COMPOSITOR_DIR}/oasis_core.cc"
  "${COMPOSITOR_DIR}/oasis_cursor.cc"
  "${COMPOSITOR_DIR}/oasis_decoration.cc"
  "${COMPOSITOR_DIR}/oasis_egl_debug.cc"
  "${COMPOSITOR_DIR}/oasis_export.cc"
  "${COMPOSITOR_DIR}/oasis_frame.cc"
  "${COMPOSITOR_DIR}/oasis_inhibit.cc"
  "${COMPOSITOR_DIR}/oasis_input.cc"
  "${COMPOSITOR_DIR}/oasis_keyboard.cc"
  "${COMPOSITOR_DIR}/oasis_layer.cc"
  "${COMPOSITOR_DIR}/oasis_lock.cc"
  "${COMPOSITOR_DIR}/oasis_output.cc"
  "${COMPOSITOR_DIR}/oasis_output_config.cc"
  "${COMPOSITOR_DIR}/oasis_report.cc"
  "${COMPOSITOR_DIR}/oasis_seat.cc"
  "${COMPOSITOR_DIR}/oasis_surface.cc"
  "${COMPOSITOR_DIR}/oasis_text_input.cc"
  "${COMPOSITOR_DIR}/oasis_xdg.cc"
  "${COMPOSITOR_DIR}/oasis_xwayland.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

target_include_directories(${BINARY_NAME} PRIVATE "${COMPOSITOR_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${PROTOCOL_GEN_DIR}")
add_dependencies(${BINARY_NAME} wlr_protocols_gen)

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
add_definitions(-DWLR_USE_UNSTABLE)
if(XKB_NAMES2_FOUND)
  add_definitions(-DOASIS_XKB_NAMES2)
endif()

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WLROOTS)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
