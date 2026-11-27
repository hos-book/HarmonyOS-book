#include "hsda_core.h"
#include "speech_stream.h"
#include <napi/native_api.h>
#include <algorithm>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <unistd.h>
#include <zlib.h>

namespace {
void Check(bool success, const char *message = "rust_core_input") {
    if (!success) throw std::runtime_error(message);
}

void Status(uint32_t status) {
    if (status == 1) throw std::runtime_error("import_mobi_invalid");
    if (status == 2) throw std::runtime_error("import_mobi_size");
    if (status == 3) throw std::runtime_error("offline_tts_audio");
    if (status == 5) throw std::runtime_error("EPUB 元数据或目录过大");
    if (status == 6) throw std::runtime_error("EPUB XML 结构过大");
    if (status == 7) throw std::runtime_error("HTML 编解码超时");
    if (status == 8) throw std::runtime_error("TXT_CHAPTER_TOO_LARGE");
    Check(status == 0);
}

std::vector<napi_value> Args(napi_env env, napi_callback_info info, size_t count) {
    std::vector<napi_value> args(count);
    size_t received = count;
    Check(napi_get_cb_info(env, info, &received, args.data(), nullptr, nullptr) == napi_ok && received == count);
    return args;
}

uint32_t Uint(napi_env env, napi_value value) {
    double number;
    Check(napi_get_value_double(env, value, &number) == napi_ok && number >= 0 &&
        number <= UINT32_MAX && number == static_cast<uint32_t>(number));
    return static_cast<uint32_t>(number);
}

std::u16string Text(napi_env env, napi_value value) {
    size_t length = 0;
    Check(napi_get_value_string_utf16(env, value, nullptr, 0, &length) == napi_ok);
    std::u16string text(length + 1, u'\0');
    Check(napi_get_value_string_utf16(env, value, text.data(), text.size(), &length) == napi_ok);
    text.resize(length);
    return text;
}

struct TypedData { void *data; size_t length; };
TypedData Typed(napi_env env, napi_value value, napi_typedarray_type expected) {
    napi_typedarray_type type;
    napi_value buffer;
    TypedData result {};
    size_t offset = 0;
    Check(napi_get_typedarray_info(env, value, &type, &result.length, &result.data, &buffer, &offset) == napi_ok &&
        type == expected);
    return result;
}

napi_value TextResult(napi_env env, HsdaBuffer<uint16_t> buffer) {
    // N-API scans for the UTF-16 terminator even with an explicit length.
    std::u16string text(buffer.len + 1, u'\0');
    if (buffer.len) std::memcpy(text.data(), buffer.data, buffer.len * sizeof(uint16_t));
    napi_value result = nullptr;
    napi_status status = napi_create_string_utf16(env, text.c_str(), buffer.len, &result);
    hsda_text_free(buffer);
    Check(status == napi_ok, "rust_core_output");
    return result;
}

napi_value Bytes(napi_env env, const void *data, size_t length, bool typed = true) {
    napi_value buffer, result;
    void *destination = nullptr;
    Check(napi_create_arraybuffer(env, length, &destination, &buffer) == napi_ok, "rust_core_output");
    if (length) std::memcpy(destination, data, length);
    if (!typed) return buffer;
    Check(napi_create_typedarray(env, napi_uint8_array, length, buffer, 0, &result) == napi_ok, "rust_core_output");
    return result;
}

template<typename F> napi_value Call(napi_env env, F operation) {
    try { return operation(); }
    catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}

napi_value WaitRuleHostInterval(napi_env env, napi_callback_info) {
    // Keep the mailbox worker's existing polling interval within a native call.
    usleep(50 * 1000);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

napi_value Transform(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        auto input = Text(env, args[0]);
        auto result = hsda_text(reinterpret_cast<const uint16_t *>(input.data()), input.size(), Uint(env, args[1]));
        Status(result.status);
        return TextResult(env, result);
    });
}

napi_value EpubBody(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto text = Text(env, args[0]), prefix = Text(env, args[1]);
        uint32_t count = 0;
        Check(napi_get_array_length(env, args[2], &count) == napi_ok);
        std::vector<std::u16string> images;
        images.reserve(count);
        for (uint32_t index = 0; index < count; ++index) {
            napi_value image;
            Check(napi_get_element(env, args[2], index, &image) == napi_ok);
            images.push_back(Text(env, image));
        }
        std::vector<HsdaInputText> input;
        input.reserve(count);
        for (const auto &image : images) {
            input.push_back({reinterpret_cast<const uint16_t *>(image.data()), image.size()});
        }
        return TextResult(env, hsda_epub_body(reinterpret_cast<const uint16_t *>(text.data()), text.size(),
            reinterpret_cast<const uint16_t *>(prefix.data()), prefix.size(), input.data(), input.size()));
    });
}

