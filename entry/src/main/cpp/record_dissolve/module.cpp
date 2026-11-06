#include "shatter_renderer.h"

namespace {
napi_value Init(napi_env env, napi_value exports) {
    ShatterRegister(env, exports);
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "record_dissolve", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterRecordDissolve() {
    napi_module_register(&module);
}
