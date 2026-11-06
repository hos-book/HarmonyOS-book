#pragma once
#include "AceDecoder.h"
#include <functional>
#include <string>

namespace hsda::ace {
struct Entry {
    std::string name;
    uint64_t offset = 0, packed = 0, size = 0;
    uint32_t checksum = 0;
    uint8_t method = 0;
    bool directory = false;
    bool image() const;
};
class Archive {
    int fd;
    Budget& budget;
    Decoder decoder;
    bool solid = false;
    size_t next = 0;
public:
    std::vector<Entry> entries;
    Archive(int descriptor, Budget& limit);
    Bytes read(size_t index);
};
std::vector<std::string> extractComic(int fd, const std::string& directory,
    const std::function<void(size_t, size_t)>& progress);
}
