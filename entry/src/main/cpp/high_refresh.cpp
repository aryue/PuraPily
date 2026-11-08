#include <napi/native_api.h>
#include <native_vsync/native_vsync.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <hilog/log.h>
#include <cstdint>
#include <mutex>

namespace {
std::mutex mutex;
OH_NativeVSync* vsync = nullptr;
uintptr_t generation = 0;
uint64_t frames = 0;

void OnFrame(long long, void* token)
{
    std::lock_guard<std::mutex> lock(mutex);
    // A callback already dispatched before Stop must never rearm a new session.
    if (!vsync || reinterpret_cast<uintptr_t>(token) != generation) return;
    if (++frames == 1) {
        long long period = 0;
        OH_NativeVSync_GetPeriod(vsync, &period);
        OH_LOG_INFO(LOG_APP, "HighRefresh first callback, period=%{public}lld ns", period);
    }
    const int result = OH_NativeVSync_RequestFrame(vsync, OnFrame, token);
    if (result != 0) {
        OH_NativeVSync_ExpectedRateRange range {0, 0, 0};
        OH_NativeVSync_SetExpectedFrameRateRange(vsync, &range);
        OH_LOG_ERROR(LOG_APP, "HighRefresh rearm failed: %{public}d", result);
    }
}

void Stop(void* = nullptr)
{
    OH_NativeVSync* old = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex);
        ++generation;
        old = vsync;
        vsync = nullptr;
        if (old) {
            OH_NativeVSync_ExpectedRateRange range {0, 0, 0};
            OH_NativeVSync_SetExpectedFrameRateRange(old, &range);
            OH_LOG_INFO(LOG_APP, "HighRefresh stopped, callbacks=%{public}llu",
                static_cast<unsigned long long>(frames));
        }
    }
    // Destroy outside the lock: an in-flight callback may be waiting for it.
    if (old) OH_NativeVSync_Destroy(old);
}

napi_value SetRate(napi_env env, napi_callback_info info)
{
    napi_value arg = nullptr;
    size_t argc = 1;
    int32_t rate = -1;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1 || napi_get_value_int32(env, arg, &rate) != napi_ok ||
        (rate != 0 && rate != 90 && rate != 120 && rate != 144)) {
        napi_throw_range_error(env, nullptr, "Expected 0, 90, 120 or 144 Hz");
        return nullptr;
    }
    Stop();
    int result = 0;
    if (rate != 0) {
        std::lock_guard<std::mutex> lock(mutex);
        constexpr char name[] = "PuraPilyHighRefresh";
        vsync = OH_NativeVSync_Create(name, sizeof(name) - 1);
        result = vsync ? 0 : -1;
        if (vsync) {
            OH_NativeVSync_ExpectedRateRange range {rate, rate, rate};
            result = OH_NativeVSync_SetExpectedFrameRateRange(vsync, &range);
            frames = 0;
            if (result == 0) {
                result = OH_NativeVSync_RequestFrame(vsync, OnFrame, reinterpret_cast<void*>(generation));
            }
        }
        OH_LOG_INFO(LOG_APP, "HighRefresh request=%{public}d Hz, result=%{public}d", rate, result);
    }
    if (result != 0) Stop();
    napi_value value = nullptr;
    napi_create_int32(env, result, &value);
    return value;
}

// Query codec availability before replacing a working AVPlayer (notably on emulators).
napi_value HasVideoDecoder(napi_env env, napi_callback_info info)
{
    napi_value arg = nullptr;
    size_t argc = 1, length = 0;
    char mime[64] = {};
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1 || napi_get_value_string_utf8(env, arg, mime, sizeof(mime), &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a video MIME type");
        return nullptr;
    }
    const bool supported = OH_AVCodec_GetCapability(mime, false) != nullptr;
    napi_value value = nullptr;
    napi_get_boolean(env, supported, &value);
    return value;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"setRate", nullptr, SetRate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hasVideoDecoder", nullptr, HasVideoDecoder, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    napi_add_env_cleanup_hook(env, Stop, nullptr);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "high_refresh", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterHighRefresh()
{
    napi_module_register(&module);
}
