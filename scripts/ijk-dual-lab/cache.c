// 本地预载缓存（AVIO 层，稀疏分段版）：
//   把流按 64KB 块缓存；每块单独标记「已落盘的有效字节数」，存进 .idx 段表。
//   任意 seek 位置只要落在已缓存块里就直接读盘，缺块才按该块的 Range 回源。
//   这是为了解决连续前缀版的回归：续播点/索引 seek 越过前缀就要回源，反而更慢。
//
// 为什么在 AVIO 层做：puradual 是自定义 demuxer，音视频各一条 AVIOContext，
// 在这里拦截既能复用 ffmpeg 的 Range/重连逻辑，又不用碰 IJK 的播放路径。
//
// 缓存身份使用完整媒体路径，忽略 CDN 域名和临时签名；同名不同编码目录不能混用。
#include <libavformat/avio.h>
#include <libavutil/dict.h>
#include <libavutil/time.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <libavutil/crc.h>
#include <errno.h>
#include <hilog/log.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <dirent.h>
#include <unistd.h>

#define CACHE_IO_BUF (32 * 1024)
#define CACHE_BLOCK (64 * 1024)                 // 与官方 sub-segment 同量级
#define CACHE_DIR_MAX 512
#define CACHE_KEY_MAX 96
// 单条流只缓存「前 32MB」。4K 一条流能写到上百 MB，按 128MB 上限时三四条就
// 把目录撑满，淘汰时整条流连首段一起删掉 —— 首帧最需要的那几 MB 反而保不住。
// 超过这个范围的块走 read_uncached_direct 回源（播放期回源不受预算限制），
// 相当于用「尾部不缓存」换「更多视频的首段常驻」。
#define CACHE_FILE_MAX (32LL * 1024 * 1024)
#define CACHE_MAX_BLOCKS (int)(CACHE_FILE_MAX / CACHE_BLOCK)
#define CACHE_TOTAL_MAX (384LL * 1024 * 1024)  // 目录上限 384MB
#define CACHE_EVICT_AT (300LL * 1024 * 1024)   // 超过 300MB 开始清理
#define IDX_MAGIC "PDC4"

extern void *purapily_prefix_take(const char *,const char *,const char *,const char *);
extern int64_t purapily_prefix_size(void *,const AVIOInterruptCB *);
extern int purapily_prefix_read(void *,int64_t,uint8_t *,int,const AVIOInterruptCB *);
extern AVIOContext *purapily_prefix_adopt(void *,int64_t,int64_t *);
extern void purapily_prefix_discard(void *);

typedef struct {
    int fd;
    int idx_fd;
    int64_t pos;                 // 逻辑读位置
    int64_t total;              // 流总长（-1 未知）
    uint32_t *lens;             // 每块已落盘的有效字节数，0 = 缺块
    uint32_t *checksums;        // 整块 CRC；未校验的数据不能交给 demuxer
    uint8_t *block_buf;
    char bin_path[CACHE_DIR_MAX + 256];
    char idx_path[CACHE_DIR_MAX + 256];
    int nblocks;                // 当前已分配的块表长度
    int dirty;                  // 段表是否需要写回
    int dirty_blocks;           // 距上次落盘新增的块数
    int64_t last_save;          // 上次段表落盘时间（微秒）
    void *prefix;
    AVIOContext *net;
    int64_t net_end;             // 本条连接可服务到的逻辑末尾（total 或 INT64_MAX）
    int64_t network_bytes;
    int64_t network_logged_at, network_logged_bytes, network_read_max_us;
    int64_t expected_bps, sample_bytes, sample_read_us;
    int slow_source;
    int64_t net_pos;
    int net_fresh;               // 刚从预热接管、还没成功读过：首次读到 0 要重开一次
    int short_block;             // 正在修复的短块索引（-1 无）
    int short_retries;           // 该短块连续修复次数，封顶 2 次避免反复回源
    char *url;                  // 当前生效的源（base 或 failover 后的 backup）
    char *backup_url;           // 备用源，可为空
    int using_backup;           // 只切一次，避免来回抖动
    char *agent;
    char *referer;
    char *cookie;
    AVIOInterruptCB ic;
} CacheCtx;

// 建连失败、持续供给不足或已建立连接读失败时均可按字节位置恢复。

static char g_dir[CACHE_DIR_MAX];
static int64_t g_evicted_at;
static void copy_str(char **dst, const char *src)
{
    if (!src) src = "";
    size_t n = strlen(src) + 1;
    *dst = (char *)av_malloc(n);
    if (*dst) memcpy(*dst, src, n);
}

static uint32_t block_checksum(const uint8_t *data, size_t size)
{
    return av_crc(av_crc_get_table(AV_CRC_32_IEEE), 0, data, size);
}

// B站同一个文件末段名可以出现在不同转码路径下。CDN/签名变化仍复用同一路径。
// 其它站点保留域名，避免跨站同路径共用缓存。拒绝截断身份。
static uint64_t resource_hash(const char *url)
{
    const char *start = strstr(url, "://");
    start = start ? start + 3 : url;
    const char *path = strchr(start, '/');
    if (path && !strncmp(path, "/upgcxcode/", 11)) start = path;
    uint64_t hash = 1469598103934665603ULL;
    for (const char *p = start; *p && *p != '?' && *p != '#'; p++) {
        hash ^= (unsigned char)*p;
        hash *= 1099511628211ULL;
    }
    return hash;
}

