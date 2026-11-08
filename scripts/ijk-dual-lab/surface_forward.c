#include "ijksdl_vout.h"
#include "video/ijksdl_vout_android_nativewindow.h"
SDL_Vout *SDL_VoutAndroid_CreateForAndroidSurface(void) { return SDL_VoutAndroid_CreateForANativeWindow(); }
void SDL_VoutAndroid_SetAndroidSurface(SDL_Vout *vout, void *window) { SDL_VoutAndroid_SetNativeWindow(vout, window); }
