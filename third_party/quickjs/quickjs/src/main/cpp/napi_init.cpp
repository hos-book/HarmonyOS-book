/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "napi/native_api.h"
#include "quickjs_headers.h"
#include "handle_registry.h"
#include <string>
#include <vector>
#include <cstring>
#include <chrono>
#include <algorithm>

// Static member definitions for registries
std::mutex EngineRegistry::mutex_;
std::unordered_map<int64_t, EngineEntry> EngineRegistry::engines_;
int64_t EngineRegistry::nextHandle_ = 1;

std::mutex ValueRegistry::mutex_;
std::unordered_map<int64_t, ValueEntry> ValueRegistry::values_;
int64_t ValueRegistry::nextHandle_ = 1;

#define NAPI_CALL_RET(call, return_value)                                                                              \
    do {                                                                                                               \
        napi_status status = (call);                                                                                   \
        if (status != napi_ok) {                                                                                       \
            const napi_extended_error_info *error_info = nullptr;                                                      \
            napi_get_last_error_info(env, &error_info);                                                                \
            bool is_pending;                                                                                           \
            napi_is_exception_pending(env, &is_pending);                                                               \
            if (!is_pending) {                                                                                         \
                auto message = error_info->error_message ? error_info->error_message : "null";                         \
                napi_throw_error(env, nullptr, message);                                                               \
                return return_value;                                                                                   \
            }                                                                                                          \
        }                                                                                                              \
    } while (0)

#define NAPI_CALL(call) NAPI_CALL_RET(call, nullptr)

// Helper: convert JSValue to int64_t handle via ValueRegistry
static napi_value JSValueToHandle(napi_env env, JSValue value, JSContext* ctx) {
    JSValue dup = JS_DupValue(ctx, value);
    int64_t handle = ValueRegistry::Register(dup, ctx);
    napi_value result;
    napi_create_bigint_uint64(env, (uint64_t)handle, &result);
    return result;
}

// Helper: get JSValue from handle
static ValueEntry HandleToValue(int64_t handle) {
    return ValueRegistry::Get(handle);
}

// Helper: get context from engine handle
static JSContext* HandleToContext(int64_t handle) {
    return EngineRegistry::GetContext(handle);
}

// Helper: read bigint arg
static int64_t NValueToHandle(napi_env env, napi_value value) {
    uint64_t result;
    bool lossless;
    napi_get_value_bigint_uint64(env, value, &result, &lossless);
    return (int64_t)result;
}

// Helper: convert NAPI value to QuickJS JSValue
static JSValue NAPIValueToJSValue(napi_env env, napi_value value, JSContext* ctx) {
    napi_valuetype type;
    napi_typeof(env, value, &type);

    if (type == napi_number) {
        double num;
        napi_get_value_double(env, value, &num);
        return JS_NewFloat64(ctx, num);
    } else if (type == napi_string) {
        size_t len;
        napi_get_value_string_utf8(env, value, nullptr, 0, &len);
        std::string str(len, '\0');
        napi_get_value_string_utf8(env, value, &str[0], len + 1, nullptr);
        return JS_NewString(ctx, str.c_str());
    } else if (type == napi_boolean) {
        bool b;
        napi_get_value_bool(env, value, &b);
        return JS_NewBool(ctx, b);
    } else if (type == napi_bigint) {
        uint64_t v;
        bool lossless;
        napi_get_value_bigint_uint64(env, value, &v, &lossless);
        return JS_NewInt64(ctx, (int64_t)v);
    } else if (type == napi_null) {
        return JS_NULL;
    } else {
        return JS_UNDEFINED;
    }
}

// Helper: free JSValue args after call
static void FreeJSValues(JSContext* ctx, std::vector<JSValue>& values) {
    for (auto& v : values) {
        JS_FreeValue(ctx, v);
    }
}

// Helper: read string arg (may be undefined)
static std::string NValueToString(napi_env env, napi_value value) {
    napi_valuetype type;
    napi_typeof(env, value, &type);
    if (type == napi_undefined || type == napi_null) {
        return "";
    }
    size_t size;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);
    std::string result(size, '\0');
    napi_get_value_string_utf8(env, value, &result[0], size + 1, nullptr);
    return result;
}

