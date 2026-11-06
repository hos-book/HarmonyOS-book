#include "AceArchive.h"
#include <algorithm>
#include <cerrno>
#include <cctype>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

namespace hsda::ace {
namespace {
constexpr uint64_t MIB = 1024 * 1024;
uint64_t little(const Bytes& bytes, size_t offset, size_t width) {
    require(offset <= bytes.size() && width <= bytes.size() - offset);
    uint64_t value = 0;
    for (size_t i = 0; i < width; ++i) value |= uint64_t(bytes[offset + i]) << (8 * i);
    return value;
}
Bytes readAt(int fd, uint64_t offset, size_t count) {
    Bytes bytes(count);
    for (size_t done = 0; done < count;) {
        const ssize_t got = pread(fd, bytes.data() + done, count - done, off_t(offset + done));
        if (got < 0 && errno == EINTR) continue;
        require(got > 0); done += size_t(got);
    }
    return bytes;
}
std::string lower(std::string value) {
    for (auto& ch : value) {
        if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
        else if (ch == '\\') ch = '/';
    }
    return value;
}
bool naturalLess(const std::string& left, const std::string& right) {
    const std::string a = lower(left), b = lower(right);
    size_t i = 0, j = 0;
    auto digit = [](char c) { return c >= '0' && c <= '9'; };
    while (i < a.size() && j < b.size()) {
        if (digit(a[i]) && digit(b[j])) {
            size_t x = i, y = j;
            while (x < a.size() && digit(a[x])) ++x;
            while (y < b.size() && digit(b[y])) ++y;
            size_t nzA = i, nzB = j;
            while (nzA + 1 < x && a[nzA] == '0') ++nzA;
            while (nzB + 1 < y && b[nzB] == '0') ++nzB;
            if (x - nzA != y - nzB) return x - nzA < y - nzB;
            const int order = a.compare(nzA, x - nzA, b, nzB, y - nzB);
            if (order) return order < 0;
            if (x - i != y - j) return x - i < y - j;
            i = x; j = y;
        } else {
            if (a[i] != b[j]) return uint8_t(a[i]) < uint8_t(b[j]);
            ++i; ++j;
        }
    }
    return i == a.size() && j != b.size();
}
void writeImage(const std::string& path, const Bytes& bytes) {
    int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) throw std::runtime_error("import_cba_write");
    size_t done = 0;
    while (done < bytes.size()) {
        const ssize_t written = write(fd, bytes.data() + done, bytes.size() - done);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { close(fd); unlink(path.c_str()); throw std::runtime_error("import_cba_write"); }
        done += size_t(written);
    }
    if (close(fd) != 0) { unlink(path.c_str()); throw std::runtime_error("import_cba_write"); }
}
}

bool Entry::image() const {
    if (directory) return false;
    const std::string value = lower(name);
    if (value.find("__macosx/") != std::string::npos || value.find("/._") != std::string::npos ||
        value.rfind("._", 0) == 0) return false;
    const size_t dot = value.rfind('.');
    if (dot == std::string::npos) return false;
    const std::string extension = value.substr(dot);
    return extension == ".jpg" || extension == ".jpeg" || extension == ".png" || extension == ".gif" ||
        extension == ".webp" || extension == ".bmp" || extension == ".heic" || extension == ".heif" ||
        extension == ".avif" || extension == ".tif" || extension == ".tiff";
}

