#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <hilog/log.h>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
extern "C" {
#include "ijkplayer/ijkplayer_android.h"
int ijk_lab_register_dual(void);
int purapily_prewarm_async(const char *url, const char *agent, const char *referer, const char *cookie, int bytes, int seek_ms);
}

// ff_ffplay_options.h 中 max-fps 的取值上界；121 以下的内核默认值 31 会把
// 60/120fps 源当成「过高帧率」并在软解路径丢弃非参考帧。
#ifndef PURA_MAX_FPS
#define PURA_MAX_FPS 121
#endif

namespace {
struct Event { int what; int first; int second; };

void Deliver(napi_env env, napi_value callback, void *, void *data)
{
    std::unique_ptr<Event> event(static_cast<Event *>(data));
    if (!env || !callback) return;
    napi_value args[3], receiver, ignored;
    napi_get_undefined(env, &receiver);
    napi_create_int32(env, event->what, &args[0]);
    napi_create_int32(env, event->first, &args[1]);
    napi_create_int32(env, event->second, &args[2]);
    napi_call_function(env, receiver, callback, 3, args, &ignored);
}

struct Player {
    std::atomic<int64_t> prepareAt{0};
    IjkMediaPlayer *native = nullptr;
    OHNativeWindow *window = nullptr;
    std::unordered_map<uint64_t, OHNativeWindow *> windows;
    napi_threadsafe_function events = nullptr;

    ~Player()
    {
        if (native) { ijkmp_shutdown(native); ijkmp_dec_ref_p(&native); }
        for (const auto &entry : windows) OH_NativeWindow_DestroyNativeWindow(entry.second);
        if (events) napi_release_threadsafe_function(events, napi_tsfn_abort);
    }

    int bind(uint64_t surface)
    {
        auto found = windows.find(surface);
        OHNativeWindow *next = found == windows.end() ? nullptr : found->second;
        if (!next) {
            int rc = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface, &next);
            if (rc != 0) return rc;
            windows.emplace(surface, next);
        }
        // Hand the window to the pipeline as a real surface: the OH decoder then
        // configures itself with output_to_window and renders decoded frames
        // straight to it (AV_PIX_FMT_OHCODEC). With isSurface=false the pipeline
        // gets NULL, the decoder falls back to NV12 buffers, and every frame is
        // copied through swscale + GLES - which caps 4K at ~40 fps.
        ijkmp_android_set_surface(native, next, true);
        window = next;
        // A previously-current EGLSurface can still reference its native window
        // until the render thread applies this handoff.
        return 0;
    }
};

std::unordered_map<int, std::shared_ptr<Player>> players;
int nextId = 1;
std::once_flag initialized;

void NativeLog(void *, int level, const char *format, va_list args)
{
    if (level > AV_LOG_WARNING) return;
    char line[1024];
    vsnprintf(line, sizeof(line), format, args);
    // Signed media URLs and account headers never enter diagnostics.
    if (strstr(line, "http") || strstr(line, "Cookie") || strstr(line, "cookie")) return;
    OH_LOG_Print(LOG_APP, LOG_WARN, 0, "IjkBackend", "%{public}s", line);
}

int MessageLoop(void *argument)
{
    auto native = static_cast<IjkMediaPlayer *>(argument);
    auto player = static_cast<Player *>(ijkmp_get_weak_thiz(native));
    AVMessage message;
    while (ijkmp_get_msg(native, &message, 1) > 0) {
        if (player && (message.what == FFP_MSG_OPEN_INPUT ||
            message.what == FFP_MSG_FIND_STREAM_INFO || message.what == FFP_MSG_COMPONENT_OPEN ||
            message.what == FFP_MSG_PREPARED || message.what == FFP_MSG_VIDEO_DECODED_START ||
            message.what == FFP_MSG_VIDEO_RENDERING_START)) {
            const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend",
                "startup event=%{public}d elapsed=%{public}lldms", message.what,
                static_cast<long long>(now - player->prepareAt.load()));
        }
        if (player && player->events) {
            auto event = new Event{message.what, message.arg1, message.arg2};
            if (napi_call_threadsafe_function(player->events, event, napi_tsfn_nonblocking) != napi_ok)
                delete event;
        }
        msg_free_res(&message);
    }
    ijkmp_dec_ref_p(&native);
    return 0;
}

std::string String(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return {};
    std::string result(length + 1, '\0');
    napi_get_value_string_utf8(env, value, result.data(), result.size(), &length);
    result.resize(length);
    return result;
}

napi_value Number(napi_env env, double number)
{
    napi_value result;
    napi_create_double(env, number, &result);
    return result;
}

