cmake_minimum_required(VERSION 3.5)

# Rebuilds libijkplayer.so from the OHOS ijkplayer source drop so the video
# pacing loop can be changed. The prebuilt kernel is 10 ms tick based, which
# caps 120 fps content near 90 fps.
project(ijkplayer_kernel LANGUAGES C CXX)

foreach(required IJK_SOURCE FFMPEG_INCLUDE SOUNDTOUCH_SOURCE IJKSDL_LIB PREBUILT_LIBS)
  if(NOT DEFINED ${required})
    message(FATAL_ERROR "${required} must be provided")
  endif()
endforeach()

# Paths arrive Windows-style when configured from cmd/PowerShell; normalise so
# they can be embedded in source lists without backslash escapes.
foreach(item IJK_SOURCE FFMPEG_INCLUDE SOUNDTOUCH_SOURCE IJKSDL_LIB PREBUILT_LIBS)
  file(TO_CMAKE_PATH "${${item}}" ${item})
endforeach()

set(KERNEL_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(IJK_CORE ${IJK_SOURCE}/ijkplayer)
set(SOUNDTOUCH_INCLUDE ${SOUNDTOUCH_SOURCE}/include)

add_library(soundtouch STATIC
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/AAFilter.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/BPMDetect.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/FIFOSampleBuffer.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/FIRFilter.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/InterpolateCubic.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/InterpolateLinear.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/InterpolateShannon.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/PeakFinder.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/RateTransposer.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/SoundTouch.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/TDStretch.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/cpu_detect_x86.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/mmx_optimized.cpp
    ${SOUNDTOUCH_SOURCE}/source/SoundTouch/sse_optimized.cpp
)
target_include_directories(soundtouch PUBLIC ${SOUNDTOUCH_INCLUDE})
target_compile_options(soundtouch PRIVATE -O2 -fPIC -w)
# The shipped kernel used 16-bit samples; float samples would both change the ABI
# and make ijk_soundtouch_translate cast short buffers to float.
target_compile_definitions(soundtouch PUBLIC SOUNDTOUCH_INTEGER_SAMPLES)

# The published tree keeps ijkavformat/ijkavutil/record inside ijkplayer/ and
# carries no ijksoundtouch_wrap.*, so the wrapper lives in this directory.
add_library(ijkplayer SHARED
    ${IJK_CORE}/ff_cmdutils.c
    ${IJK_CORE}/ff_ffpipeline.c
    ${IJK_CORE}/ff_ffpipenode.c
    ${IJK_CORE}/ff_ffplay.c
    ${IJK_CORE}/ijkmeta.c
    ${IJK_CORE}/ijkplayer.c
    ${IJK_CORE}/ijkplayer_android.c
    ${IJK_CORE}/pipeline/ffpipenode_ffplay_vdec.c
    ${IJK_CORE}/pipeline/ffpipeline_android.c
    ${IJK_CORE}/ijkavformat/allformats.c
    ${IJK_CORE}/ijkavformat/ijkio.c
    ${IJK_CORE}/ijkavformat/ijkioapplication.c
    ${IJK_CORE}/ijkavformat/ijkiocache.c
    ${IJK_CORE}/ijkavformat/ijkioffio.c
    ${IJK_CORE}/ijkavformat/ijkiomanager.c
    ${IJK_CORE}/ijkavformat/ijkioprotocol.c
    ${IJK_CORE}/ijkavformat/ijkiourlhook.c
    ${IJK_CORE}/ijkavformat/ijkurlhook.c
    ${IJK_CORE}/ijkavutil/ijkstl.cpp
    ${IJK_CORE}/ijkavutil/ijkthreadpool.c
    ${IJK_CORE}/record/ijkplayer_record.cpp
    ${KERNEL_DIR}/ijksoundtouch_wrap.cpp
)

target_include_directories(ijkplayer PRIVATE
    ${KERNEL_DIR}
    ${IJK_SOURCE}
    ${IJK_CORE}
    ${IJK_SOURCE}/ijksdl
    ${FFMPEG_INCLUDE}
    ${SOUNDTOUCH_INCLUDE}
)

target_compile_definitions(ijkplayer PRIVATE OHOS_PLATFORM)
target_compile_options(ijkplayer PRIVATE -O2 -Wno-int-conversion -Wno-incompatible-pointer-types)

add_library(ijksdl SHARED IMPORTED)
set_target_properties(ijksdl PROPERTIES IMPORTED_LOCATION ${IJKSDL_LIB})

target_link_directories(ijkplayer PRIVATE ${PREBUILT_LIBS})
target_link_libraries(ijkplayer PRIVATE
    ijksdl
    soundtouch
    EGL GLESv3
    hilog_ndk.z deviceinfo_ndk.z
    z
    avcodec avfilter avformat avutil swresample swscale
    native_media_codecbase native_media_core native_media_vdec native_media_venc
    native_window native_buffer
)