Archive::Archive(int descriptor, Budget& limit) : fd(descriptor), budget(limit), decoder(limit) {
    struct stat info{};
    require(fstat(fd, &info) == 0 && info.st_size > 0);
    const uint64_t size = uint64_t(info.st_size);
    if (size > 3 * 1024 * MIB) throw std::runtime_error("import_cba_limit");
    uint64_t offset = 0, total = 0;
    bool main = false;
    size_t headers = 0;
    while (offset < size) {
        budget.check();
        if (++headers > 50000) throw std::runtime_error("import_cba_limit");
        require(size - offset >= 4);
        const Bytes prefix = readAt(fd, offset, 4);
        const size_t length = size_t(little(prefix, 2, 2));
        require(length >= 3 && length <= size - offset - 4);
        const Bytes header = readAt(fd, offset + 4, length);
        require((crc(header) & 65535) == little(prefix, 0, 2));
        const unsigned type = header[0], flags = unsigned(little(header, 1, 2));
        offset += 4 + length;
        if (!main) {
            require(type == 0 && !(flags & 1) && header.size() >= 27);
            require(std::string(header.begin() + 3, header.begin() + 10) == "**ACE**");
            if (flags & 0x800 || header[13]) throw std::runtime_error("import_cba_volume");
            require(header[10] <= 20 && 27U + header[26] <= header.size());
            solid = (flags & 0x8000) != 0; main = true; continue;
        }
        require(type != 0);
        if (type == 1 || type == 3) {
            require((flags & 1) && bool(flags & 4) == (type == 3));
            if (flags & 0x4000) throw std::runtime_error("import_cba_password");
            if (flags & 0x3000) throw std::runtime_error("import_cba_volume");
            const size_t width = flags & 4 ? 8 : 4;
            Entry entry;
            entry.packed = little(header, 3, width); entry.size = little(header, 3 + width, width);
            const size_t p = 3 + 2 * width;
            const uint32_t attributes = uint32_t(little(header, p + 4, 4));
            entry.directory = (attributes & 0x10) != 0;
            entry.checksum = uint32_t(little(header, p + 8, 4));
            entry.method = uint8_t(little(header, p + 12, 1));
            require((little(header, p + 14, 2) & 15) <= 12);
            const size_t nameSize = size_t(little(header, p + 18, 2));
            require(nameSize && nameSize <= 4096 && p + 20 + nameSize <= header.size());
            entry.name.assign(header.begin() + p + 20, header.begin() + p + 20 + nameSize);
            require(entry.name.find('\0') == std::string::npos);
            require(entry.packed <= size - offset);
            if (entry.size > 20 * MIB || entry.packed > 32 * MIB || total + entry.size > 6 * 1024 * MIB) {
                throw std::runtime_error("import_cba_limit");
            }
            if (entry.method > 2) throw std::runtime_error("import_cba_method");
            if (entry.directory) require(entry.size == 0 && entry.packed == 0);
            total += entry.size; entry.offset = offset; offset += entry.packed;
            entries.push_back(std::move(entry));
        } else if (flags & 1) {
            // Recovery and optional headers never supply application paths or content.
            const uint64_t extra = little(header, 3, flags & 4 ? 8 : 4);
            require(extra <= size - offset); offset += extra;
        }
    }
    require(main && !entries.empty());
}

Bytes Archive::read(size_t index) {
    require(index == next && index < entries.size());
    ++next; budget.check();
    const auto& entry = entries[index];
    if (!solid) decoder.reset();
    if (entry.directory) return {};
    const Bytes packed = readAt(fd, entry.offset, size_t(entry.packed));
    Bytes data = decoder.decode(packed, size_t(entry.size), entry.method);
    require(data.size() == entry.size && crc(data) == entry.checksum);
    return data;
}

std::vector<std::string> extractComic(int fd, const std::string& directory,
    const std::function<void(size_t, size_t)>& progress) {
    Budget budget; Archive archive(fd, budget);
    std::vector<size_t> order;
    uint64_t needed = 0;
    for (size_t i = 0; i < archive.entries.size(); ++i) if (archive.entries[i].image()) {
        order.push_back(i); needed += archive.entries[i].size;
    }
    if (order.empty()) throw std::runtime_error("import_cba_no_images");
    auto space = [&](uint64_t amount) {
        struct statvfs info{};
        if (statvfs(directory.c_str(), &info) != 0 || uint64_t(info.f_bavail) * info.f_frsize < amount + 256 * MIB) {
            throw std::runtime_error("import_cba_space");
        }
    };
    space(needed);
    std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) {
        return naturalLess(archive.entries[a].name, archive.entries[b].name);
    });
    std::vector<std::string> paths(archive.entries.size()), created;
    std::vector<std::string> result;
    for (size_t i = 0; i < order.size(); ++i) {
        std::string path = directory + "/image_" + std::to_string(i) + "_0.img";
        paths[order[i]] = path; result.push_back(path);
    }
    try {
        progress(0, archive.entries.size());
        for (size_t i = 0; i < archive.entries.size(); ++i) {
            // Always decode physical order, including non-images needed by a solid dictionary.
            const Bytes data = archive.read(i);
            if (!paths[i].empty()) {
                space(data.size()); writeImage(paths[i], data); created.push_back(paths[i]);
            }
            progress(i + 1, archive.entries.size());
        }
    } catch (...) { for (const auto& path : created) unlink(path.c_str()); throw; }
    return result;
}
}