napi_value BoundedHtml(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto input = Text(env, args[0]);
        bool encode = false;
        Check(napi_get_value_bool(env, args[1], &encode) == napi_ok);
        auto buffer = hsda_html_bounded(reinterpret_cast<const uint16_t *>(input.data()), input.size(),
            encode, Uint(env, args[2]));
        Status(buffer.status);
        return TextResult(env, buffer);
    });
}

napi_value CleanBatch(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 1);
        uint32_t length = 0;
        Check(napi_get_array_length(env, args[0], &length) == napi_ok);
        napi_value output;
        Check(napi_create_array_with_length(env, length, &output) == napi_ok, "rust_core_output");
        for (uint32_t index = 0; index < length; ++index) {
            napi_value value;
            Check(napi_get_element(env, args[0], index, &value) == napi_ok);
            auto input = Text(env, value);
            auto buffer = hsda_text(reinterpret_cast<const uint16_t *>(input.data()), input.size(), 0);
            Check(napi_set_element(env, output, index, TextResult(env, buffer)) == napi_ok, "rust_core_output");
        }
        return output;
    });
}

napi_value Search(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto text = Text(env, args[0]), keyword = Text(env, args[1]);
        auto offsets = hsda_search(reinterpret_cast<const uint16_t *>(text.data()), text.size(),
            reinterpret_cast<const uint16_t *>(keyword.data()), keyword.size(), Uint(env, args[2]));
        napi_value buffer = nullptr, result = nullptr;
        void *data = nullptr;
        napi_status status = napi_create_arraybuffer(env, offsets.len * sizeof(uint32_t), &data, &buffer);
        if (status == napi_ok) {
            if (offsets.len) std::memcpy(data, offsets.data, offsets.len * sizeof(uint32_t));
            status = napi_create_typedarray(env, napi_uint32_array, offsets.len, buffer, 0, &result);
        }
        hsda_offsets_free(offsets);
        Check(status == napi_ok, "rust_core_output");
        return result;
    });
}

napi_value WhiteBorder(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto pixels = Typed(env, args[0], napi_uint8_array);
        double crop[4];
        hsda_white_border(static_cast<const uint8_t *>(pixels.data), pixels.length,
            Uint(env, args[1]), Uint(env, args[2]), crop);
        napi_value output;
        Check(napi_create_array_with_length(env, 4, &output) == napi_ok, "rust_core_output");
        for (uint32_t index = 0; index < 4; ++index) {
            napi_value number;
            Check(napi_create_double(env, crop[index], &number) == napi_ok &&
                napi_set_element(env, output, index, number) == napi_ok, "rust_core_output");
        }
        return output;
    });
}

napi_value Wave(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        auto samples = Typed(env, args[0], napi_float32_array);
        auto buffer = hsda_wave(static_cast<const float *>(samples.data), samples.length, Uint(env, args[1]));
        Status(buffer.status);
        napi_value output;
        try { output = Bytes(env, buffer.data, buffer.len, false); }
        catch (...) { hsda_bytes_free(buffer); throw; }
        hsda_bytes_free(buffer);
        return output;
    });
}

struct EpubZipJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    int fd = -1;
    size_t fileSize = 0;
    std::vector<uint32_t> entries;
    std::vector<std::vector<uint8_t>> output;
    std::string error;
    ~EpubZipJob() { if (fd >= 0) close(fd); }
};

std::vector<uint8_t> ReadEpubBytes(const EpubZipJob &job, size_t offset, size_t length) {
    if (offset > job.fileSize || length > 64 * 1024 * 1024 || length > job.fileSize - offset) {
        throw std::runtime_error("EPUB ZIP 读取范围超出文件: offset=" + std::to_string(offset) +
            "; length=" + std::to_string(length) + "; fileSize=" + std::to_string(job.fileSize));
    }
    std::vector<uint8_t> bytes(length);
    size_t at = 0;
    while (at < length) {
        ssize_t count = pread(job.fd, bytes.data() + at, length - at, static_cast<off_t>(offset + at));
        Check(count > 0, "EPUB 压缩包数据缺失");
        at += static_cast<size_t>(count);
    }
    return bytes;
}