std::shared_ptr<Player> Find(napi_env env, napi_value id)
{
    int key = 0;
    napi_get_value_int32(env, id, &key);
    auto found = players.find(key);
    return found == players.end() ? nullptr : found->second;
}

napi_value Create(napi_env env, napi_callback_info info)
{
    napi_value args[1], name;
    size_t count = 1;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    std::call_once(initialized, [] { ijkmp_global_init(); av_log_set_callback(NativeLog); });
    if (!ijk_lab_register_dual()) return Number(env, 0);
    auto player = std::make_shared<Player>();
    napi_create_string_utf8(env, "IjkPlaybackEvents", NAPI_AUTO_LENGTH, &name);
    if (napi_create_threadsafe_function(env, args[0], nullptr, name, 0, 1,
        nullptr, nullptr, nullptr, Deliver, &player->events) != napi_ok) return Number(env, 0);
    player->native = ijkmp_android_create(MessageLoop);
    if (!player->native) return Number(env, 0);
    ijkmp_set_weak_thiz(player->native, player.get());
    ijkmp_set_option(player->native, 4, "iformat", "puradual");
    // puradual fully probes both child inputs before publishing their streams.
    // Probing the combined input again reads/decodes media before the real
    // decoders can start. Keep child probing, skip only this redundant pass.
    ijkmp_set_option_int(player->native, 4, "find_stream_info", 0);
    ijkmp_set_option(player->native, 4, "mediacodec-all-videos", "1");
    ijkmp_set_option(player->native, 4, "enable-accurate-seek", "1");
    ijkmp_set_option(player->native, 4, "start-on-prepared", "0");
    // 15MiB 是高码率安全上限，不能以缩小共享队列来省流。
    ijkmp_set_option_int(player->native, 4, "max-buffer-size", PURA_PROBE_QUEUE_MIB * 1024 * 1024);
    // 默认 50000 包几乎只会触发字节上限。两轨各有 200 个包时即可暂停预取：
    // 常见 24~60fps / AAC 来源约有 4~8 秒余量，低码率也不必预读满 15MiB。
    ijkmp_set_option_int(player->native, 4, "min-frames", 200);
    // 视频渲染落后时必须丢弃过期帧，否则视频积压会再次挤停两轨取包、拖住音频。
    ijkmp_set_option_int(player->native, 4, "framedrop", PURA_PROBE_FRAMEDROP);
    // 内核默认 max-fps=31：高于 31fps 的源会被标记 is_video_high_fps，进而给软解
    // 打开 skip_frame/skip_loop_filter/skip_idct（非参考帧直接丢）。60/120fps 源在
    // 软解回退时因此掉帧，这里放宽到选项表上限，只在真正异常的 >121fps 时才降级。
    ijkmp_set_option_int(player->native, 4, "max-fps", PURA_MAX_FPS);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend",
        "playback config queue_mib=%{public}d framedrop=%{public}d max_fps=%{public}d min_packets=200",
        PURA_PROBE_QUEUE_MIB, PURA_PROBE_FRAMEDROP, PURA_MAX_FPS);
    int id = nextId++;
    std::string identity = "purapily-" + std::to_string(id);
    ijkmp_set_id(player->native, identity.data());
    players.emplace(id, player);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "created id=%{public}d", id);
    return Number(env, id);
}

napi_value Prepare(napi_env env, napi_callback_info info)
{
    napi_value args[4];
    size_t count = 4;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    auto player = Find(env, args[0]);
    if (!player) return Number(env, -1);
    player->prepareAt.store(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
    uint64_t surface = 0;
    try { surface = std::stoull(String(env, args[2])); } catch (...) { return Number(env, -1); }
    int rc = player->bind(surface);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "prepare surface=%{public}llu bind=%{public}d", static_cast<unsigned long long>(surface), rc);
    if (rc) return Number(env, rc);
    double position = 0;
    napi_get_value_double(env, args[3], &position);
#if defined(PURA_PROBE_START_MS) && PURA_PROBE_START_MS >= 0
    position = PURA_PROBE_START_MS;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "diagnostic fixed_start=%{public}.0f", position);
#endif
    ijkmp_set_option_int(player->native, 4, "seek-at-start", static_cast<int64_t>(position));
    auto path = String(env, args[1]);
    rc = ijkmp_set_data_source(player->native, path.c_str());
    if (!rc) rc = ijkmp_prepare_async(player->native);
    return Number(env, rc);
}

