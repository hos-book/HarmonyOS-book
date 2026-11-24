#include <napi/native_api.h>
#include <mindspore/model.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr size_t SEQUENCE_LENGTH = 512;
constexpr size_t INPUT_BYTES = SEQUENCE_LENGTH * sizeof(int32_t);
constexpr std::array<const char *, 3> INPUT_NAMES{"input_ids", "token_type_ids", "attention_mask"};
constexpr std::array<const char *, 2> OUTPUT_NAMES{"start_logits", "end_logits"};

struct Runtime {
    std::string path;
    OH_AI_ContextHandle context{};
    OH_AI_ModelHandle model{};
    bool accelerator{};
    std::array<OH_AI_TensorHandle, 3> inputs{};
};

struct Job {
    napi_async_work work{};
    napi_deferred deferred{};
    std::string operation;
    std::string path;
    std::string backend;
    std::array<std::vector<uint8_t>, 3> inputs;
    std::vector<float> output;
    std::string error;
};

Runtime runtime;
std::mutex runtimeMutex;

void releaseRuntime()
{
    if (runtime.model != nullptr) OH_AI_ModelDestroy(&runtime.model);
    if (runtime.context != nullptr) OH_AI_ContextDestroy(&runtime.context);
    runtime = Runtime{};
}

void requireStatus(OH_AI_Status status, const char *operation)
{
    if (status != OH_AI_STATUS_SUCCESS) {
        throw std::runtime_error(std::string(operation) + "_" + std::to_string(static_cast<int>(status)));
    }
}

void buildModel(const std::string &path, bool preferAccelerator)
{
    releaseRuntime();
    runtime.context = OH_AI_ContextCreate();
    if (runtime.context == nullptr) throw std::runtime_error("role_memory");
    OH_AI_ContextSetThreadNum(runtime.context, 2);
    OH_AI_ContextSetEnableParallel(runtime.context, false);
    if (preferAccelerator) {
        auto accelerator = OH_AI_CreateNNRTDeviceInfoByType(OH_AI_NNRTDEVICE_ACCELERATOR);
        if (accelerator != nullptr) {
            OH_AI_DeviceInfoSetPerformanceMode(accelerator, OH_AI_PERFORMANCE_HIGH);
            OH_AI_ContextAddDeviceInfo(runtime.context, accelerator);
            runtime.accelerator = true;
        }
    }
    auto cpu = OH_AI_DeviceInfoCreate(OH_AI_DEVICETYPE_CPU);
    if (cpu == nullptr) throw std::runtime_error("role_memory");
    OH_AI_DeviceInfoSetEnableFP16(cpu, true);
    OH_AI_ContextAddDeviceInfo(runtime.context, cpu);
    runtime.model = OH_AI_ModelCreate();
    if (runtime.model == nullptr) throw std::runtime_error("role_memory");
    requireStatus(OH_AI_ModelBuildFromFile(runtime.model, path.c_str(), OH_AI_MODELTYPE_MINDIR,
        runtime.context), "role_model_load");
    const auto inputs = OH_AI_ModelGetInputs(runtime.model);
    const auto outputs = OH_AI_ModelGetOutputs(runtime.model);
    if (inputs.handle_num != INPUT_NAMES.size() || outputs.handle_num != OUTPUT_NAMES.size()) {
        throw std::runtime_error("role_model_unsupported");
    }
    for (size_t index = 0; index < INPUT_NAMES.size(); ++index) {
        auto tensor = OH_AI_ModelGetInputByTensorName(runtime.model, INPUT_NAMES[index]);
        if (tensor == nullptr) throw std::runtime_error("role_model_unsupported");
        size_t rank = 0;
        const auto *shape = OH_AI_TensorGetShape(tensor, &rank);
        if (OH_AI_TensorGetDataType(tensor) != OH_AI_DATATYPE_NUMBERTYPE_INT32 ||
            rank != 2 || shape == nullptr || shape[0] != 1 || shape[1] != SEQUENCE_LENGTH ||
            OH_AI_TensorGetDataSize(tensor) != INPUT_BYTES) {
            throw std::runtime_error("role_model_unsupported");
        }
        runtime.inputs[index] = tensor;
    }
    runtime.path = path;
}

void ensureRuntime(const std::string &path)
{
    if (runtime.model != nullptr && runtime.path == path) return;
    try {
        buildModel(path, true);
    } catch (const std::exception &) {
        if (!runtime.accelerator) throw;
        buildModel(path, false);
    }
}