// URL -> 稳定的资源名：取路径最后一段，去掉 query。
static void key_from_url(const char *url, char *out, size_t capacity)
{
    const char *start = strstr(url, "://");
    start = start ? start + 3 : url;
    const char *path = strchr(start, '/');
    const char *name = path ? path + 1 : start;
    const char *slash = name;
    for (const char *p = name; *p && *p != '?'; p++) {
        if (*p == '/') slash = p + 1;
    }
    size_t len = 0;
    while (slash[len] && slash[len] != '?' && len + 1 < capacity) len++;
    memcpy(out, slash, len);
    out[len] = 0;
    if (len == 0) snprintf(out, capacity, "stream");
}

static void cache_paths(const char *url, char *bin, char *idx, size_t capacity)
{
    char key[CACHE_KEY_MAX];
    key_from_url(url, key, sizeof(key));
    snprintf(bin, capacity, "%s/%016llx-%s.bin", g_dir,
             (unsigned long long)resource_hash(url), key);
    snprintf(idx, capacity, "%s/%016llx-%s.idx", g_dir,
             (unsigned long long)resource_hash(url), key);
}

// 目录超限时按 mtime 从旧到新删（.bin 与 .idx 成对删），直到降到 80%。
static void evict_if_needed(void)
{
    int64_t now = av_gettime_relative() / 1000000;
    if (now - g_evicted_at < 60) return;
    g_evicted_at = now;
    DIR *dir = opendir(g_dir);
    if (!dir) return;
    int64_t total = 0;
    struct Entry { char name[192]; int64_t size; int64_t mtime; } *items = NULL;
    size_t count = 0, capacity = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        size_t len = strlen(ent->d_name);
        if (len < 5 || (strcmp(ent->d_name + len - 4, ".bin") != 0 &&
                        strcmp(ent->d_name + len - 4, ".idx") != 0)) continue;
        char full[CACHE_DIR_MAX + 200];
        snprintf(full, sizeof(full), "%s/%s", g_dir, ent->d_name);
        struct stat st;
        if (stat(full, &st) != 0) continue;
        total += st.st_size;
        if (count == capacity) {
            capacity = capacity ? capacity * 2 : 64;
            items = (struct Entry *)realloc(items, capacity * sizeof(*items));
            if (!items) break;
        }
        snprintf(items[count].name, sizeof(items[count].name), "%s", ent->d_name);
        items[count].size = st.st_size;
        items[count].mtime = st.st_mtime;
        count++;
    }
    closedir(dir);
    if (total > CACHE_EVICT_AT && items) {
        // 目标必须明显低于触发线：原来取 CACHE_TOTAL_MAX*0.8=307MB > 触发线 300MB，
        // 于是刚超限的 305MB 一次都不删，目录长期贴在 350MB 上下反复触发 evict。
        int64_t target = CACHE_EVICT_AT * 8 / 10;
        for (size_t i = 0; i < count && total > target; i++) {
            // 优先淘汰大文件（旧版 128MB 流、4K 尾部数据），小块的预热/首段尽量留着；
            // 大小相近时再按 mtime 取最旧。.bin 被删时会连同 .idx 一起删。
            size_t victim = i;
            for (size_t j = i + 1; j < count; j++) {
                int64_t dj = items[j].size, dv = items[victim].size;
                if (dj > dv + CACHE_BLOCK ||
                    (dj + CACHE_BLOCK >= dv && items[j].mtime < items[victim].mtime)) victim = j;
            }
            struct Entry tmp = items[i]; items[i] = items[victim]; items[victim] = tmp;
            char full[CACHE_DIR_MAX + 200];
            snprintf(full, sizeof(full), "%s/%s", g_dir, items[i].name);
            // 预热/播放实例可能仍在读写。活动文件不能被淘汰，否则另一个实例
            // 会创建同名新文件，旧实例再发布索引便会把两代数据混在一起。
            char data_path[CACHE_DIR_MAX + 200];
            snprintf(data_path, sizeof(data_path), "%s", full);
            strcpy(strrchr(data_path, '.'), ".bin");
            int active = open(data_path, O_RDWR);
            if (active < 0) continue;
            if (flock(active, LOCK_EX | LOCK_NB) != 0) { close(active); continue; }
            if (unlink(full) == 0) {
                total -= items[i].size;
                char *dot = strrchr(full, '.');
                if (dot) {
                    const char *other = strcmp(dot, ".bin") == 0 ? ".idx" : ".bin";
                    strcpy(dot, other);
                    struct stat sst;
                    if (stat(full, &sst) == 0 && unlink(full) == 0) total -= sst.st_size;
                }
            }
            close(active);
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache", "evicted to %{public}lldMB",
                     (long long)(total / (1024 * 1024)));
    }
    free(items);
}

void purapily_cache_set_dir(const char *dir)
{
    if (!dir || !dir[0]) { g_dir[0] = 0; return; }
    snprintf(g_dir, sizeof(g_dir), "%s/puradual-cache", dir);
    mkdir(g_dir, 0700);
    g_evicted_at = 0;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache", "dir %{public}s", g_dir);
}

