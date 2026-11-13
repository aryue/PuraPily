// Bounded prefix jobs shared by list preparation and the real demuxer.
// 读满字节上限就停读，但连接留着交给播放期接管（purapily_prefix_adopt），
// 所以既不会继续拉流，也不用在开播时重付一次 TCP+TLS 握手。
// No decoder, no independent disk index writer.
#include <libavformat/avformat.h>
#include <libavutil/time.h>
#include <libavutil/mem.h>
#include <libavutil/error.h>
#include <hilog/log.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <time.h>
#define SLOTS 4
#define LIMIT (512 * 1024)
#define TTL_US 60000000LL
// 首帧段上限：sidx 给出的第一个分片（首个 moof+mdat）通常就是解码首帧所需的
// 全部样本。1080P 约 200~500KiB，4K 可达 1~3MiB。前缀若只按固定 512KiB 读，
// 高码率下必然在分片中途截断，首帧仍要现场去 CDN 取。这里允许把预算对齐到
// 分片末尾，但设硬上限，避免重新变成「整段响应」。
#define SEG_CAP_VIDEO (1536 * 1024)
#define SEG_CAP_AUDIO (256 * 1024)
#define PROBE_HEAD 4096
#define PROBE_BYTES (128 * 1024)
#ifndef PURA_PREFIX_QUOTA_PROBE
#define PURA_PREFIX_QUOTA_PROBE 0
#endif
#if PURA_PREFIX_QUOTA_PROBE
// Diagnostic build only: reproduce the removed global quota exactly.
static struct { int64_t at; int bytes; } reservations[32];
#endif

// 前缀由 1~2 个不连续区间组成：0 起点的索引段，和（续播时的）目标分片段。
// 两段共用一块 buffer，第二段紧跟在第一段后面存放。
typedef struct Slice { int64_t off; int len, filled; } Slice;
typedef struct PrefixJob {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    atomic_int cancel;
    int refs, limit, filled, opened, done, failed, served, adopted;
    int nslice, seek_ms;
    Slice s[2];
    int64_t total, created, deadline;
    // 读满前缀后不关连接：留给播放期直接接管，省掉一次 TCP+TLS 握手。
    // 被接管时置回 NULL，避免这边再关一次。
    AVIOContext *pb;
    unsigned char *data;
    char *url, *agent, *referer, *cookie;
} PrefixJob;
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;
static PrefixJob *pool[SLOTS];
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void init_network(void) { avformat_network_init(); }

