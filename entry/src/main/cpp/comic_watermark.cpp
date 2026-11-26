#include <napi/native_api.h>
#include <onnxruntime_c_api.h>
#include <mindspore/context.h>
#include <mindspore/model.h>
#include <mindspore/tensor.h>
#include <hilog/log.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int TILE = 256;
constexpr int OVERLAP = 32;
constexpr int PLANE = TILE * TILE;
// The packaged sherpa-onnx dependency provides ONNX Runtime 1.16.3.
constexpr uint32_t RUNTIME_API_VERSION = 16;
const OrtApi *api = OrtGetApiBase()->GetApi(RUNTIME_API_VERSION);

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
    OH_AI_ContextHandle liteContext{};
    OH_AI_ModelHandle liteModel{};
    OH_AI_TensorHandleArray liteInputs{};
    OH_AI_TensorHandleArray liteOutputs{};
    ~Model()
    {
        if (liteModel) OH_AI_ModelDestroy(&liteModel);
        if (liteContext) OH_AI_ContextDestroy(&liteContext);
        if (memory) api->ReleaseMemoryInfo(memory);
        if (session) api->ReleaseSession(session);
        if (options) api->ReleaseSessionOptions(options);
        if (env) api->ReleaseEnv(env);
    }
    void loadMindIR(const std::string &path)
    {
        liteContext = OH_AI_ContextCreate();
        OH_AI_ContextSetThreadNum(liteContext, 2);
        auto accelerator = OH_AI_CreateNNRTDeviceInfoByType(OH_AI_NNRTDEVICE_ACCELERATOR);
        if (accelerator) {
            OH_AI_DeviceInfoSetPerformanceMode(accelerator, OH_AI_PERFORMANCE_HIGH);
            OH_AI_ContextAddDeviceInfo(liteContext, accelerator);
        }
        auto cpu = OH_AI_DeviceInfoCreate(OH_AI_DEVICETYPE_CPU);
        OH_AI_DeviceInfoSetEnableFP16(cpu, false);
        OH_AI_ContextAddDeviceInfo(liteContext, cpu);
        liteModel = OH_AI_ModelCreate();
        const auto status = OH_AI_ModelBuildFromFile(liteModel, path.c_str(), OH_AI_MODELTYPE_MINDIR, liteContext);
        if (status != OH_AI_STATUS_SUCCESS) {
            throw std::runtime_error("watermark_mindir_build:" + std::to_string(status));
        }
        liteInputs = OH_AI_ModelGetInputs(liteModel);
        liteOutputs = OH_AI_ModelGetOutputs(liteModel);
        if (liteInputs.handle_num != 1 || liteOutputs.handle_num != 1) {
            throw std::runtime_error("watermark_model_contract");
        }
        for (auto tensor : {liteInputs.handle_list[0], liteOutputs.handle_list[0]}) {
            size_t rank = 0;
            const int64_t *shape = OH_AI_TensorGetShape(tensor, &rank);
            if (OH_AI_TensorGetDataType(tensor) != OH_AI_DATATYPE_NUMBERTYPE_FLOAT32 ||
                rank != 4 || shape[0] != 1 || shape[1] != 3 || shape[2] != TILE || shape[3] != TILE) {
                throw std::runtime_error("watermark_model_contract");
            }
        }
        OH_LOG_INFO(LOG_APP, 0, "ComicWatermark", "model=mindir requested=%{public}s",
            accelerator ? "nnrt-accelerator" : "cpu");
    }
    void load(const std::string &path, bool mindir)
    {
        if (mindir) {
            loadMindIR(path);
            return;
        }
        if (api == nullptr) {
            throw std::runtime_error(std::string("ONNX Runtime ") + OrtGetApiBase()->GetVersionString() +
                ": requested C API " + std::to_string(RUNTIME_API_VERSION));
        }
        check(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ComicWatermark", &env));
        check(api->CreateSessionOptions(&options));
        check(api->SetIntraOpNumThreads(options, 2));
        check(api->AddSessionConfigEntry(options, "session.intra_op.allow_spinning", "0"));
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
        OH_LOG_INFO(LOG_APP, 0, "ComicWatermark", "model=onnx backend=cpu");
    }
};

std::unique_ptr<Model> cachedModel;
std::string cachedModelPath;