void ExecuteEpubZip(napi_env, void *data) {
    auto &job = *static_cast<EpubZipJob *>(data);
    try {
        job.output.reserve(job.entries.size() / 4);
        for (size_t index = 0; index < job.entries.size(); index += 4) {
            size_t offset = static_cast<size_t>(job.entries[index]);
            size_t compressed = static_cast<size_t>(job.entries[index + 1]);
            size_t size = static_cast<size_t>(job.entries[index + 2]);
            uint32_t method = static_cast<uint32_t>(job.entries[index + 3]);
            auto header = ReadEpubBytes(job, offset, 30);
            const auto word = [&](size_t at) -> uint32_t {
                return header[at] | (static_cast<uint32_t>(header[at + 1]) << 8);
            };
            Check(word(0) == 0x4b50 && word(2) == 0x0403 && word(8) == method &&
                (word(6) & 1) == 0, "EPUB 资源头损坏");
            auto input = ReadEpubBytes(job, offset + 30 + word(26) + word(28), compressed);
            if (method == 0) {
                job.output.push_back(std::move(input));
            } else if (method == 8) {
                std::vector<uint8_t> output(std::max<size_t>(1, size));
                z_stream stream {};
                Check(inflateInit2(&stream, -15) == Z_OK, "EPUB 解压初始化失败");
                stream.next_in = input.data();
                stream.avail_in = static_cast<uInt>(input.size());
                stream.next_out = output.data();
                stream.avail_out = static_cast<uInt>(output.size());
                int status = inflate(&stream, Z_FINISH);
                size_t expanded = stream.total_out;
                inflateEnd(&stream);
                Check(status == Z_STREAM_END && expanded == size, "EPUB 资源解压失败");
                output.resize(size);
                job.output.push_back(std::move(output));
            } else {
                throw std::runtime_error("EPUB 压缩方式超出支持范围");
            }
        }
    } catch (const std::exception &error) { job.error = error.what(); }
}

void CompleteEpubZip(napi_env env, napi_status status, void *data) {
    std::unique_ptr<EpubZipJob> job(static_cast<EpubZipJob *>(data));
    if (status != napi_ok) job->error = "epub_zip_worker";
    napi_value output = nullptr;
    if (job->error.empty()) {
        try {
            Check(napi_create_array_with_length(env, job->output.size(), &output) == napi_ok, "rust_core_output");
            for (uint32_t index = 0; index < job->output.size(); ++index) {
                const auto &bytes = job->output[index];
                Check(napi_set_element(env, output, index, Bytes(env, bytes.data(), bytes.size(), false)) == napi_ok,
                    "rust_core_output");
            }
        } catch (const std::exception &error) { job->error = error.what(); }
    }
    if (job->error.empty()) { napi_resolve_deferred(env, job->deferred, output); }
    else {
        napi_value message, error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, job->deferred, error);
    }
    napi_delete_async_work(env, job->work);
}

napi_value ReadEpubEntries(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto job = std::make_unique<EpubZipJob>();
        job->fd = dup(static_cast<int>(Uint(env, args[0])));
        Check(job->fd >= 0, "EPUB 文件打开失败");
        job->fileSize = Uint(env, args[1]);
        uint32_t length = 0;
        Check(napi_get_array_length(env, args[2], &length) == napi_ok && length % 4 == 0);
        job->entries.reserve(length);
        for (uint32_t index = 0; index < length; ++index) {
            napi_value value;
            Check(napi_get_element(env, args[2], index, &value) == napi_ok);
            job->entries.push_back(Uint(env, value));
        }
        napi_value name, promise;
        try {
            Check(napi_create_promise(env, &job->deferred, &promise) == napi_ok &&
                napi_create_string_utf8(env, "EpubZipRead", NAPI_AUTO_LENGTH, &name) == napi_ok &&
                napi_create_async_work(env, nullptr, name, ExecuteEpubZip, CompleteEpubZip, job.get(), &job->work) == napi_ok &&
                napi_queue_async_work(env, job->work) == napi_ok, "epub_zip_worker");
        } catch (...) {
            if (job->work) napi_delete_async_work(env, job->work);
            throw;
        }
        job.release();
        return promise;
    });
}

struct HuffHandle {
    void *decoder = nullptr;
    ~HuffHandle() { hsda_huff_release(decoder); }
};

void FinalizeHuff(napi_env, void *data, void *) { delete static_cast<HuffHandle *>(data); }

struct MobiJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref handleRef = nullptr;
    std::vector<std::vector<uint8_t>> input;
    std::vector<HsdaBuffer<uint8_t>> output;
    HuffHandle *huff = nullptr;
    void *createdDecoder = nullptr;
    size_t capacity = 0;
    bool create = false;
    bool kf8 = false;
    HsdaBuffer<HsdaBuffer<uint8_t>> sections {};
    std::string error;
    ~MobiJob() {
        for (auto bytes : output) hsda_bytes_free(bytes);
        hsda_huff_release(createdDecoder);
        hsda_sections_free(sections);
    }
};

std::vector<std::vector<uint8_t>> Records(napi_env env, napi_value array) {
    uint32_t length = 0;
    Check(napi_get_array_length(env, array, &length) == napi_ok);
    std::vector<std::vector<uint8_t>> records;
    records.reserve(length);
    for (uint32_t index = 0; index < length; ++index) {
        napi_value value;
        Check(napi_get_element(env, array, index, &value) == napi_ok);
        auto bytes = Typed(env, value, napi_uint8_array);
        records.emplace_back(bytes.length);
        if (bytes.length) std::memcpy(records.back().data(), bytes.data, bytes.length);
    }
    return records;
}

