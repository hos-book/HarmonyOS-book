// Copyright (c) 2017-2026, Daniel Roethlisberger and contributors.
// C++ adaptation for bounded local comic import. See LICENSE (BSD-2-Clause).
#include "AceDecoder.h"
#include <algorithm>
#include <numeric>
#include <utility>

namespace hsda::ace {
namespace {
int bitLength(uint32_t value) { int bits = 0; while (value) { ++bits; value >>= 1; } return bits; }
int signedByte(int value) { value &= 255; return value < 128 ? value : value - 256; }

class Bits {
    const Bytes& data;
    size_t position = 0;
    Budget& budget;
    uint32_t word(size_t index) const {
        const size_t p = index * 4;
        if (p >= data.size()) return 0;
        return uint32_t(data[p]) | (uint32_t(data[p + 1]) << 8) |
            (uint32_t(data[p + 2]) << 16) | (uint32_t(data[p + 3]) << 24);
    }
public:
    Bits(const Bytes& bytes, Budget& limit) : data(bytes), budget(limit) { require(data.size() % 4 == 0); }
    uint32_t peek(unsigned count) const {
        require(count <= 31 && position + count <= data.size() * 8 + 31);
        if (!count) return 0;
        uint64_t joined = (uint64_t(word(position / 32)) << 32) | word(position / 32 + 1);
        return uint32_t((joined << (position % 32)) >> (64 - count));
    }
    void skip(unsigned count) {
        require(position + count <= data.size() * 8);
        position += count; budget.tick();
    }
    uint32_t read(unsigned count) { const auto value = peek(count); skip(count); return value; }
    uint32_t known(unsigned count) { return count < 2 ? count : read(count - 1) + (1U << (count - 1)); }
    uint32_t rice(unsigned count) {
        require(count <= 24);
        uint32_t value = read(count);
        while (read(1)) { require(value < (1U << 25)); value += 1U << count; }
        return value;
    }
    int signedRice(unsigned count) {
        uint32_t value = rice(count);
        return (value & 1) ? -int(value >> 1) - 1 : int(value >> 1);
    }
};

struct Mode {
    int kind = -1;
    unsigned distance = 0;
    size_t length = 0;
    int executable = 0;
    static Mode read(Bits& bits) {
        Mode mode; mode.kind = int(bits.read(8));
        require(mode.kind <= 7);
        if (mode.kind == 1) { mode.distance = bits.read(8); mode.length = bits.read(17); }
        else if (mode.kind == 2) mode.executable = int(bits.read(8));
        return mode;
    }
};
struct Chunk { Bytes bytes; Mode next; };

class Huffman {
    std::vector<int> codes;
    std::vector<int> widths;
    unsigned maximum = 0;
    // ACE's ordering of equal widths is significant. std::sort is not equivalent.
    static void sort(std::vector<int>& keys, std::vector<int>& values, int left, int right) {
        int a = left, b = right, pivot = keys[right];
        do {
            while (keys[a] > pivot) ++a;
            while (keys[b] < pivot) --b;
            if (a <= b) { std::swap(keys[a], keys[b]); std::swap(values[a], values[b]); ++a; --b; }
        } while (a < b);
        auto pair = [&](int x, int y) {
            if (keys[x] < keys[y]) { std::swap(keys[x], keys[y]); std::swap(values[x], values[y]); }
        };
        if (left < b) { if (left < b - 1) sort(keys, values, left, b); else pair(left, b); }
        if (right > a) { if (a < right - 1) sort(keys, values, a, right); else pair(a, right); }
    }
    static Huffman make(std::vector<int> widths, unsigned maximum) {
        require(!widths.empty());
        std::vector<int> symbols(widths.size());
        std::iota(symbols.begin(), symbols.end(), 0);
        auto ordered = widths;
        sort(ordered, symbols, 0, int(widths.size()) - 1);
        size_t used = 0;
        while (used < ordered.size() && ordered[used]) ++used;
        if (used < 2) { widths[symbols[0]] = 1; if (!used) ++used; }
        Huffman tree; tree.maximum = maximum; tree.widths = std::move(widths);
        for (size_t i = used; i-- > 0;) {
            require(ordered[i] >= 0 && unsigned(ordered[i]) <= maximum);
            const size_t repeat = 1U << (maximum - ordered[i]);
            require(tree.codes.size() + repeat <= (1U << maximum));
            tree.codes.insert(tree.codes.end(), repeat, symbols[i]);
        }
        return tree;
    }
public:
    int symbol(Bits& bits) const {
        const auto code = bits.peek(maximum);
        require(code < codes.size());
        const int value = codes[code]; bits.skip(widths[value]); return value;
    }
    static Huffman read(Bits& bits, unsigned maximum, unsigned count) {
        const size_t number = std::min(bits.read(9) + 1, count + 1);
        const int lower = int(bits.read(4)), upper = int(bits.read(4));
        std::vector<int> smallWidths;
        for (int i = 0; i <= upper; ++i) smallWidths.push_back(int(bits.read(3)));
        const Huffman small = make(std::move(smallWidths), 7);
        std::vector<int> widths;
        while (widths.size() < number) {
            int code = small.symbol(bits);
            if (code < upper) widths.push_back(code);
            else widths.insert(widths.end(), std::min(size_t(bits.read(4) + 4), number - widths.size()), 0);
        }
        if (upper) for (size_t i = 1; i < widths.size(); ++i) widths[i] = (widths[i] + widths[i - 1]) % upper;
        for (auto& width : widths) if (width) width += lower;
        return make(std::move(widths), maximum);
    }
};

class Lz {
    Decoder& decoder;
    Huffman mainTree, lengthTree;
    unsigned symbols = 0;
    std::array<unsigned, 4> distances{};
public:
    explicit Lz(Decoder& owner) : decoder(owner) {}
    Chunk read(Bits& bits, size_t wanted) {
        Chunk chunk;
        while (chunk.bytes.size() < wanted) {
            if (!symbols) {
                mainTree = Huffman::read(bits, 11, 284);
                lengthTree = Huffman::read(bits, 11, 255);
                symbols = bits.read(15); require(symbols > 0);
            }
            --symbols;
            const int symbol = mainTree.symbol(bits);
            if (symbol < 256) { chunk.bytes.push_back(uint8_t(symbol)); decoder.registerByte(uint8_t(symbol)); }
            else if (symbol < 283) {
                unsigned distance;
                size_t length;
                if (symbol <= 259) {
                    const int offset = symbol & 3;
                    length = lengthTree.symbol(bits) + (offset > 1 ? 3 : 2);
                    distance = distances[3 - offset];
                    for (int i = 3 - offset; i < 3; ++i) distances[i] = distances[i + 1];
                } else {
                    distance = bits.known(symbol - 260);
                    length = lengthTree.symbol(bits) + (distance <= 255 ? 2 : distance <= 8191 ? 3 : 4);
                    for (size_t i = 0; i < 3; ++i) distances[i] = distances[i + 1];
                }
                distances[3] = distance;
                require(length <= wanted - chunk.bytes.size());
                decoder.copy(chunk.bytes, size_t(distance) + 1, length);
            } else if (symbol == 283) { chunk.next = Mode::read(bits); break; }
            else invalid();
        }
        return chunk;
    }
};

struct SoundChannel {
    std::array<int, 2> prediction{}, previous{};
    std::array<int, 4> differences{}, coefficients{};
    std::array<int, 9> errors{};
    unsigned count = 0;
    int sample = 0, delta = 0, adaptation = 0, use = 0, state = 0, code = 0;
    int predicted() const {
        int value = 8 * sample;
        for (size_t i = 0; i < 4; ++i) value += coefficients[i] * differences[i];
        return (value >> 3) & 255;
    }
    int predict() const { return prediction[0] > prediction[1] ? sample : predicted(); }
    static int quantize(int value) { value &= 255; return bitLength(std::min(value, 256 - value)); }
    void adjust(int value) {
        ++count;
        const int difference = signedByte(predicted() - value) * 8;
        for (size_t i = 0; i < 4; ++i) {
            errors[2 * i] += std::abs(difference - differences[i]);
            errors[2 * i + 1] += std::abs(difference + differences[i]);
        }
        errors[8] += std::abs(difference);
        delta = signedByte(value - sample);
        prediction[0] += quantize(difference >> 3);
        prediction[1] += quantize(sample - value);
        sample = value;
        if ((count & 31) == 0) {
            int best = 8, minimum = 65535;
            for (int i = 8; i >= 0; --i) { if (errors[i] <= minimum) { minimum = errors[i]; best = i; } errors[i] = 0; }
            if (best != 8) {
                int& coefficient = coefficients[best / 2];
                if ((best & 1) == 0) { if (coefficient >= -16) --coefficient; }
                else if (coefficient <= 16) ++coefficient;
            }
            if ((count & 255) == 0) for (size_t i = 0; i < 2; ++i) {
                prediction[i] -= previous[i]; previous[i] = prediction[i];
            }
        }
        differences[3] = differences[2]; differences[2] = differences[1];
        differences[1] = delta - differences[0]; differences[0] = delta;
    }
};

class Sound {
    int mode = 0;
    unsigned symbols = 0;
    std::vector<Huffman> trees;
    std::array<SoundChannel, 3> channels{};
    int get(Bits& bits, int index, Mode& next) {
        auto& ch = channels[index];
        if (ch.state != 2) {
            if (!symbols) {
                for (auto& tree : trees) tree = Huffman::read(bits, 10, 289);
                symbols = bits.read(15); require(symbols > 0);
            }
            --symbols;
            const int model = (ch.state ? ch.state * 2 : ch.use) + 3 * index;
            require(size_t(model) < trees.size());
            ch.code = trees[model].symbol(bits);
            if (ch.code == 288) { next = Mode::read(bits); return 0; }
        }
        int value = 0;
        if (ch.state == 0) {
            if (ch.code >= 32) {
                value = ch.code - 32;
                ch.adaptation = (ch.adaptation * 7 >> 3) + value;
                ch.use = ch.adaptation > 40 ? 1 : 0;
            } else ch.state = 2;
        } else if (ch.state == 1) { value = ch.code; ch.state = 0; }
        if (ch.state == 2) { if (ch.code == 0) ch.state = 1; else --ch.code; value = 0; }
        return (value & 1) ? 255 - (value >> 1) : value >> 1;
    }
public:
    void reset(int kind) {
        mode = kind - 3; symbols = 0; channels = {};
        constexpr int counts[] = {1, 2, 3, 3}; trees = std::vector<Huffman>(counts[mode] * 3);
    }
    Chunk read(Bits& bits, size_t wanted) {
        constexpr int order[4][4] = {{0, 0, 0, 0}, {0, 1, 0, 1}, {0, 1, 0, 2}, {1, 0, 2, 0}};
        Chunk chunk;
        for (size_t i = 0; i < (wanted & ~size_t(3)); ++i) {
            const int index = order[mode][i % 4];
            const int value = get(bits, index, chunk.next);
            if (chunk.next.kind != -1) break;
            const uint8_t sample = uint8_t(value + channels[index].predict());
            chunk.bytes.push_back(sample); channels[index].adjust(signedByte(sample));
        }
        return chunk;
    }
};

struct ErrorContext {
    unsigned used = 0, predictor = 0, average = 4;
    std::array<unsigned, 4> errors{};
};
struct Pixel {
    int kind, a, b, c, d = 0, x;
    explicit Pixel(int mode) : kind(mode), a(mode ? 128 : 0), b(a), c(a), x(a) {}
    static int quantize(int value) {
        const int absolute = std::abs(value);
        int q = absolute == 0 ? 0 : absolute <= 2 ? 1 : absolute <= 6 ? 2 : absolute <= 20 ? 3 : 4;
        return value < 0 ? -q : q;
    }
    unsigned context() const { return unsigned(std::abs(81 * quantize(d - a) + 9 * quantize(a - c) + quantize(c - b))); }
    int predict(unsigned id) const {
        if (id == 0) return a;
        if (id == 1) return b;
        return id == 2 ? (a + b) >> 1 : (a + b - c) & 255;
    }
    void updateD(int current, int reference) {
        d = kind == 0 ? current : (128 + current - (kind == 1 ? reference : reference * 11 >> 4)) & 255;
    }
    uint8_t produce(int reference) const {
        return uint8_t(kind == 0 ? x : x + (kind == 1 ? reference : reference * 11 >> 4) - 128);
    }
    void read(Bits& bits, ErrorContext& context) {
        ++context.used;
        const int epsilon = bits.signedRice(bitLength(context.average / context.used));
        x = (predict(context.predictor) + epsilon) & 255;
        context.average += unsigned(std::abs(epsilon));
        if (context.used == 128) { context.used >>= 1; context.average >>= 1; }
        unsigned best = 0;
        bool halve = false;
        for (unsigned i = 0; i < 4; ++i) {
            const int difference = signedByte(x - predict(i));
            context.errors[i] += bitLength(unsigned(difference < 0 ? -2 * difference - 1 : 2 * difference));
            if (context.errors[i] < context.errors[best]) best = i;
            if (context.errors[i] > 127) halve = true;
        }
        context.predictor = best;
        if (halve) for (auto& error : context.errors) error >>= 1;
    }
};

class Picture {
    size_t width = 0, planes = 0;
    std::array<ErrorContext, 365> first{}, others{};
    Bytes previous, leftover;
    Bytes row(Bits& bits) {
        Bytes output(width + planes, 0);
        for (size_t plane = 0; plane < planes; ++plane) {
            int kind = plane == 0 ? 0 : int(bits.read(2)); require(kind <= 2);
            Pixel pixel(kind);
            auto& model = plane == 0 ? first : others;
            pixel.updateD(previous[plane], plane ? previous[plane - 1] : previous.back());
            for (size_t column = plane; column < width; column += planes) {
                pixel.c = pixel.a; pixel.a = pixel.d; pixel.b = pixel.x;
                pixel.updateD(previous[column + planes], previous[column + planes - 1]);
                const unsigned context = pixel.context(); require(context < model.size());
                pixel.read(bits, model[context]);
                output[column] = pixel.produce(column ? output[column - 1] : output.back());
            }
        }
        previous = output; output.resize(width); return output;
    }
public:
    void reset(Bits& bits) {
        width = bits.rice(12); planes = bits.rice(2);
        require(width > 0 && width <= 1024 * 1024 && planes > 0 && planes <= 256);
        first = {}; others = {}; previous = Bytes(width + planes, 0); leftover.clear();
    }
    Chunk read(Bits& bits, size_t wanted) {
        Chunk chunk; chunk.bytes.swap(leftover);
        require(chunk.bytes.size() <= wanted);
        while (chunk.bytes.size() < wanted) {
            if (bits.read(1) == 0) { chunk.next = Mode::read(bits); break; }
            auto data = row(bits);
            const size_t take = std::min(wanted - chunk.bytes.size(), data.size());
            chunk.bytes.insert(chunk.bytes.end(), data.begin(), data.begin() + take);
            leftover.assign(data.begin() + take, data.end());
        }
        return chunk;
    }
};
}

void Decoder::registerByte(uint8_t value) {
    dictionary[position] = value; position = (position + 1) & (dictionary.size() - 1);
    filled = std::min(filled + 1, dictionary.size()); budget.tick();
}
void Decoder::copy(Bytes& output, size_t distance, size_t count) {
    require(distance > 0 && distance <= filled);
    for (size_t i = 0; i < count; ++i) {
        const uint8_t value = dictionary[(position + dictionary.size() - distance) & (dictionary.size() - 1)];
        output.push_back(value); registerByte(value);
    }
}

Bytes Decoder::decode(const Bytes& packed, size_t size, uint8_t method) {
    require(size <= 20 * 1024 * 1024);
    if (method == 0) {
        require(packed.size() == size);
        for (auto byte : packed) registerByte(byte);
        return packed;
    }
    require(method == 1 || method == 2);
    Bits bits(packed, budget); Lz lz(*this);
    if (method == 1) { auto chunk = lz.read(bits, size); require(chunk.next.kind == -1); return chunk.bytes; }
    Sound sound; Picture picture; Mode mode; mode.kind = 0; Mode next;
    Bytes output, exeLeftover; output.reserve(size);
    int lastDelta = 0;
    while (output.size() < size) {
        budget.tick();
        if (next.kind != -1) {
            if (next.kind != mode.kind) {
                if (next.kind >= 3 && next.kind <= 6) sound.reset(next.kind);
                else if (next.kind == 7) picture.reset(bits);
            }
            mode = next; next = Mode();
        }
        Chunk chunk;
        if (mode.kind == 1) {
            require(mode.distance && mode.length && mode.length % mode.distance == 0 && mode.length <= size - output.size());
            Bytes delta;
            while (delta.size() < mode.length) {
                auto part = lz.read(bits, mode.length - delta.size());
                delta.insert(delta.end(), part.bytes.begin(), part.bytes.end());
                if (part.next.kind != -1) { require(next.kind == -1); next = part.next; if (delta.empty()) break; }
                require(!part.bytes.empty() || part.next.kind != -1);
            }
            if (delta.empty() && next.kind != -1) continue;
            for (auto& value : delta) { value = uint8_t(value + lastDelta); lastDelta = value; }
            const size_t planeSize = mode.length / mode.distance;
            for (size_t p = 0; p < planeSize; ++p)
                for (size_t base = 0; base < mode.length; base += planeSize) chunk.bytes.push_back(delta[base + p]);
        } else if (mode.kind == 0 || mode.kind == 2) {
            chunk.bytes.swap(exeLeftover);
            require(chunk.bytes.size() <= size - output.size());
            if (chunk.bytes.size() < size - output.size()) {
                auto part = lz.read(bits, size - output.size() - chunk.bytes.size());
                next = part.next; chunk.bytes.insert(chunk.bytes.end(), part.bytes.begin(), part.bytes.end());
            }
            if (mode.kind == 2) {
                size_t i = 0;
                for (; i + 4 < chunk.bytes.size(); ++i) {
                    if (chunk.bytes[i] != 0xe8 && chunk.bytes[i] != 0xe9) continue;
                    const size_t width = chunk.bytes[i] == 0xe8 && mode.executable != 0 ? 4 : 2;
                    uint32_t relative = 0;
                    for (size_t j = 0; j < width; ++j) relative |= uint32_t(chunk.bytes[i + 1 + j]) << (8 * j);
                    relative -= uint32_t(output.size() + i);
                    for (size_t j = 0; j < width; ++j) chunk.bytes[i + 1 + j] = uint8_t(relative >> (8 * j));
                    i += width;
                }
                // A mode transition can split a machine instruction. Carry only that tail.
                if (next.kind != -1) for (; i < chunk.bytes.size(); ++i) {
                    if (chunk.bytes[i] == 0xe8 || chunk.bytes[i] == 0xe9) {
                        exeLeftover.assign(chunk.bytes.begin() + i, chunk.bytes.end()); chunk.bytes.resize(i); break;
                    }
                }
            }
        } else if (mode.kind >= 3 && mode.kind <= 7) {
            chunk = mode.kind == 7 ? picture.read(bits, size - output.size()) : sound.read(bits, size - output.size());
            next = chunk.next;
            for (auto byte : chunk.bytes) registerByte(byte);
        } else invalid();
        require(chunk.bytes.size() <= size - output.size());
        require(!chunk.bytes.empty() || next.kind != -1);
        output.insert(output.end(), chunk.bytes.begin(), chunk.bytes.end());
    }
    require(exeLeftover.empty());
    return output;
}

uint32_t crc(const Bytes& bytes) {
    static const auto table = [] {
        std::array<uint32_t, 256> values{};
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t value = i;
            for (int bit = 0; bit < 8; ++bit) value = (value >> 1) ^ ((value & 1) ? 0xedb88320U : 0);
            values[i] = value;
        }
        return values;
    }();
    uint32_t result = 0xffffffff;
    for (uint8_t byte : bytes) result = table[(result ^ byte) & 255] ^ (result >> 8);
    return result;
}
}