static napi_value NAPIUndefined(napi_env env) {
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value NAPIBoolean(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

static napi_value NAPINumber(napi_env env, double value) {
    napi_value result;
    napi_create_double(env, value, &result);
    return result;
}

static napi_value NAPIString(napi_env env, const std::string& value) {
    napi_value result;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

static void SetNamedProperty(napi_env env, napi_value object, const char* name, napi_value value) {
    napi_set_named_property(env, object, name, value);
}

static double NValueToNumber(napi_env env, napi_value value, double fallback) {
    if (value == nullptr) return fallback;
    napi_valuetype type;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_number) return fallback;
    double result = fallback;
    if (napi_get_value_double(env, value, &result) != napi_ok) return fallback;
    return result;
}

// ============== Engine/Context Lifecycle ==============

static napi_value CreateEngine(napi_env env, napi_callback_info info) {
    JSRuntime* rt = JS_NewRuntime();
    JS_SetMemoryLimit(rt, 64 * 1024 * 1024);  // 64MB memory limit
    JS_SetMaxStackSize(rt, 256 * 1024);       // 256KB stack limit
    JSContext* ctx = JS_NewContext(rt);
    if (!ctx) {
        return NAPIUndefined(env);
    }
    int64_t handle = EngineRegistry::Register(rt, ctx);
    napi_value result;
    napi_create_bigint_uint64(env, (uint64_t)handle, &result);
    return result;
}

static napi_value CreateEngineWithOptions(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    const double requestedMemory = NValueToNumber(env, args[0], 64.0 * 1024.0 * 1024.0);
    const double requestedStack = NValueToNumber(env, args[1], 256.0 * 1024.0);
    const size_t memoryLimit = static_cast<size_t>(std::max(1024.0 * 1024.0,
        std::min(512.0 * 1024.0 * 1024.0, requestedMemory)));
    const size_t stackLimit = static_cast<size_t>(std::max(64.0 * 1024.0,
        std::min(8.0 * 1024.0 * 1024.0, requestedStack)));

    JSRuntime* rt = JS_NewRuntime();
    if (!rt) return NAPIUndefined(env);
    JS_SetMemoryLimit(rt, memoryLimit);
    JS_SetMaxStackSize(rt, stackLimit);
    JSContext* ctx = JS_NewContext(rt);
    if (!ctx) {
        JS_FreeRuntime(rt);
        return NAPIUndefined(env);
    }
    int64_t handle = EngineRegistry::Register(rt, ctx);
    napi_value result;
    napi_create_bigint_uint64(env, static_cast<uint64_t>(handle), &result);
    return result;
}

static napi_value ReleaseEngine(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (ctx) {
        JSRuntime* rt = EngineRegistry::GetRuntime(engineHandle);
        EngineRegistry::Unregister(engineHandle);
        JS_FreeContext(ctx);
        JS_FreeRuntime(rt);
    }
    return NAPIUndefined(env);
}

static napi_value GetGlobal(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) {
        return NAPIUndefined(env);
    }

    JSValue globalVal = JS_GetGlobalObject(ctx);
    return JSValueToHandle(env, globalVal, ctx);
}

// ============== Value Factory ==============

static napi_value CreateUndefined(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    return JSValueToHandle(env, JS_UNDEFINED, ctx);
}

static napi_value CreateNull(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    return JSValueToHandle(env, JS_NULL, ctx);
}

static napi_value CreateBoolean(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    bool value;
    napi_get_value_bool(env, args[1], &value);
    return JSValueToHandle(env, JS_NewBool(ctx, value), ctx);
}

static napi_value CreateNumber(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    double value;
    napi_get_value_double(env, args[1], &value);
    return JSValueToHandle(env, JS_NewFloat64(ctx, value), ctx);
}

static napi_value CreateString(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    std::string str = NValueToString(env, args[1]);
    return JSValueToHandle(env, JS_NewString(ctx, str.c_str()), ctx);
}

static napi_value CreateObject(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    return JSValueToHandle(env, JS_NewObject(ctx), ctx);
}

static napi_value CreateArray(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    JSValue arr = JS_NewArray(ctx);
    if (argc > 1) {
        napi_valuetype type;
        napi_typeof(env, args[1], &type);
        if (type == napi_number) {
            double len;
            napi_get_value_double(env, args[1], &len);
            JS_SetPropertyStr(ctx, arr, "length", JS_NewInt64(ctx, (int64_t)len));
        }
    }
    return JSValueToHandle(env, arr, ctx);
}

static napi_value CreateError(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    std::string code = NValueToString(env, args[1]);
    std::string message = NValueToString(env, args[2]);

    JSValue error = JS_NewError(ctx);
    JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, message.c_str()));
    JS_SetPropertyStr(ctx, error, "name", JS_NewString(ctx, code.empty() ? "Error" : code.c_str()));
    return JSValueToHandle(env, error, ctx);
}

static napi_value CreateDate(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    double timeMs;
    napi_get_value_double(env, args[1], &timeMs);
    JSValue dateVal = JS_StrictDate(ctx, timeMs);
    return JSValueToHandle(env, dateVal, ctx);
}

// ============== Value Type Checks ==============

static napi_value IsUndefined(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsUndefined(entry.value));
}

static napi_value IsNull(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsNull(entry.value));
}

static napi_value IsBoolean(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsBool(entry.value));
}

static napi_value IsNumber(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsNumber(entry.value));
}

static napi_value IsString(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsString(entry.value));
}

static napi_value IsObject(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsObject(entry.value));
}

static napi_value IsArray(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsArray(entry.context, entry.value));
}

static napi_value IsDate(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsDate(entry.context, entry.value));
}

static napi_value IsCallable(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsFunction(entry.context, entry.value));
}

static napi_value IsError(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsError(entry.context, entry.value));
}

// ============== Error / Exception ==============

static napi_value IsException(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_IsException(entry.value));
}

static napi_value GetException(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) {
        napi_value result;
        napi_create_bigint_uint64(env, 0, &result);
        return result;
    }

    // In QuickJS, we always try to get the exception value
    JSValue exc = JS_GetException(ctx);
    if (JS_IsUndefined(exc) || JS_IsNull(exc)) {
        napi_value result;
        napi_create_bigint_uint64(env, 0, &result);
        return result;
    }
    return JSValueToHandle(env, exc, ctx);
}

static napi_value ThrowException(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) {
        napi_value result;
        napi_create_bigint_uint64(env, 0, &result);
        return result;
    }

    int64_t valueHandle = NValueToHandle(env, args[1]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) {
        napi_value result;
        napi_create_bigint_uint64(env, 0, &result);
        return result;
    }

    JSValue exc = JS_Throw(ctx, JS_DupValue(ctx, entry.value));
    return JSValueToHandle(env, exc, ctx);
}

// ============== Value Conversion ==============

