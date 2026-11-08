// Runs the actual production pool with deterministic fake HTTP; no network bytes.
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdatomic.h>
#include "../ijk-dual-lab/prewarm.c"
static atomic_llong clock_us=50000000;
static atomic_int hold_reads, opens, live, fail_open;
int64_t av_gettime_relative(void) { return atomic_load(&clock_us); }
int avformat_network_init(void) { return 0; }
int av_dict_set_int(AVDictionary **o,const char *k,int64_t v,int f) {
    (void)f; if(!*o) *o=calloc(1,sizeof(**o));
    if(!strcmp(k,"end_offset")) (*o)->end=v;
    if(!strcmp(k,"offset")) (*o)->offset=v;
    return 0;
}
int av_dict_set(AVDictionary **o,const char *k,const char *v,int f) {
    av_dict_set_int(o,k,0,f);
    if(!strcmp(k,"recv_buffer_size")) (*o)->recv=atoi(v);
    if(!strcmp(k,"reconnect")) assert(!strcmp(v,"0"));
    return 0;
}
void av_dict_free(AVDictionary **o) { free(*o); *o=NULL; }
int avio_open2(AVIOContext **p,const char *url,int flags,const AVIOInterruptCB *ic,AVDictionary **o) {
    (void)url; (void)flags;
    assert((*o)->offset==0 && (*o)->end>0 && (*o)->end<=LIMIT && (*o)->recv==32768);
    atomic_fetch_add(&opens,1);
    if(atomic_load(&fail_open)) return -5;
    *p=calloc(1,sizeof(**p)); (*p)->limit=(*o)->end; (*p)->ic=*ic;
    atomic_fetch_add(&live,1); return 0;
}
int64_t avio_size(AVIOContext *p) { (void)p; return 2*1024*1024; }
int avio_read(AVIOContext *p,unsigned char *b,int n) {
    while(atomic_load(&hold_reads)) { if(p->ic.callback(p->ic.opaque)) return AVERROR_EXIT; usleep(1000); }
    if(n>p->limit-p->pos) n=p->limit-p->pos;
    for(int i=0;i<n;i++) b[i]=(unsigned char)((p->pos+i)%251);
    p->pos+=n; return n;
}
void avio_closep(AVIOContext **p) { free(*p); *p=NULL; atomic_fetch_sub(&live,1); }
static void wait_for(atomic_int *v,int target) {
    for(int i=0;i<2000 && atomic_load(v)!=target;i++) usleep(1000);
    assert(atomic_load(v)==target);
}
static int start(const char *u,int n) { return purapily_prewarm_async(u,"agent","ref","cookie",n); }
int main(void) {
    const char *u="https://prefix.test/upgcxcode/1/2/12-1-30066.m4s?sig=old";
    const char *renewed="https://other-cdn.test/upgcxcode/1/2/12-1-30066.m4s?sig=new";
    atomic_store(&hold_reads,1);
    assert(start(u,512*1024)==1);
    assert(start(renewed,512*1024)==1);
    wait_for(&opens,1);
    void *j=purapily_prefix_take(renewed,"agent","ref","cookie");
    assert(j && purapily_prefix_size(j,NULL)==2*1024*1024);
    atomic_store(&hold_reads,0);
    unsigned char data[65536]; int pos=0;
    while(pos<512*1024) {
        int n=purapily_prefix_read(j,pos,data,sizeof(data),NULL); assert(n>0);
        for(int k=0;k<n;k++) assert(data[k]==(unsigned char)((pos+k)%251));
        pos+=n;
    }
    assert(purapily_prefix_read(j,pos,data,sizeof(data),NULL)==AVERROR(ENOSYS));
    purapily_prefix_discard(j); wait_for(&live,0);
    assert(atomic_load(&opens)==1); // pending consumer used the same request
    assert(start("https://prefix.test/a1",64*1024)==1);
    assert(start("https://prefix.test/v2",512*1024)==1);
    assert(start("https://prefix.test/a2",64*1024)==1);
    assert(purapily_prefix_take("https://prefix.test/v2","agent","ref","other-account")==NULL);
    j=purapily_prefix_take("https://prefix.test/a1","agent","ref","cookie"); assert(j); purapily_prefix_discard(j);
    assert(start("https://prefix.test/a1",64*1024)==1); // no rolling-window reservation survives consumption
    for(int i=0;i<40;i++) { char url[80]; snprintf(url,sizeof(url),"https://prefix.test/repeat-%d",i); assert(start(url,65536)==1); }
    atomic_store(&clock_us,79000000); assert(start("https://prefix.test/extra",1)==1);
    atomic_store(&clock_us,81000000); assert(start("https://prefix.test/extra",64*1024)==1);
    atomic_store(&clock_us,150000000); // expired jobs cannot be handed over
    assert(purapily_prefix_take("https://prefix.test/v2","agent","ref","cookie")==NULL);
    purapily_prewarm_clear(); wait_for(&live,0);
    atomic_store(&clock_us,200000000); atomic_store(&fail_open,1);
    for(int i=0;i<18;i++) { char url[80]; snprintf(url,sizeof(url),"https://prefix.test/fail-%d",i); assert(start(url,65536)==1); }
    assert(start("https://prefix.test/fail-extra",1)==1); // no failure-based rolling quota remains
    usleep(100000); purapily_prewarm_clear();
    puts("PASS native prefix: pending handoff, exact bytes, range/receive limits, no rolling quota, credentials, expiry");
    return 0;
}