void ExecuteMobi(napi_env, void *data) {
    auto &job = *static_cast<MobiJob *>(data);
    try {
        if (job.kf8) {
            std::vector<HsdaInputBytes> records;
            for (size_t index = 1; index < job.input.size(); ++index) {
                const auto &input = job.input[index];
                records.push_back({input.data(), input.size()});
            }
            const auto &raw = job.input[0];
            job.sections = hsda_kf8(raw.data(), raw.size(), records.data(), records.size(), job.capacity);
            Status(job.sections.status);
        } else if (job.create) {
            std::vector<HsdaInputBytes> records;
            for (const auto &input : job.input) records.push_back({input.data(), input.size()});
            uint32_t status = 0;
            job.createdDecoder = hsda_huff_create(records.data(), records.size(), job.capacity, &status);
            Status(status);
        } else {
            job.output.reserve(job.input.size());
            for (const auto &input : job.input) {
                auto output = job.huff ? hsda_huff_unpack(job.huff->decoder, input.data(), input.size()) :
                    hsda_palmdoc(input.data(), input.size(), job.capacity);
                job.output.push_back(output);
                Status(output.status);
            }
        }
    } catch (const std::exception &error) { job.error = error.what(); }
}

void CompleteMobi(napi_env env, napi_status status, void *data) {
    std::unique_ptr<MobiJob> job(static_cast<MobiJob *>(data));
    if (status != napi_ok) job->error = "rust_core_worker";
    napi_value output = nullptr;
    if (job->error.empty()) {
        try {
            if (job->create) {
                auto handle = std::make_unique<HuffHandle>();
                handle->decoder = job->createdDecoder;
                job->createdDecoder = nullptr;
                Check(napi_create_external(env, handle.get(), FinalizeHuff, nullptr, &output) == napi_ok, "rust_core_output");
                handle.release();
            } else {
                const size_t count = job->kf8 ? job->sections.len : job->output.size();
                Check(napi_create_array_with_length(env, count, &output) == napi_ok, "rust_core_output");
                for (uint32_t index = 0; index < count; ++index) {
                    const auto &bytes = job->kf8 ? job->sections.data[index] : job->output[index];
                    Check(napi_set_element(env, output, index, Bytes(env, bytes.data, bytes.len)) == napi_ok, "rust_core_output");
                }
            }
        } catch (const std::exception &error) { job->error = error.what(); }
    }
    if (job->error.empty()) { napi_resolve_deferred(env, job->deferred, output); }
    else {
        napi_value message, error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, job->deferred, error);
    }
    if (job->handleRef) napi_delete_reference(env, job->handleRef);
    napi_delete_async_work(env, job->work);
}

napi_value QueueMobi(napi_env env, std::unique_ptr<MobiJob> job) {
    napi_value name, promise;
    try {
        Check(napi_create_promise(env, &job->deferred, &promise) == napi_ok &&
            napi_create_string_utf8(env, "RustMobi", NAPI_AUTO_LENGTH, &name) == napi_ok &&
            napi_create_async_work(env, nullptr, name, ExecuteMobi, CompleteMobi, job.get(), &job->work) == napi_ok &&
            napi_queue_async_work(env, job->work) == napi_ok, "rust_core_worker");
    } catch (...) {
        if (job->handleRef) napi_delete_reference(env, job->handleRef);
        if (job->work) napi_delete_async_work(env, job->work);
        throw;
    }
    job.release();
    return promise;
}

napi_value CreateHuff(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        auto job = std::make_unique<MobiJob>();
        job->create = true;
        job->capacity = Uint(env, args[1]);
        job->input = Records(env, args[0]);
        return QueueMobi(env, std::move(job));
    });
}

napi_value DecodeMobi(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto job = std::make_unique<MobiJob>();
        job->capacity = Uint(env, args[1]);
        job->input = Records(env, args[0]);
        napi_valuetype type;
        Check(napi_typeof(env, args[2], &type) == napi_ok);
        if (type != napi_undefined) {
            Check(napi_get_value_external(env, args[2], reinterpret_cast<void **>(&job->huff)) == napi_ok &&
                job->huff->decoder, "import_mobi_invalid");
            Check(napi_create_reference(env, args[2], 1, &job->handleRef) == napi_ok, "rust_core_worker");
        }
        return QueueMobi(env, std::move(job));
    });
}

napi_value ReleaseHuff(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 1);
        HuffHandle *handle = nullptr;
        Check(napi_get_value_external(env, args[0], reinterpret_cast<void **>(&handle)) == napi_ok);
        hsda_huff_release(handle->decoder);
        handle->decoder = nullptr;
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    });
}

napi_value RebuildKf8(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto job = std::make_unique<MobiJob>();
        job->kf8 = true;
        job->input = Records(env, args[0]);
        auto fragments = Records(env, args[1]);
        job->capacity = job->input.size();
        for (auto &record : fragments) job->input.push_back(std::move(record));
        auto raw = Typed(env, args[2], napi_uint8_array);
        std::vector<uint8_t> body(raw.length);
        if (raw.length) std::memcpy(body.data(), raw.data, raw.length);
        job->input.insert(job->input.begin(), std::move(body));
        return QueueMobi(env, std::move(job));
    });
}

