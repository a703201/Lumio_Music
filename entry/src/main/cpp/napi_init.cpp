#include <napi/native_api.h>
#include <hilog/log.h>
#include <string>
#include "audio_metadata.h"

#undef LOG_TAG
#define LOG_TAG "NativeModule"

static napi_value NativeAdd(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double a, b;
    napi_get_value_double(env, args[0], &a);
    napi_get_value_double(env, args[1], &b);

    double result = a + b;
    napi_value ret;
    napi_create_double(env, result, &ret);

    return ret;
}

// 安全构造 UTF-8 字符串：非法 UTF-8 时回退空串，避免 napi_value 保持未初始化被后续使用（P1-6 联动）
static napi_value MakeString(napi_env env, const std::string& s) {
    napi_value v;
    if (napi_create_string_utf8(env, s.c_str(), s.length(), &v) != napi_ok) {
        napi_create_string_utf8(env, "", 0, &v);
    }
    return v;
}

static napi_value NativeParseAudioMetadata(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value undefinedVal = nullptr;
    napi_get_undefined(env, &undefinedVal);
    // P0-6：调用方漏传参数（argc == 0）时 args[0] 未初始化，直接返回 undefined
    if (argc < 1 || args[0] == nullptr) {
        return undefinedVal;
    }

    char filePath[1024] = { 0 };
    size_t filePathLen = 0; // P0-6：显式初始化，杜绝栈上垃圾值作长度
    if (napi_get_value_string_utf8(env, args[0], filePath, sizeof(filePath), &filePathLen) != napi_ok) {
        return undefinedVal;
    }

    AudioMetadata metadata = parseAudioMetadata(std::string(filePath, filePathLen));

    napi_value result;
    napi_create_object(env, &result);

    napi_set_named_property(env, result, "title", MakeString(env, metadata.title));
    napi_set_named_property(env, result, "artist", MakeString(env, metadata.artist));
    napi_set_named_property(env, result, "album", MakeString(env, metadata.album));

    napi_value duration;
    napi_create_int32(env, metadata.durationMs, &duration);
    napi_set_named_property(env, result, "duration", duration);

    napi_value sampleRate;
    napi_create_int32(env, metadata.sampleRate, &sampleRate);
    napi_set_named_property(env, result, "sampleRate", sampleRate);

    napi_value channels;
    napi_create_int32(env, metadata.channels, &channels);
    napi_set_named_property(env, result, "channels", channels);

    return result;
}

static napi_value NativeGetDeviceInfo(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);

    napi_value brand;
    napi_create_string_utf8(env, "HarmonyOS", NAPI_AUTO_LENGTH, &brand);
    napi_set_named_property(env, result, "brand", brand);

    napi_value osType;
    napi_create_string_utf8(env, "HarmonyOS", NAPI_AUTO_LENGTH, &osType);
    napi_set_named_property(env, result, "osType", osType);

    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "add", nullptr, NativeAdd, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "parseAudioMetadata", nullptr, NativeParseAudioMetadata, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getDeviceInfo", nullptr, NativeGetDeviceInfo, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_START
static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "native_module",
    .nm_priv = (void *)0,
    .reserved = { 0 }
};

__attribute__((constructor)) void RegisterModule(void) {
    napi_module_register(&g_module);
}
EXTERN_C_END
