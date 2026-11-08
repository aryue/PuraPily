// Host-side check for the rebuilt kernel's SoundTouch wrapper.
// Compiles the same sources as the OHOS build (integer 16-bit samples).
#include <cmath>
#include <cstdio>
#include <vector>

#include "ijksoundtouch_wrap.h"

static double RunCase(float speed, int frames)
{
    const int channels = 2;
    void *handle = ijk_soundtouch_create();
    std::vector<short> buffer(frames * channels);
    for (int i = 0; i < frames; ++i) {
        const short sample = (short)(12000.0 * sin(2.0 * M_PI * 440.0 * i / 48000.0));
        buffer[i * 2] = sample;
        buffer[i * 2 + 1] = sample;
    }

    int produced = 0;
    int calls = 0;
    const int chunk = 1024; // frames per call
    for (int offset = 0; offset + chunk <= frames; offset += chunk) {
        std::vector<short> block(buffer.begin() + offset * channels,
            buffer.begin() + (offset + chunk) * channels);
        const int bytes = ijk_soundtouch_translate(handle, block.data(), speed, 1.0f / speed,
            chunk * channels, 2, channels, 48000);
        ++calls;
        if (bytes > 0) produced += bytes / (2 * channels);
    }

    // Drain whatever the stretcher still holds.
    std::vector<short> tail(8192 * channels);
    for (int i = 0; i < 8; ++i) {
        const int bytes = ijk_soundtouch_translate(handle, tail.data(), speed, 1.0f / speed,
            1024 * channels, 2, channels, 48000);
        if (bytes <= 0) break;
        produced += bytes / (2 * channels);
    }
    ijk_soundtouch_destroy(handle);
    printf("speed=%.2f calls=%d in=%d produced=%d ratio=%.3f\n",
        speed, calls, frames, produced, (double)produced / frames);
    return (double)produced / frames;
}

int main()
{
    const int frames = 48000; // one second of stereo audio
    const double normal = RunCase(1.0f, frames);
    const double fast = RunCase(1.5f, frames);
    const double slow = RunCase(0.5f, frames);
    const bool ok = normal > 0.9 && normal < 1.15 && fast > 0.5 && fast < 1.15 && slow > 0.45 && slow < 1.15;
    printf("RESULT %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
