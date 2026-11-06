// Host-driven regression executable; never linked into the app.
#include "../entry/src/main/cpp/ace/AceArchive.h"
#include <fcntl.h>
#include <iostream>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return 3;
    try {
        if (argc == 3) {
            const auto pages = hsda::ace::extractComic(fd, argv[2], [](size_t, size_t) {});
            std::cout << "pages " << pages.size() << '\n';
        } else {
            hsda::ace::Budget budget;
            hsda::ace::Archive archive(fd, budget);
            for (size_t i = 0; i < archive.entries.size(); ++i) {
                const auto bytes = archive.read(i);
                uint64_t hash = 14695981039346656037ULL;
                for (auto byte : bytes) { hash ^= byte; hash *= 1099511628211ULL; }
                std::cout << i << ' ' << bytes.size() << ' ' << std::hex << hash << std::dec << '\n';
            }
        }
        close(fd); return 0;
    } catch (const std::exception& error) {
        close(fd); std::cout << "ERROR " << error.what() << '\n'; return 1;
    }
}