// 段表：magic + total + nblocks + lens[]。版本不匹配就当空表，避免与旧版连续前缀文件混用。
static void load_index(CacheCtx *ctx)
{
    if (ctx->idx_fd < 0) return;
    uint8_t head[20];
    if (pread(ctx->idx_fd, head, sizeof(head), 0) != sizeof(head)) return;
    if (memcmp(head, IDX_MAGIC, 4) != 0) return;
    int64_t total, n;
    memcpy(&total, head + 4, 8);
    memcpy(&n, head + 12, 8);
    if (n <= 0 || n > CACHE_MAX_BLOCKS) return;
    uint32_t *lens = (uint32_t *)av_mallocz((size_t)n * sizeof(uint32_t));
    uint32_t *checksums = (uint32_t *)av_mallocz((size_t)n * sizeof(uint32_t));
    if (!lens || !checksums) { av_free(lens); av_free(checksums); return; }
    if (pread(ctx->idx_fd, lens, (size_t)n * sizeof(uint32_t), sizeof(head)) !=
        (ssize_t)(n * sizeof(uint32_t))) {
        av_free(lens);
        av_free(checksums);
        return;
    }
    if (pread(ctx->idx_fd, checksums, (size_t)n * sizeof(uint32_t), sizeof(head) + n * sizeof(uint32_t)) !=
        (ssize_t)(n * sizeof(uint32_t))) {
        av_free(lens); av_free(checksums); return;
    }
    struct stat data_stat;
    if (fstat(ctx->fd, &data_stat) != 0) { av_free(lens); av_free(checksums); return; }
    for (int i = 0; i < n; i++) {
        if (lens[i] > CACHE_BLOCK || (lens[i] && (int64_t)i * CACHE_BLOCK + lens[i] > data_stat.st_size)) {
            lens[i] = 0;
            checksums[i] = 0;
            ctx->dirty = 1;
        }
    }
    ctx->lens = lens;
    ctx->checksums = checksums;
    ctx->nblocks = (int)n;
    if (total > 0) ctx->total = total;
    // 段表里的 total 曾被写成有界 Range 的长度（例如 1MiB）。缓存块一旦越过它，
    // 段表与真实流长自相矛盾：AVSEEK_SIZE 会把大文件报成小文件，demuxer 算不出
    // 时长，seek 也会回卷。此时作废整张表，让播放期连接重新给出权威长度。
    int64_t extent = 0;
    for (int i = 0; i < ctx->nblocks; i++) {
        if (lens[i] > 0) {
            int64_t end = (int64_t)i * CACHE_BLOCK + lens[i];
            if (end > extent) extent = end;
        }
    }
    if (ctx->total > 0 && extent > ctx->total) {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache",
                     "index total stale %{public}lld < extent %{public}lld, reset",
                     (long long)ctx->total, (long long)extent);
        memset(lens, 0, (size_t)ctx->nblocks * sizeof(uint32_t));
        ctx->total = -1;
        ctx->dirty = 1;
    }
}

static void save_index(CacheCtx *ctx)
{
    if (ctx->idx_fd < 0 || !ctx->lens || !ctx->dirty) return;
    struct stat held, named;
    // 用户清缓存或目录被替换后，旧实例不能把旧索引发布给同名的新文件。
    if (fstat(ctx->fd, &held) != 0 || stat(ctx->bin_path, &named) != 0 ||
        held.st_ino != named.st_ino || held.st_dev != named.st_dev) return;
    size_t size = 20 + (size_t)ctx->nblocks * sizeof(uint32_t) * 2;
    uint8_t *snapshot = av_malloc(size);
    if (!snapshot) return;
    memcpy(snapshot, IDX_MAGIC, 4);
    int64_t total = ctx->total;
    int64_t n = ctx->nblocks;
    memcpy(snapshot + 4, &total, 8);
    memcpy(snapshot + 12, &n, 8);
    memcpy(snapshot + 20, ctx->lens, (size_t)n * sizeof(uint32_t));
    memcpy(snapshot + 20 + n * sizeof(uint32_t), ctx->checksums, (size_t)n * sizeof(uint32_t));
    // 数据先落盘，完整索引再原子发布。进程中断不会留下半份新索引配旧正文。
    char tmp[sizeof(ctx->idx_path) + 40];
    snprintf(tmp, sizeof(tmp), "%s.%ld.%d.tmp", ctx->idx_path, (long)getpid(), ctx->fd);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    int ok = fd >= 0 && fsync(ctx->fd) == 0 &&
        pwrite(fd, snapshot, size, 0) == (ssize_t)size && fsync(fd) == 0;
    if (fd >= 0) close(fd);
    av_free(snapshot);
    if (!ok || rename(tmp, ctx->idx_path) != 0) { unlink(tmp); return; }
    ctx->dirty = 0;
    ctx->dirty_blocks = 0;
    ctx->last_save = av_gettime_relative();
}

static int ensure_blocks(CacheCtx *ctx, int block)
{
    if (block < 0 || block >= CACHE_MAX_BLOCKS) return -1;
    if (block < ctx->nblocks) return 0;
    int want = block + 1;
    if (want < 64) want = 64;
    if (want > CACHE_MAX_BLOCKS) want = CACHE_MAX_BLOCKS;
    uint32_t *grown = (uint32_t *)av_mallocz((size_t)want * sizeof(uint32_t));
    uint32_t *checksums = (uint32_t *)av_mallocz((size_t)want * sizeof(uint32_t));
    if (!grown || !checksums) { av_free(grown); av_free(checksums); return -1; }
    if (ctx->lens && ctx->nblocks > 0) {
        memcpy(grown, ctx->lens, (size_t)ctx->nblocks * sizeof(uint32_t));
        memcpy(checksums, ctx->checksums, (size_t)ctx->nblocks * sizeof(uint32_t));
        av_free(ctx->lens);
        av_free(ctx->checksums);
    }
    ctx->lens = grown;
    ctx->checksums = checksums;
    ctx->nblocks = want;
    return 0;
}

