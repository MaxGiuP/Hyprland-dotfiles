cmake_minimum_required(VERSION 3.21)

project(linmax-notification-activation LANGUAGES C CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 REQUIRED COMPONENTS Core DBus Gui Qml Quick)
find_package(Qt6GuiPrivate REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WaylandClient REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(WaylandProtocols REQUIRED wayland-protocols)

find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
set(XDG_ACTIVATION_XML
    "${WAYLAND_PROTOCOLS_DIR}/staging/xdg-activation/xdg-activation-v1.xml"
)
if(NOT EXISTS "${XDG_ACTIVATION_XML}")
    message(FATAL_ERROR "xdg-activation-v1 protocol XML was not found")
endif()
set(XDG_ACTIVATION_HEADER
    "${CMAKE_CURRENT_BINARY_DIR}/xdg-activation-v1-client-protocol.h"
)
set(XDG_ACTIVATION_CODE
    "${CMAKE_CURRENT_BINARY_DIR}/xdg-activation-v1-protocol.c"
)

add_custom_command(
    OUTPUT "${XDG_ACTIVATION_HEADER}"
    COMMAND "${WAYLAND_SCANNER}" client-header
        "${XDG_ACTIVATION_XML}" "${XDG_ACTIVATION_HEADER}"
    DEPENDS "${XDG_ACTIVATION_XML}"
)

add_custom_command(
    OUTPUT "${XDG_ACTIVATION_CODE}"
    COMMAND "${WAYLAND_SCANNER}" private-code
        "${XDG_ACTIVATION_XML}" "${XDG_ACTIVATION_CODE}"
    DEPENDS "${XDG_ACTIVATION_XML}"
)

add_library(notificationactivationplugin MODULE
    notificationactivation.cpp
    notificationactivation.hpp
    plugin.cpp
    "${XDG_ACTIVATION_HEADER}"
    "${XDG_ACTIVATION_CODE}"
)

set_target_properties(notificationactivationplugin PROPERTIES
    OUTPUT_NAME "notificationactivationplugin"
)

target_link_libraries(notificationactivationplugin PRIVATE
    PkgConfig::WaylandClient
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Qml
    Qt6::Quick
)

target_include_directories(notificationactivationplugin PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
)

set(notification_activation_qml_dir
    "lib/qt6/qml/Linmax/NotificationActivation"
)

install(TARGETS notificationactivationplugin
    LIBRARY DESTINATION "${notification_activation_qml_dir}"
)

install(FILES qmldir
    DESTINATION "${notification_activation_qml_dir}"
)
