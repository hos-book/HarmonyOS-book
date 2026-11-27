#include "speech_stream.h"
#include <multimedia/player_framework/native_avsource.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr size_t AUDIO_LIMIT = 8 * 1024 * 1024;
void Require(bool valid, const char *message) { if (!valid) throw std::runtime_error(message); }

struct SpeechStream : std::enable_shared_from_this<SpeechStream> {
    std::mutex mutex;
    std::condition_variable changed;
    std::vector<uint8_t> encoded;
    std::deque<std::vector<uint8_t>> pcm;
    size_t offset = 0;
    size_t queued = 0;
    size_t inputPosition = 0;
    int32_t rate = 0;
    int32_t channels = 0;
    int64_t frames = 0;
    double duration = 0;
    bool ended = false;
    bool decoded = false;
    bool cancelled = false;
    bool started = false;
    bool raw = false;
    std::string error;

    void Cancel() {
        std::lock_guard<std::mutex> lock(mutex);
        cancelled = true;
        std::vector<uint8_t>().swap(encoded);
        pcm.clear(); offset = 0; queued = 0;
        changed.notify_all();
    }

    static int32_t Read(OH_AVBuffer *buffer, int32_t length, int64_t position, void *data) {
        auto &stream = *static_cast<SpeechStream *>(data);
        std::unique_lock<std::mutex> lock(stream.mutex);
        const size_t at = position < 0 ? stream.inputPosition : static_cast<size_t>(position);
        stream.changed.wait(lock, [&] { return stream.cancelled || stream.ended || stream.encoded.size() > at; });
        if (stream.cancelled) return -2;
        if (at >= stream.encoded.size()) return -1;
        const size_t count = std::min({static_cast<size_t>(length), stream.encoded.size() - at,
            static_cast<size_t>(OH_AVBuffer_GetCapacity(buffer))});
        std::memcpy(OH_AVBuffer_GetAddr(buffer), stream.encoded.data() + at, count);
        stream.inputPosition = at + count;
        return static_cast<int32_t>(count);
    }

    void Push(const uint8_t *data, size_t length, bool wait) {
        std::unique_lock<std::mutex> lock(mutex);
        if (wait) changed.wait(lock, [&] { return cancelled || queued + length <= AUDIO_LIMIT; });
        if (cancelled) return;
        Require(queued + length <= AUDIO_LIMIT, "speech_audio_budget");
        pcm.emplace_back(data, data + length);
        queued += length;
        frames += length / (channels * 2);
        changed.notify_all();
    }

    void Decode();
};

struct SpeechDecoder {
    OH_AVSource *source = nullptr;
    OH_AVDemuxer *demux = nullptr;
    OH_AVCodec *codec = nullptr;
    OH_AVFormat *format = nullptr;
    OH_AVBuffer *buffer = nullptr;
    ~SpeechDecoder() {
        if (buffer) OH_AVBuffer_Destroy(buffer);
        if (codec) OH_AudioCodec_Destroy(codec);
        if (format) OH_AVFormat_Destroy(format);
        if (demux) OH_AVDemuxer_Destroy(demux);
        if (source) OH_AVSource_Destroy(source);
    }
};

