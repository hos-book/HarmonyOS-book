cmake_minimum_required(VERSION 3.5.0)
project(subtitle_audio)
set(CMAKE_CXX_STANDARD 17)
add_subdirectory(rust_bridge)
find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(MODEL_PACK_KEY_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/model_pack_key.py")
set(MODEL_PACK_KEY_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../../../../signing/model-pack.key")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${MODEL_PACK_KEY_SCRIPT}" "${MODEL_PACK_KEY_FILE}")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${MODEL_PACK_KEY_SCRIPT}"
  --header "${CMAKE_CURRENT_BINARY_DIR}/private/model_pack_key.h"
  RESULT_VARIABLE MODEL_PACK_KEY_RESULT)
if(NOT MODEL_PACK_KEY_RESULT EQUAL 0)
  message(FATAL_ERROR "Cannot load the private model-pack release key")
endif()
add_library(model_pack_crypto SHARED model_pack_crypto.cpp)
target_include_directories(model_pack_crypto PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/private")
target_compile_options(model_pack_crypto PRIVATE -Wall -Wextra -fstack-protector-strong -fvisibility=hidden)
target_link_libraries(model_pack_crypto PRIVATE libace_napi.z.so)
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



