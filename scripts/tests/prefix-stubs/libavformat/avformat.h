#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct { int (*callback)(void *); void *opaque; } AVIOInterruptCB;
typedef struct { int64_t end; int offset, recv; } AVDictionary;
typedef struct { int pos, limit; AVIOInterruptCB ic; } AVIOContext;
#define AVIO_FLAG_READ 1
int avformat_network_init(void);
int av_dict_set(AVDictionary **,const char *,const char *,int);
int av_dict_set_int(AVDictionary **,const char *,int64_t,int);
void av_dict_free(AVDictionary **);
int avio_open2(AVIOContext **,const char *,int,const AVIOInterruptCB *,AVDictionary **);
int64_t avio_size(AVIOContext *);
int64_t avio_seek(AVIOContext *,int64_t,int);
int avio_read(AVIOContext *,unsigned char *,int);
void avio_closep(AVIOContext **);
