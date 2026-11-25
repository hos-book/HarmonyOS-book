#include <napi/native_api.h>
#include <onnxruntime_c_api.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int TILE = 256;
constexpr int OVERLAP = 32;
constexpr int PLANE = TILE * TILE;
const OrtApi *api = OrtGetApiBase()->GetApi(ORT_API_VERSION);

void check(OrtStatus *status)
{
    if (status == nullptr) return;
    const std::string message = api->GetErrorMessage(status);
    api->ReleaseStatus(status);
    throw std::runtime_error(message);
}

struct Model {
    OrtEnv *env{};
    OrtSessionOptions *options{};
    OrtSession *session{};
    OrtMemoryInfo *memory{};
    ~Model()
    {
        if (memory) api->ReleaseMemoryInfo(memory);
        if (session) api->ReleaseSession(session);
        if (options) api->ReleaseSessionOptions(options);
        if (env) api->ReleaseEnv(env);
    }
    void load(const std::string &path)
    {
        if (api == nullptr) throw std::runtime_error("watermark_runtime");
        check(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ComicWatermark", &env));
        check(api->CreateSessionOptions(&options));
        check(api->SetIntraOpNumThreads(options, 2));
        check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL));
        check(api->CreateSession(env, path.c_str(), options, &session));
        size_t inputs = 0;
        size_t outputs = 0;
        check(api->SessionGetInputCount(session, &inputs));
        check(api->SessionGetOutputCount(session, &outputs));
        if (inputs != 1 || outputs != 1) throw std::runtime_error("watermark_model_contract");
        OrtAllocator *allocator = nullptr;
        check(api->GetAllocatorWithDefaultOptions(&allocator));
        for (int index = 0; index < 2; ++index) {
            char *name = nullptr;
            check(index == 0 ? api->SessionGetInputName(session, 0, allocator, &name) :
                api->SessionGetOutputName(session, 0, allocator, &name));
            const std::string actual(name);
            allocator->Free(allocator, name);
            if (actual != (index == 0 ? "image" : "clean")) throw std::runtime_error("watermark_model_contract");
            OrtTypeInfo *type = nullptr;
            check(index == 0 ? api->SessionGetInputTypeInfo(session, 0, &type) :
                api->SessionGetOutputTypeInfo(session, 0, &type));
            const OrtTensorTypeAndShapeInfo *tensor = nullptr;
            auto status = api->CastTypeInfoToTensorInfo(type, &tensor);
            if (status) { api->ReleaseTypeInfo(type); check(status); }
            ONNXTensorElementDataType dtype;
            size_t rank = 0;
            status = api->GetTensorElementType(tensor, &dtype);
            if (status) { api->ReleaseTypeInfo(type); check(status); }
            status = api->GetDimensionsCount(tensor, &rank);
            if (status) { api->ReleaseTypeInfo(type); check(status); }
            std::array<int64_t, 4> shape{};
            if (rank == 4) status = api->GetDimensions(tensor, shape.data(), shape.size());
            api->ReleaseTypeInfo(type);
            check(status);
            if (dtype != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || shape != std::array<int64_t, 4>{1, 3, TILE, TILE}) {
                throw std::runtime_error("watermark_model_contract");
            }
        }
        check(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory));
    }
};

struct Job {
    napi_async_work work{};
    napi_deferred deferred{};
    std::string path;
    int width = 0;
    int height = 0;
    std::vector<uint8_t> rgba;
    std::string error;
};

std::vector<int> starts(int length)
{
    std::vector<int> positions{0};
    while (positions.back() + TILE < length) {
        positions.push_back(std::min(length - TILE, positions.back() + TILE - OVERLAP));
    }
    return positions;
}

