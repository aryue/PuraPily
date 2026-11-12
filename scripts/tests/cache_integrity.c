// Exercise the production cache against deterministic AVIO inputs and real disk files.
// Link shipped libavutil (CRC, memory, dictionaries); emulate AVIO network/dispatch.
#define _GNU_SOURCE
#define avio_open2 test_net_open
#define avio_closep test_net_close
#ifndef CACHE_UNDER_TEST
#define CACHE_UNDER_TEST "../ijk-dual-lab/cache.c"
#endif
#include CACHE_UNDER_TEST
#include <assert.h>
#include <sys/wait.h>

typedef struct {
    int64_t pos, size;
    int seed, stall;
    AVIOInterruptCB ic;
} TestNet;
static atomic_int opens, cancelled_reads;
static int fail_open;
static int read_failures, read_fault = AVERROR(ETIMEDOUT);
static int64_t remote_size = 512 * 1024 + 123;
AVIOContext *avio_alloc_context(unsigned char *buffer, int size, int write_flag, void *opaque,
    int (*read_packet)(void *, uint8_t *, int), int (*write_packet)(void *, const uint8_t *, int),
    int64_t (*seek)(void *, int64_t, int))
{
    AVIOContext *p = av_mallocz(sizeof(*p));
    p->buffer=buffer; p->buffer_size=size; p->opaque=opaque; p->read_packet=read_packet; p->seek=seek;
    return p;
}
void avio_context_free(AVIOContext **p) { av_freep(p); }
int64_t avio_size(AVIOContext *p) { return p->seek(p->opaque,0,AVSEEK_SIZE); }
int64_t avio_seek(AVIOContext *p,int64_t offset,int whence)
{
    // Match FFmpeg's forward short-seek optimization: consume rather than call
    // the protocol seek while the desired position is within its read window.
    if (whence == SEEK_SET && offset >= p->pos && offset - p->pos <= 512*1024) {
        uint8_t discard[4096];
        while(p->pos < offset) {
            int want=offset-p->pos > sizeof(discard) ? sizeof(discard) : (int)(offset-p->pos);
            int n=p->read_packet(p->opaque,discard,want);
            if(n<=0) return AVERROR(EIO);
            p->pos+=n;
        }
        return offset;
    }
    int64_t pos=p->seek(p->opaque,offset,whence); if(pos>=0) p->pos=pos; return pos;
}
int avio_read(AVIOContext *p,unsigned char *buf,int size)
{
    if (p->error) return p->error;
    if (p->eof_reached) return AVERROR_EOF;
    if (read_failures > 0) {
        read_failures--;
        if (read_fault == AVERROR_EOF) p->eof_reached = 1;
        else p->error = read_fault;
        return read_fault;
    }
    int n=p->read_packet(p->opaque,buf,size); if(n>0) p->pos+=n; return n;
}
static unsigned char expected(int64_t pos, int seed) { return (unsigned char)((pos * 31 + pos / 997 + seed) % 251); }
static int net_read(void *opaque, uint8_t *buf, int size)
{
    TestNet *n = opaque;
    if (n->stall) {
        while (!n->ic.callback(n->ic.opaque)) av_usleep(1000);
        atomic_fetch_add(&cancelled_reads, 1);
        return AVERROR_EXIT;
    }
    if (n->pos >= n->size) return AVERROR_EOF;
    if (size > n->size - n->pos) size = (int)(n->size - n->pos);
    for (int i = 0; i < size; i++) buf[i] = expected(n->pos + i, n->seed);
    n->pos += size;
    return size;
}
static int64_t net_seek(void *opaque, int64_t offset, int whence)
{
    TestNet *n = opaque;
    if (whence == AVSEEK_SIZE) return n->size;
    whence &= ~AVSEEK_FORCE;
    int64_t target = whence == SEEK_SET ? offset : whence == SEEK_CUR ? n->pos + offset : n->size + offset;
    if (target < 0) return AVERROR(EINVAL);
    return n->pos = target;
}
int test_net_open(AVIOContext **pb, const char *url, int flags, const AVIOInterruptCB *ic, AVDictionary **options)
{
    (void)flags;
    opens++;
    if (fail_open) return AVERROR(EIO);
    TestNet *n = av_mallocz(sizeof(*n));
    n->size = remote_size;
    n->seed = strstr(url, "/variant-b/") ? 17 : 3;
    n->stall = strstr(url, "/stall/") != NULL;
    if (ic) n->ic = *ic;
    AVDictionaryEntry *offset = av_dict_get(*options, "offset", NULL, 0);
    n->pos = offset ? strtoll(offset->value, NULL, 10) : 0;
    *pb = avio_alloc_context(av_malloc(4096), 4096, 0, n, net_read, NULL, net_seek);
    assert(*pb);
    // Real ffio_fdopen leaves AVIO pos=0 even when HTTP was opened at offset N.
    (*pb)->seekable = AVIO_SEEKABLE_NORMAL;
    return 0;
}
int test_net_close(AVIOContext **pb)
{
    if (!pb || !*pb) return 0;
    av_free((*pb)->opaque);
    av_freep(&(*pb)->buffer);
    avio_context_free(pb);
    return 0;
}
void *purapily_prefix_take(const char *a,const char *b,const char *c,const char *d) { return NULL; }
int64_t purapily_prefix_size(void *p,const AVIOInterruptCB *ic) { return -1; }
int purapily_prefix_read(void *p,int64_t at,uint8_t *b,int n,const AVIOInterruptCB *ic) { return AVERROR(ENOSYS); }
AVIOContext *purapily_prefix_adopt(void *p,int64_t at,int64_t *pos) { return NULL; }
void purapily_prefix_discard(void *p) {}