struct TxtHandle {
    void *parser = nullptr;
    ~TxtHandle() { hsda_txt_release(parser); }
};

void FinalizeTxt(napi_env, void *data, void *) { delete static_cast<TxtHandle *>(data); }

struct TxtJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref handleRef = nullptr;
    TxtHandle *handle = nullptr;
    std::u16string input;
    bool finalChunk = false;
    HsdaBuffer<HsdaTxtSection> sections {};
    std::string error;
    ~TxtJob() { hsda_txt_sections_free(sections); }
};

napi_value TxtText(napi_env env, const HsdaBuffer<uint16_t> &buffer) {
    std::u16string text(buffer.len + 1, u'\0');
    if (buffer.len) std::memcpy(text.data(), buffer.data, buffer.len * sizeof(uint16_t));
    napi_value result = nullptr;
    Check(napi_create_string_utf16(env, text.c_str(), buffer.len, &result) == napi_ok, "rust_core_output");
    return result;
}

struct RankingJob {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::u16string input[4];
    bool cached = false;
    double now = 0;
    HsdaRankingResult result {};
    std::string error;
    ~RankingJob() { hsda_ranking_free(result); }
};

void ExecuteRanking(napi_env, void *data) {
    auto &job = *static_cast<RankingJob *>(data);
    HsdaInputText input[4];
    for (size_t index = 0; index < 4; ++index) {
        input[index] = {reinterpret_cast<const uint16_t *>(job.input[index].data()), job.input[index].size()};
    }
    try {
        job.result = hsda_ranking(input, job.cached, job.now);
        Check(job.result.books.status == 0, "ranking_parse");
    } catch (const std::exception &error) { job.error = error.what(); }
}

void RankingNumber(napi_env env, napi_value item, const char *name, double number) {
    napi_value value;
    Check(napi_create_double(env, number, &value) == napi_ok &&
        napi_set_named_property(env, item, name, value) == napi_ok, "rust_core_output");
}

void CompleteRanking(napi_env env, napi_status status, void *data) {
    std::unique_ptr<RankingJob> job(static_cast<RankingJob *>(data));
    if (status != napi_ok) job->error = "rust_core_worker";
    napi_value output = nullptr;
    if (job->error.empty()) {
        try {
            napi_value books;
            Check(napi_create_object(env, &output) == napi_ok &&
                napi_create_array_with_length(env, job->result.books.len, &books) == napi_ok, "rust_core_output");
            const char *names[] = {"id", "platformId", "title", "author", "narrator", "coverUrl", "originalUrl", "intro"};
            for (uint32_t index = 0; index < job->result.books.len; ++index) {
                const auto &book = job->result.books.data[index];
                napi_value item;
                Check(napi_create_object(env, &item) == napi_ok, "rust_core_output");
                for (size_t field = 0; field < 8; ++field) {
                    Check(napi_set_named_property(env, item, names[field], TxtText(env, book.fields[field])) == napi_ok,
                        "rust_core_output");
                }
                RankingNumber(env, item, "rank", book.rank);
                RankingNumber(env, item, "rating", book.rating);
                RankingNumber(env, item, "contentType", book.contentType);
                Check(napi_set_element(env, books, index, item) == napi_ok, "rust_core_output");
            }
            Check(napi_set_named_property(env, output, "books", books) == napi_ok, "rust_core_output");
            RankingNumber(env, output, "fetchedAt", job->result.fetchedAt);
        } catch (const std::exception &error) { job->error = error.what(); }
    }
    if (job->error.empty()) { napi_resolve_deferred(env, job->deferred, output); }
    else {
        napi_value message, error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, job->deferred, error);
    }
    napi_delete_async_work(env, job->work);
}

napi_value ParseRanking(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 6);
        auto job = std::make_unique<RankingJob>();
        for (size_t index = 0; index < 4; ++index) job->input[index] = Text(env, args[index]);
        Check(napi_get_value_bool(env, args[4], &job->cached) == napi_ok &&
            napi_get_value_double(env, args[5], &job->now) == napi_ok);
        napi_value name, promise;
        try {
            Check(napi_create_promise(env, &job->deferred, &promise) == napi_ok &&
                napi_create_string_utf8(env, "RustRankingParse", NAPI_AUTO_LENGTH, &name) == napi_ok &&
                napi_create_async_work(env, nullptr, name, ExecuteRanking, CompleteRanking, job.get(), &job->work) == napi_ok &&
                napi_queue_async_work(env, job->work) == napi_ok, "rust_core_worker");
        } catch (...) {
            if (job->work) napi_delete_async_work(env, job->work);
            throw;
        }
        job.release();
        return promise;
    });
}

