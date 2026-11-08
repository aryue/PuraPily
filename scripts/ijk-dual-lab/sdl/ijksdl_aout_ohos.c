// Observe the shipped OHAudio backend without depending on private FFPlayer layouts.
#include "ijksdl_aout.h"
#include <libavutil/time.h>
#include <hilog/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct FFPlayer FFPlayer;
typedef struct AudioProbe {
    SDL_Aout *aout;
    int (*open)(SDL_Aout *,const SDL_AudioSpec *,SDL_AudioSpec *);
    void (*free)(SDL_Aout *);
    SDL_AudioCallback callback;
    void *userdata;
    int rate, channels;
    int64_t last, at, bytes, silent, gap, cost;
    struct AudioProbe *next;
} AudioProbe;
static pthread_mutex_t probes_lock = PTHREAD_MUTEX_INITIALIZER;
static AudioProbe *probes;
static AudioProbe *find_probe(SDL_Aout *aout) {
    pthread_mutex_lock(&probes_lock);
    AudioProbe *p=probes;
    while(p && p->aout!=aout) p=p->next;
    pthread_mutex_unlock(&probes_lock);
    return p;
}
static void callback(void *userdata,uint8_t *buffer,int len) {
    AudioProbe *p=userdata;
    int64_t now=av_gettime_relative(), gap=p->at?now-p->at:0;
    p->at=now;
    if(gap>p->gap) p->gap=gap;
    p->callback(p->userdata,buffer,len);
    int64_t cost=av_gettime_relative()-now;
    if(cost>p->cost) p->cost=cost;
    p->bytes+=len;
    int silent=1;
    for(int i=0;i<len;i++) if(buffer[i]) {silent=0;break;}
    if(silent) p->silent+=len;
    if(now-p->last>=1000000) {
        double latency=p->aout->func_get_latency_seconds ? p->aout->func_get_latency_seconds(p->aout):0;
        OH_LOG_Print(LOG_APP,LOG_INFO,0,"AudioClock",
            "callback bytes=%{public}lld silent=%{public}lld gap_us=%{public}lld cost_us=%{public}lld latency_us=%{public}lld block=%{public}d rate=%{public}d channels=%{public}d",
            (long long)p->bytes,(long long)p->silent,(long long)p->gap,(long long)p->cost,
            (long long)(latency*1000000),len,p->rate,p->channels);
        p->last=now;p->bytes=p->silent=p->gap=p->cost=0;
    }
}
static int open_audio(SDL_Aout *aout,const SDL_AudioSpec *desired,SDL_AudioSpec *obtained) {
    AudioProbe *p=find_probe(aout);
    if(!p) return -1;
    p->callback=desired->callback;p->userdata=desired->userdata;
    p->rate=desired->freq;p->channels=desired->channels;
    SDL_AudioSpec observed=*desired;
    observed.callback=callback;observed.userdata=p;
    return p->open(aout,&observed,obtained);
}
static void free_audio(SDL_Aout *aout) {
    AudioProbe *p=find_probe(aout);
    if(!p) return;
    p->free(aout);
    pthread_mutex_lock(&probes_lock);
    AudioProbe **link=&probes;
    while(*link && *link!=p) link=&(*link)->next;
    if(*link) *link=p->next;
    pthread_mutex_unlock(&probes_lock);
    free(p);
}
SDL_Aout *SDLAoutCreateForOpenSLES(FFPlayer *ffp) {
    void *library=dlopen("libijksdx.so",RTLD_NOW|RTLD_LOCAL);
    SDL_Aout *(*create)(FFPlayer *)=library?dlsym(library,"SDLAoutCreateForOpenSLES"):NULL;
    if(!create) return NULL;
    SDL_Aout *aout=create(ffp);
    if(!aout) return NULL;
    AudioProbe *p=calloc(1,sizeof(*p));
    if(!p) {aout->free_l(aout);return NULL;}
    p->aout=aout;p->open=aout->open_audio;p->free=aout->free_l;
    pthread_mutex_lock(&probes_lock);
    p->next=probes;probes=p;
    pthread_mutex_unlock(&probes_lock);
    aout->open_audio=open_audio;aout->free_l=free_audio;
    return aout;
}