napi_value Control(napi_env env, napi_callback_info info)
{
    napi_value args[3];
    size_t count = 3;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    auto player = Find(env, args[0]);
    if (!player) return Number(env, -1);
    int operation = 0;
    double value = 0;
    napi_get_value_int32(env, args[1], &operation);
    napi_get_value_double(env, args[2], &value);
    if (operation >= 1 && operation <= 4)
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "control op=%{public}d value=%{public}.0f", operation, value);
    switch (operation) {
        case 1: return Number(env, ijkmp_start(player->native));
        case 2: return Number(env, ijkmp_pause(player->native));
        case 3: return Number(env, ijkmp_seek_to(player->native, static_cast<long>(value)));
        case 4: ijkmp_set_playback_rate(player->native, value); break;
        case 5: ijkmp_android_set_volume(player->native, value, value); break;
        case 6: return Number(env, ijkmp_get_current_position(player->native));
        case 7: return Number(env, ijkmp_get_duration(player->native));
        case 8: return Number(env, ijkmp_get_property_float(player->native, FFP_PROP_FLOAT_VIDEO_OUTPUT_FRAMES_PER_SECOND, 0));
        case 13: return Number(env, ijkmp_get_property_float(player->native, FFP_PROP_FLOAT_VIDEO_DECODE_FRAMES_PER_SECOND, 0));
        case 14: return Number(env, ijkmp_get_property_float(player->native, FFP_PROP_FLOAT_DROP_FRAME_RATE, 0));
        case 9: return Number(env, ijkmp_get_property_float(player->native, FFP_PROP_FLOAT_AVDIFF, 0));
        case 10: return Number(env, ijkmp_get_property_int64(player->native, FFP_PROP_INT64_AUDIO_CACHED_DURATION, 0));
        case 11: return Number(env, ijkmp_get_property_int64(player->native, FFP_PROP_INT64_VIDEO_CACHED_DURATION, 0));
        default: return Number(env, -1);
    }
    return Number(env, 0);
}

napi_value Bind(napi_env env, napi_callback_info info)
{
    napi_value args[2];
    size_t count = 2;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    auto player = Find(env, args[0]);
    if (!player) return Number(env, -1);
    try {
        auto surface = std::stoull(String(env, args[1]));
        int rc = player->bind(surface);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "handoff surface=%{public}llu rc=%{public}d", surface, rc);
        return Number(env, rc);
    }
    catch (...) { return Number(env, -1); }
}

// 列表/点击阶段预建连接：异步执行，命中与否都不影响 JS 线程。
napi_value Prewarm(napi_env env, napi_callback_info info)
{
    napi_value args[6];
    size_t count = 6;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    if (count < 1) return Number(env, 0);
    auto url = String(env, args[0]);
    auto agent = count > 1 ? String(env, args[1]) : std::string();
    auto referer = count > 2 ? String(env, args[2]) : std::string();
    auto cookie = count > 3 ? String(env, args[3]) : std::string();
    int bytes=65536;
    if(count>4) napi_get_value_int32(env,args[4],&bytes);
    // 续播起点（毫秒）：>0 时前缀会跳过中间数据，直接覆盖该时间点所在的分片。
    int seekMs=0;
    if(count>5) napi_get_value_int32(env,args[5],&seekMs);
    return Number(env, purapily_prewarm_async(url.c_str(), agent.c_str(), referer.c_str(), cookie.c_str(),bytes,seekMs));
}

struct ReleaseWork {
    std::shared_ptr<Player> player;
    napi_deferred completion;
    napi_async_work work;
};

napi_value Release(napi_env env, napi_callback_info info)
{
    napi_value args[1], promise, name;
    size_t count = 1;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    int id = 0;
    napi_get_value_int32(env, args[0], &id);
    auto work = new ReleaseWork();
    napi_create_promise(env, &work->completion, &promise);
    auto found = players.find(id);
    if (found == players.end()) {
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        napi_resolve_deferred(env, work->completion, undefined);
        delete work;
        return promise;
    }
    work->player = found->second;
    players.erase(found);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "IjkBackend", "released id=%{public}d", id);
    // The channel stays alive until shutdown has joined the message thread.
    // JS generation guards discard callbacks while this release is pending.
    napi_create_string_utf8(env, "IjkRelease", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name,
        [](napi_env, void *data) { static_cast<ReleaseWork *>(data)->player.reset(); },
        [](napi_env env, napi_status, void *data) {
            auto work = static_cast<ReleaseWork *>(data);
            napi_value undefined;
            napi_get_undefined(env, &undefined);
            napi_resolve_deferred(env, work->completion, undefined);
            napi_delete_async_work(env, work->work);
            delete work;
        }, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}
}

extern "C" void register_player_backend(napi_env env, napi_value exports)
{
    napi_property_descriptor methods[] = {
        {"createPlayer", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"preparePlayer", nullptr, Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"controlPlayer", nullptr, Control, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"bindPlayer", nullptr, Bind, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releasePlayer", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prewarmUrl", nullptr, Prewarm, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(methods) / sizeof(methods[0]), methods);
}
