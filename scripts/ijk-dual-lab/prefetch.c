#include <stddef.h>
extern int purapily_prewarm_async(const char *,const char *,const char *,const char *,int);
int purapily_prefetch_head_async(const char *dir,const char *url,const char *agent,const char *referer,const char *cookie)
{
    (void)dir;
    return purapily_prewarm_async(url,agent?agent:"Mozilla/5.0",referer?referer:"",cookie?cookie:"",65536);
}
