#include "offline_tts_archive_core.h"
#include "offline_tts_assets.h"
#include "bzlib.h"
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <set>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

// BZ_NO_STDIO delegates internal invariant failures to its host. Keep errors
// inside the import transaction instead of invoking upstream's process exit.
extern "C" void bz_internal_error(int) { throw std::runtime_error("offline_tts_pack_invalid"); }

namespace hsda::offline_tts {
namespace {
constexpr uint64_t MAX_EXPANDED = 256ULL * 1024 * 1024;
constexpr uint64_t MAX_SINGLE = 128ULL * 1024 * 1024;
constexpr uint64_t MAX_SOURCE = 192ULL * 1024 * 1024;
constexpr size_t BLOCK = 65536;

void require(bool value, const char *error = "offline_tts_pack_invalid") {
    if (!value) throw std::runtime_error(error);
}

class Fd {
public:
    explicit Fd(int value = -1) : value_(value) {}
    ~Fd() { if (value_ >= 0) close(value_); }
    Fd(const Fd &) = delete;
    Fd &operator=(const Fd &) = delete;
    int get() const { return value_; }
    void reset(int value) { if (value_ >= 0) close(value_); value_ = value; }
private:
    int value_;
};

class Reader {
public:
    Reader(int fd, const std::function<void()> &check) : fd_(fd), check_(check) {
        struct stat status {};
        require(fstat(fd_, &status) == 0 && status.st_size > 0 && uint64_t(status.st_size) <= MAX_SOURCE);
        size_ = uint64_t(status.st_size);
        require(BZ2_bzDecompressInit(&stream_, 0, 0) == BZ_OK);
        initialized_ = true;
    }
    ~Reader() { if (initialized_) BZ2_bzDecompressEnd(&stream_); }

    size_t read(char *output, size_t length) {
        check_();
        if (ended_) return 0;
        require(length > 0 && length <= BLOCK);
        while (true) {
            check_();
            if (stream_.avail_in == 0 && sourceAt_ < size_) {
                ssize_t count;
                do { count = pread(fd_, input_.data(), std::min<uint64_t>(BLOCK, size_ - sourceAt_), off_t(sourceAt_)); }
                while (count < 0 && errno == EINTR);
                require(count > 0);
                sourceAt_ += uint64_t(count);
                stream_.next_in = input_.data(); stream_.avail_in = unsigned(count);
            }
            stream_.next_out = output; stream_.avail_out = unsigned(length);
            const unsigned before = stream_.avail_in;
            const int status = BZ2_bzDecompress(&stream_);
            const size_t count = length - stream_.avail_out;
            expanded_ += count;
            require(expanded_ <= MAX_EXPANDED, "offline_tts_archive_limit");
            require(status == BZ_OK || status == BZ_STREAM_END);
            if (status == BZ_STREAM_END) {
                ended_ = true;
                // Reject concatenated BZ streams and ignored trailing compressed payloads.
                require(stream_.avail_in == 0 && sourceAt_ == size_);
            }
            if (count > 0 || ended_) return count;
            require(before != stream_.avail_in || sourceAt_ < size_);
        }
    }

    void exact(char *output, size_t length) {
        size_t offset = 0;
        while (offset < length) {
            const size_t count = read(output + offset, std::min(BLOCK, length - offset));
            require(count > 0); offset += count;
        }
    }

    void skip(uint64_t length) {
        std::array<char, BLOCK> buffer {};
        while (length > 0) {
            const size_t count = size_t(std::min<uint64_t>(BLOCK, length));
            exact(buffer.data(), count); length -= count;
        }
    }

