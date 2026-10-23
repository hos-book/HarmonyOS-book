#pragma once
#include "quickjs_headers.h"
#include <functional>
#include <string>
#include <vector>

// Encoded image bytes in/out. No paths, network, website algorithms or platform objects.
bool ReorderImageStrips(JSContext* ctx, const std::string& options, const uint8_t* input, size_t inputSize,
    const std::function<bool()>& stopped, std::vector<uint8_t>& output, std::string& error);