void SpeechStream::Decode() {
    try {
        int64_t sourceSize = -1;
        { std::lock_guard<std::mutex> lock(mutex); if (ended) sourceSize = static_cast<int64_t>(encoded.size()); }
        OH_AVDataSourceExt input {sourceSize, Read};
        SpeechDecoder d;
        d.source = OH_AVSource_CreateWithDataSourceExt(&input, this);
        Require(d.source, "speech_audio_source");
        auto sourceFormat = OH_AVSource_GetSourceFormat(d.source);
        int32_t tracks = 0;
        int64_t durationUs = 0;
        if (sourceFormat) {
            OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &tracks);
            OH_AVFormat_GetLongValue(sourceFormat, OH_MD_KEY_DURATION, &durationUs);
            OH_AVFormat_Destroy(sourceFormat);
        }
        uint32_t track = 0;
        std::string mime;
        for (int32_t i = 0; i < tracks; ++i) {
            auto format = OH_AVSource_GetTrackFormat(d.source, i);
            int32_t type = -1;
            const char *name = nullptr;
            if (format && OH_AVFormat_GetIntValue(format, OH_MD_KEY_TRACK_TYPE, &type) && type == MEDIA_TYPE_AUD &&
                OH_AVFormat_GetStringValue(format, OH_MD_KEY_CODEC_MIME, &name)) {
                d.format = format; mime = name; track = i; break;
            }
            if (format) OH_AVFormat_Destroy(format);
        }
        Require(d.format, "speech_audio_track");
        d.demux = OH_AVDemuxer_CreateWithSource(d.source);
        Require(d.demux && OH_AVDemuxer_SelectTrackByID(d.demux, track) == AV_ERR_OK, "speech_audio_demux");
        const bool sourcePcm = mime == "audio/raw";
        if (sourcePcm) {
            d.buffer = OH_AVBuffer_Create(64 * 1024);
            Require(d.buffer, "speech_audio_memory");
        } else {
            d.codec = OH_AudioCodec_CreateByMime(mime.c_str(), false);
            Require(d.codec, "speech_audio_codec");
            OH_AVFormat_SetIntValue(d.format, OH_MD_KEY_ENABLE_SYNC_MODE, 1);
            OH_AVFormat_SetIntValue(d.format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
            Require(OH_AudioCodec_Configure(d.codec, d.format) == AV_ERR_OK &&
                OH_AudioCodec_Prepare(d.codec) == AV_ERR_OK && OH_AudioCodec_Start(d.codec) == AV_ERR_OK,
                "speech_audio_configure");
        }
        int32_t sampleRate = 0, channelCount = 0, sampleFormat = SAMPLE_S16LE;
        OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUD_SAMPLE_RATE, &sampleRate);
        OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUD_CHANNEL_COUNT, &channelCount);
        if (sourcePcm) OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat);
        bool inputDone = false;
        for (;;) {
            { std::lock_guard<std::mutex> lock(mutex); if (cancelled) return; }
            uint32_t index = 0;
            if (!sourcePcm && !inputDone) {
                auto rc = OH_AudioCodec_QueryInputBuffer(d.codec, &index, 0);
                if (rc == AV_ERR_OK) {
                    auto buffer = OH_AudioCodec_GetInputBuffer(d.codec, index);
                    Require(buffer && OH_AVDemuxer_ReadSampleBuffer(d.demux, track, buffer) == AV_ERR_OK,
                        "speech_audio_read");
                    OH_AVCodecBufferAttr attr {};
                    OH_AVBuffer_GetBufferAttr(buffer, &attr);
                    inputDone = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
                    Require(OH_AudioCodec_PushInputBuffer(d.codec, index) == AV_ERR_OK, "speech_audio_input");
                } else Require(rc == AV_ERR_TRY_AGAIN_LATER, "speech_audio_input_state");
            }
            const auto rc = sourcePcm ? OH_AVDemuxer_ReadSampleBuffer(d.demux, track, d.buffer) :
                OH_AudioCodec_QueryOutputBuffer(d.codec, &index, 10000);
            if (rc == AV_ERR_STREAM_CHANGED) {
                auto format = OH_AudioCodec_GetOutputDescription(d.codec);
                Require(format, "speech_audio_format");
                OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, &sampleRate);
                OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, &channelCount);
                OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat);
                OH_AVFormat_Destroy(format);
                continue;
            }
            if (rc == AV_ERR_TRY_AGAIN_LATER) continue;
            Require(rc == AV_ERR_OK, "speech_audio_output");
            auto buffer = sourcePcm ? d.buffer : OH_AudioCodec_GetOutputBuffer(d.codec, index);
            OH_AVCodecBufferAttr attr {};
            Require(buffer && OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK, "speech_audio_buffer");
            Require(sampleRate > 0 && channelCount > 0 && sampleFormat >= SAMPLE_U8 && sampleFormat <= SAMPLE_F32LE,
                "speech_audio_pcm_format");
            {
                std::lock_guard<std::mutex> lock(mutex);
                rate = sampleRate; channels = channelCount;
                duration = std::max<int64_t>(0, durationUs) / 1000.0;
            }
            if (attr.size > 0) {
                const auto data = OH_AVBuffer_GetAddr(buffer) + attr.offset;
                if (sampleFormat == SAMPLE_S16LE) Push(data, attr.size, true);
                else {
                    const int bytes = sampleFormat == SAMPLE_U8 ? 1 : (sampleFormat == SAMPLE_S24LE ? 3 : 4);
                    std::vector<int16_t> samples(attr.size / bytes);
                    for (size_t i = 0; i < samples.size(); ++i) {
                        const auto sample = data + i * bytes;
                        if (sampleFormat == SAMPLE_U8) samples[i] = (sample[0] - 128) * 256;
                        else if (sampleFormat == SAMPLE_F32LE) {
                            float value = 0;
                            std::memcpy(&value, sample, sizeof(value));
                            samples[i] = static_cast<int16_t>(std::clamp(value, -1.0f, 1.0f) * 32767.0f);
                        } else samples[i] = static_cast<int16_t>(sample[bytes - 2] | (sample[bytes - 1] << 8));
                    }
                    Push(reinterpret_cast<const uint8_t *>(samples.data()), samples.size() * sizeof(int16_t), true);
                }
            }
            if (!sourcePcm) OH_AudioCodec_FreeOutputBuffer(d.codec, index);
            if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) break;
        }
        std::lock_guard<std::mutex> lock(mutex);
        decoded = true;
        if (rate > 0) duration = frames * 1000.0 / rate;
    } catch (const std::exception &failure) {
        std::lock_guard<std::mutex> lock(mutex);
        if (!cancelled) error = failure.what();
    }
    changed.notify_all();
}

