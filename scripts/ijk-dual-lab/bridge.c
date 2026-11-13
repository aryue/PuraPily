#include <napi/native_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int ijk_lab_register_dual(void);
void purapily_cache_set_dir(const char *dir);
void purapily_cache_set_startup_backup_delay(int delay_ms);
int purapily_prefetch_head_async(const char *dir, const char *url, const char *agent,
                                 const char *referer, const char *cookie);
void register_player_backend(napi_env env, napi_value exports);

static int read_string(napi_env env, napi_value value, char *buffer, size_t capacity)
{
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, NULL, 0, &size) != napi_ok ||
        size == 0 || size >= capacity) return 0;
    return napi_get_value_string_utf8(env, value, buffer, capacity, &size) == napi_ok;
}

static napi_value source(napi_env env, napi_callback_info info)
{
    napi_value args[12], result;
    size_t argc = 12;
    char directory[512], video[16384], audio[16384], path[600];
    char videoBackup[16384] = "", audioBackup[16384] = "";
    char agent[4096] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";
    char referer[4096] = "https://www.bilibili.com/";
    char cookie[16384] = "";
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    napi_create_string_utf8(env, "", 0, &result);
    if (argc < 3 || !read_string(env, args[0], directory, sizeof(directory)) ||
        !read_string(env, args[1], video, sizeof(video)) ||
        !read_string(env, args[2], audio, sizeof(audio))) return result;
    char *headers[] = {agent, referer, cookie};
    size_t capacities[] = {sizeof(agent), sizeof(referer), sizeof(cookie)};
    // 只处理 agent/referer/cookie 三个字符串可选参数；第 7 个（cacheOn）是数字，
    // 不能被这个循环当字符串读，否则 napi_get_value_string_utf8 失败会让 source() 返回空。
    for (size_t i = 3; i < argc && i < 6; i++) {
        size_t size = 0;
        if (napi_get_value_string_utf8(env, args[i], NULL, 0, &size) != napi_ok ||
            size >= capacities[i - 3]) return result;
        if (size == 0) headers[i - 3][0] = 0;
        else if (!read_string(env, args[i], headers[i - 3], capacities[i - 3])) return result;
        if (strpbrk(headers[i - 3], "\r\n")) return result;
    }
    int cacheOn = 0;
    if (argc >= 7) napi_get_value_int32(env, args[6], &cacheOn);
    // 第 8、9 个参数：base_url 之外的备用源（可为空），随 descriptor 带进 native。
    size_t bsize = 0;
    if (argc >= 8 && napi_get_value_string_utf8(env, args[7], NULL, 0, &bsize) == napi_ok &&
        bsize > 0 && bsize < sizeof(videoBackup))
        read_string(env, args[7], videoBackup, sizeof(videoBackup));
    if (argc >= 9 && napi_get_value_string_utf8(env, args[8], NULL, 0, &bsize) == napi_ok &&
        bsize > 0 && bsize < sizeof(audioBackup))
        read_string(env, args[8], audioBackup, sizeof(audioBackup));
    if (strpbrk(videoBackup, "\r\n") || strpbrk(audioBackup, "\r\n")) return result;
    int64_t videoBps = 0, audioBps = 0;
    if (argc >= 10) napi_get_value_int64(env, args[9], &videoBps);
    if (argc >= 11) napi_get_value_int64(env, args[10], &audioBps);
    int32_t backupDelayMs = 350;
    if (argc >= 12) napi_get_value_int32(env, args[11], &backupDelayMs);
    purapily_cache_set_startup_backup_delay(backupDelayMs);
    // 稀疏分段缓存（64KB 块 + 段表）：默认开启，--ps diskCache off 关闭做 A/B。
    // 连续前缀版的「带续播点重开 prepared→frame +1.1s」回归已由稀疏分块消除。
    purapily_cache_set_dir(cacheOn ? directory : NULL);
    if (strncmp(video, "https://", 8) || strncmp(audio, "https://", 8) ||
        strpbrk(video, "\r\n") || strpbrk(audio, "\r\n") ||
        !ijk_lab_register_dual()) return result;
    snprintf(path, sizeof(path), "%s/puradual-XXXXXX", directory);
    int fd = mkstemp(path);
    if (fd < 0) return result;
    FILE *file = fdopen(fd, "wb");
    if (!file) { close(fd); unlink(path); return result; }
    int written = fprintf(file, "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%lld\n%lld\n",
                          video, audio, agent, referer, cookie, videoBackup, audioBackup,
                          (long long)videoBps, (long long)audioBps);
    int closed = fclose(file);
    if (written < 0 || closed != 0) { unlink(path); return result; }
    napi_create_string_utf8(env, path, NAPI_AUTO_LENGTH, &result);
    return result;
}

// 点击瞬间下发首帧区间任务：与页面转场并行，不占起播关键路径。
// 对齐官方 navigateRoute.PUSH 后 2ms 内的 addTask/assignRangeTask(firstRender)。
static napi_value prefetchFirstRender(napi_env env, napi_callback_info info)
{
    napi_value args[6], result;
    size_t argc = 6;
    char directory[512], video[16384], audio[16384];
    char agent[4096] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";
    char referer[4096] = "https://www.bilibili.com/";
    char cookie[16384] = "";
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    napi_create_int32(env, 0, &result);
    if (argc < 3 || !read_string(env, args[0], directory, sizeof(directory)) ||
        !read_string(env, args[1], video, sizeof(video)) ||
        !read_string(env, args[2], audio, sizeof(audio))) return result;
    char *headers[] = {agent, referer, cookie};
    size_t capacities[] = {sizeof(agent), sizeof(referer), sizeof(cookie)};
    for (size_t i = 3; i < argc && i < 6; i++) {
        size_t size = 0;
        if (napi_get_value_string_utf8(env, args[i], NULL, 0, &size) != napi_ok ||
            size >= capacities[i - 3]) return result;
        if (size == 0) headers[i - 3][0] = 0;
        else if (!read_string(env, args[i], headers[i - 3], capacities[i - 3])) return result;
        if (strpbrk(headers[i - 3], "\r\n")) return result;
    }
    if (strncmp(video, "https://", 8) || strncmp(audio, "https://", 8) ||
        strpbrk(video, "\r\n") || strpbrk(audio, "\r\n")) return result;
    int launched = purapily_prefetch_head_async(directory, video, agent, referer, cookie) +
                   purapily_prefetch_head_async(directory, audio, agent, referer, cookie);
    napi_create_int32(env, launched, &result);
    return result;
}

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"source", NULL, source, NULL, NULL, NULL, napi_default, NULL},
        {"prefetchFirstRender", NULL, prefetchFirstRender, NULL, NULL, NULL, napi_default, NULL},
    };
    napi_define_properties(env, exports, 2, descriptors);
    register_player_backend(env, exports);
    return exports;
}

#ifndef IJK_NATIVE_MODULE
#define IJK_NATIVE_MODULE "probe"
#endif
static napi_module module = {1, 0, NULL, Init, IJK_NATIVE_MODULE, NULL, {0}};
__attribute__((constructor)) static void register_module(void)
{
    napi_module_register(&module);
}
