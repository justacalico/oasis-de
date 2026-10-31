cmake_minimum_required(VERSION 3.13)
find_package(PkgConfig REQUIRED)
project(oasis_kms LANGUAGES CXX)

pkg_check_modules(KMS REQUIRED IMPORTED_TARGET
  gbm
  libdrm
  libinput
  xkbcommon
  egl
  glesv2
  wayland-server
  pixman-1
)
pkg_check_modules(WLROOTS REQUIRED IMPORTED_TARGET wlroots-0.20)

set(COMPOSITOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../compositor")

add_executable(oasis_kms
  "oasis_kms.cc"
  "${COMPOSITOR_DIR}/oasis_core.cc"
  "${COMPOSITOR_DIR}/oasis_input.cc"
  "${COMPOSITOR_DIR}/oasis_surface.cc"
  "${COMPOSITOR_DIR}/oasis_xdg.cc"
  "${COMPOSITOR_DIR}/oasis_xwayland.cc"
)
target_compile_features(oasis_kms PRIVATE cxx_std_17)
target_include_directories(oasis_kms PRIVATE "${COMPOSITOR_DIR}")
target_compile_definitions(oasis_kms PRIVATE WLR_USE_UNSTABLE)
target_link_libraries(oasis_kms PRIVATE PkgConfig::KMS PkgConfig::WLROOTS dl)
