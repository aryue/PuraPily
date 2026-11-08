/*
 * Minimal replacement for ijkplayer's ijksoundtouch_wrap.h.
 *
 * The published OHOS ijkplayer source drop ships ff_ffplay.c calling into a
 * soundtouch wrapper whose files are missing from the tree, while the shipped
 * libijkplayer.so has SoundTouch statically linked. Rebuilt kernels therefore
 * need this shim plus a SoundTouch static library.
 */
#ifndef IJK_SOUNDTOUCH_WRAP_H
#define IJK_SOUNDTOUCH_WRAP_H

#ifdef __cplusplus
extern "C" {
#endif

void *ijk_soundtouch_create(void);
void ijk_soundtouch_destroy(void *handle);

/*
 * Resample `samples` int16 samples (interleaved, n_channel channels) in place.
 * `rate` is the pitch ratio, `tempo` the time ratio. Returns the number of
 * bytes written to `data` (0 when SoundTouch still needs more input).
 */
int ijk_soundtouch_translate(void *handle, short *data, float rate, float tempo,
    int samples, int bytes_per_sample, int n_channel, int sample_rate);

#ifdef __cplusplus
}
#endif

#endif /* IJK_SOUNDTOUCH_WRAP_H */
