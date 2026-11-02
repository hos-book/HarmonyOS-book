#include <napi/native_api.h>
#include <multimedia/player_framework/native_avsource.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct Decoder {
    int fd = -1;
    OH_AVSource *source = nullptr;
    OH_AVDemuxer *demux = nullptr;
    OH_AVCodec *codec = nullptr;
    OH_AVFormat *format = nullptr;
    OH_AVBuffer *rawBuffer = nullptr;
    ~Decoder() {
        if (rawBuffer) OH_AVBuffer_Destroy(rawBuffer);
        if (codec) OH_AudioCodec_Destroy(codec);
        if (format) OH_AVFormat_Destroy(format);
        if (demux) OH_AVDemuxer_Destroy(demux);
        if (source) OH_AVSource_Destroy(source);
        if (fd >= 0) close(fd);
    }
};
void Check(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
void Number(napi_env env, napi_value object, const char *name, double number) {
    napi_value value; napi_create_double(env, number, &value); napi_set_named_property(env, object, name, value);
}
napi_value Decode(napi_env env, napi_callback_info info) {
    try {
        size_t argc = 3; napi_value argv[3];
        napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
        Check(argc == 3, "subtitle_decode_arguments");
        size_t length = 0;
        Check(napi_get_value_string_utf8(env, argv[0], nullptr, 0, &length) == napi_ok && length < 4096,
            "subtitle_decode_path");
        std::vector<char> path(length + 1);
        napi_get_value_string_utf8(env, argv[0], path.data(), path.size(), &length);
        double startMs = 0, durationMs = 0;
        Check(napi_get_value_double(env, argv[1], &startMs) == napi_ok &&
              napi_get_value_double(env, argv[2], &durationMs) == napi_ok && std::isfinite(startMs) &&
              std::isfinite(durationMs) && startMs >= 0 && startMs <= 86400000 && durationMs > 0 && durationMs <= 16000,
              "subtitle_decode_range");
        Decoder d;
        d.fd = open(path.data(), O_RDONLY | O_CLOEXEC);
        struct stat st{};
        Check(d.fd >= 0 && fstat(d.fd, &st) == 0 && st.st_size > 0 && st.st_size <= 512LL * 1024 * 1024,
              "subtitle_decode_file");
        d.source = OH_AVSource_CreateWithFD(d.fd, 0, st.st_size);
        Check(d.source, "subtitle_decode_source");
        OH_AVFormat *sourceFormat = OH_AVSource_GetSourceFormat(d.source);
        int32_t tracks = 0;
        if (sourceFormat) {
            OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &tracks);
            OH_AVFormat_Destroy(sourceFormat);
        }
        uint32_t track = 0; std::string mime;
        for (int32_t i = 0; i < std::min(tracks, 64); ++i) {
            auto *f = OH_AVSource_GetTrackFormat(d.source, i);
            int32_t type = -1; const char *m = nullptr;
            if (f && OH_AVFormat_GetIntValue(f, OH_MD_KEY_TRACK_TYPE, &type) && type == MEDIA_TYPE_AUD &&
                OH_AVFormat_GetStringValue(f, OH_MD_KEY_CODEC_MIME, &m) && m) {
                d.format = f; mime = m; track = i; break;
            }
            if (f) OH_AVFormat_Destroy(f);
        }
        Check(d.format, "subtitle_decode_no_audio");
        d.demux = OH_AVDemuxer_CreateWithSource(d.source);
        Check(d.demux && OH_AVDemuxer_SelectTrackByID(d.demux, track) == AV_ERR_OK, "subtitle_decode_demux");
        if (startMs > 0) Check(OH_AVDemuxer_SeekToTime(d.demux, static_cast<int64_t>(startMs),
            SEEK_MODE_PREVIOUS_SYNC) == AV_ERR_OK, "subtitle_decode_seek");
        const bool raw = mime == "audio/raw";
        if (raw) {
            // PCM WAV is already decoded; platform AudioCodec has no audio/raw decoder.
            d.rawBuffer = OH_AVBuffer_Create(1024 * 1024);
            Check(d.rawBuffer, "subtitle_decode_memory");
        } else {
            d.codec = OH_AudioCodec_CreateByMime(mime.c_str(), false);
            Check(d.codec, "subtitle_decode_unsupported");
            OH_AVFormat_SetIntValue(d.format, OH_MD_KEY_ENABLE_SYNC_MODE, 1);
            OH_AVFormat_SetIntValue(d.format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
            Check(OH_AudioCodec_Configure(d.codec, d.format) == AV_ERR_OK &&
                OH_AudioCodec_Prepare(d.codec) == AV_ERR_OK && OH_AudioCodec_Start(d.codec) == AV_ERR_OK,
                "subtitle_decode_configure");
        }
        int32_t rate = 0, channels = 0, sampleFormat = SAMPLE_S16LE;
        OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUD_SAMPLE_RATE, &rate);
        OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUD_CHANNEL_COUNT, &channels);
        if (raw) OH_AVFormat_GetIntValue(d.format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat);
        const size_t capacity = static_cast<size_t>(durationMs * 16);
        std::vector<float> pcm(capacity, 0);
        size_t used = 0; bool inputDone = false, done = false;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
        while (!done) {
            Check(std::chrono::steady_clock::now() < deadline, "subtitle_decode_timeout");
            uint32_t index = 0;
            if (!raw && !inputDone) {
                auto rc = OH_AudioCodec_QueryInputBuffer(d.codec, &index, 1000);
                if (rc == AV_ERR_OK) {
                    auto *buffer = OH_AudioCodec_GetInputBuffer(d.codec, index);
                    Check(buffer && OH_AVDemuxer_ReadSampleBuffer(d.demux, track, buffer) == AV_ERR_OK,
                        "subtitle_decode_read");
                    OH_AVCodecBufferAttr attr{};
                    Check(OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK, "subtitle_decode_input");
                    inputDone = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
                    Check(OH_AudioCodec_PushInputBuffer(d.codec, index) == AV_ERR_OK, "subtitle_decode_push");
                } else Check(rc == AV_ERR_TRY_AGAIN_LATER, "subtitle_decode_input_state");
            }
            auto rc = raw ? OH_AVDemuxer_ReadSampleBuffer(d.demux, track, d.rawBuffer) :
                OH_AudioCodec_QueryOutputBuffer(d.codec, &index, 1000);
            if (rc == AV_ERR_STREAM_CHANGED) {
                auto *f = OH_AudioCodec_GetOutputDescription(d.codec);
                Check(f, "subtitle_decode_format");
                OH_AVFormat_GetIntValue(f, OH_MD_KEY_AUD_SAMPLE_RATE, &rate);
                OH_AVFormat_GetIntValue(f, OH_MD_KEY_AUD_CHANNEL_COUNT, &channels);
                OH_AVFormat_GetIntValue(f, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &sampleFormat);
                OH_AVFormat_Destroy(f);
                continue;
            }
            if (rc == AV_ERR_TRY_AGAIN_LATER) continue;
            Check(rc == AV_ERR_OK, "subtitle_decode_output_state");
            auto *buffer = raw ? d.rawBuffer : OH_AudioCodec_GetOutputBuffer(d.codec, index);
            OH_AVCodecBufferAttr attr{};
            Check(buffer && OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK, "subtitle_decode_output");
            Check(rate >= 8000 && rate <= 192000 && channels > 0 && channels <= 8 &&
                (sampleFormat == SAMPLE_S16LE || sampleFormat == SAMPLE_F32LE), "subtitle_decode_pcm_format");
            const int bytes = sampleFormat == SAMPLE_F32LE ? 4 : 2;
            Check(attr.offset >= 0 && attr.size >= 0 &&
                static_cast<int64_t>(attr.offset) + attr.size <= OH_AVBuffer_GetCapacity(buffer), "subtitle_decode_buffer");
            auto *data = OH_AVBuffer_GetAddr(buffer);
            Check(data || attr.size == 0, "subtitle_decode_buffer");
            const int frames = attr.size / (bytes * channels);
            const double firstMs = attr.pts / 1000.0;
            // Convert by media PTS, not callback time. Output stays bounded to 16 kHz mono.
            const int64_t begin = std::max<int64_t>(0, static_cast<int64_t>(std::ceil((firstMs - startMs) * 16)));
            const int64_t end = std::min<int64_t>(capacity,
                static_cast<int64_t>(std::ceil((firstMs + frames * 1000.0 / rate - startMs) * 16)));
            for (int64_t p = begin; p < end; ++p) {
                const double sourcePos = (startMs + p / 16.0 - firstMs) * rate / 1000.0;
                const int frame = std::clamp(static_cast<int>(sourcePos), 0, std::max(0, frames - 1));
                if (frames == 0) break;
                float sum = 0;
                for (int c = 0; c < channels; ++c) {
                    const uint8_t *sample = data + attr.offset + (frame * channels + c) * bytes;
                    if (bytes == 2) { int16_t v; std::memcpy(&v, sample, 2); sum += v / 32768.0f; }
                    else { float v; std::memcpy(&v, sample, 4); sum += std::isfinite(v) ? v : 0; }
                }
                pcm[p] = std::clamp(sum / channels, -1.0f, 1.0f);
                used = std::max(used, static_cast<size_t>(p + 1));
            }
            done = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0 ||
                firstMs + frames * 1000.0 / rate >= startMs + durationMs;
            if (!raw) Check(OH_AudioCodec_FreeOutputBuffer(d.codec, index) == AV_ERR_OK, "subtitle_decode_release");
        }
        napi_value result, arrayBuffer, samples; void *dst = nullptr;
        napi_create_object(env, &result);
        Check(napi_create_arraybuffer(env, used * sizeof(float), &dst, &arrayBuffer) == napi_ok, "subtitle_decode_memory");
        if (used) std::memcpy(dst, pcm.data(), used * sizeof(float));
        napi_create_typedarray(env, napi_float32_array, used, arrayBuffer, 0, &samples);
        napi_set_named_property(env, result, "samples", samples);
        Number(env, result, "sampleRate", 16000);
        Number(env, result, "endMs", startMs + used / 16.0);
        return result;
    } catch (const std::exception &e) {
        napi_throw_error(env, nullptr, e.what()); return nullptr;
    }
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptor = {"decodeSubtitleAudio", nullptr, Decode, nullptr, nullptr, nullptr, napi_default, nullptr};
    napi_define_properties(env, exports, 1, &descriptor); return exports;
}
napi_module module = {1, 0, nullptr, Init, "subtitle_audio", nullptr, {0}};
}
extern "C" __attribute__((constructor)) void RegisterSubtitleAudio() { napi_module_register(&module); }