using SpeechHandle = std::shared_ptr<SpeechStream>;
SpeechHandle Handle(napi_env env, napi_value value) {
    void *data = nullptr;
    napi_get_value_external(env, value, &data);
    return *static_cast<SpeechHandle *>(data);
}
void Finalize(napi_env, void *data, void *) {
    auto handle = static_cast<SpeechHandle *>(data);
    (*handle)->Cancel(); delete handle;
}
napi_value Create(napi_env env, napi_callback_info) {
    napi_value result;
    napi_create_external(env, new SpeechHandle(std::make_shared<SpeechStream>()), Finalize, nullptr, &result);
    return result;
}
napi_value Feed(napi_env env, napi_callback_info info) {
    try {
        size_t argc = 3; napi_value args[3];
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        auto stream = Handle(env, args[0]);
        void *data = nullptr; size_t size = 0; int32_t rate = 0;
        napi_get_arraybuffer_info(env, args[1], &data, &size);
        napi_get_value_int32(env, args[2], &rate);
        if (rate > 0) {
            { std::lock_guard<std::mutex> lock(stream->mutex); stream->raw = true; stream->rate = rate; stream->channels = 1; }
            stream->Push(static_cast<uint8_t *>(data), size, false);
        } else {
            std::lock_guard<std::mutex> lock(stream->mutex);
            if (stream->cancelled) return nullptr;
            Require(stream->encoded.size() + size <= AUDIO_LIMIT, "speech_audio_budget");
            auto bytes = static_cast<uint8_t *>(data);
            stream->encoded.insert(stream->encoded.end(), bytes, bytes + size);
            stream->changed.notify_all();
        }
    } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); }
    return nullptr;
}
napi_value Finish(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value args[1]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto stream = Handle(env, args[0]);
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->ended = true;
    if (stream->raw) { stream->decoded = true; stream->duration = stream->frames * 1000.0 / stream->rate; }
    stream->changed.notify_all();
    return nullptr;
}
napi_value Start(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value args[1]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto stream = Handle(env, args[0]);
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (!stream->started && !stream->raw && !stream->cancelled) {
        stream->started = true;
        std::thread([stream] { stream->Decode(); }).detach();
    }
    return nullptr;
}
napi_value Cancel(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value args[1]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    Handle(env, args[0])->Cancel(); return nullptr;
}
napi_value ReadPcm(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value args[2]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto stream = Handle(env, args[0]);
    void *data = nullptr; size_t length = 0;
    napi_get_arraybuffer_info(env, args[1], &data, &length);
    std::lock_guard<std::mutex> lock(stream->mutex);
    size_t used = 0;
    if (!stream->cancelled && (stream->queued >= length || stream->decoded)) {
        auto output = static_cast<uint8_t *>(data);
        while (used < length && !stream->pcm.empty()) {
            auto &front = stream->pcm.front();
            const size_t count = std::min(length - used, front.size() - stream->offset);
            std::memcpy(output + used, front.data() + stream->offset, count);
            used += count; stream->offset += count; stream->queued -= count;
            if (stream->offset == front.size()) { stream->pcm.pop_front(); stream->offset = 0; }
        }
        if (used > 0 && used < length) std::memset(output + used, 0, length - used);
    }
    stream->changed.notify_all();
    napi_value result; napi_create_uint32(env, used, &result); return result;
}
void Number(napi_env env, napi_value object, const char *name, double value) {
    napi_value result; napi_create_double(env, value, &result); napi_set_named_property(env, object, name, result);
}
napi_value Status(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value args[1]; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto stream = Handle(env, args[0]);
    std::lock_guard<std::mutex> lock(stream->mutex);
    napi_value result, done, error; napi_create_object(env, &result);
    Number(env, result, "rate", stream->rate); Number(env, result, "channels", stream->channels);
    Number(env, result, "queued", stream->queued); Number(env, result, "duration", stream->duration);
    napi_get_boolean(env, stream->decoded, &done); napi_set_named_property(env, result, "done", done);
    napi_create_string_utf8(env, stream->error.c_str(), stream->error.size(), &error);
    napi_set_named_property(env, result, "error", error);
    return result;
}
}

void RegisterSpeechStream(napi_env env, napi_value exports) {
    const napi_property_descriptor properties[] = {
        {"createSpeechStream", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"feedSpeechStream", nullptr, Feed, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"finishSpeechStream", nullptr, Finish, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startSpeechStream", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelSpeechStream", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readSpeechPcm", nullptr, ReadPcm, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"speechStreamStatus", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
}
