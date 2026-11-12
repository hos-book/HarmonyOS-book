#pragma once
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>

namespace hsda::offline_tts {
// The caller owns the fd and an empty private staging directory for the pinned modelId.
size_t extractTarBz2(int fd, const std::string &staging, const std::string &modelId, const std::function<void()> &check,
                     const std::function<void(uint64_t)> &progress);
}
