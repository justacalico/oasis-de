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
  wayland-protocols
)

find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)

set(WAYLAND_PROTOCOLS
  "stable/xdg-shell/xdg-shell.xml"
  "unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"
  "stable/linux-dmabuf/linux-dmabuf-v1.xml"
)

set(GENERATED_SOURCES "")
set(GENERATED_HEADERS "")
foreach(proto ${WAYLAND_PROTOCOLS})
  get_filename_component(proto_name ${proto} NAME_WE)
  set(xml "${WAYLAND_PROTOCOLS_DIR}/${proto}")
  set(header "${CMAKE_CURRENT_BINARY_DIR}/${proto_name}-server-protocol.h")
  set(code "${CMAKE_CURRENT_BINARY_DIR}/${proto_name}-protocol.c")
  add_custom_command(
    OUTPUT ${header}
    COMMAND ${WAYLAND_SCANNER} server-header ${xml} ${header}
    DEPENDS ${xml}
  )
  add_custom_command(
    OUTPUT ${code}
    COMMAND ${WAYLAND_SCANNER} private-code ${xml} ${code}
    DEPENDS ${xml}
  )
  list(APPEND GENERATED_HEADERS ${header})
  list(APPEND GENERATED_SOURCES ${code})
endforeach()

set_source_files_properties(${GENERATED_SOURCES}
  PROPERTIES COMPILE_OPTIONS "-w")

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "oasis_compositor.cc"
  "oasis_textures.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  ${GENERATED_SOURCES}
  ${GENERATED_HEADERS}
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