static napi_value ToBooleanValue(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPIBoolean(env, false);

    int result = JS_ToBool(entry.context, entry.value);
    return NAPIBoolean(env, result == 1);
}

static napi_value ToNumberValue(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) return NAPINumber(env, 0);

    double result;
    JS_ToFloat64(entry.context, &result, entry.value);
    return NAPINumber(env, result);
}

static napi_value ToStringValue(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (!entry.context) {
        napi_value result;
        napi_create_string_utf8(env, "", 0, &result);
        return result;
    }

    const char* str = JS_ToCString(entry.context, entry.value);
    napi_value result;
    if (str) {
        napi_create_string_utf8(env, str, strlen(str), &result);
        JS_FreeCString(entry.context, str);
    } else {
        napi_create_string_utf8(env, "", 0, &result);
    }
    return result;
}

// ============== Property Access ==============

static napi_value GetProperty(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t objHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    ValueEntry objEntry = HandleToValue(objHandle);
    if (!objEntry.context) return NAPIUndefined(env);

    std::string key = NValueToString(env, args[2]);
    JSValue prop = JS_GetPropertyStr(ctx, objEntry.value, key.c_str());
    return JSValueToHandle(env, prop, ctx);
}

static napi_value SetProperty(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t objHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIBoolean(env, false);

    ValueEntry objEntry = HandleToValue(objHandle);
    if (!objEntry.context) return NAPIBoolean(env, false);

    std::string key = NValueToString(env, args[2]);
    // ArkTS passes a registry handle here, not the primitive payload itself. Duplicate the
    // registered value because JS_SetPropertyStr consumes its JSValue argument.
    int64_t valueHandle = NValueToHandle(env, args[3]);
    ValueEntry valueEntry = HandleToValue(valueHandle);
    if (!valueEntry.context || valueEntry.context != ctx) return NAPIBoolean(env, false);
    JSValue val = JS_DupValue(ctx, valueEntry.value);

    int result = JS_SetPropertyStr(ctx, objEntry.value, key.c_str(), val);
    return NAPIBoolean(env, result == 1);
}

static napi_value HasProperty(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t objHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIBoolean(env, false);

    ValueEntry objEntry = HandleToValue(objHandle);
    if (!objEntry.context) return NAPIBoolean(env, false);

    std::string key = NValueToString(env, args[2]);
    JSValue prop = JS_GetPropertyStr(ctx, objEntry.value, key.c_str());
    bool has = !JS_IsUndefined(prop);
    JS_FreeValue(ctx, prop);
    return NAPIBoolean(env, has);
}

static napi_value DeleteProperty(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t objHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIBoolean(env, false);

    ValueEntry objEntry = HandleToValue(objHandle);
    if (!objEntry.context) return NAPIBoolean(env, false);

    std::string key = NValueToString(env, args[2]);
    JSAtom atom = JS_NewAtom(ctx, key.c_str());
    int result = JS_DeleteProperty(ctx, objEntry.value, atom, 0);
    JS_FreeAtom(ctx, atom);
    return NAPIBoolean(env, result == 1);
}

static napi_value GetPropertyNames(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t objHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    ValueEntry objEntry = HandleToValue(objHandle);
    if (!objEntry.context) return NAPIUndefined(env);

    JSPropertyEnum* props = nullptr;
    uint32_t count;
    if (JS_GetOwnPropertyNames(ctx, &props, &count, objEntry.value, JS_GPN_STRING_MASK) < 0) {
        return NAPIUndefined(env);
    }

    JSValue arr = JS_NewArray(ctx);
    for (uint32_t i = 0; i < count; i++) {
        const char* name = JS_AtomToCString(ctx, props[i].atom);
        if (name) {
            JS_SetPropertyUint32(ctx, arr, i, JS_NewString(ctx, name));
            JS_FreeCString(ctx, name);
        }
        JS_FreeAtom(ctx, props[i].atom);
    }
    js_free(ctx, props);
    return JSValueToHandle(env, arr, ctx);
}

static napi_value GetElement(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t arrayHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    ValueEntry arrEntry = HandleToValue(arrayHandle);
    if (!arrEntry.context) return NAPIUndefined(env);

    double index;
    napi_get_value_double(env, args[2], &index);

    JSValue elem = JS_GetPropertyUint32(ctx, arrEntry.value, (uint32_t)index);
    return JSValueToHandle(env, elem, ctx);
}

static napi_value SetElement(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t arrayHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIBoolean(env, false);

    ValueEntry arrEntry = HandleToValue(arrayHandle);
    if (!arrEntry.context) return NAPIBoolean(env, false);

    double index;
    napi_get_value_double(env, args[2], &index);
    // Keep the registry-owned value alive; JS_SetPropertyUint32 consumes the duplicate.
    int64_t valueHandle = NValueToHandle(env, args[3]);
    ValueEntry valueEntry = HandleToValue(valueHandle);
    if (!valueEntry.context || valueEntry.context != ctx) return NAPIBoolean(env, false);
    JSValue val = JS_DupValue(ctx, valueEntry.value);

    int result = JS_SetPropertyUint32(ctx, arrEntry.value, (uint32_t)index, val);
    return NAPIBoolean(env, result == 1);
}

static napi_value GetArrayLength(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t arrayHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPINumber(env, 0);

    ValueEntry arrEntry = HandleToValue(arrayHandle);
    if (!arrEntry.context) return NAPINumber(env, 0);

    JSValue lenVal = JS_GetPropertyStr(ctx, arrEntry.value, "length");
    uint32_t len = 0;
    JS_ToUint32(ctx, &len, lenVal);
    JS_FreeValue(ctx, lenVal);
    return NAPINumber(env, (double)len);
}

