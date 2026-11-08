cmake_minimum_required(VERSION 3.4.1)
project("video_filter")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(high_refresh SHARED high_refresh.cpp)
target_link_libraries(high_refresh PUBLIC ace_napi.z native_vsync hilog_ndk.z native_media_codecbase)

add_library(video_filter SHARED
    napi_init.cpp
    video_render.cpp
)

target_include_directories(video_filter PUBLIC
    ${NODE_INCLUDE_DIR}
)

target_link_libraries(video_filter PUBLIC
    ace_napi.z
    EGL
    GLESv3
    native_image
    native_window
    hilog_ndk.z
)