static AVDictionary *net_options(const CacheCtx *ctx)
{
    AVDictionary *options = NULL;
    av_dict_set(&options, "protocol_whitelist", "https,http,tls,tcp", 0);
    if (ctx->agent && ctx->agent[0]) av_dict_set(&options, "user_agent", ctx->agent, 0);
    if (ctx->referer && ctx->referer[0]) av_dict_set(&options, "referer", ctx->referer, 0);
    if (ctx->cookie && ctx->cookie[0]) {
        size_t size = strlen(ctx->cookie) + 16;
        char *header = (char *)malloc(size);
        if (header) {
            snprintf(header, size, "Cookie: %s\r\n", ctx->cookie);
            av_dict_set(&options, "headers", header, 0);
            free(header);
        }
    }
    // 保留 8s 超时；供给不足以累计的实际读取时间判断，避免短时抖动误切。
    av_dict_set(&options, "rw_timeout", "8000000", 0);
    // 与 dual.c / prewarm.c 保持一致：断流要能按当前 offset 重连。
    av_dict_set(&options, "reconnect", "1", 0);
    av_dict_set(&options, "reconnect_streamed", "1", 0);
    av_dict_set(&options, "reconnect_on_network_error", "1", 0);
    av_dict_set(&options, "reconnect_delay_max", "2", 0);
    av_dict_set(&options, "reconnect_max_retries", "5", 0);
    av_dict_set(&options, "reconnect_delay_total_max", "20", 0);
    return options;
}

// 单源慢/失败时切到 backup 一次；切完用长超时，之后不再来回抖动。
static int failover_once(CacheCtx *ctx)
{
    if (ctx->using_backup || !ctx->backup_url || !ctx->backup_url[0]) return 0;
    size_t n = strlen(ctx->backup_url) + 1;
    char *dup = (char *)av_malloc(n);
    if (!dup) return 0;
    memcpy(dup, ctx->backup_url, n);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache", "failover base -> backup");
    if (ctx->net) avio_closep(&ctx->net);
    ctx->net = NULL;
    ctx->net_pos = 0;
    av_free(ctx->url);
    ctx->url = dup;
    ctx->using_backup = 1;
    return 1;
}

// end > offset 时发有界 Range；end <= 0 表示不设结束位置，一条连接读到 EOF 或下一次 seek。
// 失败仅切备用源一次。
static void record_network_read(CacheCtx *ctx, int n, int64_t started)
{
    int64_t now = av_gettime_relative();
    if (n > 0 && !ctx->using_backup && ctx->expected_bps > 0) {
        ctx->sample_bytes += n;
        ctx->sample_read_us += now - started;
        // Count only time spent reading this connection: pauses, full queues and
        // disk hits must not make a healthy CDN appear slow. Require a sustained
        // sample, then switch once at the next unread byte without losing data.
        if (ctx->sample_read_us >= 4000000) {
            int64_t bps = ctx->sample_bytes * 8000000 / ctx->sample_read_us;
            if (bps < ctx->expected_bps && ctx->backup_url && ctx->backup_url[0]) {
                ctx->slow_source = 1;
                OH_LOG_Print(LOG_APP, LOG_WARN, 0, "PlaybackNetwork",
                    "slow source read_bps=%{public}lld expected_bps=%{public}lld",
                    (long long)bps, (long long)ctx->expected_bps);
            }
            ctx->sample_bytes = ctx->sample_read_us = 0;
        }
    }
    if (now-started > ctx->network_read_max_us) ctx->network_read_max_us = now-started;
    if (n > 0) ctx->network_bytes += n;
    if (!ctx->network_logged_at) ctx->network_logged_at = started;
    int64_t elapsed = now-ctx->network_logged_at;
    if (elapsed < 1000000) return;
    int64_t bytes = ctx->network_bytes-ctx->network_logged_bytes;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "PlaybackNetwork",
        "network bytes=%{public}lld elapsed_us=%{public}lld Bps=%{public}lld read_max_us=%{public}lld",
        (long long)bytes, (long long)elapsed, (long long)(bytes*1000000/elapsed),
        (long long)ctx->network_read_max_us);
    ctx->network_logged_at=now;ctx->network_logged_bytes=ctx->network_bytes;ctx->network_read_max_us=0;
}

static AVIOContext *open_net(CacheCtx *ctx, int64_t offset, int64_t end)
{
    AVIOContext *pb = NULL;
    AVDictionary *options = net_options(ctx);
    av_dict_set_int(&options, "offset", offset, 0);
    if (end > offset) av_dict_set_int(&options, "end_offset", end, 0);
    if (avio_open2(&pb, ctx->url, AVIO_FLAG_READ, &ctx->ic, &options) < 0) pb = NULL;
    av_dict_free(&options);
    if (!pb && failover_once(ctx)) {
        options = net_options(ctx);
        av_dict_set_int(&options, "offset", offset, 0);
        if (end > offset) av_dict_set_int(&options, "end_offset", end, 0);
        if (avio_open2(&pb, ctx->url, AVIO_FLAG_READ, &ctx->ic, &options) < 0) pb = NULL;
        av_dict_free(&options);
    }
    // HTTP 的 offset 只定位协议层，ffio_fdopen 新建 AVIO 时 pos 仍为 0。
    // 若不对齐，后续跨过已缓存块时 avio_seek 会按错误的缓冲区坐标做
    // short-seek（丢读），把 offset+目标位置的正文写入目标块。CRC 无法发现
    // 写入前就已错位的内容。此时 AVIO 缓冲区为空，直接设置其文件坐标。
    if (pb) pb->pos = offset;
    return pb;
}

