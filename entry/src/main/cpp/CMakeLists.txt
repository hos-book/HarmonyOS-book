cmake_minimum_required(VERSION 3.5.0)
project(subtitle_audio)
set(CMAKE_CXX_STANDARD 17)
add_library(subtitle_audio SHARED subtitle_audio.cpp)
target_link_libraries(subtitle_audio PUBLIC libace_napi.z.so libnative_media_core.so
  libnative_media_avsource.so libnative_media_avdemuxer.so libnative_media_acodec.so libnative_media_codecbase.so)
add_library(cba_archive SHARED cba_archive.cpp ace/AceArchive.cpp ace/AceDecoder.cpp)
target_compile_options(cba_archive PRIVATE -Wall -Wextra -fstack-protector-strong)
target_link_libraries(cba_archive PUBLIC libace_napi.z.so)

add_library(record_dissolve SHARED record_dissolve/module.cpp record_dissolve/shatter_renderer.cpp)
target_compile_options(record_dissolve PRIVATE -Wall -Wextra -fstack-protector-strong)
target_link_libraries(record_dissolve PRIVATE libace_napi.z.so libhilog_ndk.z.so
  libpixelmap.so libnative_window.so libnative_vsync.so libEGL.so libGLESv3.so)
