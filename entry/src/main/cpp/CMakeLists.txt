cmake_minimum_required(VERSION 3.5.0)
project(subtitle_audio)
set(CMAKE_CXX_STANDARD 17)
add_library(subtitle_audio SHARED subtitle_audio.cpp)
target_link_libraries(subtitle_audio PUBLIC libace_napi.z.so libnative_media_core.so
  libnative_media_avsource.so libnative_media_avdemuxer.so libnative_media_acodec.so libnative_media_codecbase.so)
