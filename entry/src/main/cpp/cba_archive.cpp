#include "ace/AceArchive.h"
#include <napi/native_api.h>

namespace {
napi_value Extract(napi_env env, napi_callback_info info) {
    size_t count = 3; napi_value args[3];
    if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 3) {
        napi_throw_error(env, nullptr, "import_cba_invalid"); return nullptr;
    }
    try {
        int32_t fd; size_t length; napi_valuetype type;
        hsda::ace::require(napi_get_value_int32(env, args[0], &fd) == napi_ok && fd >= 0);
        hsda::ace::require(napi_get_value_string_utf8(env, args[1], nullptr, 0, &length) == napi_ok && length > 0 && length < 4096);
        std::vector<char> buffer(length + 1);
        hsda::ace::require(napi_get_value_string_utf8(env, args[1], buffer.data(), buffer.size(), &length) == napi_ok);
        hsda::ace::require(napi_typeof(env, args[2], &type) == napi_ok && type == napi_function);
        auto paths = hsda::ace::extractComic(fd, std::string(buffer.data(), length), [&](size_t done, size_t total) {
            napi_handle_scope scope;
            hsda::ace::require(napi_open_handle_scope(env, &scope) == napi_ok);
            napi_value receiver, values[2], ignored;
            napi_get_undefined(env, &receiver);
            napi_create_uint32(env, uint32_t(done), &values[0]);
            napi_create_uint32(env, uint32_t(total), &values[1]);
            const napi_status status = napi_call_function(env, receiver, args[2], 2, values, &ignored);
            napi_close_handle_scope(env, scope);
            hsda::ace::require(status == napi_ok);
        });
        napi_value result; hsda::ace::require(napi_create_array_with_length(env, paths.size(), &result) == napi_ok);
        for (size_t i = 0; i < paths.size(); ++i) {
            napi_value value;
            hsda::ace::require(napi_create_string_utf8(env, paths[i].c_str(), paths[i].size(), &value) == napi_ok);
            hsda::ace::require(napi_set_element(env, result, uint32_t(i), value) == napi_ok);
        }
        return result;
    } catch (const std::bad_alloc&) { napi_throw_error(env, nullptr, "import_cba_limit"); }
    catch (const std::exception& error) {
        bool pending = false; napi_is_exception_pending(env, &pending);
        if (!pending) napi_throw_error(env, nullptr, error.what());
    }
    return nullptr;
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor property = {"extract", nullptr, Extract, nullptr, nullptr, nullptr, napi_default, nullptr};
    napi_define_properties(env, exports, 1, &property); return exports;
}
napi_module module = {1, 0, nullptr, Init, "cba_archive", nullptr, {0}};
}
extern "C" __attribute__((constructor)) void RegisterCbaArchive() { napi_module_register(&module); }
