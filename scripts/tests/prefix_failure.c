// Run the production worker with failed/cancelled HTTP and active diagnostic logging.
// Compile with -ftrivial-auto-var-init=pattern to expose skipped initialization.
#define _GNU_SOURCE
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int test_log(int type, int level, unsigned int domain, const char *tag, const char *format, ...);
#define OH_LOG_Print test_log
#include "../ijk-dual-lab/prewarm.c"

static int mode, reads, layouts, closes;
enum { OPEN_ERROR, READ_ERROR, CANCELLED_READ, PARTIAL_ERROR, NO_INDEX };

int64_t av_gettime_relative(void) { return 50000000; }
int avformat_network_init(void) { return 0; }
int av_dict_set(AVDictionary **o, const char *k, const char *v, int f) { return 0; }
int av_dict_set_int(AVDictionary **o, const char *k, int64_t v, int f) { return 0; }
void av_dict_free(AVDictionary **o) { *o = NULL; }
int avio_open2(AVIOContext **p, const char *url, int flags, const AVIOInterruptCB *ic, AVDictionary **o) {
    if (mode == OPEN_ERROR) return AVERROR(EIO);
    *p = calloc(1, sizeof(**p));
    return 0;
}
int64_t avio_size(AVIOContext *p) { return 65536; }
int64_t avio_seek(AVIOContext *p, int64_t at, int whence) { return p->pos = at; }
int avio_read(AVIOContext *p, unsigned char *b, int n) {
    reads++;
    if (mode == CANCELLED_READ) return AVERROR_EXIT;
    if (mode == READ_ERROR || (mode == PARTIAL_ERROR && reads > 1)) return AVERROR(EIO);
    if (mode == PARTIAL_ERROR && n > 4) n = 4;
    memset(b, 0, n); p->pos += n;
    return n;
}
void avio_closep(AVIOContext **p) { free(*p); *p = NULL; closes++; }
static int test_log(int type, int level, unsigned int domain, const char *tag, const char *format, ...) {
    if (strncmp(format, "layout src=", 11)) return 0;
    va_list args; va_start(args, format);
    const char *why = va_arg(args, const char *);
    // The real HiLog encoder calls strlen() here. The old worker passes stack garbage.
    assert(!strcmp(why, mode == NO_INDEX ? "no-sidx" : "read-error"));
    assert(va_arg(args, int) == 0); // segs
    assert(va_arg(args, long long) == 0); // idx
    assert(va_arg(args, int) == 0); // seek
    assert(va_arg(args, int) == -1); // picked
    assert(va_arg(args, long long) == 0); // seg_off
    assert(va_arg(args, long long) == 0); // seg_size
    va_end(args); layouts++;
    return 0;
}
int main(void) {
    for (int repeat = 0; repeat < 100; repeat++) {
        for (mode = OPEN_ERROR; mode <= NO_INDEX; mode++) {
            PrefixJob *j = calloc(1, sizeof(*j));
            pthread_mutex_init(&j->lock, NULL); pthread_cond_init(&j->changed, NULL);
            atomic_init(&j->cancel, 0);
            j->refs = 1; j->limit = 8192; j->data = malloc(j->limit);
            j->url = strdup("https://prefix.test/failure"); j->agent = strdup("test");
            j->referer = strdup(""); j->cookie = strdup("");
            j->created = av_gettime_relative(); j->deadline = j->created + TTL_US;
            reads = 0; worker(j);
        }
    }
    assert(layouts == 500 && closes == 400);
    puts("PASS: 500 production-worker cases: open/read failure, cancellation, partial failure and no-index success with logging enabled.");
    return 0;
}
