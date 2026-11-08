#include "ijksoundtouch_wrap.h"

#include "SoundTouch.h"

using soundtouch::SoundTouch;
using soundtouch::SAMPLETYPE;

extern "C" {

void *ijk_soundtouch_create(void)
{
    SoundTouch *handle = new SoundTouch();
    handle->setChannels(2);
    handle->setSampleRate(44100);
    handle->setRate(1.0f);
    handle->setTempo(1.0f);
    return handle;
}

void ijk_soundtouch_destroy(void *handle)
{
    delete static_cast<SoundTouch *>(handle);
}

int ijk_soundtouch_translate(void *handle, short *data, float rate, float tempo,
    int samples, int bytes_per_sample, int n_channel, int sample_rate)
{
    if (!handle || !data || samples <= 0 || n_channel <= 0 || bytes_per_sample != 2)
        return -1;

    SoundTouch *soundtouch = static_cast<SoundTouch *>(handle);
    soundtouch->setSampleRate(sample_rate);
    soundtouch->setChannels(n_channel);
    soundtouch->setRate(rate);
    soundtouch->setTempo(tempo);

    const int frames = samples / n_channel;
    soundtouch->putSamples(reinterpret_cast<const SAMPLETYPE *>(data), frames);
    const int produced = soundtouch->receiveSamples(reinterpret_cast<SAMPLETYPE *>(data), frames);
    return produced * n_channel * bytes_per_sample;
}

} // extern "C"