void purapily_prefix_release(void *opaque)
{
    PrefixJob *j = opaque;
    if (!j) return;
    pthread_mutex_lock(&j->lock);
    int last = --j->refs == 0;
    pthread_mutex_unlock(&j->lock);
    if (!last) return;
    pthread_cond_destroy(&j->changed);
    pthread_mutex_destroy(&j->lock);
    if (j->pb) avio_closep(&j->pb);
    av_free(j->data);
    free(j->url); free(j->agent); free(j->referer); free(j->cookie); free(j);
}
static int cancelled(void *opaque)
{
    PrefixJob *j = opaque;
    return atomic_load(&j->cancel) || av_gettime_relative() >= j->deadline;
}
static int same_resource(const char *a,const char *b)
{
    const char *pa=strstr(a,"/upgcxcode/"), *pb=strstr(b,"/upgcxcode/");
    if(!pa || !pb) return !strcmp(a,b);
    size_t na=strcspn(pa,"?"), nb=strcspn(pb,"?");
    return na==nb && !memcmp(pa,pb,na);
}
// seek_ms 传 -1 表示通配：take 时还不知道调用方会不会续播。
static int same(PrefixJob *j, const char *url, const char *agent, const char *referer, const char *cookie, int seek_ms)
{
    // Signed query/CDN changes must not invalidate the same Bilibili resource.
    // Credentials and request policy still have to match exactly.
    return same_resource(j->url,url) && !strcmp(j->agent, agent) &&
        !strcmp(j->referer, referer) && !strcmp(j->cookie, cookie) &&
        (seek_ms < 0 || j->seek_ms == seek_ms);
}
static void retire(PrefixJob *j)
{
    if (!j) return;
    atomic_store(&j->cancel, 1);
    pthread_mutex_lock(&j->lock);
    pthread_cond_broadcast(&j->changed);
    pthread_mutex_unlock(&j->lock);
    purapily_prefix_release(j);
}
// ---- m4s 布局解析（方案 A：先读索引，再决定前缀覆盖到哪） ----
// B 站 DASH 的 m4s 是 ftyp/moov/sidx + 多个 moof+mdat。sidx 里每个 reference
// 描述一个分片（subsegment）的字节长度，第一个 reference 就是从 0 开始播时
// 解码首帧要用的那段。拿到它就不用再靠「固定 512KiB」猜。
#define MAX_SEG 512
typedef struct SegInfo { int64_t off, size; uint32_t dur; } SegInfo;
typedef struct Layout {
    int has_sidx, segs, nseg;
    int64_t idx_end;   // sidx box 结束位置（首个分片的基准点）
    int64_t seg_off;   // 首个媒体分片起点
    int64_t seg_size;  // 首个媒体分片长度；0 表示只定位到起点
    uint32_t timescale;
    SegInfo seg[MAX_SEG];   // 完整分片表，供续播定位
    const char *why;
} Layout;
static uint32_t rb32(const unsigned char *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static uint64_t rb64(const unsigned char *p)
{
    return ((uint64_t)rb32(p) << 32) | rb32(p + 4);
}
// 只解析头部 box；数据不够时返回 0 并把 why 设成 sidx-truncated 供调用方多读一截。
static int parse_layout(const unsigned char *d, int n, Layout *L)
{
    memset(L, 0, sizeof(*L));
    L->why = "no-box";
    int64_t off = 0;
    while (off + 8 <= n) {
        uint64_t size = rb32(d + off);
        const unsigned char *t = d + off + 4;
        int hdr = 8;
        if (size == 1) {
            if (off + 16 > n) break;
            size = rb64(d + off + 8);
            hdr = 16;
        } else if (size == 0) {
            break; // 延伸到文件尾，头部里不会有这种 box
        }
        if (size < (uint64_t)hdr) break;
        if (!memcmp(t, "sidx", 4)) {
            int64_t body = off + hdr;
            if (body + 12 > n) { L->why = "sidx-truncated"; return 0; }
            int ver = d[body];
            int64_t p = body + 4;
            int64_t first_offset;
            if (p + 8 > n) { L->why = "sidx-truncated"; return 0; }
            L->timescale = rb32(d + p + 4);
            if (ver == 0) {
                if (p + 16 > n) { L->why = "sidx-truncated"; return 0; }
                first_offset = (int64_t)rb32(d + p + 12);
                p += 16;
            } else {
                if (p + 24 > n) { L->why = "sidx-truncated"; return 0; }
                first_offset = (int64_t)rb64(d + p + 16);
                p += 24;
            }
            if (p + 4 > n) { L->why = "sidx-truncated"; return 0; }
            uint32_t count = ((uint32_t)d[p + 2] << 8) | d[p + 3];
            p += 4;
            int64_t end = off + (int64_t)size;
            L->has_sidx = 1;
            L->idx_end = end;
            L->segs = (int)count;
            int64_t cur = end + first_offset;
            int64_t avail = n - p;
            int use = (int64_t)count * 12 <= avail ? (int)count : (int)(avail / 12);
            for (int i = 0; i < use; i++) {
                uint32_t w = rb32(d + p + i * 12);
                int64_t rsize = w & 0x7fffffffu;
                if (((w >> 31) & 1) == 0) { // 0 = 媒体分片
                    if (!L->nseg) { L->seg_off = cur; L->seg_size = rsize; }
                    if (L->nseg < MAX_SEG) {
                        L->seg[L->nseg].off = cur;
                        L->seg[L->nseg].size = rsize;
                        L->seg[L->nseg].dur = rb32(d + p + i * 12 + 4);
                        L->nseg++;
                    }
                }
                cur += rsize; // 指向下一层 sidx，跳过
            }
            if (L->nseg > 0) { L->why = "sidx"; return L->seg_size > 0; }
            L->why = "no-media-ref";
            return 0;
        }
        if (!memcmp(t, "moof", 4)) {
            // 没有 sidx 的流：首个 moof 就是首帧段起点，长度要看紧随的 mdat。
            L->seg_off = off;
            int64_t q = off + (int64_t)size;
            for (int k = 0; k < 4 && q + 8 <= n; k++) {
                uint64_t s2 = rb32(d + q);
                int h2 = 8;
                if (s2 == 1) {
                    if (q + 16 > n) break;
                    s2 = rb64(d + q + 8);
                    h2 = 16;
                }
                if (s2 < (uint64_t)h2) break;
                if (!memcmp(d + q + 4, "mdat", 4)) {
                    L->seg_size = q + (int64_t)s2 - off;
                    L->why = "moof+mdat";
                    return L->seg_size > 0;
                }
                q += (int64_t)s2;
            }
            L->why = "moof-only";
            return 0;
        }
        off += (int64_t)size;
    }
    if (L->why[0] == 'n') L->why = "no-sidx";
    return 0;
}
// 把第 k 段读到 len 为止；需要时先把连接 seek 到段起点。
// 续播场景下第二段在文件后部，avio_seek 会在同一条 TCP 上发新的 Range 请求。
static int seek_abs(AVIOContext *pb, int64_t *cur, int64_t pos)
{
    if (*cur == pos) return 0;
    int64_t r = avio_seek(pb, pos, SEEK_SET);
    if (r < 0) return (int)r;
    *cur = r;
    return 0;
}
static void read_slice(PrefixJob *j, AVIOContext *pb, int k, int64_t *cur, int *rc)
{
    int base = 0;
    for (int i = 0; i < k; i++) base += j->s[i].len;
    while (*rc >= 0 && pb && !cancelled(j)) {
        pthread_mutex_lock(&j->lock);
        int rel = j->s[k].filled, len = j->s[k].len;
        int64_t off = j->s[k].off;
        pthread_mutex_unlock(&j->lock);
        if (rel >= len) return;
        if (seek_abs(pb, cur, off + rel) < 0) { *rc = AVERROR(EIO); return; }
        int want = len - rel;
        if (want > 32768) want = 32768;
        int n = avio_read(pb, j->data + base + rel, want);
        if (n <= 0) { *rc = n; return; }
        pthread_mutex_lock(&j->lock);
        j->s[k].filled += n;
        j->filled += n;
        pthread_cond_broadcast(&j->changed);
        pthread_mutex_unlock(&j->lock);
    }
}
// 连接只在前缀任务存活期间保留（take/discard/换槽即关），不额外挂定时器。
static void *worker(void *opaque)
{
    PrefixJob *j = opaque;
    pthread_once(&once, init_network);
    AVDictionary *o = NULL;
    av_dict_set(&o, "protocol_whitelist", "https,http,tls,tcp", 0);
    av_dict_set(&o, "user_agent", j->agent, 0);
    if (j->referer[0]) av_dict_set(&o, "referer", j->referer, 0);
    if (j->cookie[0]) {
        size_t n = strlen(j->cookie) + 16;
        char *header = malloc(n);
        if (header) { snprintf(header, n, "Cookie: %s\r\n", j->cookie); av_dict_set(&o, "headers", header, 0); free(header); }
    }
    av_dict_set_int(&o, "offset", 0, 0);
    // 这条连接会被播放接管并承载整段播放，接收窗口必须够大：显式设 SO_RCVBUF 会关掉
    // 内核自增，32KiB 时实测吞吐被卡在 0.8~2MB/s（≈窗口/RTT），4K 直接不够用；
    // 256KiB 在 60ms RTT 下约 4MB/s，同时把「没人接管时的多余缓冲」限制在 256KiB/任务。
    av_dict_set(&o, "recv_buffer_size", "262144", 0);
    av_dict_set(&o, "rw_timeout", "2000000", 0);
    // Do not retry failed speculative requests in the background.
    av_dict_set(&o, "reconnect", "0", 0);
    // 这条连接读满前缀后要交给播放期继续用，所以不能带 end_offset（带 Range 结束后
    // 服务器会关掉响应），也不能挂任务自己的 interrupt 回调——那个回调绑定在 job 上，
    // 接管后 job 可能已释放。取消靠每轮循环检查，单次读由 rw_timeout 兜住。
    AVIOContext *pb = NULL;
    int rc = avio_open2(&pb, j->url, AVIO_FLAG_READ, NULL, &o);
    av_dict_free(&o);
    pthread_mutex_lock(&j->lock);
    j->total = pb ? avio_size(pb) : -1;
    j->opened = 1;
    pthread_cond_broadcast(&j->changed);
    pthread_mutex_unlock(&j->lock);
    // 阶段 1：先读一小段头部（实测 ftyp+moov+sidx 只有 1~2KiB）。
    int64_t cur = 0;
    int64_t head = PROBE_HEAD < j->limit ? PROBE_HEAD : j->limit;
    pthread_mutex_lock(&j->lock);
    j->s[0].off = 0; j->s[0].len = (int)head; j->s[0].filled = 0; j->nslice = 1;
    pthread_mutex_unlock(&j->lock);
    read_slice(j, pb, 0, &cur, &rc);
    // 阶段 2：解析段表；sidx 没读完就多读一截重试。
    // Open/read failure short-circuits parse_layout(), which normally initializes L.
    // The layout diagnostic below still reads why and segment fields on that path.
    Layout L = { .why = "read-error" };
    int ok = rc >= 0 && parse_layout(j->data, j->filled, &L);
    if (rc >= 0 && !ok && !strcmp(L.why, "sidx-truncated") && head < j->limit) {
        int64_t more = PROBE_BYTES < j->limit ? PROBE_BYTES : j->limit;
        pthread_mutex_lock(&j->lock);
        j->s[0].len = (int)more;
        pthread_mutex_unlock(&j->lock);
        read_slice(j, pb, 0, &cur, &rc);
        ok = rc >= 0 && parse_layout(j->data, j->filled, &L);
    }
    // 阶段 3：按段表决定布局。
    //   0 起点：连续读到「首个分片末尾」，但不越过预算（实测首帧只要分片开头 ~64KiB）。
    //   续播：保留 0 处索引段（~1KiB），其余预算全部压到目标分片，跳过中间几十 MB。
    int64_t idx_len = 0, seg_off = -1, seg_len = 0;
    int picked = -1;
    if (ok && L.idx_end > 0 && L.idx_end <= j->limit) idx_len = L.idx_end;
    if (ok && j->seek_ms > 0 && L.nseg > 0 && L.timescale > 0 && idx_len > 0 && idx_len < j->limit) {
        int64_t target = (int64_t)j->seek_ms * (int64_t)L.timescale / 1000;
        int64_t acc = 0;
        for (int i = 0; i < L.nseg; i++) {
            acc += L.seg[i].dur;
            if (acc > target) { picked = i; break; }
        }
        if (picked < 0) picked = L.nseg - 1;
        if (picked > 0) { seg_off = L.seg[picked].off; seg_len = L.seg[picked].size; }
        if (seg_off > 0 && seg_off < idx_len) seg_off = -1;
    }
    pthread_mutex_lock(&j->lock);
    if (seg_off > 0) {
        int64_t room = j->limit - idx_len;
        if (seg_len <= 0 || seg_len > room) seg_len = room;
        j->s[0].len = (int)idx_len;
        j->s[1].off = seg_off;
        j->s[1].len = (int)seg_len;
        j->s[1].filled = 0;
        j->nslice = 2;
    } else if (ok && L.seg_off + L.seg_size > 0) {
        int64_t end = L.seg_off + L.seg_size;
        if (end > j->limit) end = j->limit;
        if (end > j->s[0].len) j->s[0].len = (int)end;
    }
    // 探测阶段多读的字节落在间隙里，回吐掉，别让 filled 虚高影响接管判断。
    if (j->s[0].filled > j->s[0].len) {
        j->filled -= j->s[0].filled - j->s[0].len;
        j->s[0].filled = j->s[0].len;
    }
    int nslice = j->nslice;
    int l0 = j->s[0].len, l1 = j->nslice > 1 ? j->s[1].len : 0;
    pthread_mutex_unlock(&j->lock);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Prefix",
        "layout src=%{public}s segs=%{public}d idx=%{public}lld seek=%{public}d pick=%{public}d seg_off=%{public}lld seg_size=%{public}lld s0=%{public}d s1=%{public}d",
        L.why, L.segs, (long long)idx_len, j->seek_ms, picked,
        (long long)L.seg_off, (long long)L.seg_size, l0, l1);
    // 阶段 4：把各段读满。
    for (int k = 0; k < nslice && rc >= 0 && pb; k++) read_slice(j, pb, k, &cur, &rc);
    // 自检：第二段开头应该是分片 box（moof/styp/sidx/mdat），否则说明 seek 落错位置。
    if (nslice > 1) {
        pthread_mutex_lock(&j->lock);
        int idx = j->s[0].len, filled = j->s[1].filled;
        int64_t off = j->s[1].off;
        char hdr[5] = {0};
        if (filled >= 8 && idx + 7 < j->limit) memcpy(hdr, j->data + idx + 4, 4);
        pthread_mutex_unlock(&j->lock);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Prefix", "seghdr=%{public}s off=%{public}lld filled=%{public}d",
            hdr, (long long)off, filled);
    }
    pthread_mutex_lock(&j->lock);
    // 读满最后一段才算「可接管」：连接正好停在那一段末尾，播放接着顺序读就是无缝续传。
    // 中途出错或没读够的流，播放侧仍按常规回源，别把一条坏连接递过去。
    Slice *last = j->nslice > 0 ? &j->s[j->nslice - 1] : NULL;
    if (pb && rc >= 0 && last && last->len > 0 && last->filled >= last->len) { j->pb = pb; pb = NULL; }
    int kept = j->pb ? 1 : 0;
    int adopt_at = kept ? (int)(last->off + last->len) : -1;
    j->failed = !kept;
    j->done = 1;
    pthread_cond_broadcast(&j->changed);
    pthread_mutex_unlock(&j->lock);
    if (pb) avio_closep(&pb);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Prefix", "ready bytes=%{public}d slices=%{public}d adopt_at=%{public}d cost=%{public}lldms rc=%{public}d net=%{public}d",
        j->filled, nslice, adopt_at, (long long)((av_gettime_relative()-j->created)/1000), rc, kept);
    // 连接留在任务里等播放接管：任务被 take/discard/换槽时会连 512KB 一起释放，
    // 所以最多只有 4 条（池容量）空闲连接，且 SO_RCVBUF 32KB 已把缓冲量卡死。
    purapily_prefix_release(j); // worker ownership
    return NULL;
}