void ExecuteTxt(napi_env, void *data) {
    auto &job = *static_cast<TxtJob *>(data);
    try {
        job.sections = hsda_txt_feed(job.handle->parser,
            reinterpret_cast<const uint16_t *>(job.input.data()), job.input.size(), job.finalChunk);
        Status(job.sections.status);
    } catch (const std::exception &error) { job.error = error.what(); }
}

void CompleteTxt(napi_env env, napi_status status, void *data) {
    std::unique_ptr<TxtJob> job(static_cast<TxtJob *>(data));
    if (status != napi_ok) job->error = "rust_core_worker";
    napi_value output = nullptr;
    if (job->error.empty()) {
        try {
            Check(napi_create_array_with_length(env, job->sections.len, &output) == napi_ok, "rust_core_output");
            for (uint32_t index = 0; index < job->sections.len; ++index) {
                const auto &section = job->sections.data[index];
                napi_value item, preserve;
                Check(napi_create_object(env, &item) == napi_ok &&
                    napi_get_boolean(env, section.preserveChapter, &preserve) == napi_ok, "rust_core_output");
                Check(napi_set_named_property(env, item, "title", TxtText(env, section.title)) == napi_ok &&
                    napi_set_named_property(env, item, "content", TxtText(env, section.content)) == napi_ok &&
                    napi_set_named_property(env, item, "preserveChapter", preserve) == napi_ok &&
                    napi_set_element(env, output, index, item) == napi_ok, "rust_core_output");
            }
        } catch (const std::exception &error) { job->error = error.what(); }
    }
    if (job->error.empty()) { napi_resolve_deferred(env, job->deferred, output); }
    else {
        napi_value message, error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, job->deferred, error);
    }
    napi_delete_reference(env, job->handleRef);
    napi_delete_async_work(env, job->work);
}

napi_value CreateTxt(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 1);
        auto title = Text(env, args[0]);
        auto handle = std::make_unique<TxtHandle>();
        handle->parser = hsda_txt_create(reinterpret_cast<const uint16_t *>(title.data()), title.size());
        napi_value output;
        Check(napi_create_external(env, handle.get(), FinalizeTxt, nullptr, &output) == napi_ok, "rust_core_output");
        handle.release();
        return output;
    });
}

napi_value FeedTxt(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        auto job = std::make_unique<TxtJob>();
        Check(napi_get_value_external(env, args[0], reinterpret_cast<void **>(&job->handle)) == napi_ok);
        job->input = Text(env, args[1]);
        Check(napi_get_value_bool(env, args[2], &job->finalChunk) == napi_ok);
        napi_value name, promise;
        try {
            Check(napi_create_reference(env, args[0], 1, &job->handleRef) == napi_ok &&
                napi_create_promise(env, &job->deferred, &promise) == napi_ok &&
                napi_create_string_utf8(env, "RustTxtImport", NAPI_AUTO_LENGTH, &name) == napi_ok &&
                napi_create_async_work(env, nullptr, name, ExecuteTxt, CompleteTxt, job.get(), &job->work) == napi_ok &&
                napi_queue_async_work(env, job->work) == napi_ok, "rust_core_worker");
        } catch (...) {
            if (job->handleRef) napi_delete_reference(env, job->handleRef);
            if (job->work) napi_delete_async_work(env, job->work);
            throw;
        }
        job.release();
        return promise;
    });
}

napi_value ReleaseTxt(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 1);
        TxtHandle *handle = nullptr;
        Check(napi_get_value_external(env, args[0], reinterpret_cast<void **>(&handle)) == napi_ok);
        hsda_txt_release(handle->parser);
        handle->parser = nullptr;
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    });
}

template<typename T> struct RustOwned {
    T value;
    void (*release)(T);
    ~RustOwned() { release(value); }
};

napi_value Property(napi_env env, napi_value object, const char *name) {
    napi_value value;
    Check(napi_get_named_property(env, object, name, &value) == napi_ok);
    return value;
}

napi_value Element(napi_env env, napi_value array, uint32_t index) {
    napi_value value;
    Check(napi_get_element(env, array, index, &value) == napi_ok);
    return value;
}

uint32_t Length(napi_env env, napi_value array) {
    uint32_t length;
    Check(napi_get_array_length(env, array, &length) == napi_ok);
    return length;
}

double Number(napi_env env, napi_value value) {
    double number;
    Check(napi_get_value_double(env, value, &number) == napi_ok);
    return number;
}

bool Boolean(napi_env env, napi_value value) {
    bool result;
    Check(napi_get_value_bool(env, value, &result) == napi_ok);
    return result;
}

void Set(napi_env env, napi_value object, const char *name, napi_value value) {
    Check(napi_set_named_property(env, object, name, value) == napi_ok, "rust_core_output");
}

void SetNumber(napi_env env, napi_value object, const char *name, double number) {
    napi_value value;
    Check(napi_create_double(env, number, &value) == napi_ok, "rust_core_output");
    Set(env, object, name, value);
}

