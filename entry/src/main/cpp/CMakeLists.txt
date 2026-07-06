cmake_minimum_required(VERSION 3.5.0)
project(native_module)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(native_module SHARED
    napi_init.cpp
    audio_metadata.cpp
)

target_link_libraries(native_module PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libnative_window.so
)