float halfToFloat(uint16_t half)
{
    const uint32_t sign = static_cast<uint32_t>(half & 0x8000U) << 16;
    uint32_t exponent = (half >> 10) & 0x1FU;
    uint32_t fraction = half & 0x03FFU;
    uint32_t bits = sign;
    if (exponent == 0) {
        if (fraction != 0) {
            int32_t adjustedExponent = -14;
            while ((fraction & 0x0400U) == 0) { fraction <<= 1; --adjustedExponent; }
            bits |= static_cast<uint32_t>(adjustedExponent + 127) << 23;
            bits |= (fraction & 0x03FFU) << 13;
        }
    } else if (exponent == 0x1FU) {
        bits |= 0x7F800000U | (fraction << 13);
    } else {
        bits |= (exponent - 15 + 127) << 23;
        bits |= fraction << 13;
    }
    float value = 0.0F;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

std::vector<float> predictModel(const std::array<std::vector<uint8_t>, 3> &inputBuffers)
{
    if (runtime.model == nullptr) throw std::runtime_error("role_model_invalid");
    for (size_t index = 0; index < runtime.inputs.size(); ++index) {
        void *data = OH_AI_TensorGetMutableData(runtime.inputs[index]);
        if (data == nullptr) throw std::runtime_error("role_memory");
        std::memcpy(data, inputBuffers[index].data(), INPUT_BYTES);
    }
    auto outputs = OH_AI_ModelGetOutputs(runtime.model);
    requireStatus(OH_AI_ModelPredict(runtime.model, OH_AI_ModelGetInputs(runtime.model), &outputs,
        nullptr, nullptr), "role_inference");
    std::vector<float> result(SEQUENCE_LENGTH * 2);
    for (size_t index = 0; index < OUTPUT_NAMES.size(); ++index) {
        auto tensor = OH_AI_ModelGetOutputByTensorName(runtime.model, OUTPUT_NAMES[index]);
        if (tensor == nullptr || OH_AI_TensorGetElementNum(tensor) != SEQUENCE_LENGTH) {
            throw std::runtime_error("role_model_unsupported");
        }
        const void *data = OH_AI_TensorGetData(tensor);
        if (data == nullptr) throw std::runtime_error("role_memory");
        float *destination = result.data() + index * SEQUENCE_LENGTH;
        const auto type = OH_AI_TensorGetDataType(tensor);
        if (type == OH_AI_DATATYPE_NUMBERTYPE_FLOAT32) {
            std::memcpy(destination, data, SEQUENCE_LENGTH * sizeof(float));
        } else if (type == OH_AI_DATATYPE_NUMBERTYPE_FLOAT16) {
            const auto *values = static_cast<const uint16_t *>(data);
            for (size_t position = 0; position < SEQUENCE_LENGTH; ++position) {
                destination[position] = halfToFloat(values[position]);
            }
        } else {
            throw std::runtime_error("role_model_unsupported");
        }
    }
    return result;
}

std::vector<float> predictSelectedModel(const std::array<std::vector<uint8_t>, 3> &inputs)
{
    try {
        return predictModel(inputs);
    } catch (const std::exception &) {
        if (!runtime.accelerator) throw;
        const std::string path = runtime.path;
        buildModel(path, false);
        return predictModel(inputs);
    }
}

std::unique_ptr<Job> newJob(const char *operation)
{
    auto job = std::make_unique<Job>();
    job->operation = operation;
    return job;
}

napi_value queueJob(napi_env env, std::unique_ptr<Job> job)
{
    napi_value promise{};
    if (napi_create_promise(env, &job->deferred, &promise) != napi_ok) return nullptr;
    napi_value name{};
    napi_create_string_utf8(env, "RoleNnrt", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, [](napi_env, void *data) {
            auto &queuedJob = *static_cast<Job *>(data);
            std::lock_guard<std::mutex> lock(runtimeMutex);
            try {
                if (queuedJob.operation == "load") {
                    ensureRuntime(queuedJob.path);
                } else if (queuedJob.operation == "predict") {
                    queuedJob.output = predictSelectedModel(queuedJob.inputs);
                } else {
                    releaseRuntime();
                }
                queuedJob.backend = runtime.accelerator ? "nnrt" : "cpu";
            } catch (const std::bad_alloc &) {
                queuedJob.error = "role_memory";
                releaseRuntime();
            } catch (const std::exception &error) {
                queuedJob.error = error.what();
                releaseRuntime();
            } catch (...) {
                queuedJob.error = "role_inference";
                releaseRuntime();
            }
        }, [](napi_env callbackEnv, napi_status status, void *data) {
            std::unique_ptr<Job> completedJob(static_cast<Job *>(data));
            if (status != napi_ok && completedJob->error.empty()) completedJob->error = "role_inference";
            napi_value value{};
            if (completedJob->error.empty()) {
                if (completedJob->operation == "predict") {
                    void *buffer = nullptr;
                    napi_value output{};
                    napi_value backend{};
                    const size_t byteLength = completedJob->output.size() * sizeof(float);
                    napi_create_arraybuffer(callbackEnv, byteLength, &buffer, &output);
                    if (buffer != nullptr) std::memcpy(buffer, completedJob->output.data(), byteLength);
                    napi_create_object(callbackEnv, &value);
                    napi_create_string_utf8(callbackEnv, completedJob->backend.c_str(), NAPI_AUTO_LENGTH, &backend);
                    napi_set_named_property(callbackEnv, value, "output", output);
                    napi_set_named_property(callbackEnv, value, "backend", backend);
                } else if (completedJob->operation == "load") {
                    napi_create_string_utf8(callbackEnv, completedJob->backend.c_str(), NAPI_AUTO_LENGTH, &value);
                } else {
                    napi_get_undefined(callbackEnv, &value);
                }
                napi_resolve_deferred(callbackEnv, completedJob->deferred, value);
            } else {
                napi_value message{};
                napi_create_string_utf8(callbackEnv, completedJob->error.c_str(), NAPI_AUTO_LENGTH, &message);
                napi_create_error(callbackEnv, nullptr, message, &value);
                napi_reject_deferred(callbackEnv, completedJob->deferred, value);
            }
            napi_delete_async_work(callbackEnv, completedJob->work);
        }, job.get(), &job->work) != napi_ok) return nullptr;
    if (napi_queue_async_work(env, job->work) != napi_ok) {
        napi_delete_async_work(env, job->work);
        return nullptr;
    }
    job.release();
    return promise;
}