void SetBoolean(napi_env env, napi_value object, const char *name, bool flag) {
    napi_value value;
    Check(napi_get_boolean(env, flag, &value) == napi_ok, "rust_core_output");
    Set(env, object, name, value);
}

napi_value ReaderIndent(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        auto input = Text(env, args[0]);
        RustOwned<HsdaReaderDisplay> result {hsda_reader_indent(
            reinterpret_cast<const uint16_t *>(input.data()), input.size(), Uint(env, args[1])), hsda_reader_display_free};
        napi_value output, indents;
        Check(napi_create_object(env, &output) == napi_ok &&
            napi_create_array_with_length(env, result.value.indents.len, &indents) == napi_ok, "rust_core_output");
        Set(env, output, "text", TxtText(env, result.value.text));
        for (uint32_t i = 0; i < result.value.indents.len; ++i) {
            napi_value value;
            Check(napi_create_uint32(env, result.value.indents.data[i], &value) == napi_ok &&
                napi_set_element(env, indents, i, value) == napi_ok, "rust_core_output");
        }
        Set(env, output, "indents", indents);
        return output;
    });
}

napi_value SourceTagPairs(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        auto input = Text(env, args[0]), tag = Text(env, args[1]);
        RustOwned<HsdaBuffer<uint32_t>> result {hsda_source_tag_pairs(
            reinterpret_cast<const uint16_t *>(input.data()), input.size(),
            reinterpret_cast<const uint16_t *>(tag.data()), tag.size()), hsda_offsets_free};
        napi_value output;
        Check(napi_create_array_with_length(env, result.value.len, &output) == napi_ok, "rust_core_output");
        for (uint32_t i = 0; i < result.value.len; ++i) {
            napi_value value;
            const double number = result.value.data[i] == UINT32_MAX ? -1. : result.value.data[i];
            Check(napi_create_double(env, number, &value) == napi_ok &&
                napi_set_element(env, output, i, value) == napi_ok, "rust_core_output");
        }
        return output;
    });
}

napi_value SpeechSplit(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 5);
        auto input = Text(env, args[0]);
        std::vector<uint32_t> boundaries(Length(env, args[1]));
        for (uint32_t i = 0; i < boundaries.size(); ++i) boundaries[i] = Uint(env, Element(env, args[1], i));
        RustOwned<HsdaBuffer<HsdaSpeechSegment>> result {hsda_speech_split(
            reinterpret_cast<const uint16_t *>(input.data()), input.size(), boundaries.data(), boundaries.size(),
            Boolean(env, args[2]), Uint(env, args[3]), Uint(env, args[4])), hsda_speech_free};
        napi_value output;
        Check(napi_create_array_with_length(env, result.value.len, &output) == napi_ok, "rust_core_output");
        for (uint32_t i = 0; i < result.value.len; ++i) {
            const auto &segment = result.value.data[i];
            napi_value item;
            Check(napi_create_object(env, &item) == napi_ok, "rust_core_output");
            Set(env, item, "text", TxtText(env, segment.text));
            SetNumber(env, item, "start", segment.start);
            SetNumber(env, item, "end", segment.end);
            SetNumber(env, item, "leadingWhitespace", segment.leadingWhitespace);
            SetNumber(env, item, "paragraphStart", segment.paragraphStart);
            SetNumber(env, item, "paragraphEnd", segment.paragraphEnd);
            Check(napi_set_element(env, output, i, item) == napi_ok, "rust_core_output");
        }
        return output;
    });
}

struct SubtitleInputList {
    std::vector<std::u16string> texts;
    std::vector<HsdaSubtitleInput> units;
    SubtitleInputList(napi_env env, napi_value array, const char *flag) {
        napi_valuetype type;
        Check(napi_typeof(env, array, &type) == napi_ok);
        if (type == napi_undefined || type == napi_null) return;
        const uint32_t length = Length(env, array);
        texts.reserve(length);
        units.reserve(length);
        for (uint32_t i = 0; i < length; ++i) {
            auto item = Element(env, array, i);
            texts.push_back(Text(env, Property(env, item, "text")));
            const auto &text = texts.back();
            units.push_back({{reinterpret_cast<const uint16_t *>(text.data()), text.size()},
                Number(env, Property(env, item, "startMs")), Number(env, Property(env, item, "endMs")),
                Boolean(env, Property(env, item, flag))});
        }
    }
};

napi_value SubtitleResult(napi_env env, HsdaBuffer<HsdaSubtitleSpan> buffer, const char *flag) {
    RustOwned<HsdaBuffer<HsdaSubtitleSpan>> result {buffer, hsda_subtitle_free};
    napi_value output;
    Check(napi_create_array_with_length(env, buffer.len, &output) == napi_ok, "rust_core_output");
    for (uint32_t i = 0; i < buffer.len; ++i) {
        const auto &span = buffer.data[i];
        napi_value item;
        Check(napi_create_object(env, &item) == napi_ok, "rust_core_output");
        Set(env, item, "text", TxtText(env, span.text));
        SetNumber(env, item, "startMs", span.startMs);
        SetNumber(env, item, "endMs", span.endMs);
        SetBoolean(env, item, flag, span.flag);
        Check(napi_set_element(env, output, i, item) == napi_ok, "rust_core_output");
    }
    return output;
}

