cmake_minimum_required(VERSION 3.5.0)
project(subtitle_audio)
set(CMAKE_CXX_STANDARD 17)
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

# API 20-compatible streaming support for the publishers' original tar.bz2 models.
set(OFFLINE_TTS_ASSET_SPEC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/offline-tts-assets.json")
set(OFFLINE_TTS_PIPER_ASSET_SPEC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/piper-tts-assets.json")
set(OFFLINE_TTS_ASSET_GENERATOR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/generate-offline-tts-native-assets.py")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${OFFLINE_TTS_ASSET_SPEC}"
  "${OFFLINE_TTS_PIPER_ASSET_SPEC}" "${OFFLINE_TTS_ASSET_GENERATOR}")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${OFFLINE_TTS_ASSET_GENERATOR}"
  --spec "${OFFLINE_TTS_ASSET_SPEC}" --piper-spec "${OFFLINE_TTS_PIPER_ASSET_SPEC}"
  --output "${CMAKE_CURRENT_BINARY_DIR}/private/offline_tts_assets.h"
  RESULT_VARIABLE OFFLINE_TTS_ASSET_RESULT)
if(NOT OFFLINE_TTS_ASSET_RESULT EQUAL 0)
  message(FATAL_ERROR "Cannot generate the pinned offline TTS archive asset allowlist")
endif()
set(BZIP2_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/bzip2")
add_library(offline_tts_bzip2 STATIC
  "${BZIP2_SOURCE}/bzlib.c" "${BZIP2_SOURCE}/blocksort.c" "${BZIP2_SOURCE}/compress.c"
  "${BZIP2_SOURCE}/decompress.c" "${BZIP2_SOURCE}/huffman.c" "${BZIP2_SOURCE}/crctable.c"
  "${BZIP2_SOURCE}/randtable.c")
set_target_properties(offline_tts_bzip2 PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(offline_tts_bzip2 PRIVATE BZ_NO_STDIO)
target_compile_options(offline_tts_bzip2 PRIVATE -O2 -fexceptions -fvisibility=hidden -fstack-protector-strong)
add_library(offline_tts_archive SHARED offline_tts_archive.cpp offline_tts_archive_core.cpp)
target_include_directories(offline_tts_archive PRIVATE "${BZIP2_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}/private")
target_compile_options(offline_tts_archive PRIVATE -O2 -Wall -Wextra -fstack-protector-strong -fvisibility=hidden)
target_link_libraries(offline_tts_archive PRIVATE offline_tts_bzip2 libace_napi.z.so)

add_library(record_dissolve SHARED record_dissolve/module.cpp record_dissolve/shatter_renderer.cpp)
target_compile_options(record_dissolve PRIVATE -Wall -Wextra -fstack-protector-strong)
target_link_libraries(record_dissolve PRIVATE libace_napi.z.so libhilog_ndk.z.so
  libpixelmap.so libnative_window.so libnative_vsync.so libEGL.so libGLESv3.so)

# Only the inference library is packaged. GGUF weights are imported by the user.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMIT "cd959bae99ff4bed22bef2604f45241c09bbb8c8")
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_REPACK OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
add_subdirectory(../../../../third_party/role-llama role-llama EXCLUDE_FROM_ALL)
# OHOS uses musl; expose the GNU CPU affinity declarations used by the CPU backend.
target_compile_definitions(ggml-cpu PRIVATE _GNU_SOURCE)
target_compile_options(ggml-cpu PRIVATE -include "${CMAKE_CURRENT_SOURCE_DIR}/role_thread_compat.h")
# Model evaluation must remain optimized even in an application debug build.
foreach(role_target ggml-base ggml-cpu llama)
  target_compile_options(${role_target} PRIVATE -O2)
endforeach()
add_library(role_inference SHARED role_inference.cpp)
target_compile_options(role_inference PRIVATE -Wall -Wextra -fstack-protector-strong)
target_link_libraries(role_inference PRIVATE llama libace_napi.z.so)