napi_value loadModel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1]{};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    try {
        size_t length = 0;
        if (argc != 1 || napi_get_value_string_utf8(env, argv[0], nullptr, 0, &length) != napi_ok ||
            length == 0 || length > 4096) throw std::runtime_error("role_model_invalid");
        std::vector<char> buffer(length + 1);
        if (napi_get_value_string_utf8(env, argv[0], buffer.data(), buffer.size(), &length) != napi_ok) {
            throw std::runtime_error("role_model_invalid");
        }
        auto job = newJob("load");
        job->path.assign(buffer.data(), length);
        if (job->path.find("/role_models/") == std::string::npos || job->path.find("..") != std::string::npos ||
            job->path.size() < 3 || job->path.substr(job->path.size() - 3) != ".ms") {
            throw std::runtime_error("role_model_invalid");
        }
        return queueJob(env, std::move(job));
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value predict(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3]{};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    try {
        if (argc != 3) throw std::runtime_error("role_model_unsupported");
        auto job = newJob("predict");
        for (size_t index = 0; index < 3; ++index) {
            bool isArrayBuffer = false;
            void *data = nullptr;
            size_t byteLength = 0;
            if (napi_is_arraybuffer(env, argv[index], &isArrayBuffer) != napi_ok || !isArrayBuffer ||
                napi_get_arraybuffer_info(env, argv[index], &data, &byteLength) != napi_ok ||
                byteLength != INPUT_BYTES || data == nullptr) throw std::runtime_error("role_model_unsupported");
            job->inputs[index].resize(byteLength);
            std::memcpy(job->inputs[index].data(), data, byteLength);
        }
        return queueJob(env, std::move(job));
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value releaseModel(napi_env env, napi_callback_info)
{
    return queueJob(env, newJob("unload"));
}

napi_value initialize(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"loadRoleNnrtModel", nullptr, loadModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"predictRoleNnrtModel", nullptr, predict, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseRoleNnrtModel", nullptr, releaseModel, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
napi_module module = {1, 0, nullptr, initialize, "role_nnrt", nullptr, {nullptr}};
}

extern "C" __attribute__((constructor)) void RegisterRoleNnrt()
{
    napi_module_register(&module);
}