// 播放期回源不再按 1 MiB 切段：4K 约 2.5~5MB/s，原先每秒要重开 3~5 次 TCP/TLS，
// 供给跟不上就成了「像 PPT」的卡顿。字节窗口只约束后台投机预热（prewarm.c）。
static AVIOContext *ensure_net(CacheCtx *ctx, int64_t offset)
{
    if (ctx->net && offset >= ctx->net_pos && offset < ctx->net_end) return ctx->net;
    if (ctx->net) avio_closep(&ctx->net);
    AVIOContext *pb = NULL;
    int64_t adopted_at = -1;
    // 前缀预热读满 512KB 后连接留在原生层，正好停在播放要续读的位置：直接接管，
    // 省掉一次 TCP+TLS 握手（实测 200~300ms）。位置对不上或没读满就照旧回源。
    if (ctx->prefix) pb = purapily_prefix_adopt(ctx->prefix, offset, &adopted_at);
    if (!pb) pb = open_net(ctx, offset, 0);
    if (!pb) return NULL;
    ctx->net = pb;
    ctx->net_pos = adopted_at >= 0 ? adopted_at : offset;
    ctx->net_fresh = adopted_at >= 0;
    // 播放期响应（Range: bytes=N-）的 Content-Range 给出的是整条流的长度，
    // 是权威口径。段表/探测若留下偏小的值，会让 AVSEEK_SIZE 把大文件报成小文件，
    // demuxer 算不出时长、seek 回卷，必须在这里纠正。
    int64_t size = avio_size(pb);
    if (size > 0 && (ctx->total <= 0 || size != ctx->total)) {
        if (ctx->total > 0 && ctx->lens && ctx->nblocks > 0) {
            // 旧长度截断过的块不可信，作废后按新长度重新回源。
            memset(ctx->lens, 0, (size_t)ctx->nblocks * sizeof(uint32_t));
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache",
                     "total refresh %{public}lld -> %{public}lld at %{public}lld",
                     (long long)ctx->total, (long long)size, (long long)offset);
        ctx->total = size;
        ctx->dirty = 1;
    }
    ctx->net_end = ctx->total > 0 ? ctx->total : INT64_MAX;
    return pb;
}

// 成功读取后仍可能断流。识别真实文件尾，错误连接最多重开两次，随后保留错误。
static int read_net(CacheCtx *ctx, uint8_t *buf, int size)
{
    if (ctx->ic.callback && ctx->ic.callback(ctx->ic.opaque)) return AVERROR_EXIT;
    if (ctx->slow_source) {
        int64_t at = ctx->net_pos;
        ctx->slow_source = 0;
        if (failover_once(ctx) && !ensure_net(ctx, at)) return AVERROR(EIO);
    }
    for (int attempt = 0; ; attempt++) {
        int64_t started = av_gettime_relative();
        int n = avio_read(ctx->net, buf, size);
        record_network_read(ctx, n, started);
        if (n > 0) { ctx->net_pos += n; ctx->net_fresh = 0; return n; }
        if (n == AVERROR_EXIT || (ctx->ic.callback && ctx->ic.callback(ctx->ic.opaque))) return AVERROR_EXIT;
        int premature_eof = (n == 0 || n == AVERROR_EOF) && ctx->total > 0 && ctx->net_pos < ctx->total;
        if ((n == 0 || n == AVERROR_EOF) && !premature_eof) {
            // 预热接管的连接第一次读到 0 不能当真 EOF：它可能只带到了预热
            // 切片的位置。原位置重开一次真实回源再判定，最多一次，避免循环。
            if (ctx->net_fresh && attempt == 0) {
                int64_t at = ctx->net_pos;
                ctx->net_fresh = 0;
                OH_LOG_Print(LOG_APP, LOG_WARN, 0, "Cache",
                    "adopted connection EOF at=%{public}lld, reopen once", (long long)at);
                avio_closep(&ctx->net);
                if (ensure_net(ctx, at)) continue;
                return AVERROR(EIO);
            }
            return n;
        }
        if (attempt >= 2) return premature_eof ? AVERROR(EIO) : n;
        int64_t at = ctx->net_pos;
        OH_LOG_Print(LOG_APP, LOG_WARN, 0, "Cache",
            "read recovery at=%{public}lld rc=%{public}d attempt=%{public}d",
            (long long)at, n, attempt + 1);
        // AVIO latches error/eof. Clearing the outer demuxer's error cannot
        // revive this inner connection. Replace it and retain partial reads.
        avio_closep(&ctx->net);
        ctx->net_fresh = 0;
        if (attempt == 1) failover_once(ctx);
        if (!ensure_net(ctx, at)) return AVERROR(EIO);
    }
}

void purapily_cache_set_bandwidth(AVIOContext *pb, int64_t bps)
{
    if (pb && bps > 0) ((CacheCtx *)pb->opaque)->expected_bps = bps;
}

// 只为拿流总长：仍用 1 MiB 有界 Range，且取到长度立刻关闭，绝不留下闲置响应继续推流。
// 这是启动 95MB 流量修复的边界，不能因为放开播放期回源而一起放宽。
static int64_t probe_total(CacheCtx *ctx)
{
    AVIOContext *pb = open_net(ctx, 0, 1024 * 1024);
    if (!pb) return -1;
    int64_t size = avio_size(pb);
    avio_closep(&pb);
    return size > 0 ? size : -1;
}

