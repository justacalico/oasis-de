cmake_minimum_required(VERSION 3.13)
find_package(PkgConfig REQUIRED)
project(oasis_kms LANGUAGES CXX)

pkg_check_modules(KMS REQUIRED IMPORTED_TARGET
  gbm
  libdrm
  libinput
  libudev
  libseat
  xkbcommon
  egl
  glesv2
  wayland-server
  pixman-1
)
pkg_check_modules(WLROOTS REQUIRED IMPORTED_TARGET wlroots-0.20)

# xkb_keymap_new_from_names2 appeared in libxkbcommon 1.11.
pkg_check_modules(XKB_NAMES2 QUIET xkbcommon>=1.11)

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

set(COMPOSITOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../compositor")

add_executable(oasis_kms
  "oasis_kms.cc"
  "${COMPOSITOR_DIR}/oasis_capture.cc"
  "${COMPOSITOR_DIR}/oasis_core.cc"
  "${COMPOSITOR_DIR}/oasis_input.cc"
  "${COMPOSITOR_DIR}/oasis_layer.cc"
  "${COMPOSITOR_DIR}/oasis_lock.cc"
  "${COMPOSITOR_DIR}/oasis_output.cc"
  "${COMPOSITOR_DIR}/oasis_surface.cc"
  "${COMPOSITOR_DIR}/oasis_xdg.cc"
  "${COMPOSITOR_DIR}/oasis_xwayland.cc"
)
target_compile_features(oasis_kms PRIVATE cxx_std_17)
target_include_directories(oasis_kms PRIVATE "${COMPOSITOR_DIR}")
target_include_directories(oasis_kms PRIVATE "${PROTOCOL_GEN_DIR}")
target_compile_definitions(oasis_kms PRIVATE WLR_USE_UNSTABLE)
if(XKB_NAMES2_FOUND)
  target_compile_definitions(oasis_kms PRIVATE OASIS_XKB_NAMES2)
endif()
add_dependencies(oasis_kms wlr_protocols_gen)
target_link_libraries(oasis_kms PRIVATE PkgConfig::KMS PkgConfig::WLROOTS dl)
