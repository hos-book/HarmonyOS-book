find_program(HSDA_CARGO cargo
  HINTS "$ENV{HSDA_RUST_HOME}/bin" "$ENV{USERPROFILE}/.cargo/bin" "D:/soft/rust-1.100.0/bin"
  REQUIRED)
get_filename_component(HSDA_RUST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/rust" ABSOLUTE)
if(CMAKE_OHOS_ARCH_ABI STREQUAL "arm64-v8a")
  set(HSDA_RUST_TARGET aarch64-unknown-linux-ohos)
elseif(CMAKE_OHOS_ARCH_ABI STREQUAL "x86_64")
  set(HSDA_RUST_TARGET x86_64-unknown-linux-ohos)
else()
  message(FATAL_ERROR "Rust core ABI: ${CMAKE_OHOS_ARCH_ABI}")
endif()
set(HSDA_RUST_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/cargo")
set(HSDA_RUST_LIBRARY "${HSDA_RUST_OUTPUT}/${HSDA_RUST_TARGET}/release/libhsda_core.a")
get_filename_component(HSDA_RUST_BIN "${HSDA_CARGO}" DIRECTORY)
file(GLOB_RECURSE HSDA_RUST_SOURCES CONFIGURE_DEPENDS "${HSDA_RUST_ROOT}/*.rs" "${HSDA_RUST_ROOT}/Cargo.toml" "${HSDA_RUST_ROOT}/*/Cargo.toml")
add_custom_command(OUTPUT "${HSDA_RUST_LIBRARY}"
  COMMAND "${CMAKE_COMMAND}" -E env "RUSTC=${HSDA_RUST_BIN}/rustc.exe"
    "RUSTFLAGS=-C relocation-model=pic"
    "${HSDA_CARGO}" build --offline --release --target "${HSDA_RUST_TARGET}"
    --manifest-path "${HSDA_RUST_ROOT}/Cargo.toml" --target-dir "${HSDA_RUST_OUTPUT}" -p hsda_core
  DEPENDS ${HSDA_RUST_SOURCES}
  COMMENT "Compiling Rust core for ${HSDA_RUST_TARGET}"
  VERBATIM)
add_custom_target(hsda_rust_build DEPENDS "${HSDA_RUST_LIBRARY}")
add_library(hsda_rust STATIC IMPORTED)
set_target_properties(hsda_rust PROPERTIES IMPORTED_LOCATION "${HSDA_RUST_LIBRARY}")
add_dependencies(hsda_rust hsda_rust_build)
add_library(hsda_core SHARED module.cpp speech_stream.cpp)
add_dependencies(hsda_core hsda_rust_build)
target_compile_options(hsda_core PRIVATE -O2 -Wall -Wextra -fstack-protector-strong -fvisibility=hidden)
target_link_options(hsda_core PRIVATE "-Wl,--exclude-libs,ALL")
target_link_libraries(hsda_core PRIVATE hsda_rust libace_napi.z.so z dl m
  libnative_media_core.so libnative_media_avsource.so libnative_media_avdemuxer.so
  libnative_media_acodec.so libnative_media_codecbase.so)