// 缺块回源：按块起始 offset 定位，读满一块（或到 EOF），写入稀疏文件并登记长度。
// 返回该块可用的字节数；<0 为错误。
static int fetch_block(CacheCtx *ctx, int block)
{
    if (ensure_blocks(ctx, block) != 0) return AVERROR(ENOMEM);
    int64_t start = (int64_t)block * CACHE_BLOCK;
    int want = CACHE_BLOCK;
    if (ctx->total > 0 && start + want > ctx->total) {
        want = (int)(ctx->total - start);
    }
    if (want <= 0) {
        // 可能是段表里遗留的偏小 total。开一次真实回源复核：ensure_net 会用
        // 响应的 Content-Range 纠正 total；纠正不了才说明确实到了文件尾。
        if (!ensure_net(ctx, start) || ctx->total <= start) return 0;
        int64_t room = ctx->total - start;
        want = room > CACHE_BLOCK ? CACHE_BLOCK : (int)room;
    }
    uint8_t *tmp = (uint8_t *)av_malloc(CACHE_BLOCK);
    if (!tmp) return AVERROR(ENOMEM);
    int got = 0;
    while (got < want) {
        int n = purapily_prefix_read(ctx->prefix,start+got,tmp+got,want-got,&ctx->ic);
        if (n == AVERROR(ENOSYS)) {
            AVIOContext *net = ensure_net(ctx,start+got);
            if (!net) { av_free(tmp); return AVERROR(EIO); }
            if (ctx->net_pos != start+got) {
                int64_t moved=avio_seek(net,start+got,SEEK_SET);
                if(moved<0) { av_free(tmp); return (int)moved; }
                ctx->net_pos=moved;
            }
            int64_t room=ctx->net_end-ctx->net_pos;
            if(room<=0) break;                 // 真 EOF，不要拿负数 size 调 avio_read
            int ask=want-got;
            if(ask>room) ask=(int)room;
            n=read_net(ctx,tmp+got,ask);
        }
        if (n == AVERROR_EOF || n == 0) break;
        if (n < 0) { av_free(tmp); return n; }
        got += n;
    }
    if (got > 0) {
        ssize_t written = pwrite(ctx->fd, tmp, (size_t)got, start);
        if (written == got) {
            if (ensure_blocks(ctx, block) == 0) {
                ctx->lens[block] = (uint32_t)got;
                ctx->checksums[block] = block_checksum(tmp, (size_t)got);
                ctx->dirty = 1;
                ctx->dirty_blocks++;
                // 每 16 块或每 2 秒落一次段表：进程被系统杀掉也不会整段缓存作废。
                if (ctx->dirty_blocks >= 16 || av_gettime_relative() - ctx->last_save > 2000000) {
                    save_index(ctx);
                }
            }
        } else {
            got = 0;
        }
    }
    av_free(tmp);
    return got;
}

// 超过单流上限的块不落盘，直接回源读，避免文件无限膨胀。
static int read_uncached_direct(CacheCtx *ctx, uint8_t *buf, int size)
{
    int from_prefix=purapily_prefix_read(ctx->prefix,ctx->pos,buf,size,&ctx->ic);
    if(from_prefix>=0) { ctx->pos+=from_prefix; return from_prefix; }
    if(from_prefix!=AVERROR(ENOSYS)) return from_prefix;
    // 先建连再判文件尾：ensure_net 会用响应的 Content-Range 纠正段表里偏小的 total，
    // 否则会在假想的文件尾提前 EOF。
    AVIOContext *net = ensure_net(ctx, ctx->pos);
    if (!net) return AVERROR(EIO);
    if (ctx->total > 0 && ctx->pos >= ctx->total) return AVERROR_EOF;
    if (ctx->net_pos != ctx->pos) {
        int64_t moved = avio_seek(net, ctx->pos, SEEK_SET);
        if (moved < 0) return (int)moved;
        ctx->net_pos = moved;
    }
    // 读到已知文件尾就截断，别让 AVIO 把正常 EOF 误判成断流而触发 reconnect/backoff。
    // 用连接的实际位置而不是逻辑 pos：seek 越过文件尾时 pos 会大于 net_end，
    // 相减为负会被当成 size 传给 avio_read。
    int64_t remaining = ctx->net_end - ctx->net_pos;
    if (remaining <= 0) return AVERROR_EOF;
    if (size > remaining) size = (int)remaining;
    int n = read_net(ctx, buf, size);
    if (n > 0) ctx->pos += n;
    return n;
}