int purapily_prewarm_async(const char *url, const char *agent, const char *referer, const char *cookie, int bytes, int seek_ms)
{
    if (!url || strncmp(url, "https://", 8) || !agent || !referer || !cookie || bytes <= 0 || bytes > LIMIT) return 0;
    if (strpbrk(agent,"\r\n") || strpbrk(referer,"\r\n") || strpbrk(cookie,"\r\n")) return 0;
    int64_t now = av_gettime_relative();
    int j_seek = seek_ms > 0 ? seek_ms : 0;
    PrefixJob *old[SLOTS] = {0};
    PrefixJob *stale = NULL;
    pthread_mutex_lock(&pool_lock);
    int slot = -1, duplicate = 0;
    for (int i = 0; i < SLOTS; i++) {
        if (pool[i] && now - pool[i]->created >= TTL_US) { old[i] = pool[i]; pool[i] = NULL; }
        if (!pool[i] && slot < 0) slot = i;
        if (pool[i] && same(pool[i],url,agent,referer,cookie,-1)) {
            pthread_mutex_lock(&pool[i]->lock);
            int failed = pool[i]->failed;
            pthread_mutex_unlock(&pool[i]->lock);
            if (pool[i]->seek_ms == j_seek && !failed) {
                duplicate = 1;
            } else {
                // 失败或起点变化时重新预热。
                stale = pool[i]; pool[i] = NULL;
                if (slot < 0) slot = i;
            }
        }
    }
    if (slot < 0 && !duplicate) {
        slot=0;
        for(int i=1;i<SLOTS;i++) if(pool[i]->created<pool[slot]->created) slot=i;
    }
    if (duplicate || slot < 0) {
        pthread_mutex_unlock(&pool_lock);
        for (int i=0;i<SLOTS;i++) retire(old[i]);
        retire(stale);
        return duplicate ? 1 : 0;
    }
#if PURA_PREFIX_QUOTA_PROBE
    int reserved=0, reservation=-1;
    for(int i=0;i<32;i++) {
        if(!reservations[i].at || now-reservations[i].at>=30000000LL) { if(reservation<0) reservation=i; }
        else reserved+=reservations[i].bytes;
    }
    if(reservation<0 || reserved+bytes>1179648) {
        pthread_mutex_unlock(&pool_lock);
        for(int i=0;i<SLOTS;i++) retire(old[i]);
        retire(stale);
        OH_LOG_Print(LOG_APP,LOG_INFO,0,"Prefix","quota reject bytes=%{public}d reserved=%{public}d",bytes,reserved);
        return 0;
    }
#endif
    PrefixJob *j = calloc(1, sizeof(*j));
    if (!j) {
        pthread_mutex_unlock(&pool_lock);
        for (int i=0;i<SLOTS;i++) retire(old[i]);
        retire(stale);
        return 0;
    }
    j->data = av_malloc(bytes);
    j->url = strdup(url); j->agent = strdup(agent); j->referer = strdup(referer); j->cookie = strdup(cookie);
    if (!j->data || !j->url || !j->agent || !j->referer || !j->cookie) {
        av_free(j->data); free(j->url); free(j->agent); free(j->referer); free(j->cookie); free(j);
        pthread_mutex_unlock(&pool_lock);
        for (int i=0;i<SLOTS;i++) retire(old[i]);
        retire(stale);
        return 0;
    }
    pthread_mutex_init(&j->lock,NULL); pthread_cond_init(&j->changed,NULL);
    atomic_init(&j->cancel,0);
    j->refs=2; j->limit=bytes; j->total=-1; j->created=now; j->deadline=now+3000000;
    // 解析完成前先按「0 起点连续 bytes」对外声明，避免读取方误判为无前缀。
    j->nslice=1; j->seek_ms=j_seek;
    j->s[0].off=0; j->s[0].len=bytes; j->s[0].filled=0;
    if(pool[slot]) old[slot]=pool[slot];
    pool[slot]=j;
#if PURA_PREFIX_QUOTA_PROBE
    reservations[reservation].at=now; reservations[reservation].bytes=bytes;
#endif
    pthread_t thread;
    int rc=pthread_create(&thread,NULL,worker,j);
    if (!rc) pthread_detach(thread);
    else pool[slot]=NULL;
    pthread_mutex_unlock(&pool_lock);
    for(int i=0;i<SLOTS;i++) retire(old[i]);
    if (rc) { purapily_prefix_release(j); purapily_prefix_release(j); return 0; }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "Prefix", "reserve bytes=%{public}d rolling_quota=%{public}d", bytes, PURA_PREFIX_QUOTA_PROBE);
    return 1;
}