Model &modelFor(const std::string &path)
{
    if (!cachedModel || cachedModelPath != path) {
        auto model = std::make_unique<Model>();
        model->load(path, path.size() >= 3 && path.substr(path.size() - 3) == ".ms");
        cachedModel = std::move(model);
        cachedModelPath = path;
    }
    return *cachedModel;
}

enum class JobKind { Load, Process, Release };

struct Job {
    napi_async_work work{};
    napi_deferred deferred{};
    JobKind kind = JobKind::Load;
    int32_t requestId = 0;
    std::string path;
    bool mindir = false;
    int width = 0;
    int height = 0;
    int total = 0;
    std::atomic<int> completed{-1};
    std::atomic<bool> cancelled{false};
    OrtRunOptions *runOptions{};
    std::vector<uint8_t> rgba;
    std::string error;
    ~Job()
    {
        if (runOptions) api->ReleaseRunOptions(runOptions);
    }
};

std::mutex activeMutex;
Job *activeJob = nullptr;

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
    {
        std::lock_guard<std::mutex> lock(activeMutex);
        if (job.cancelled.load()) return;
        if (!model.liteModel) check(api->CreateRunOptions(&job.runOptions));
    }
    job.completed.store(0);
    const size_t pixels = static_cast<size_t>(job.width) * job.height;
    std::vector<float> totals(pixels * 3, 0);
    std::vector<float> weights(pixels, 0);
    std::vector<float> input(PLANE * 3);
    const std::array<int64_t, 4> shape{1, 3, TILE, TILE};
    OrtValue *inputValue = nullptr;
    if (!model.liteModel) {
        check(api->CreateTensorWithDataAsOrtValue(model.memory, input.data(), input.size() * sizeof(float),
            shape.data(), shape.size(), ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputValue));
    }
    const auto releaseValue = [](OrtValue *value) { api->ReleaseValue(value); };
    std::unique_ptr<OrtValue, decltype(releaseValue)> inputOwner(inputValue, releaseValue);
    const char *inputNames[]{"image"};
    const char *outputNames[]{"clean"};
    for (const int top : starts(job.height)) {
        for (const int left : starts(job.width)) {
            if (job.cancelled.load()) return;
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
            const auto started = std::chrono::steady_clock::now();
            const float *output = nullptr;
            if (model.liteModel) {
                std::memcpy(OH_AI_TensorGetMutableData(model.liteInputs.handle_list[0]),
                    input.data(), input.size() * sizeof(float));
                const auto status = OH_AI_ModelPredict(model.liteModel, model.liteInputs,
                    &model.liteOutputs, nullptr, nullptr);
                if (status != OH_AI_STATUS_SUCCESS) {
                    throw std::runtime_error("watermark_mindir_predict:" + std::to_string(status));
                }
                output = static_cast<const float *>(OH_AI_TensorGetData(model.liteOutputs.handle_list[0]));
            } else {
                const OrtValue *inputs[]{inputValue};
                check(api->Run(model.session, job.runOptions, inputNames, inputs, 1, outputNames, 1, &outputValue));
                void *outputData = nullptr;
                check(api->GetTensorMutableData(outputValue, &outputData));
                output = static_cast<const float *>(outputData);
            }
            std::unique_ptr<OrtValue, decltype(releaseValue)> outputOwner(outputValue, releaseValue);
            if (job.cancelled.load()) return;
            if (job.completed.load() == 0) {
                const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - started).count();
                OH_LOG_INFO(LOG_APP, 0, "ComicWatermark", "request=%{public}d firstTileMs=%{public}lld tiles=%{public}d",
                    job.requestId, static_cast<long long>(elapsed), job.total);
            }
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
            job.completed.fetch_add(1);
        }
    }
    if (job.cancelled.load()) return;
    for (size_t pixel = 0; pixel < pixels; ++pixel) {
        for (int channel = 0; channel < 3; ++channel) {
            const float value = std::clamp(totals[pixel * 3 + channel] / weights[pixel], 0.0F, 1.0F);
            job.rgba[pixel * 4 + channel] = static_cast<uint8_t>(std::round(value * 255.0F));
        }
    }
}