static int cache_read(void *opaque, uint8_t *buf, int size)
{
    CacheCtx *ctx = (CacheCtx *)opaque;
    if (size <= 0) return 0;
    if (ctx->fd < 0) return read_uncached_direct(ctx, buf, size);
    int filled = 0;
    while (filled < size) {
        int64_t pos = ctx->pos;
        int block = (int)(pos / CACHE_BLOCK);
        int off = (int)(pos % CACHE_BLOCK);
        if (block >= CACHE_MAX_BLOCKS) {
            int n = read_uncached_direct(ctx, buf + filled, size - filled);
            if (n <= 0) return filled > 0 ? filled : (n < 0 ? n : AVERROR_EOF);
            filled += n;
            continue;
        }
        uint32_t have = (block < ctx->nblocks && ctx->lens) ? ctx->lens[block] : 0;
        if (have == 0) {
            int got = fetch_block(ctx, block);
            if (got < 0) return filled > 0 ? filled : got;
            have = (uint32_t)got;
            if (have == 0) return filled > 0 ? filled : AVERROR_EOF;
        }
        if (off >= (int)have) {
            // 短块只有正好落在流尾才是真 EOF。断流或旧 total 留下的半块会被
            // 段表长期保存，直接报 EOF 会让视频轨先结束而音频继续（有声无画），
            // 且下一次打开同一缓存仍复发。作废该块、复核长度后回源补齐。
            int64_t block_start = (int64_t)block * CACHE_BLOCK;
            int64_t block_end = block_start + (int64_t)have;
            int short_block = have > 0 && (int)have < CACHE_BLOCK;
            if (short_block && (ctx->total <= 0 || ctx->total > block_end)) {
                if (ctx->short_block != block) {
                    ctx->short_block = block;
                    ctx->short_retries = 0;
                }
                if (ctx->short_retries < 2) {
                    ctx->short_retries++;
                    // 强制重开连接：ensure_net 会用播放期响应的 Content-Range
                    // 纠正段表里偏小的 total，fetch_block 才能读满这一块。
                    if (ctx->net) avio_closep(&ctx->net);
                    AVIOContext *net = ensure_net(ctx, block_start);
                    if (net && ctx->total > block_end) {
                        OH_LOG_Print(LOG_APP, LOG_WARN, 0, "Cache",
                            "short block=%{public}d have=%{public}u total=%{public}lld, refetch",
                            block, have, (long long)ctx->total);
                        ctx->lens[block] = 0;
                        ctx->checksums[block] = 0;
                        ctx->dirty = 1;
                        continue;
                    }
                }
            }
            // 修复次数用尽后保留 short_block 标记：demuxer 若在同一位置重试，
            // 直接判 EOF，不要每轮都重开连接。
            // 已到该块的有效末尾（通常是文件尾）。
            return filled > 0 ? filled : AVERROR_EOF;
        }
        // 每次读完整有效块并核对 CRC，不能把“pread 成功”当成媒体内容正确。
        // 失败只淘汰本块，同一逻辑位置回源；不让坏字节先进入解码队列再等用户清缓存。
        ssize_t checked = pread(ctx->fd, ctx->block_buf, have, (off_t)block * CACHE_BLOCK);
        if (checked != have || block_checksum(ctx->block_buf, have) != ctx->checksums[block]) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0, "Cache", "invalid block=%{public}d, refetch", block);
            ctx->lens[block] = 0;
            ctx->checksums[block] = 0;
            ctx->dirty = 1;
            int got = fetch_block(ctx, block);
            if (got < 0) return filled > 0 ? filled : got;
            if (got == 0) return filled > 0 ? filled : AVERROR(EIO);
            have = (uint32_t)got;
            checked = pread(ctx->fd, ctx->block_buf, have, (off_t)block * CACHE_BLOCK);
            if (checked != have || block_checksum(ctx->block_buf, have) != ctx->checksums[block])
                return filled > 0 ? filled : AVERROR(EIO);
            if (off >= (int)have) {
                // 补块仍是半块：交回主循环的统一短块修复路径，别在这里报 EOF。
                ctx->lens[block] = 0;
                ctx->checksums[block] = 0;
                ctx->dirty = 1;
                continue;
            }
        }
        ctx->short_block = -1;
        int want = (int)have - off;
        if (want > size - filled) want = size - filled;
        memcpy(buf + filled, ctx->block_buf + off, (size_t)want);
        filled += want;
        ctx->pos += want;
    }
    return filled;
}

static int64_t cache_seek(void *opaque, int64_t offset, int whence)
{
    CacheCtx *ctx = (CacheCtx *)opaque;
    if (whence == AVSEEK_SIZE) return ctx->total > 0 ? ctx->total : AVERROR(ENOSYS);
    if (whence & AVSEEK_FORCE) whence &= ~AVSEEK_FORCE;
    int64_t target;
    if (whence == SEEK_SET) target = offset;
    else if (whence == SEEK_CUR) target = ctx->pos + offset;
    else if (whence == SEEK_END) {
        if (ctx->total < 0) return AVERROR(ENOSYS);
        target = ctx->total + offset;
    } else return AVERROR(EINVAL);
    if (target < 0) return AVERROR(EINVAL);
    ctx->pos = target;
    return target;
}

