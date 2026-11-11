#include "napi/native_api.h"
#include "model_pack_key.h"

// The release key never appears in ArkTS/source control. Offline extraction is
// still possible with instrumentation; this is package encryption, not DRM.
static napi_value GetKey(napi_env env, napi_callback_info)
{
    void* data = nullptr;
    napi_value result = nullptr;
    if (napi_create_arraybuffer(env, 32, &data, &result) != napi_ok || data == nullptr) {
        napi_throw_error(env, nullptr, "model_pack_invalid");
        return nullptr;
    }
    auto* bytes = static_cast<unsigned char*>(data);
    for (int i = 0; i < 32; ++i) bytes[i] = PACK_KEY_MASK[i] ^ PACK_KEY_DATA[i];
    return result;
}

static napi_value GetKeyId(napi_env env, napi_callback_info)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, PACK_KEY_ID, NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"getKey", nullptr, GetKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getKeyId", nullptr, GetKeyId, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 2, properties);
    return exports;
}

static napi_module module = {1, 0, nullptr, Init, "model_pack_crypto", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterModelPackCrypto()
{
    napi_module_register(&module);
}