// ============== Function Call ==============

static napi_value CallFunction(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t thisHandle = NValueToHandle(env, args[1]);
    int64_t funcHandle = NValueToHandle(env, args[2]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    ValueEntry thisEntry = HandleToValue(thisHandle);
    ValueEntry funcEntry = HandleToValue(funcHandle);
    if (!funcEntry.context) return NAPIUndefined(env);

    uint32_t argsLen;
    napi_get_array_length(env, args[3], &argsLen);

    std::vector<JSValue> argValues(argsLen);
    for (uint32_t i = 0; i < argsLen; i++) {
        napi_value elem;
        napi_get_element(env, args[3], i, &elem);
        int64_t argHandle = NValueToHandle(env, elem);
        ValueEntry argEntry = HandleToValue(argHandle);
        argValues[i] = JS_DupValue(ctx, argEntry.context ? argEntry.value : JS_UNDEFINED);
    }

    JSValue thisVal = thisEntry.context ? thisEntry.value : JS_UNDEFINED;
    JSValue result = JS_Call(ctx, funcEntry.value, thisVal, argValues.size(),
                             (JSValueConst*)argValues.data());

    FreeJSValues(ctx, argValues);
    return JSValueToHandle(env, result, ctx);
}

static napi_value Construct(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    int64_t constructorHandle = NValueToHandle(env, args[1]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    ValueEntry ctorEntry = HandleToValue(constructorHandle);
    if (!ctorEntry.context) return NAPIUndefined(env);

    uint32_t argsLen;
    napi_get_array_length(env, args[2], &argsLen);

    std::vector<JSValue> argValues(argsLen);
    for (uint32_t i = 0; i < argsLen; i++) {
        napi_value elem;
        napi_get_element(env, args[2], i, &elem);
        int64_t argHandle = NValueToHandle(env, elem);
        ValueEntry argEntry = HandleToValue(argHandle);
        argValues[i] = JS_DupValue(ctx, argEntry.context ? argEntry.value : JS_UNDEFINED);
    }

    JSValue result = JS_CallConstructor(ctx, ctorEntry.value, argValues.size(),
                                        (JSValueConst*)argValues.data());

    FreeJSValues(ctx, argValues);
    return JSValueToHandle(env, result, ctx);
}

// ============== Comparison ==============

static napi_value StrictEquals(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t handle1 = NValueToHandle(env, args[0]);
    int64_t handle2 = NValueToHandle(env, args[1]);
    ValueEntry entry1 = HandleToValue(handle1);
    ValueEntry entry2 = HandleToValue(handle2);
    if (!entry1.context || !entry2.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_StrictEquals(entry1.context, entry1.value, entry2.value));
}

static napi_value LooseEquals(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t handle1 = NValueToHandle(env, args[0]);
    int64_t handle2 = NValueToHandle(env, args[1]);
    ValueEntry entry1 = HandleToValue(handle1);
    ValueEntry entry2 = HandleToValue(handle2);
    if (!entry1.context || !entry2.context) return NAPIBoolean(env, false);

    return NAPIBoolean(env, JS_LooseEquals(entry1.context, entry1.value, entry2.value));
}

static napi_value InstanceOf(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    int64_t constructorHandle = NValueToHandle(env, args[1]);
    ValueEntry valueEntry = HandleToValue(valueHandle);
    ValueEntry ctorEntry = HandleToValue(constructorHandle);
    if (!valueEntry.context || !ctorEntry.context) return NAPIBoolean(env, false);

    int result = JS_IsInstanceOf(valueEntry.context, valueEntry.value, ctorEntry.value);
    return NAPIBoolean(env, result == 1);
}

// ============== Value Lifecycle ==============

static napi_value AddRef(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (entry.context) {
        JS_DupValue(entry.context, entry.value);
    }
    return NAPIUndefined(env);
}

static napi_value Release(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t valueHandle = NValueToHandle(env, args[0]);
    ValueEntry entry = HandleToValue(valueHandle);
    if (entry.context) {
        JS_FreeValue(entry.context, entry.value);
        ValueRegistry::Unregister(valueHandle);
    }
    return NAPIUndefined(env);
}

// ============== Evaluate Script ==============

static napi_value EvaluateScript(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    if (!ctx) return NAPIUndefined(env);

    std::string script = NValueToString(env, args[1]);
    std::string sourceURL;
    if (argc > 2) {
        sourceURL = NValueToString(env, args[2]);
    } else {
        sourceURL = "evaluate";
    }

    JSValue result = JS_Eval(ctx, script.c_str(), script.size(), sourceURL.c_str(), 0);
    return JSValueToHandle(env, result, ctx);
}

struct BoundedExecutionState {
    std::chrono::steady_clock::time_point deadline;
    std::chrono::steady_clock::time_point overallDeadline;
    int32_t* cancelSignal = nullptr;
    bool timedOut = false;
    bool cancelled = false;
    std::chrono::steady_clock::duration hostWait {};
};

static int BoundedInterruptHandler(JSRuntime* runtime, void* opaque) {
    (void)runtime;
    auto* state = static_cast<BoundedExecutionState*>(opaque);
    if (!state) return 0;
    if (state->cancelSignal && __atomic_load_n(state->cancelSignal, __ATOMIC_RELAXED) != 0) {
        state->cancelled = true;
        return 1;
    }
    const auto now = std::chrono::steady_clock::now();
    if (now < state->deadline && now < state->overallDeadline) return 0;
    state->timedOut = true;
    return 1;
}

static std::string QuickJsValueToString(JSContext* ctx, JSValueConst value) {
    const char* raw = JS_ToCString(ctx, value);
    if (!raw) return "";
    std::string result(raw);
    JS_FreeCString(ctx, raw);
    return result;
}

static std::string TakeQuickJsException(JSContext* ctx) {
    JSValue exception = JS_GetException(ctx);
    std::string message = QuickJsValueToString(ctx, exception);
    if (JS_IsObject(exception)) {
        JSValue stack = JS_GetPropertyStr(ctx, exception, "stack");
        if (!JS_IsUndefined(stack) && !JS_IsNull(stack)) {
            std::string stackText = QuickJsValueToString(ctx, stack);
            if (!stackText.empty() && stackText != message) {
                if (!message.empty()) message += "\n";
                message += stackText;
            }
        }
        JS_FreeValue(ctx, stack);
    }
    JS_FreeValue(ctx, exception);
    return message;
}

static constexpr size_t MAX_IMAGE_BYTES = 20 * 1024 * 1024;

static bool ReadNapiBytes(napi_env env, napi_value value, uint8_t*& bytes, size_t& length) {
    napi_typedarray_type type;
    void* data = nullptr;
    napi_value buffer;
    size_t offset = 0;
    if (napi_get_typedarray_info(env, value, &type, &length, &data, &buffer, &offset) != napi_ok ||
        type != napi_uint8_array || length > MAX_IMAGE_BYTES) return false;
    bytes = static_cast<uint8_t*>(data);
    return bytes || length == 0;
}

static napi_value NapiBytes(napi_env env, const uint8_t* bytes, size_t length) {
    void* target = nullptr;
    napi_value buffer = nullptr;
    napi_value result = nullptr;
    if (napi_create_arraybuffer(env, length, &target, &buffer) != napi_ok) return nullptr;
    if (length) memcpy(target, bytes, length);
    if (napi_create_typedarray(env, napi_uint8_array, length, buffer, 0, &result) != napi_ok) return nullptr;
    return result;
}

// Read real ArrayBuffers/views without consulting script-defined properties or iterators.
static bool ReadQuickJsBytes(JSContext* ctx, JSValueConst value, uint8_t*& data, size_t& length) {
    size_t offset = 0;
    size_t elementSize = 0;
    JSValue buffer = JS_GetTypedArrayBuffer(ctx, value, &offset, &length, &elementSize);
    const bool view = !JS_IsException(buffer);
    if (!view) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        buffer = JS_DupValue(ctx, value);
    }
    size_t bufferLength = 0;
    uint8_t* base = JS_GetArrayBuffer(ctx, &bufferLength, buffer);
    JSValue exception = JS_GetException(ctx);
    const bool valid = JS_IsNull(exception) || JS_IsUndefined(exception);
    JS_FreeValue(ctx, exception);
    if (!view) length = bufferLength;
    const bool bounded = valid && (!view || elementSize == 1) && length <= MAX_IMAGE_BYTES &&
        offset <= bufferLength && length <= bufferLength - offset;
    data = bounded && base ? base + offset : nullptr;
    JS_FreeValue(ctx, buffer);
    return bounded && (data || length == 0);
}

struct BoundedImageHost {
    napi_env env;
    napi_value callback;
    BoundedExecutionState* execution;
    size_t calls = 0;
    size_t totalBytes = 0;
    bool exhausted = false;
};

static JSValue CallBoundedImageHost(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
    auto* host = static_cast<BoundedImageHost*>(JS_GetContextOpaque(ctx));
    if (!host || argc != 3 || !JS_IsString(argv[0]) || !JS_IsString(argv[2])) {
        return JS_ThrowTypeError(ctx, "Invalid image operation");
    }
    if (BoundedInterruptHandler(JS_GetRuntime(ctx), host->execution)) {
        return JS_ThrowInternalError(ctx, "Image execution stopped");
    }
    if (host->exhausted || ++host->calls > 32) {
        host->exhausted = true;
        return JS_ThrowRangeError(ctx, "Image host call budget exceeded");
    }
    size_t operationLength = 0, optionsLength = 0;
    const char* rawOperation = JS_ToCStringLen(ctx, &operationLength, argv[0]);
    const char* rawOptions = JS_ToCStringLen(ctx, &optionsLength, argv[2]);
    if (!rawOperation || !rawOptions) {
        if (rawOperation) JS_FreeCString(ctx, rawOperation);
        if (rawOptions) JS_FreeCString(ctx, rawOptions);
        return JS_EXCEPTION;
    }
    const bool bounded = operationLength <= 16 && optionsLength <= 16384;
    const std::string operation = bounded ? std::string(rawOperation, operationLength) : "";
    const std::string options = bounded ? std::string(rawOptions, optionsLength) : "";
    JS_FreeCString(ctx, rawOperation);
    JS_FreeCString(ctx, rawOptions);
    if (!bounded || (operation != "decrypt" && operation != "encrypt" && operation != "hash" && operation != "hmac")) {
        return JS_ThrowTypeError(ctx, "Unsupported image operation");
    }
    uint8_t* input = nullptr;
    size_t inputLength = 0;
    if (!ReadQuickJsBytes(ctx, argv[1], input, inputLength)) return JS_ThrowTypeError(ctx, "Expected bounded image bytes");
    host->totalBytes += inputLength;
    if (host->totalBytes > 128 * 1024 * 1024) {
        host->exhausted = true;
        return JS_ThrowRangeError(ctx, "Image operation byte budget exceeded");
    }
    napi_handle_scope scope;
    if (napi_open_handle_scope(host->env, &scope) != napi_ok) return JS_ThrowOutOfMemory(ctx);
    napi_value args[3] = {NAPIString(host->env, operation), NapiBytes(host->env, input, inputLength), NAPIString(host->env, options)};
    napi_value output = nullptr;
    const auto hostStarted = std::chrono::steady_clock::now();
    napi_status status = args[1] ? napi_call_function(host->env, NAPIUndefined(host->env), host->callback, 3, args, &output) : napi_generic_failure;
    host->execution->deadline += std::chrono::steady_clock::now() - hostStarted;
    JSValue result = JS_UNDEFINED;
    uint8_t* bytes = nullptr;
    size_t length = 0;
    if (status != napi_ok) {
        bool pending = false;
        napi_is_exception_pending(host->env, &pending);
        if (pending) {
            napi_value exception;
            napi_get_and_clear_last_exception(host->env, &exception);
        }
        result = JS_ThrowInternalError(ctx, "Image crypto operation failed");
    } else if (!ReadNapiBytes(host->env, output, bytes, length)) {
        result = JS_ThrowTypeError(ctx, "Invalid image crypto result");
    } else if (BoundedInterruptHandler(JS_GetRuntime(ctx), host->execution)) {
        result = JS_ThrowInternalError(ctx, "Image execution stopped");
    } else {
        host->totalBytes += length;
        if (host->totalBytes > 128 * 1024 * 1024) {
            host->exhausted = true;
            result = JS_ThrowRangeError(ctx, "Image operation byte budget exceeded");
        } else result = JS_NewArrayBufferCopy(ctx, bytes, length);
    }
    napi_close_handle_scope(host->env, scope);
    return result;
}

// A single bounded task retains its stack while the application answers a JSON host call.
// No runtime/session escapes evaluateBounded; the application still owns all capabilities.
struct BoundedScriptHost {
    napi_env env;
    napi_value callback;
    BoundedExecutionState* execution;
    size_t calls = 0;
    size_t totalBytes = 0;
    bool exhausted = false;
};

static JSValue CallBoundedScriptHost(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
    auto* host = static_cast<BoundedScriptHost*>(JS_GetContextOpaque(ctx));
    if (!host || argc != 2 || !JS_IsString(argv[0]) || !JS_IsString(argv[1])) {
        return JS_ThrowTypeError(ctx, "Invalid script host call");
    }
    if (BoundedInterruptHandler(JS_GetRuntime(ctx), host->execution)) {
        return JS_ThrowInternalError(ctx, "Script execution stopped");
    }
    if (host->exhausted || ++host->calls > 4096) {
        host->exhausted = true;
        return JS_ThrowRangeError(ctx, "Script host call budget exceeded");
    }
    size_t nameLength = 0, payloadLength = 0;
    const char* name = JS_ToCStringLen(ctx, &nameLength, argv[0]);
    const char* payload = JS_ToCStringLen(ctx, &payloadLength, argv[1]);
    if (!name || !payload) {
        if (name) JS_FreeCString(ctx, name);
        if (payload) JS_FreeCString(ctx, payload);
        return JS_EXCEPTION;
    }
    host->totalBytes += payloadLength;
    if (nameLength > 128 || payloadLength > 4 * 1024 * 1024 || host->totalBytes > 64 * 1024 * 1024) {
        host->exhausted = true;
        JS_FreeCString(ctx, name);
        JS_FreeCString(ctx, payload);
        return JS_ThrowRangeError(ctx, "Script host input budget exceeded");
    }
    napi_handle_scope scope;
    if (napi_open_handle_scope(host->env, &scope) != napi_ok) {
        JS_FreeCString(ctx, name);
        JS_FreeCString(ctx, payload);
        return JS_ThrowOutOfMemory(ctx);
    }
    napi_value args[2] = {nullptr, nullptr};
    napi_create_string_utf8(host->env, name, nameLength, &args[0]);
    napi_create_string_utf8(host->env, payload, payloadLength, &args[1]);
    JS_FreeCString(ctx, name);
    JS_FreeCString(ctx, payload);
    napi_value output = nullptr;
    const auto hostStarted = std::chrono::steady_clock::now();
    const napi_status status = napi_call_function(host->env, NAPIUndefined(host->env), host->callback, 2, args, &output);
    const auto waited = std::chrono::steady_clock::now() - hostStarted;
    host->execution->deadline += waited;
    host->execution->hostWait += waited;
    JSValue result = JS_UNDEFINED;
    size_t length = 0;
    if (status != napi_ok) {
        bool pending = false;
        napi_is_exception_pending(host->env, &pending);
        if (pending) {
            napi_value exception;
            napi_get_and_clear_last_exception(host->env, &exception);
        }
        result = JS_ThrowInternalError(ctx, "Script host operation stopped");
    } else if (BoundedInterruptHandler(JS_GetRuntime(ctx), host->execution)) {
        result = JS_ThrowInternalError(ctx, "Script execution stopped");
    } else if (napi_get_value_string_utf8(host->env, output, nullptr, 0, &length) != napi_ok ||
        length > 8 * 1024 * 1024 || host->totalBytes + length > 64 * 1024 * 1024) {
        host->exhausted = true;
        result = JS_ThrowRangeError(ctx, "Script host output budget exceeded");
    } else {
        host->totalBytes += length;
        std::vector<char> text(length + 1);
        napi_get_value_string_utf8(host->env, output, text.data(), text.size(), &length);
        result = JS_NewStringLen(ctx, text.data(), length);
    }
    napi_close_handle_scope(host->env, scope);
    return result;
}

static napi_value EvaluateBounded(napi_env env, napi_callback_info info) {
    size_t argc = 9;
    napi_value args[9] = {};
    NAPI_CALL(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));

    const int64_t engineHandle = NValueToHandle(env, args[0]);
    JSContext* ctx = HandleToContext(engineHandle);
    JSRuntime* runtime = EngineRegistry::GetRuntime(engineHandle);
    if (!ctx || !runtime) return NAPIUndefined(env);

    const std::string script = NValueToString(env, args[1]);
    std::string sourceURL = NValueToString(env, args[2]);
    if (sourceURL.empty()) sourceURL = "evaluate";
    const int timeoutMs = static_cast<int>(std::max(1.0,
        std::min(60000.0, NValueToNumber(env, args[3], 100.0))));
    const int maxPendingJobs = static_cast<int>(std::max(0.0,
        std::min(1024.0, NValueToNumber(env, args[4], 8.0))));

    const auto startedAt = std::chrono::steady_clock::now();
    BoundedExecutionState state;
    state.deadline = startedAt + std::chrono::milliseconds(timeoutMs);
    state.overallDeadline = state.deadline;
    napi_valuetype inputType = napi_undefined;
    if (argc > 5) napi_typeof(env, args[5], &inputType);
    const bool binary = inputType != napi_undefined;
    BoundedImageHost host {env, argc > 6 ? args[6] : nullptr, &state};
    napi_valuetype scriptHostType = napi_undefined;
    if (argc > 8) napi_typeof(env, args[8], &scriptHostType);
    const bool scripted = scriptHostType == napi_function;
    BoundedScriptHost scriptHost {env, scripted ? args[8] : nullptr, &state};
    bool prepared = true;
    std::string prepareError = "Invalid bounded execution arguments";
    if (scripted) {
        // The application watchdog enforces active wall time and cancellation, including
        // interrupted HTTP/browser waits. This independent ceiling also bounds manual verification.
        state.overallDeadline = startedAt + std::chrono::minutes(16);
        napi_typedarray_type type = napi_int8_array;
        size_t count = 0, offset = 0;
        void* data = nullptr;
        const napi_status signalStatus = napi_get_typedarray_info(env, args[7], &type, &count, &data, nullptr, &offset);
        prepared = !binary && script.size() <= 12 * 1024 * 1024 &&
            signalStatus == napi_ok &&
            // Some Ark N-API builds report TypedArray byte length (4), others element count (1).
            type == napi_int32_array && (count == 1 || count == sizeof(int32_t)) && data;
        if (!prepared) prepareError += ": signalStatus=" + std::to_string(signalStatus) +
            " type=" + std::to_string(type) + " count=" + std::to_string(count) +
            " binary=" + std::to_string(binary) + " data=" + std::to_string(data != nullptr);
        if (prepared) {
            state.cancelSignal = static_cast<int32_t*>(data);
            JS_SetContextOpaque(ctx, &scriptHost);
            JSValue global = JS_GetGlobalObject(ctx);
            prepared = JS_SetPropertyStr(ctx, global, "__boundedHost",
                JS_NewCFunction(ctx, CallBoundedScriptHost, "boundedHost", 2)) >= 0;
            JS_FreeValue(ctx, global);
        }
    }
    if (binary) {
        state.overallDeadline = startedAt + std::chrono::seconds(10);
        uint8_t* bytes = nullptr;
        size_t length = 0;
        napi_valuetype callbackType = napi_undefined;
        if (host.callback) napi_typeof(env, host.callback, &callbackType);
        prepared = !scripted && script.size() <= 1536 * 1024 && ReadNapiBytes(env, args[5], bytes, length) && length > 0 && callbackType == napi_function;
        napi_valuetype signalType = napi_undefined;
        if (argc > 7) napi_typeof(env, args[7], &signalType);
        if (signalType != napi_undefined) {
            napi_typedarray_type type;
            size_t count = 0, offset = 0;
            void* data = nullptr;
            napi_value buffer;
            if (napi_get_typedarray_info(env, args[7], &type, &count, &data, &buffer, &offset) == napi_ok &&
                type == napi_int32_array && (count == 1 || count == sizeof(int32_t))) state.cancelSignal = static_cast<int32_t*>(data);
            else prepared = false;
        }
        if (prepared) {
            JS_SetContextOpaque(ctx, &host);
            JSValue global = JS_GetGlobalObject(ctx);
            prepared = JS_SetPropertyStr(ctx, global, "__imageInput", JS_NewArrayBufferCopy(ctx, bytes, length)) >= 0 &&
                JS_SetPropertyStr(ctx, global, "__imageHost", JS_NewCFunction(ctx, CallBoundedImageHost, "imageOperation", 3)) >= 0;
            JS_FreeValue(ctx, global);
        }
    }
    JS_SetInterruptHandler(runtime, BoundedInterruptHandler, &state);

    JSValue evaluated = prepared ? JS_Eval(ctx, script.c_str(), script.size(), sourceURL.c_str(), 0) :
        JS_ThrowTypeError(ctx, "%s", prepareError.c_str());
    bool success = !JS_IsException(evaluated);
    std::string value;
    std::string error;
    napi_value binaryResult = nullptr;
    if (!success) {
        error = TakeQuickJsException(ctx);
    }

    int pendingJobs = 0;
    while (success && !state.timedOut && !state.cancelled && pendingJobs < maxPendingJobs) {
        JSContext* jobContext = nullptr;
        const int jobResult = JS_ExecutePendingJob(runtime, &jobContext);
        if (jobResult == 0) break;
        if (jobResult < 0) {
            success = false;
            error = TakeQuickJsException(jobContext ? jobContext : ctx);
            break;
        }
        pendingJobs++;
    }
    // Resolve returned promises within the same interrupt and pending-job budgets.
    if (success && !state.timedOut && !state.cancelled) {
        const int promiseState = JS_PromiseState(ctx, evaluated);
        if (promiseState == JS_PROMISE_PENDING) {
            success = false;
            error = "Script promise did not settle within the pending-job budget";
        } else if (promiseState == JS_PROMISE_REJECTED) {
            JSValue reason = JS_PromiseResult(ctx, evaluated);
            error = QuickJsValueToString(ctx, reason);
            JS_FreeValue(ctx, reason);
            success = false;
        } else {
            JSValue result = promiseState == JS_PROMISE_FULFILLED ? JS_PromiseResult(ctx, evaluated) : JS_DupValue(ctx, evaluated);
            if (binary) {
                uint8_t* bytes = nullptr;
                size_t length = 0;
                if (!ReadQuickJsBytes(ctx, result, bytes, length) || length == 0) {
                    success = false;
                    error = "Image script must return 1 byte to 20 MiB of binary data";
                } else {
                    binaryResult = NapiBytes(env, bytes, length);
                    if (!binaryResult) { success = false; error = "Image output allocation failed"; }
                }
            } else value = QuickJsValueToString(ctx, result);
            JS_FreeValue(ctx, result);
        }
    }
    JS_FreeValue(ctx, evaluated);
    JS_SetInterruptHandler(runtime, nullptr, nullptr);
    JS_SetContextOpaque(ctx, nullptr);
    BoundedInterruptHandler(runtime, &state);
    if (state.cancelled || host.exhausted || scriptHost.exhausted) {
        success = false;
        error = state.cancelled ? "Script execution cancelled" : "Script host budget exceeded";
    }
    if (state.timedOut) {
        success = false;
        if (error.empty()) error = "Script execution timed out";
    }

    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - startedAt - state.hostWait).count();
    napi_value output;
    napi_create_object(env, &output);
    SetNamedProperty(env, output, "success", NAPIBoolean(env, success));
    SetNamedProperty(env, output, "value", NAPIString(env, value));
    SetNamedProperty(env, output, "error", NAPIString(env, error));
    SetNamedProperty(env, output, "timedOut", NAPIBoolean(env, state.timedOut));
    SetNamedProperty(env, output, "elapsedMs", NAPINumber(env, static_cast<double>(elapsed)));
    SetNamedProperty(env, output, "pendingJobs", NAPINumber(env, static_cast<double>(pendingJobs)));
    napi_value resultBytes = success && binaryResult ? binaryResult : NapiBytes(env, nullptr, 0);
    if (!resultBytes) return nullptr;
    SetNamedProperty(env, output, "bytes", resultBytes);
    return output;
}

