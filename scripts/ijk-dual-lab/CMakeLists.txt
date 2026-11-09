cmake_minimum_required(VERSION 3.16)
project(purapily_ijk LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
foreach(required IJK_SOURCE FFMPEG_SOURCE ORIGINAL_LIBS SDL_BASE)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} must be provided")
  endif()
endforeach()
# Incoming paths are Windows-style when configured from cmd/PowerShell; normalise
# so they can be embedded in source lists without tripping over backslash escapes.
foreach(item IJK_SOURCE FFMPEG_SOURCE ORIGINAL_LIBS SDL_BASE)
  file(TO_CMAKE_PATH "${${item}}" ${item})
endforeach()
add_library(purapily_ijk SHARED bridge.c ../ijk_dual_demux_lab.c prewarm.c cache.c prefetch.c player_backend.cpp)
target_compile_definitions(purapily_ijk PRIVATE IJK_NATIVE_MODULE="purapily_ijk")
option(PURA_PREFIX_QUOTA_PROBE "Reproduce removed prefix quota for diagnostics only" OFF)
set(PURA_PROBE_START_MS -1 CACHE STRING "Fixed playback start for controlled device diagnostics")
set(PURA_PROBE_QUEUE_MIB 15 CACHE STRING "Playback queue size for controlled device diagnostics")
set(PURA_PROBE_FRAMEDROP 1 CACHE STRING "Expired frame dropping for controlled device diagnostics")
target_compile_definitions(purapily_ijk PRIVATE PURA_PREFIX_QUOTA_PROBE=$<BOOL:${PURA_PREFIX_QUOTA_PROBE}> PURA_PROBE_START_MS=${PURA_PROBE_START_MS} PURA_PROBE_QUEUE_MIB=${PURA_PROBE_QUEUE_MIB} PURA_PROBE_FRAMEDROP=${PURA_PROBE_FRAMEDROP})
target_include_directories(purapily_ijk PRIVATE "${IJK_SOURCE}" "${FFMPEG_SOURCE}")
target_link_directories(purapily_ijk PRIVATE "${ORIGINAL_LIBS}" "${SDL_BASE}")
target_link_libraries(purapily_ijk PRIVATE ace_napi.z hilog_ndk.z avformat avcodec avutil ijkplayer ijksdl native_window)

# Build the complete ijksdl from the ohos-ijk sources so every SDL symbol — including
# the vout hand-off that submits a decoded frame to the surface — resolves here.
# The prebuilt copy is no longer shipped: leaving it around only created a second,
# -Bsymbolic-bound implementation of the same entry points.
add_library(ijksdl SHARED
    "${IJK_SOURCE}/ijksdl/ijksdl_aout.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_audio.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_error.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_mutex.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_stdinc.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_thread.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_timer.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_vout.c"
    "${IJK_SOURCE}/ijksdl/ijksdl_extra_log.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/color.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/common.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/renderer.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/renderer_rgb.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/renderer_yuv420p.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/renderer_yuv420sp.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/renderer_yuv444p10le.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/shader.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/fsh/rgb.fsh.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/fsh/yuv420p.fsh.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/fsh/yuv420sp.fsh.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/fsh/yuv444p10le.fsh.c"
    "${IJK_SOURCE}/ijksdl/video/gles2/vsh/mvp.vsh.c"
    "${IJK_SOURCE}/ijksdl/video/ijksdl_vout_overlay_ohos_avcodec.c"
    "${IJK_SOURCE}/ijksdl/video/ijksdl_vout_android_surface.c"
    "${IJK_SOURCE}/ijksdl/ffmpeg/ijksdl_vout_overlay_ffmpeg.c"
    "${IJK_SOURCE}/ijksdl/dummy/ijksdl_vout_dummy.c"
    "${IJK_SOURCE}/ijksdl/audio/ijksdl_aout_android_opensles.c"
    "${IJK_SOURCE}/utils/ohoslog/ohos_log.cpp"
    sdl/ijksdl_egl.c sdl/ijksdl_vout_android_nativewindow.c
    sdl/image_convert_stub.c)
target_include_directories(ijksdl PRIVATE "${IJK_SOURCE}/ijksdl" "${IJK_SOURCE}/ijksdl/video" "${IJK_SOURCE}/ijksdl/ffmpeg" "${FFMPEG_SOURCE}")
target_compile_definitions(ijksdl PRIVATE OHOS_PLATFORM)
target_compile_options(ijksdl PRIVATE -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-unused-variable)
target_link_directories(ijksdl PRIVATE "${SDL_BASE}" "${ORIGINAL_LIBS}")
target_link_libraries(ijksdl PRIVATE EGL GLESv3 hilog_ndk.z native_window native_media_vdec deviceinfo_ndk.z ohaudio avcodec avformat avutil swscale swresample z m)
