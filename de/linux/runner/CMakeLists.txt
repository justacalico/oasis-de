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

pkg_check_modules(WLROOTS REQUIRED IMPORTED_TARGET
  wlroots-0.19
)

set(COMPOSITOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../compositor")

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "oasis_compositor.cc"
  "oasis_textures.cc"
  "${COMPOSITOR_DIR}/oasis_core.cc"
  "${COMPOSITOR_DIR}/oasis_input.cc"
  "${COMPOSITOR_DIR}/oasis_surface.cc"
  "${COMPOSITOR_DIR}/oasis_xdg.cc"
  "${COMPOSITOR_DIR}/oasis_xwayland.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

target_include_directories(${BINARY_NAME} PRIVATE "${COMPOSITOR_DIR}")

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
add_definitions(-DWLR_USE_UNSTABLE)

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WLROOTS)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
