#include "offline_tts_archive_core.h"
#include <napi/native_api.h>
#include <atomic>
#include <fcntl.h>
#include <memory>
#include <stdexcept>
#include <unistd.h>
#include <vector>

namespace {
std::atomic<bool> busy {false};
std::atomic<uint64_t> epoch {0}, completedBytes {0};

struct Job {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    int fd = -1;
    std::string staging, modelId, error;
    uint64_t generation = 0;
    size_t files = 0;
    ~Job() { if (fd >= 0) close(fd); }
};

void execute(napi_env, void *data) {
    auto &job = *static_cast<Job *>(data);
    try {
        job.files = hsda::offline_tts::extractTarBz2(job.fd, job.staging, job.modelId, [&]() {
            if (job.generation != epoch.load()) throw std::runtime_error("offline_tts_cancelled");
        }, [](uint64_t count) { completedBytes.store(count); });
    } catch (const std::bad_alloc &) { job.error = "offline_tts_archive_limit"; }
    catch (const std::exception &error) { job.error = error.what(); }
    catch (...) { job.error = "offline_tts_pack_invalid"; }
}

void complete(napi_env env, napi_status status, void *data) {
    std::unique_ptr<Job> job(static_cast<Job *>(data));
    busy.store(false);
    if (status != napi_ok && job->error.empty()) job->error = "offline_tts_cancelled";
    if (!job->error.empty()) {
        napi_value message, error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error); napi_reject_deferred(env, job->deferred, error);
    } else {
        napi_value result; napi_create_uint32(env, uint32_t(job->files), &result);
        napi_resolve_deferred(env, job->deferred, result);
    }
    napi_delete_async_work(env, job->work);
}

napi_value extract(napi_env env, napi_callback_info info) {
    size_t count = 3; napi_value args[3]; int32_t source = -1; size_t length = 0, modelLength = 0;
    if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 3 ||
        napi_get_value_int32(env, args[0], &source) != napi_ok || source < 0 ||
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &length) != napi_ok || length == 0 || length >= 4096 ||
        napi_get_value_string_utf8(env, args[2], nullptr, 0, &modelLength) != napi_ok || modelLength == 0 || modelLength > 128) {
        napi_throw_error(env, nullptr, "offline_tts_pack_invalid"); return nullptr;
    }
    bool expected = false;
    if (!busy.compare_exchange_strong(expected, true)) {
        napi_throw_error(env, nullptr, "offline_tts_busy"); return nullptr;
    }
    std::unique_ptr<Job> job;
    try {
        job = std::make_unique<Job>();
        job->fd = fcntl(source, F_DUPFD_CLOEXEC, 0);
        if (job->fd < 0) throw std::runtime_error("offline_tts_pack_invalid");
        std::vector<char> text(length + 1);
        if (napi_get_value_string_utf8(env, args[1], text.data(), text.size(), &length) != napi_ok ||
            std::string(text.data()).size() != length) throw std::runtime_error("offline_tts_pack_invalid");
        job->staging.assign(text.data(), length);
        std::vector<char> model(modelLength + 1);
        if (napi_get_value_string_utf8(env, args[2], model.data(), model.size(), &modelLength) != napi_ok ||
            std::string(model.data()).size() != modelLength) throw std::runtime_error("offline_tts_pack_invalid");
        job->modelId.assign(model.data(), modelLength);
        job->generation = epoch.load(); completedBytes.store(0);
        napi_value promise, name;
        if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
            napi_create_string_utf8(env, "OfflineTtsArchive", NAPI_AUTO_LENGTH, &name) != napi_ok ||
            napi_create_async_work(env, nullptr, name, execute, complete, job.get(), &job->work) != napi_ok ||
            napi_queue_async_work(env, job->work) != napi_ok) throw std::runtime_error("offline_tts_worker");
        job.release(); return promise;
    } catch (const std::exception &error) {
        if (job && job->work) napi_delete_async_work(env, job->work);
        busy.store(false); napi_throw_error(env, nullptr, error.what());
    } catch (...) { busy.store(false); napi_throw_error(env, nullptr, "offline_tts_worker"); }
    return nullptr;
}

napi_value cancel(napi_env env, napi_callback_info) {
    epoch.fetch_add(1); napi_value result; napi_get_undefined(env, &result); return result;
}
napi_value progress(napi_env env, napi_callback_info) {
    napi_value result; napi_create_double(env, double(completedBytes.load()), &result); return result;
}
napi_value init(napi_env env, napi_value exports) {
    const napi_property_descriptor properties[] = {
        {"extract", nullptr, extract, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancel", nullptr, cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"progress", nullptr, progress, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 3, properties); return exports;
}
napi_module module = {1, 0, nullptr, init, "offline_tts_archive", nullptr, {nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterOfflineTtsArchive() { napi_module_register(&module); }
