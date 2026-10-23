# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(quickjs)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# 日志打印配置
add_definitions( "-DLOG_DOMAIN=0xd0d0" )
add_definitions( "-DLOG_TAG=\"quickjs\"" )

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH} ${NATIVERENDER_ROOT_PATH}/include)

set(SELF_LIB_NAME quickjs)
set(SELF_SRC_FILES
    napi_init.cpp
    quickjs_ext.cpp
    bounded_image_transform.cpp
)
add_library(${SELF_LIB_NAME} SHARED ${SELF_SRC_FILES})
target_link_libraries(${SELF_LIB_NAME} PUBLIC libace_napi.z.so libhilog_ndk.z.so)
target_link_libraries(${SELF_LIB_NAME} PUBLIC libimage_source.so libimage_packer.so libpixelmap.so)
target_link_libraries(${SELF_LIB_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libquickjs.a)