    void finishZeros() {
        std::array<char, BLOCK> buffer {};
        while (const size_t count = read(buffer.data(), buffer.size())) {
            require(std::all_of(buffer.begin(), buffer.begin() + count, [](char value) { return value == 0; }));
        }
    }
private:
    int fd_;
    std::function<void()> check_;
    bz_stream stream_ {};
    std::array<char, BLOCK> input_ {};
    uint64_t sourceAt_ = 0, size_ = 0, expanded_ = 0;
    bool initialized_ = false, ended_ = false;
};

uint64_t octal(const char *value, size_t length) {
    uint64_t result = 0; bool trailing = false, started = false;
    for (size_t i = 0; i < length; i++) {
        const unsigned char c = static_cast<unsigned char>(value[i]);
        if (c == 0 || c == ' ') { if (started || c == 0) trailing = true; continue; }
        require(!trailing && c >= '0' && c <= '7');
        require(result <= (MAX_EXPANDED >> 3));
        result = result * 8 + c - '0'; started = true;
    }
    return result;
}

std::string field(const char *value, size_t length) {
    size_t count = 0; while (count < length && value[count] != 0) count++;
    return std::string(value, count);
}

void safePath(const std::string &path) {
    require(!path.empty() && path.size() <= 512 && path[0] != '/');
    size_t begin = 0, depth = 0;
    for (size_t i = 0; i <= path.size(); i++) {
        if (i < path.size()) {
            const unsigned char c = static_cast<unsigned char>(path[i]);
            require(c >= 32 && c <= 126 && c != '\\' && c != ':');
        }
        if (i == path.size() || path[i] == '/') {
            const std::string part = path.substr(begin, i - begin);
            require(!part.empty() && part != "." && part != "..");
            require(++depth <= 8); begin = i + 1;
        }
    }
}

// Walk known paths relative to the staging fd. No symlink can redirect writes.
int parentFd(int root, const std::string &name, bool create) {
    Fd current(fcntl(root, F_DUPFD_CLOEXEC, 0));
    require(current.get() >= 0, "offline_tts_write");
    size_t begin = 0;
    while (true) {
        const size_t slash = name.find('/', begin);
        if (slash == std::string::npos) break;
        const std::string part = name.substr(begin, slash - begin);
        if (create && mkdirat(current.get(), part.c_str(), 0700) != 0) require(errno == EEXIST, "offline_tts_write");
        const int next = openat(current.get(), part.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        require(next >= 0, "offline_tts_write"); current.reset(next); begin = slash + 1;
    }
    const int result = fcntl(current.get(), F_DUPFD_CLOEXEC, 0);
    require(result >= 0, "offline_tts_write"); return result;
}

std::string leaf(const std::string &path) {
    const size_t slash = path.rfind('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}
}

size_t extractTarBz2(int fd, const std::string &staging, const std::string &modelId, const std::function<void()> &check,
                     const std::function<void(uint64_t)> &progress) {
    const OfflineTtsNativeModel *model = nullptr;
    for (const auto &candidate : OFFLINE_TTS_NATIVE_MODELS) {
        if (modelId == candidate.id) { model = &candidate; break; }
    }
    require(model != nullptr);
    const std::string suffix = "/offline_tts/" + modelId + ".importing";
    const std::string prefix = std::string(model->archiveRoot) + "/";
    require(staging.size() > suffix.size() && staging.compare(staging.size() - suffix.size(), suffix.size(), suffix) == 0);
    require(staging.find("/../") == std::string::npos && staging.find("/./") == std::string::npos);
    Fd root(open(staging.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    require(root.get() >= 0, "offline_tts_write");
    std::unordered_map<std::string, uint64_t> expected;
    for (size_t i = 0; i < model->count; i++) expected.emplace(model->assets[i].name, model->assets[i].bytes);
    std::set<std::string> seen, selected;
    std::vector<std::string> created;
    uint64_t written = 0, declared = 0;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(240);
    const auto bounded = [&]() {
        check(); require(std::chrono::steady_clock::now() < deadline, "offline_tts_timeout");
    };
    try {
        Reader reader(fd, bounded);
        std::array<char, 512> header {};
        std::array<char, BLOCK> buffer {};
        size_t entries = 0;
        while (true) {
            bounded(); reader.exact(header.data(), header.size());
            if (std::all_of(header.begin(), header.end(), [](char value) { return value == 0; })) {
                reader.exact(header.data(), header.size());
                require(std::all_of(header.begin(), header.end(), [](char value) { return value == 0; }));
                reader.finishZeros(); break;
            }
            require(++entries <= 4096, "offline_tts_archive_limit");
            uint64_t checksum = 0;
            for (size_t i = 0; i < header.size(); i++) checksum += i >= 148 && i < 156 ? ' ' : static_cast<unsigned char>(header[i]);
            require(octal(header.data() + 148, 8) == checksum);
            require(std::memcmp(header.data() + 257, "ustar", 5) == 0);
            std::string name = field(header.data(), 100);
            // POSIX prefix is not the GNU extended header area.
            if (header[262] == 0) {
                const std::string prefix = field(header.data() + 345, 155);
                if (!prefix.empty()) name = prefix + "/" + name;
            }
            if (name.rfind("./", 0) == 0) name.erase(0, 2);
            const char type = header[156];
            require(type == '0' || type == 0 || type == '5');
            if (type == '5' && !name.empty() && name.back() == '/') name.pop_back();
            safePath(name); require(seen.insert(name).second);
            require(name == model->archiveRoot || name.rfind(prefix, 0) == 0);
            const uint64_t size = octal(header.data() + 124, 12);
            declared += size;
            require(size <= MAX_SINGLE && declared <= MAX_EXPANDED, "offline_tts_archive_limit");
            if (type == '5') { require(size == 0); continue; }
            const std::string relative = name.rfind(prefix, 0) == 0 ? name.substr(prefix.size()) : "";
            const auto found = expected.find(relative);
            if (found == expected.end()) reader.skip(size);
            else {
                require(size == found->second && selected.insert(relative).second);
                Fd parent(parentFd(root.get(), relative, true));
                const std::string file = leaf(relative);
                Fd output(openat(parent.get(), file.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
                require(output.get() >= 0, "offline_tts_write"); created.push_back(relative);
                for (uint64_t remaining = size; remaining > 0;) {
                    bounded(); const size_t count = size_t(std::min<uint64_t>(BLOCK, remaining));
                    reader.exact(buffer.data(), count);
                    size_t offset = 0;
                    while (offset < count) {
                        bounded(); ssize_t n;
                        do { n = write(output.get(), buffer.data() + offset, count - offset); } while (n < 0 && errno == EINTR);
                        require(n > 0, "offline_tts_write"); offset += size_t(n);
                    }
                    remaining -= count; written += count; progress(written);
                }
                require(fsync(output.get()) == 0, "offline_tts_write");
            }
            reader.skip((512 - size % 512) % 512);
        }
        bounded(); require(selected.size() == model->count && written == model->bytes);
        require(fsync(root.get()) == 0, "offline_tts_write");
        return selected.size();
    } catch (...) {
        for (auto at = created.rbegin(); at != created.rend(); ++at) {
            try { Fd parent(parentFd(root.get(), *at, false)); unlinkat(parent.get(), leaf(*at).c_str(), 0); }
            catch (...) { /* The owning ArkTS importer also removes the staging directory. */ }
        }
        throw;
    }
}
}