void process(Model &model, Job &job)
{
    const size_t pixels = static_cast<size_t>(job.width) * job.height;
    std::vector<float> totals(pixels * 3, 0);
    std::vector<float> weights(pixels, 0);
    std::vector<float> input(PLANE * 3);
    const std::array<int64_t, 4> shape{1, 3, TILE, TILE};
    OrtValue *inputValue = nullptr;
    check(api->CreateTensorWithDataAsOrtValue(model.memory, input.data(), input.size() * sizeof(float),
        shape.data(), shape.size(), ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputValue));
    const auto releaseValue = [](OrtValue *value) { api->ReleaseValue(value); };
    std::unique_ptr<OrtValue, decltype(releaseValue)> inputOwner(inputValue, releaseValue);
    const char *inputNames[]{"image"};
    const char *outputNames[]{"clean"};
    for (const int top : starts(job.height)) {
        for (const int left : starts(job.width)) {
            for (int y = 0; y < TILE; ++y) {
                for (int x = 0; x < TILE; ++x) {
                    const size_t pixel = static_cast<size_t>(std::min(top + y, job.height - 1)) * job.width +
                        std::min(left + x, job.width - 1);
                    for (int channel = 0; channel < 3; ++channel) {
                        input[channel * PLANE + y * TILE + x] = job.rgba[pixel * 4 + channel] / 255.0F;
                    }
                }
            }
            OrtValue *outputValue = nullptr;
            const OrtValue *inputs[]{inputValue};
            check(api->Run(model.session, nullptr, inputNames, inputs, 1, outputNames, 1, &outputValue));
            std::unique_ptr<OrtValue, decltype(releaseValue)> outputOwner(outputValue, releaseValue);
            float *output = nullptr;
            check(api->GetTensorMutableData(outputValue, reinterpret_cast<void **>(&output)));
            for (int y = 0; y < TILE && top + y < job.height; ++y) {
                for (int x = 0; x < TILE && left + x < job.width; ++x) {
                    const float wx = std::min({1.0F, left == 0 ? 1.0F : (x + 1.0F) / OVERLAP,
                        left + TILE >= job.width ? 1.0F : (TILE - x) / static_cast<float>(OVERLAP)});
                    const float wy = std::min({1.0F, top == 0 ? 1.0F : (y + 1.0F) / OVERLAP,
                        top + TILE >= job.height ? 1.0F : (TILE - y) / static_cast<float>(OVERLAP)});
                    const float weight = wx * wy;
                    const size_t pixel = static_cast<size_t>(top + y) * job.width + left + x;
                    weights[pixel] += weight;
                    for (int channel = 0; channel < 3; ++channel) {
                        totals[pixel * 3 + channel] += output[channel * PLANE + y * TILE + x] * weight;
                    }
                }
            }
        }
    }
    for (size_t pixel = 0; pixel < pixels; ++pixel) {
        for (int channel = 0; channel < 3; ++channel) {
            const float value = std::clamp(totals[pixel * 3 + channel] / weights[pixel], 0.0F, 1.0F);
            job.rgba[pixel * 4 + channel] = static_cast<uint8_t>(std::round(value * 255.0F));
        }
    }
}

napi_value run(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4]{};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto job = std::make_unique<Job>();
    size_t length = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
    std::vector<char> path(length + 1);
    napi_get_value_string_utf8(env, args[0], path.data(), path.size(), &length);
    job->path.assign(path.data(), length);
    if (argc == 4) {
        void *bytes = nullptr;
        size_t size = 0;
        napi_get_arraybuffer_info(env, args[1], &bytes, &size);
        napi_get_value_int32(env, args[2], &job->width);
        napi_get_value_int32(env, args[3], &job->height);
        if (job->width <= 0 || job->height <= 0 || size != static_cast<size_t>(job->width) * job->height * 4) {
            napi_throw_error(env, nullptr, "watermark_pixels");
            return nullptr;
        }
        job->rgba.assign(static_cast<uint8_t *>(bytes), static_cast<uint8_t *>(bytes) + size);
    }
    napi_value promise{};
    napi_create_promise(env, &job->deferred, &promise);
    napi_value name{};
    napi_create_string_utf8(env, "ComicWatermark", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, [](napi_env, void *data) {
        auto &item = *static_cast<Job *>(data);
        try {
            Model model;
            model.load(item.path);
            if (!item.rgba.empty()) process(model, item);
        } catch (const std::exception &error) { item.error = error.what(); }
    }, [](napi_env env, napi_status status, void *data) {
        std::unique_ptr<Job> item(static_cast<Job *>(data));
        napi_value result{};
        if (status != napi_ok || !item->error.empty()) {
            napi_value message{};
            napi_create_string_utf8(env, item->error.c_str(), NAPI_AUTO_LENGTH, &message);
            napi_create_error(env, nullptr, message, &result);
            napi_reject_deferred(env, item->deferred, result);
        } else {
            void *bytes = nullptr;
            napi_create_arraybuffer(env, item->rgba.size(), &bytes, &result);
            if (!item->rgba.empty()) std::memcpy(bytes, item->rgba.data(), item->rgba.size());
            napi_resolve_deferred(env, item->deferred, result);
        }
        napi_delete_async_work(env, item->work);
    }, job.get(), &job->work);
    napi_queue_async_work(env, job->work);
    job.release();
    return promise;
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor methods[]{
        {"process", nullptr, run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"load", nullptr, run, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 2, methods);
    return exports;
}
}

static napi_module module = {1, 0, nullptr, init, "comic_watermark", nullptr, {0}};
extern "C" __attribute__((constructor)) void registerComicWatermark() { napi_module_register(&module); }
