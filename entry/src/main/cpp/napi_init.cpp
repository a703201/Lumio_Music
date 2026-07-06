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

static napi_value NativeParseAudioMetadata(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char filePath[1024];
    size_t filePathLen;
    napi_get_value_string_utf8(env, args[0], filePath, sizeof(filePath), &filePathLen);

    AudioMetadata metadata = parseAudioMetadata(std::string(filePath, filePathLen));

    napi_value result;
    napi_create_object(env, &result);

    napi_value title;
    napi_create_string_utf8(env, metadata.title.c_str(), metadata.title.length(), &title);
    napi_set_named_property(env, result, "title", title);

    napi_value artist;
    napi_create_string_utf8(env, metadata.artist.c_str(), metadata.artist.length(), &artist);
    napi_set_named_property(env, result, "artist", artist);

    napi_value album;
    napi_create_string_utf8(env, metadata.album.c_str(), metadata.album.length(), &album);
    napi_set_named_property(env, result, "album", album);

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