// ============== NAPI Init ==============

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        // Engine lifecycle
        { "createEngine", nullptr, CreateEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createEngineWithOptions", nullptr, CreateEngineWithOptions, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "releaseEngine", nullptr, ReleaseEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getGlobal", nullptr, GetGlobal, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Value factory
        { "createUndefined", nullptr, CreateUndefined, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createNull", nullptr, CreateNull, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createBoolean", nullptr, CreateBoolean, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createNumber", nullptr, CreateNumber, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createString", nullptr, CreateString, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createObject", nullptr, CreateObject, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createArray", nullptr, CreateArray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createError", nullptr, CreateError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createDate", nullptr, CreateDate, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Type checks
        { "isUndefined", nullptr, IsUndefined, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isNull", nullptr, IsNull, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isBoolean", nullptr, IsBoolean, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isNumber", nullptr, IsNumber, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isString", nullptr, IsString, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isObject", nullptr, IsObject, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isArray", nullptr, IsArray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isDate", nullptr, IsDate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isCallable", nullptr, IsCallable, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isError", nullptr, IsError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isException", nullptr, IsException, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Value conversion
        { "toBooleanValue", nullptr, ToBooleanValue, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "toNumberValue", nullptr, ToNumberValue, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "toStringValue", nullptr, ToStringValue, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Property access
        { "getProperty", nullptr, GetProperty, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setProperty", nullptr, SetProperty, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "hasProperty", nullptr, HasProperty, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deleteProperty", nullptr, DeleteProperty, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getPropertyNames", nullptr, GetPropertyNames, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getElement", nullptr, GetElement, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setElement", nullptr, SetElement, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getArrayLength", nullptr, GetArrayLength, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Function call
        { "callFunction", nullptr, CallFunction, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "construct", nullptr, Construct, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Comparison
        { "strictEquals", nullptr, StrictEquals, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "looseEquals", nullptr, LooseEquals, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "instanceOf", nullptr, InstanceOf, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Value lifecycle
        { "addRef", nullptr, AddRef, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Script evaluation
        { "evaluateScript", nullptr, EvaluateScript, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "evaluateBounded", nullptr, EvaluateBounded, nullptr, nullptr, nullptr, napi_default, nullptr },

        // Error / Exception
        { "getException", nullptr, GetException, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "throwException", nullptr, ThrowException, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "quickjs",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterQuickjsModule(void)
{
    napi_module_register(&demoModule);
}