AVIOContext *purapily_cache_open(const char *url, const char *backup, const char *agent,
                                 const char *referer, const char *cookie,
                                 const AVIOInterruptCB *ic)
{
    if (!url) return NULL;
    if (g_dir[0]) evict_if_needed();
    char bin[CACHE_DIR_MAX + 256] = {0}, idx[CACHE_DIR_MAX + 256] = {0};
    int fd = -1, idx_fd = -1;
    if (g_dir[0]) {
        cache_paths(url, bin, idx, sizeof(bin));
        fd = open(bin, O_RDWR | O_CREAT, 0600);
        if (fd >= 0) {
            struct stat held, named;
            // 同一媒体只允许一个缓存拥有者。另一个预热/播放实例直接走网络，
            // 不等待锁，也不读取对方尚未发布的段表。淘汰后的旧 inode 也不能复用。
            if (flock(fd, LOCK_EX | LOCK_NB) != 0 || fstat(fd, &held) != 0 ||
                stat(bin, &named) != 0 || held.st_ino != named.st_ino || held.st_dev != named.st_dev) {
                close(fd); fd = -1;
                OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache", "busy cache, use network");
            } else {
                idx_fd = open(idx, O_RDWR | O_CREAT, 0600);
                if (idx_fd < 0) { close(fd); fd = -1; }
            }
        }
    }
    CacheCtx *ctx = (CacheCtx *)av_mallocz(sizeof(CacheCtx));
    if (!ctx) { close(fd); if (idx_fd >= 0) close(idx_fd); return NULL; }
    ctx->fd = fd;
    ctx->idx_fd = idx_fd;
    snprintf(ctx->bin_path, sizeof(ctx->bin_path), "%s", bin);
    snprintf(ctx->idx_path, sizeof(ctx->idx_path), "%s", idx);
    if (fd >= 0) {
        ctx->block_buf = av_malloc(CACHE_BLOCK);
        if (!ctx->block_buf) { close(fd); close(idx_fd); av_free(ctx); return NULL; }
    }
    ctx->total = -1;
    ctx->short_block = -1;
    if (ic) ctx->ic = *ic;
    copy_str(&ctx->url, url);
    copy_str(&ctx->backup_url, backup);
    copy_str(&ctx->agent, agent);
    copy_str(&ctx->referer, referer);
    copy_str(&ctx->cookie, cookie);
    load_index(ctx);
    if (fd >= 0 && !ctx->lens) {
        // 没有段表（首播或旧版连续前缀残留）：数据文件不能按稀疏解释，清空重来。
        if (ftruncate(fd, 0) != 0) { /* 忽略，后面按块覆盖 */ }
        if (ensure_blocks(ctx, 63) != 0) {
            close(fd); if (idx_fd >= 0) close(idx_fd);
            av_free(ctx->url);
        av_free(ctx->backup_url); av_free(ctx->agent); av_free(ctx->referer); av_free(ctx->cookie);
            av_free(ctx->block_buf);
            av_free(ctx);
            return NULL;
        }
    }
    uint8_t *buffer = (uint8_t *)av_malloc(CACHE_IO_BUF);
    if (!buffer) {
        close(fd); if (idx_fd >= 0) close(idx_fd);
        av_free(ctx->lens);
        av_free(ctx->checksums);
        av_free(ctx->block_buf);
        av_free(ctx->url);
        av_free(ctx->backup_url); av_free(ctx->agent); av_free(ctx->referer); av_free(ctx->cookie);
        av_free(ctx);
        return NULL;
    }
    AVIOContext *pb = avio_alloc_context(buffer, CACHE_IO_BUF, 0, ctx, cache_read, NULL, cache_seek);
    if (!pb) {
        av_free(buffer); close(fd); if (idx_fd >= 0) close(idx_fd);
        av_free(ctx->lens);
        av_free(ctx->checksums);
        av_free(ctx->block_buf);
        av_free(ctx->url);
        av_free(ctx->backup_url); av_free(ctx->agent); av_free(ctx->referer); av_free(ctx->cookie);
        av_free(ctx);
        return NULL;
    }
    pb->seekable = AVIO_SEEKABLE_NORMAL;
    const char *total_src = "index";
    ctx->prefix=purapily_prefix_take(url,agent,referer,cookie);
    if(ctx->prefix && ctx->total<0) {
        int64_t hint=purapily_prefix_size(ctx->prefix,ic);
        // 预热可能还没拿到长度（返回 0/-1）。绝不能把 0 当成流总长：那样
        // AVSEEK_SIZE 只能返回 ENOSYS，demuxer 算不出时长、进度条与 seek 全废。
        if (hint > 0) { ctx->total = hint; total_src = "prefix"; }
        else total_src = "unknown";
    }
    // 段表已存 total（命中重开）或预热前缀已给出长度：不建任何连接，connect 直接为 0。
    // 首播只做一次有界探测拿长度并立即关闭；缺块时 fetch_block 按需开播放期连接。
    if (ctx->total < 0) {
        int64_t probed = probe_total(ctx);
        if (probed > 0) { ctx->total = probed; ctx->dirty = 1; total_src = "probe"; }
        else total_src = "unknown";
    }
    int blocks = 0;
    int64_t bytes = 0;
    for (int i = 0; i < ctx->nblocks; i++) {
        if (ctx->lens[i] > 0) { blocks++; bytes += ctx->lens[i]; }
    }
    char key[CACHE_KEY_MAX];
    key_from_url(url, key, sizeof(key));
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache",
                 "open %{public}s blocks=%{public}d %{public}lldKB total=%{public}lldKB src=%{public}s net=%{public}d bk=%{public}d",
                 key, blocks, (long long)(bytes / 1024), (long long)(ctx->total / 1024), total_src,
                 ctx->net ? 1 : 0, (ctx->backup_url && ctx->backup_url[0]) ? 1 : 0);
    return pb;
}

void purapily_cache_close(AVIOContext **ppb)
{
    if (!ppb || !*ppb) return;
    AVIOContext *pb = *ppb;
    CacheCtx *ctx = (CacheCtx *)pb->opaque;
    if (ctx) {
        // 先关（可能由预热交接来的）网络连接，再放掉预热任务，避免连接比任务活得久。
        if (ctx->net) avio_closep(&ctx->net);
        purapily_prefix_discard(ctx->prefix);
        save_index(ctx);
        int blocks = 0;
        int64_t bytes = 0;
        for (int i = 0; i < ctx->nblocks; i++) {
            if (ctx->lens && ctx->lens[i] > 0) { blocks++; bytes += ctx->lens[i]; }
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Cache", "close blocks=%{public}d cached=%{public}lldKB received=%{public}lldKB",
                     blocks, (long long)(bytes / 1024), (long long)(ctx->network_bytes / 1024));
        if (ctx->net) avio_closep(&ctx->net);
        if (ctx->idx_fd >= 0) close(ctx->idx_fd);
        if (ctx->fd >= 0) close(ctx->fd);
        av_free(ctx->lens);
        av_free(ctx->checksums);
        av_free(ctx->block_buf);
        av_free(ctx->url);
        av_free(ctx->backup_url);
        av_free(ctx->agent);
        av_free(ctx->referer);
        av_free(ctx->cookie);
        av_free(ctx);
    }
    av_freep(&pb->buffer);
    avio_context_free(&pb);
    *ppb = NULL;
}
