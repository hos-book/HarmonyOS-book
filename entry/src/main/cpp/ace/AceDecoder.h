// ACE decoding adapted from acefile (BSD-2-Clause). See LICENSE and README.md.
#pragma once
#include <array>
#include <chrono>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace hsda::ace {
using Bytes = std::vector<uint8_t>;
[[noreturn]] inline void invalid() { throw std::runtime_error("import_cba_invalid"); }
inline void require(bool ok) { if (!ok) invalid(); }

class Budget {
    std::chrono::steady_clock::time_point deadline = std::chrono::steady_clock::now() + std::chrono::minutes(3);
    uint32_t calls = 0;
public:
    void check() {
        if (std::chrono::steady_clock::now() > deadline) throw std::runtime_error("import_cba_limit");
    }
    void tick() { if ((++calls & 0xffff) == 0) check(); }
};

// The dictionary survives file boundaries in solid archives; other state does not.
class Decoder {
    std::vector<uint8_t> dictionary = std::vector<uint8_t>(1U << 22);
    size_t position = 0;
    size_t filled = 0;
    Budget& budget;
public:
    explicit Decoder(Budget& value) : budget(value) {}
    void reset() { position = 0; filled = 0; }
    void registerByte(uint8_t value);
    void copy(Bytes& output, size_t distance, size_t count);
    Bytes decode(const Bytes& packed, size_t size, uint8_t method);
};
uint32_t crc(const Bytes& bytes);
}