napi_value run(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5]{};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto job = std::make_unique<Job>();
    if (argc == 0) {
        job->kind = JobKind::Release;
    } else {
        size_t length = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
        std::vector<char> path(length + 1);
        napi_get_value_string_utf8(env, args[0], path.data(), path.size(), &length);
        job->path.assign(path.data(), length);
    }
    if (argc == 5) {
        job->kind = JobKind::Process;
        void *bytes = nullptr;
        size_t size = 0;
        napi_get_arraybuffer_info(env, args[1], &bytes, &size);
        napi_get_value_int32(env, args[2], &job->width);
        napi_get_value_int32(env, args[3], &job->height);
        napi_get_value_int32(env, args[4], &job->requestId);
        if (job->width <= 0 || job->height <= 0 || size != static_cast<size_t>(job->width) * job->height * 4) {
            napi_throw_error(env, nullptr, "watermark_pixels");
            return nullptr;
        }
        job->rgba.assign(static_cast<uint8_t *>(bytes), static_cast<uint8_t *>(bytes) + size);
        job->total = static_cast<int>(starts(job->width).size() * starts(job->height).size());
        std::lock_guard<std::mutex> lock(activeMutex);
        activeJob = job.get();
    } else if (argc == 2) {
        napi_get_value_bool(env, args[1], &job->mindir);
    }
    napi_value promise{};
    napi_create_promise(env, &job->deferred, &promise);
    napi_value name{};
    napi_create_string_utf8(env, "ComicWatermark", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, [](napi_env, void *data) {
        auto &item = *static_cast<Job *>(data);
        try {
            if (item.kind == JobKind::Process) {
                if (!item.cancelled.load()) process(modelFor(item.path), item);
            } else {
                cachedModel.reset();
                cachedModelPath.clear();
                if (item.kind == JobKind::Load) {
                    Model model;
                    model.load(item.path, item.mindir);
                }
            }
        } catch (const std::exception &error) { item.error = error.what(); }
    }, [](napi_env env, napi_status status, void *data) {
        std::unique_ptr<Job> item(static_cast<Job *>(data));
        {
            std::lock_guard<std::mutex> lock(activeMutex);
            if (activeJob == item.get()) activeJob = nullptr;
        }
        napi_value result{};
        if (!item->cancelled.load() && (status != napi_ok || !item->error.empty())) {
            napi_value message{};
            napi_create_string_utf8(env, item->error.c_str(), NAPI_AUTO_LENGTH, &message);
            napi_create_error(env, nullptr, message, &result);
            napi_reject_deferred(env, item->deferred, result);
        } else {
            void *bytes = nullptr;
            const size_t size = item->cancelled.load() ? 0 : item->rgba.size();
            napi_create_arraybuffer(env, size, &bytes, &result);
            if (size > 0) std::memcpy(bytes, item->rgba.data(), size);
            napi_resolve_deferred(env, item->deferred, result);
        }
        napi_delete_async_work(env, item->work);
    }, job.get(), &job->work);
    napi_queue_async_work(env, job->work);
    job.release();
    return promise;
}

napi_value cancel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value arg{};
    int32_t requestId = 0;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    napi_get_value_int32(env, arg, &requestId);
    {
        std::lock_guard<std::mutex> lock(activeMutex);
        if (activeJob && activeJob->requestId == requestId) {
            activeJob->cancelled.store(true);
            if (activeJob->runOptions) {
                OrtStatus *status = api->RunOptionsSetTerminate(activeJob->runOptions);
                if (status) api->ReleaseStatus(status);
            }
        }
    }
    napi_value result{};
    napi_get_undefined(env, &result);
    return result;
}

napi_value progress(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value arg{};
    int32_t requestId = 0;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    napi_get_value_int32(env, arg, &requestId);
    napi_value result{};
    napi_create_array(env, &result);
    std::lock_guard<std::mutex> lock(activeMutex);
    if (activeJob && activeJob->requestId == requestId) {
        napi_value completed{};
        napi_value total{};
        napi_create_int32(env, activeJob->completed.load(), &completed);
        napi_create_int32(env, activeJob->total, &total);
        napi_set_element(env, result, 0, completed);
        napi_set_element(env, result, 1, total);
    }
    return result;
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor methods[]{
        {"process", nullptr, run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"load", nullptr, run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancel", nullptr, cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"progress", nullptr, progress, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 5, methods);
    return exports;
}
}

static napi_module module = {1, 0, nullptr, init, "comic_watermark", nullptr, {0}};
extern "C" __attribute__((constructor)) void registerComicWatermark() { napi_module_register(&module); }