void *purapily_prefix_take(const char *url, const char *agent, const char *referer, const char *cookie)
{
    PrefixJob *found=NULL;
    pthread_mutex_lock(&pool_lock);
    for(int i=0;i<SLOTS;i++) if(pool[i] && same(pool[i],url,agent,referer,cookie,-1)) {
        found=pool[i]; pool[i]=NULL; break;
    }
    pthread_mutex_unlock(&pool_lock);
    if(found && av_gettime_relative()-found->created >= TTL_US) { retire(found); return NULL; }
    if (found) {
        pthread_mutex_lock(&found->lock);
        int failed = found->failed;
        int filled = found->filled;
        int kept = found->pb != NULL;
        pthread_mutex_unlock(&found->lock);
        if (failed) { retire(found); return NULL; }
        OH_LOG_Print(LOG_APP,LOG_INFO,0,"Prefix",
            "take limit=%{public}d filled=%{public}d net=%{public}d target_ms=%{public}d age_ms=%{public}lld",
            found->limit,filled,kept,found->seek_ms,
            (long long)((av_gettime_relative()-found->created)/1000));
    }
    return found; // transfers pool ownership, including a pending job
}
static void timed_wait(PrefixJob *j)
{
    struct timespec ts; clock_gettime(CLOCK_REALTIME,&ts);
    ts.tv_nsec+=10000000;
    if(ts.tv_nsec>=1000000000) { ts.tv_nsec-=1000000000; ts.tv_sec++; }
    pthread_cond_timedwait(&j->changed,&j->lock,&ts);
}
static int stopped(const AVIOInterruptCB *ic) { return ic && ic->callback && ic->callback(ic->opaque); }
int64_t purapily_prefix_size(void *opaque,const AVIOInterruptCB *ic)
{
    PrefixJob *j=opaque;
    pthread_mutex_lock(&j->lock);
    while(!j->opened && !j->done && !stopped(ic)) timed_wait(j);
    int64_t total=j->total;
    pthread_mutex_unlock(&j->lock);
    return total;
}
int purapily_prefix_read(void *opaque,int64_t offset,uint8_t *buf,int size,const AVIOInterruptCB *ic)
{
    PrefixJob *j=opaque;
    if(!j || offset<0 || size<=0) return AVERROR(ENOSYS);
    pthread_mutex_lock(&j->lock);
    int n=0;
    for(;;) {
        int k=-1;
        for(int i=0;i<j->nslice;i++)
            if(offset>=j->s[i].off && offset<j->s[i].off+j->s[i].len) { k=i; break; }
        if(k<0) break;   // 落在两段之间的间隙或前缀末尾之后
        int base=0;
        for(int i=0;i<k;i++) base+=j->s[i].len;
        int rel=(int)(offset-j->s[k].off);
        if(rel<j->s[k].filled) {
            n=j->s[k].filled-rel;
            if(n>size) n=size;
            memcpy(buf,j->data+base+rel,n);
            break;
        }
        if(j->done || stopped(ic)) break;
        timed_wait(j);
    }
    if(n>0) {
        if(j->served==0) OH_LOG_Print(LOG_APP,LOG_INFO,0,"Prefix","serve first=%{public}d offset=%{public}lld pending=%{public}d",n,(long long)offset,!j->done);
        j->served+=n;
    }
    pthread_mutex_unlock(&j->lock);
    if(stopped(ic)) return AVERROR_EXIT;
    return n>0 ? n : AVERROR(ENOSYS);
}
// 播放期接管：连接停在前缀最后一段末尾，续播时正好是播放要接着读的位置。
// 条件不满足（没读满 / 已被取消 / 位置对不上）就返回 NULL，让调用方常规回源。
AVIOContext *purapily_prefix_adopt(void *opaque,int64_t offset,int64_t *pos)
{
    PrefixJob *j=opaque;
    if(!j || offset<0) return NULL;
    AVIOContext *pb=NULL;
    int64_t at=-1;
    pthread_mutex_lock(&j->lock);
    if(j->pb && j->nslice>0 && !atomic_load(&j->cancel)) {
        Slice *s=&j->s[j->nslice-1];
        if(s->len>0 && s->filled>=s->len && offset==s->off+s->len) {
            pb=j->pb; j->pb=NULL; j->adopted=1; at=s->off+s->len;
            pthread_cond_broadcast(&j->changed);
        }
    }
    pthread_mutex_unlock(&j->lock);
    if(!pb) return NULL;
    if(pos) *pos=at;
    OH_LOG_Print(LOG_APP,LOG_INFO,0,"Prefix","adopt at=%{public}lld",(long long)at);
    return pb;
}
void purapily_prewarm_clear(void)
{
    PrefixJob *old[SLOTS];
    pthread_mutex_lock(&pool_lock);
    for(int i=0;i<SLOTS;i++) { old[i]=pool[i]; pool[i]=NULL; }
    pthread_mutex_unlock(&pool_lock);
    for(int i=0;i<SLOTS;i++) retire(old[i]);
}
// Legacy callers cannot acquire an unbounded GET anymore.
AVIOContext *purapily_take_prewarm(const char *url) { (void)url; return NULL; }

void purapily_prefix_discard(void *opaque)
{
    if(opaque) {
        PrefixJob *j=(PrefixJob *)opaque;
        atomic_store(&j->cancel,1);
        pthread_mutex_lock(&j->lock);
        pthread_cond_broadcast(&j->changed);
        pthread_mutex_unlock(&j->lock);
    }
    purapily_prefix_release(opaque);
}