static AVIOContext *open_cache(const char *url)
{
    AVIOContext *p = purapily_cache_open(url, "", "agent", "ref", "", NULL);
    assert(p); return p;
}
static void check_read(AVIOContext *p, int64_t at, int size, int seed)
{
    uint8_t *buf = malloc(size);
    assert(cache_seek(p->opaque, at, SEEK_SET) == at);
    assert(cache_read(p->opaque, buf, size) == size);
    for (int i = 0; i < size; i++) assert(buf[i] == expected(at + i, seed));
    free(buf);
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    purapily_cache_set_dir(argv[1]);
    const char *a = "https://one.test/upgcxcode/1/2/variant-a/12-1-30116.m4s?deadline=old";
    const char *renewed = "https://two.test/upgcxcode/1/2/variant-a/12-1-30116.m4s?deadline=new";
    const char *b = "https://one.test/upgcxcode/1/2/variant-b/12-1-30116.m4s?deadline=old";
    assert(resource_hash(a) == resource_hash(renewed));
    assert(resource_hash(a) != resource_hash(b));
    assert(resource_hash("https://a.test/file.m4s") != resource_hash("https://b.test/file.m4s"));
    AVIOContext *range = open_cache("https://range.test/range-origin.m4s");
    check_read(range, CACHE_BLOCK*2, CACHE_BLOCK, 3);
    check_read(range, CACHE_BLOCK*4, CACHE_BLOCK, 3);
    purapily_cache_close(&range);
    puts("PASS: nonzero HTTP Range origin plus forward short-seek writes the correct bytes");
    char bin[768], idx[768];
    cache_paths(a, bin, idx, sizeof(bin));
    AVIOContext *p = open_cache(a);
    check_read(p, 0, CACHE_BLOCK * 3, 3);
    purapily_cache_close(&p);
    int before = opens;
    p = open_cache(renewed);
    check_read(p, 0, CACHE_BLOCK * 3, 3);
    assert(opens == before); // verified disk hits keep the zero-network startup path
    purapily_cache_close(&p);
    puts("PASS: full-path identity, CDN/signature renewal and valid disk reuse");

    // Same-length byte corruption is invisible to stat/pread return values.
    int fd = open(bin, O_RDWR); assert(fd >= 0);
    unsigned char bad = 255; assert(pwrite(fd, &bad, 1, 32000) == 1); close(fd);
    p = open_cache(a); before = opens;
    check_read(p, 31000, 70000, 3);
    assert(opens > before);
    purapily_cache_close(&p);
    before = opens; p = open_cache(a); check_read(p, 0, CACHE_BLOCK, 3);
    assert(opens == before); purapily_cache_close(&p);
    puts("PASS: corrupt cached bytes never escape; repaired block persists");

    p = open_cache(a);
    assert(ftruncate(((CacheCtx *)p->opaque)->fd, 100) == 0);
    check_read(p, 300, 1000, 3); // truncate while handle is live
    purapily_cache_close(&p);
    p = open_cache(a); check_read(p, CACHE_BLOCK * 2 + 5, 8000, 3);
    purapily_cache_close(&p);
    puts("PASS: live short read and truncated file reopen recover through network");

    p = open_cache(a);
    AVIOContext *other = open_cache(renewed);
    assert(((CacheCtx *)other->opaque)->fd < 0);
    check_read(other, 0, 1234, 3);
    check_read(p, 0, 1234, 3);
    purapily_cache_close(&other);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
        other = open_cache(a);
        assert(((CacheCtx *)other->opaque)->fd < 0);
        check_read(other, 77, 555, 3); purapily_cache_close(&other); _exit(0);
    }
    int status; assert(waitpid(child, &status, 0) == child && status == 0);
    purapily_cache_close(&p);
    p = open_cache(a); assert(((CacheCtx *)p->opaque)->fd >= 0); purapily_cache_close(&p);
    puts("PASS: same-process and cross-process writer exclusion; busy handles play without waiting");

    p = open_cache(b); check_read(p, 0, 12345, 17); purapily_cache_close(&p);
    p = open_cache(a); check_read(p, 0, 12345, 3); purapily_cache_close(&p);
    puts("PASS: same filename in another encoding path cannot poison the first resource");

    // Legacy indexes have no checksum and must never make old bytes trusted.
    fd = open(idx, O_RDWR); assert(fd >= 0); assert(pwrite(fd, "PDC2", 4, 0) == 4); close(fd);
    p = open_cache(a); before = opens; check_read(p, 0, CACHE_BLOCK, 3);
    assert(opens > before); purapily_cache_close(&p);
    // An interrupted .tmp publication doesn't replace the complete index.
    char tmp[800]; snprintf(tmp, sizeof(tmp), "%s.interrupted.tmp", idx);
    fd = open(tmp, O_WRONLY|O_CREAT|O_TRUNC,0600); assert(fd >= 0); assert(write(fd,IDX_MAGIC,4)==4); close(fd);
    p = open_cache(a); before = opens; check_read(p, 0, 100, 3); assert(opens == before);
    purapily_cache_close(&p); unlink(tmp);
    puts("PASS: unverified legacy indexes discarded; incomplete temp index not published");

    fd = open(bin,O_RDWR); assert(fd >= 0); assert(pwrite(fd,&bad,1,1)==1);close(fd);
    p = open_cache(a); fail_open = 1;
    uint8_t buf[100]; memset(buf, 254, sizeof(buf));
    assert(cache_read(p->opaque,buf,sizeof(buf)) < 0);
    for(int i=0;i<sizeof(buf);i++) assert(buf[i]==254);
    fail_open = 0; check_read(p, 0, sizeof(buf), 3); purapily_cache_close(&p);
    puts("PASS: failed repair propagates an error without returning bad bytes, later retry works");

    p = open_cache(a);
    ((CacheCtx *)p->opaque)->total = remote_size + 100;
    ((CacheCtx *)p->opaque)->dirty = 1;
    assert(unlink(bin) == 0 && unlink(idx) == 0);
    other = open_cache(a); check_read(other, 0, 100, 3); purapily_cache_close(&other);
    purapily_cache_close(&p); // old inode must not publish its stale total/index
    p = open_cache(a); assert(avio_size(p) == remote_size);
    purapily_cache_close(&p);
    puts("PASS: clearing/replacing live files cannot let an old owner publish into the new generation");

    p = open_cache(a);
    assert(ftruncate(((CacheCtx *)p->opaque)->fd,CACHE_TOTAL_MAX+1)==0);
    g_evicted_at = 0; evict_if_needed(); assert(access(bin,F_OK)==0);
    assert(ftruncate(((CacheCtx *)p->opaque)->fd,CACHE_BLOCK)==0);
    purapily_cache_close(&p);
    puts("PASS: eviction skips active cache owner");
    // Production AVIO keeps error/eof sticky until the connection is replaced.
    p = open_cache("https://recovery.test/cached.m4s");
    read_failures = 1;
    check_read(p, CACHE_BLOCK * 2 + 13, CACHE_BLOCK + 17, 3);
    purapily_cache_close(&p);
    puts("PASS: cached reads reopen a latched timeout at the exact unread offset");
    purapily_cache_set_dir(NULL);
    p = purapily_cache_open(a, renewed, "agent", "ref", "", NULL);
    assert(avio_size(p) == remote_size);
    read_failures = 2;
    check_read(p, 77531, 1000, 3);
    assert(((CacheCtx *)p->opaque)->using_backup);
    purapily_cache_close(&p);
    puts("PASS: direct playback retries are bounded and fail over without skipping bytes");
    p = open_cache(a);
    read_failures = 1; read_fault = AVERROR_EOF;
    check_read(p, 90001, 1000, 3);
    CacheCtx *ctx = p->opaque;
    before = opens;
    assert(cache_seek(ctx, remote_size, SEEK_SET) == remote_size);
    assert(cache_read(ctx, buf, sizeof(buf)) == AVERROR_EOF);
    assert(opens <= before + 1); // EOF verification may open once, never recovery-loop
    purapily_cache_close(&p);
    puts("PASS: premature EOF recovers; true EOF does not reconnect");
    p = open_cache(a); before = opens;
    read_fault = AVERROR(ETIMEDOUT); read_failures = 10;
    assert(cache_read(p->opaque, buf, sizeof(buf)) == read_fault);
    assert(opens - before == 3); // initial stream plus two recovery attempts
    read_failures = 0;
    purapily_cache_close(&p);
    p = purapily_cache_open(a, renewed, "agent", "ref", "", NULL);
    assert(avio_size(p) == remote_size);
    ctx = p->opaque;
    purapily_cache_set_bandwidth(p, 20000000);
    record_network_read(ctx, 1000000, av_gettime_relative() - 4000000);
    assert(ctx->slow_source);
    check_read(p, 0, 1000, 3);
    assert(ctx->using_backup);
    purapily_cache_close(&p);
    p = purapily_cache_open(a, renewed, "agent", "ref", "", NULL);
    assert(avio_size(p) == remote_size);
    ctx = p->opaque;
    purapily_cache_set_bandwidth(p, 20000000);
    record_network_read(ctx, 12000000, av_gettime_relative() - 4000000);
    assert(!ctx->slow_source);
    read_failures = 1; read_fault = AVERROR_EXIT; before = opens;
    assert(cache_read(ctx, buf, sizeof(buf)) == AVERROR_EXIT);
    assert(opens == before);
    read_failures = 0;
    purapily_cache_close(&p);
    puts("PASS: sustained slow source switches once; healthy reads and cancellation do not");

    before = opens;
    p = purapily_cache_open(a, renewed, "agent", "ref", "", NULL);
    assert(opens == before);
    assert(avio_size(p) == remote_size);
    ctx = p->opaque;
    assert(!ctx->using_backup && ctx->total == remote_size);
    check_read(p, 0, 1000, 3);
    assert(opens - before == 1);
    purapily_cache_close(&p);
    puts("PASS: fast cold startup reads from the connection that discovered the length");

    before = opens;
    p = purapily_cache_open("https://startup.test/stall/track.m4s", renewed, "agent", "ref", "", NULL);
    assert(opens == before);
    assert(avio_size(p) == remote_size);
    ctx = p->opaque;
    assert(ctx->using_backup && ctx->total == remote_size);
    assert(cancelled_reads == 1);
    check_read(p, 0, 1000, 3);
    check_read(p, 73000, 1000, 3);
    assert(opens - before == 2);
    purapily_cache_close(&p);
    puts("PASS: stalled primary body is cancelled; backup serves exact bytes and seek");
    puts("ALL CACHE INTEGRITY TESTS PASSED");
    return 0;
}