napi_value SubtitleJoin(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        SubtitleInputList previous(env, args[0], "sentenceEnd"), current(env, args[1], "sentenceEnd");
        return SubtitleResult(env, hsda_subtitle_join(previous.units.data(), previous.units.size(),
            current.units.data(), current.units.size(), Number(env, args[2])), "sentenceEnd");
    });
}

napi_value SubtitlePunctuate(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 3);
        SubtitleInputList input(env, args[0], "sentenceEnd");
        auto text = Text(env, args[1]);
        return SubtitleResult(env, hsda_subtitle_punctuate(input.units.data(), input.units.size(),
            reinterpret_cast<const uint16_t *>(text.data()), text.size(), Boolean(env, args[2])), "sentenceEnd");
    });
}

void FinalizeSubtitleDictionary(napi_env, void *data, void *) { hsda_subtitle_dictionary_free(data); }

napi_value SubtitleDictionary(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 1);
        const uint32_t count = Length(env, args[0]);
        std::vector<std::u16string> texts;
        std::vector<HsdaInputText> words;
        texts.reserve(count);
        words.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            texts.push_back(Text(env, Element(env, args[0], i)));
            const auto &text = texts.back();
            words.push_back({reinterpret_cast<const uint16_t *>(text.data()), text.size()});
        }
        std::unique_ptr<void, decltype(&hsda_subtitle_dictionary_free)> dictionary(
            hsda_subtitle_dictionary(words.data(), words.size()), hsda_subtitle_dictionary_free);
        napi_value output;
        Check(napi_create_external(env, dictionary.get(), FinalizeSubtitleDictionary, nullptr, &output) == napi_ok,
            "rust_core_output");
        dictionary.release();
        return output;
    });
}

napi_value SubtitleTimeline(napi_env env, napi_callback_info info) {
    return Call(env, [&]() {
        auto args = Args(env, info, 2);
        void *dictionary = nullptr;
        napi_valuetype type;
        Check(napi_typeof(env, args[1], &type) == napi_ok);
        if (type == napi_external) Check(napi_get_value_external(env, args[1], &dictionary) == napi_ok);
        const uint32_t count = Length(env, args[0]);
        std::vector<SubtitleInputList> annotations, cues;
        std::vector<HsdaSubtitleChunk> chunks;
        annotations.reserve(count);
        cues.reserve(count);
        chunks.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            auto chunk = Element(env, args[0], i);
            annotations.emplace_back(env, Property(env, chunk, "annotated"), "sentenceEnd");
            cues.emplace_back(env, Property(env, chunk, "cues"), "continues");
            chunks.push_back({Uint(env, Property(env, chunk, "index")),
                annotations.back().units.data(), annotations.back().units.size(), cues.back().units.data(), cues.back().units.size()});
        }
        return SubtitleResult(env, hsda_subtitle_timeline(chunks.data(), chunks.size(), dictionary), "continues");
    });
}

napi_value Init(napi_env env, napi_value exports) {
    RegisterSpeechStream(env, exports);
    const napi_property_descriptor properties[] = {
        {"waitRuleHostInterval", nullptr, WaitRuleHostInterval, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"transformText", nullptr, Transform, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"transformHtmlBounded", nullptr, BoundedHtml, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cleanEpubHtml", nullptr, EpubBody, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cleanHtmlBatch", nullptr, CleanBatch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"searchOffsets", nullptr, Search, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detectWhiteBorder", nullptr, WhiteBorder, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"encodeWave", nullptr, Wave, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readEpubEntries", nullptr, ReadEpubEntries, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createMobiHuff", nullptr, CreateHuff, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decodeMobiBatch", nullptr, DecodeMobi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseMobiHuff", nullptr, ReleaseHuff, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rebuildKf8", nullptr, RebuildKf8, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createTxtImporter", nullptr, CreateTxt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"feedTxtImporter", nullptr, FeedTxt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseTxtImporter", nullptr, ReleaseTxt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"parseRanking", nullptr, ParseRanking, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"indentReaderText", nullptr, ReaderIndent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"splitSpeechText", nullptr, SpeechSplit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sourceTagPairs", nullptr, SourceTagPairs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createSubtitleDictionary", nullptr, SubtitleDictionary, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"joinSubtitleUnits", nullptr, SubtitleJoin, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"punctuateSubtitleUnits", nullptr, SubtitlePunctuate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"buildSubtitleTimeline", nullptr, SubtitleTimeline, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "hsda_core", nullptr, {nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterHsdaCore() { napi_module_register(&module); }
