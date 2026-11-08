// Experimental FFmpeg 8 input format for one IJK instance. Register only in
// the isolated lab process: avpriv_register_devices replaces the device lists.
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <libavformat/demux.h>
#include <libavutil/avstring.h>
#include <libavutil/mathematics.h>
#include <libavutil/time.h>
#include <hilog/log.h>
#include <pthread.h>

// HAR 2.0.13 uses ohos_ffmpeg ohos-n8.0 (69c05840), whose private input
// format has a second header callback. Building against upstream shifts
// read_packet into read_header2's slot and crashes before either track opens.
_Static_assert(offsetof(FFInputFormat, read_header2) == 88 &&
               offsetof(FFInputFormat, read_packet) == 96, "requires the 64-bit OHOS fork");

typedef struct {
    AVFormatContext *input;
    AVIOContext *io;
    int io_cached;
    AVStream *stream;
    AVPacket *packet;
    int ready;
    int eof;
} InputTrack;

extern AVIOContext *purapily_take_prewarm(const char *url);
extern AVIOContext *purapily_cache_open(const char *url, const char *backup, const char *agent,
                                        const char *referer, const char *cookie,
                                        const AVIOInterruptCB *ic);
extern void purapily_cache_close(AVIOContext **pb);
extern void purapily_cache_set_bandwidth(AVIOContext *pb, int64_t bps);

typedef struct {
    InputTrack *track;
    const char *url;
    const char *backup;
    int64_t bandwidth;
    enum AVMediaType type;
    const char *agent;
    const char *referer;
    const char *cookie;
    AVIOInterruptCB ic;
    int rc;
} FetchJob;

typedef struct {
    InputTrack tracks[2];
    FetchJob jobs[2];
    int terminal_error;
    int64_t bytes[2];
    int64_t opened_at;
    int64_t logged_at;
} DualInput;

static int fetch_track(InputTrack *track, const char *url, const char *backup,
                       enum AVMediaType type, const char *agent, const char *referer,
                       const char *cookie, const AVIOInterruptCB *ic);

static void *fetch_thread(void *arg)
{
    FetchJob *job = (FetchJob *)arg;
    job->rc = fetch_track(job->track, job->url, job->backup, job->type,
                          job->agent, job->referer, job->cookie, &job->ic);
    if (job->rc >= 0 && job->track->io_cached)
        purapily_cache_set_bandwidth(job->track->io, job->bandwidth);
    return NULL;
}

static AVDictionary *track_options(const char *agent, const char *referer, const char *cookie)
{
    AVDictionary *options = NULL;
    av_dict_set(&options, "protocol_whitelist", "https,http,tls,tcp", 0);
    av_dict_set(&options, "user_agent", agent, 0);
    if (referer[0]) av_dict_set(&options, "referer", referer, 0);
    if (cookie[0]) {
        char header[16400];
        snprintf(header, sizeof(header), "Cookie: %s\r\n", cookie);
        av_dict_set(&options, "headers", header, 0);
    }
    av_dict_set(&options, "rw_timeout", "8000000", 0);
    // CDN/PCDN 会在空闲或超时后关连接，ffmpeg 默认把这当成「流结束」，
    // 上层就会收到 null packet 并停住。打开重连：按当前 offset 重新发 Range。
    av_dict_set(&options, "reconnect", "1", 0);
    av_dict_set(&options, "reconnect_streamed", "1", 0);
    av_dict_set(&options, "reconnect_on_network_error", "1", 0);
    av_dict_set(&options, "reconnect_delay_max", "2", 0);
    av_dict_set(&options, "reconnect_max_retries", "5", 0);
    av_dict_set(&options, "reconnect_delay_total_max", "20", 0);
    return options;
}

static AVIOContext *open_track_io(const char *url, const char *agent, const char *referer,
                                  const char *cookie, const AVIOInterruptCB *ic)
{
    AVDictionary *options = track_options(agent, referer, cookie);
    AVIOContext *pb = NULL;
    int rc = avio_open2(&pb, url, AVIO_FLAG_READ, ic, &options);
    av_dict_free(&options);
    if (rc < 0) return NULL;
    return pb;
}

// 打开一条轨：优先接管预热好的连接（列表阶段已完成握手），
// 未命中或连接已被 CDN 关闭时回落到现开一条。
static int fetch_track(InputTrack *track, const char *url, const char *backup,
                       enum AVMediaType type, const char *agent, const char *referer,
                       const char *cookie, const AVIOInterruptCB *ic)
{
    const AVInputFormat *mp4 = av_find_input_format("mp4");
    track->input = avformat_alloc_context();
    if (!track->input) return AVERROR(ENOMEM);
    track->input->interrupt_callback = *ic;

    // 磁盘缓存优先：命中前缀就直接从文件读，越过末尾才回源并顺序追加。
    int64_t connect_at = av_gettime_relative();
    AVIOContext *pb = purapily_cache_open(url, backup, agent, referer, cookie, ic);
    int cached = pb != NULL;
    int reused = 0;
    if (!pb) {
        pb = purapily_take_prewarm(url);
        reused = pb != NULL;
        if (!pb) pb = open_track_io(url, agent, referer, cookie, ic);
    }
    int64_t connect = (av_gettime_relative() - connect_at) / 1000;
    if (!pb) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, "DualProbe", "io type=%{public}d connect failed",
                     (int)type);
        return AVERROR(EIO);
    }
    track->input->pb = pb;
    track->io = pb;
    track->io_cached = cached;

    int64_t t0 = av_gettime_relative();
    int rc = avformat_open_input(&track->input, NULL, mp4, NULL);
    int64_t demux = (av_gettime_relative() - t0) / 1000;
    if (rc < 0 && (reused || cached)) {
        // 预热 socket 可能已被对端关掉 / 缓存文件与流对不上：用干净连接重来一次。
        if (cached) purapily_cache_close(&pb); else avio_close(pb);
        track->io = NULL;
        track->input = avformat_alloc_context();
        if (!track->input) return AVERROR(ENOMEM);
        track->input->interrupt_callback = *ic;
        pb = open_track_io(url, agent, referer, cookie, ic);
        if (!pb) return AVERROR(EIO);
        track->input->pb = pb;
        track->io = pb;
        track->io_cached = 0;
        reused = 0;
        cached = 0;
        t0 = av_gettime_relative();
        rc = avformat_open_input(&track->input, NULL, mp4, NULL);
        demux = (av_gettime_relative() - t0) / 1000;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DualProbe",
                 "io type=%{public}d reused=%{public}d cached=%{public}d connect=%{public}lldms demux=%{public}lldms fmt=%{public}d rc=%{public}d",
                 (int)type, reused, cached, (long long)connect, (long long)demux, mp4 != NULL, rc);
    if (rc < 0) return rc;

    // MP4 moov already describes normal DASH tracks. Avoid decoding packets merely
    // to rediscover those parameters before the real playback decoder starts.
    int known = av_find_best_stream(track->input, type, -1, -1, NULL, 0);
    AVStream *candidate = known >= 0 ? track->input->streams[known] : NULL;
    AVCodecParameters *par = candidate ? candidate->codecpar : NULL;
    int complete = par && par->extradata_size > 0 &&
        candidate->time_base.num > 0 && candidate->time_base.den > 0;
    if (complete && type == AVMEDIA_TYPE_VIDEO)
        complete = (par->codec_id == AV_CODEC_ID_H264 || par->codec_id == AV_CODEC_ID_HEVC) &&
            par->width > 0 && par->height > 0 &&
            (candidate->avg_frame_rate.num > 0 || candidate->r_frame_rate.num > 0);
    else if (complete && type == AVMEDIA_TYPE_AUDIO)
        complete = par->codec_id == AV_CODEC_ID_AAC && par->sample_rate > 0 && par->ch_layout.nb_channels > 0;
    else complete = 0;
    int64_t t1 = av_gettime_relative();
    if (!complete) {
        track->input->probesize = 1048576;
        track->input->max_analyze_duration = 1000000;
        rc = avformat_find_stream_info(track->input, NULL);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DualProbe", "info type=%{public}d header_ready=%{public}d cost=%{public}lldms rc=%{public}d",
                 (int)type, complete, (long long)((av_gettime_relative() - t1) / 1000), rc);
    if (rc < 0) return rc;
    int index = av_find_best_stream(track->input, type, -1, -1, NULL, 0);
    if (index < 0) return index;
    track->stream = track->input->streams[index];
    return 0;
}

static int attach_track(AVFormatContext *outer, InputTrack *track)
{
    AVStream *out = avformat_new_stream(outer, NULL);
    track->packet = av_packet_alloc();
    if (!out || !track->packet) return AVERROR(ENOMEM);
    int rc = avcodec_parameters_copy(out->codecpar, track->stream->codecpar);
    if (rc < 0) return rc;
    out->time_base = track->stream->time_base;
    // MP4 uses 64-bit timestamps. AVStream's default 33-bit MPEG wrap rule
    // adds 2^33 after seeking back across the old wrap reference (>60s).
    // Different audio/video time bases then jump by different numbers of hours.
    out->pts_wrap_bits = track->stream->pts_wrap_bits;
    out->duration = track->stream->duration;
    out->start_time = track->stream->start_time;
    out->avg_frame_rate = track->stream->avg_frame_rate;
    out->r_frame_rate = track->stream->r_frame_rate;
    out->sample_aspect_ratio = track->stream->sample_aspect_ratio;
    return 0;
}

static int descriptor_line(AVIOContext *input, char *buffer, size_t capacity)
{
    size_t length = 0;
    int ch = 0;
    while ((ch = avio_r8(input)) != '\n' && ch != 0 && length < capacity - 1)
        buffer[length++] = (char)ch;
    buffer[length] = 0;
    return ch == '\n';
}

static int dual_header(AVFormatContext *outer)
{
    DualInput *state = outer->priv_data;
    // This IJK port requires ic->pb for seek. Keep the tiny descriptor as
    // outer AVIO; the two media inputs below still go directly to their CDNs.
    if (!outer->pb) return AVERROR(EINVAL);
    char urls[2][16384];
    char agent[4096] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";
    char referer[4096] = "https://www.bilibili.com/";
    char cookie[16384] = "";
    char backups[2][16384] = { {0}, {0} };
    int64_t bandwidths[2] = {0, 0};
    for (int i = 0; i < 2; i++) {
        if (!descriptor_line(outer->pb, urls[i], sizeof(urls[i])) ||
            !av_strstart(urls[i], "https://", NULL)) return AVERROR_INVALIDDATA;
    }
    if (!avio_feof(outer->pb)) {
        char optional[16384];
        if (descriptor_line(outer->pb, optional, sizeof(agent))) av_strlcpy(agent, optional, sizeof(agent));
        if (descriptor_line(outer->pb, optional, sizeof(referer))) av_strlcpy(referer, optional, sizeof(referer));
        if (descriptor_line(outer->pb, optional, sizeof(cookie))) av_strlcpy(cookie, optional, sizeof(cookie));
        // 第 6、7 行：base_url 之外的备用源（可为空）。
        if (descriptor_line(outer->pb, optional, sizeof(optional)))
            av_strlcpy(backups[0], optional, sizeof(backups[0]));
        if (descriptor_line(outer->pb, optional, sizeof(optional)))
            av_strlcpy(backups[1], optional, sizeof(backups[1]));
        for (int i = 0; i < 2; i++) {
            if (descriptor_line(outer->pb, optional, sizeof(optional))) {
                int64_t value = strtoll(optional, NULL, 10);
                if (value > 0 && value <= 1000000000) bandwidths[i] = value;
            }
        }
    }
    // 两条轨互不依赖：并行打开，省掉音频轨那段串行等待（实测 150ms 量级）。
    pthread_t threads[2];
    int started[2] = {0, 0};
    int64_t th0 = av_gettime_relative();
    for (int i = 0; i < 2; i++) {
        state->jobs[i].track = &state->tracks[i];
        state->jobs[i].url = urls[i];
        state->jobs[i].backup = backups[i];
        state->jobs[i].bandwidth = bandwidths[i];
        state->jobs[i].type = i == 0 ? AVMEDIA_TYPE_VIDEO : AVMEDIA_TYPE_AUDIO;
        state->jobs[i].agent = agent;
        state->jobs[i].referer = referer;
        state->jobs[i].cookie = cookie;
        state->jobs[i].ic = outer->interrupt_callback;
        state->jobs[i].rc = AVERROR_EXTERNAL;
        started[i] = pthread_create(&threads[i], NULL, fetch_thread, &state->jobs[i]) == 0;
    }
    for (int i = 0; i < 2; i++) {
        if (started[i]) pthread_join(threads[i], NULL);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DualProbe", "parallel total=%{public}lldms",
                 (long long)((av_gettime_relative() - th0) / 1000));
    int rc = 0;
    for (int i = 0; i < 2; i++) {
        if (state->jobs[i].rc < 0) { rc = state->jobs[i].rc; break; }
        rc = attach_track(outer, &state->tracks[i]);
        if (rc < 0) break;
        outer->duration = FFMAX(outer->duration, state->tracks[i].input->duration);
    }
    return rc;
}

static int interrupted(AVFormatContext *outer)
{
    const AVIOInterruptCB *cb = &outer->interrupt_callback;
    return cb->callback != NULL && cb->callback(cb->opaque) != 0;
}

// 读一包：瞬时断流/超时不向上抛错误。
// IJK 的 read_thread 收到 <0 就当成 EOF，塞 null packet 并把播放判成结束——
// 用户看到的就是「播着播着停了，手动重放才好」，所以这里必须自己扛住。
static int fill_packet(AVFormatContext *outer, InputTrack *track, int type)
{
    int retries = 0;
    while (!track->ready && !track->eof) {
        int rc = av_read_frame(track->input, track->packet);
        if (rc == AVERROR_EOF) {
            track->eof = 1;
            break;
        }
        if (rc >= 0) {
            if (track->packet->stream_index == track->stream->index) track->ready = 1;
            else av_packet_unref(track->packet);
            retries = 0;
            continue;
        }
        if (rc == AVERROR_EXIT || interrupted(outer)) return AVERROR_EXIT;
        // 清掉 IO 错误位，下一次 av_read_frame 才会真正再读一次（http 层已开 reconnect）。
        if (track->input->pb) {
            track->input->pb->error = 0;
            track->input->pb->eof_reached = 0;
        }
        if (++retries > 300) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0, "DualProbe", "read type=%{public}d give up rc=%{public}d retries=%{public}d",
                         type, rc, retries);
            return rc;
        }
        if (retries % 20 == 1) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0, "DualProbe", "read type=%{public}d retry=%{public}d rc=%{public}d",
                         type, retries, rc);
        }
        av_usleep(50 * 1000);
    }
    return 0;
}

static int64_t packet_ts(const InputTrack *track)
{
    return track->packet->dts != AV_NOPTS_VALUE ? track->packet->dts : track->packet->pts;
}

static int dual_read(AVFormatContext *outer, AVPacket *out)
{
    DualInput *state = outer->priv_data;
    if (state->terminal_error) return state->terminal_error;
    InputTrack *v = &state->tracks[0], *a = &state->tracks[1];
    int rc = fill_packet(outer, v, 0);
    if (rc < 0) return rc;
    rc = fill_packet(outer, a, 1);
    if (rc < 0) return rc;
    if (!v->ready && !a->ready) return AVERROR_EOF;
    int index = !v->ready || (a->ready && av_compare_ts(packet_ts(a), a->stream->time_base,
                                                        packet_ts(v), v->stream->time_base) < 0);
    InputTrack *track = &state->tracks[index];
    // 取流量统计：每秒最多打一行，用来看「起播突发」到底读了多少。
    if (state->opened_at == 0) state->opened_at = av_gettime_relative();
    if (state->logged_at == 0) state->logged_at = state->opened_at;
    state->bytes[index] += track->packet->size;
    int64_t now = av_gettime_relative();
    if (now - state->logged_at >= 1000000) {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DualProbe",
                     "stats t=%{public}lldms v=%{public}lldKB a=%{public}lldKB",
                     (long long)((now - state->opened_at) / 1000),
                     (long long)(state->bytes[0] / 1024), (long long)(state->bytes[1] / 1024));
        state->logged_at = now;
    }
    av_packet_move_ref(out, track->packet);
    track->ready = 0;
    out->stream_index = index;
    out->pos = -1;
    av_packet_rescale_ts(out, track->stream->time_base, outer->streams[index]->time_base);
    return 0;
}

static int reposition(AVFormatContext *outer, InputTrack *track, int64_t time_us, int type)
{
    int64_t ts = av_rescale_q(time_us, AV_TIME_BASE_Q, track->stream->time_base);
    int rc = av_seek_frame(track->input, track->stream->index, ts, AVSEEK_FLAG_BACKWARD);
    if (rc < 0) return rc;
    av_packet_unref(track->packet);
    track->ready = track->eof = 0;
    return fill_packet(outer, track, type);
}

static int dual_seek(AVFormatContext *outer, int stream, int64_t timestamp, int flags)
{
    if (flags & (AVSEEK_FLAG_BYTE | AVSEEK_FLAG_FRAME)) return AVERROR(ENOSYS);
    DualInput *state = outer->priv_data;
    InputTrack *video = &state->tracks[0];
    int64_t target = stream < 0 ? timestamp :
        av_rescale_q(timestamp, outer->streams[stream]->time_base, AV_TIME_BASE_Q);
    int rc = reposition(outer, video, target, 0);
    if (rc == 0 && !video->ready) rc = AVERROR_EOF;
    if (rc == 0) {
        int64_t pts = video->packet->pts;
        int64_t anchor = pts == AV_NOPTS_VALUE ? target :
            av_rescale_q(pts, video->stream->time_base, AV_TIME_BASE_Q);
        rc = reposition(outer, &state->tracks[1], FFMAX(0, anchor), 1);
    }
    // If only one input moved, disallow mixed-generation packets.
    state->terminal_error = rc;
    return rc;
}

static int dual_close(AVFormatContext *outer)
{
    DualInput *state = outer->priv_data;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DualProbe", "closed v=%{public}lldKB a=%{public}lldKB",
                 (long long)(state->bytes[0] / 1024), (long long)(state->bytes[1] / 1024));
    for (int i = 0; i < 2; i++) {
        av_packet_free(&state->tracks[i].packet);
        avformat_close_input(&state->tracks[i].input);
        // CUSTOM_IO: avformat_close_input 不接管 pb，由这里负责关闭。
        if (state->tracks[i].io) {
            if (state->tracks[i].io_cached) purapily_cache_close(&state->tracks[i].io);
            else avio_close(state->tracks[i].io);
        }
        state->tracks[i].io = NULL;
    }
    return 0;
}

static const FFInputFormat dual = {
    .p.name = "puradual",
    .p.long_name = "PuraPily experimental dual input",
    .p.flags = AVFMT_NO_BYTE_SEEK | AVFMT_NOGENSEARCH | AVFMT_NOBINSEARCH,
    .priv_data_size = sizeof(DualInput),
    .flags_internal = FF_INFMT_FLAG_INIT_CLEANUP,
    .read_header = dual_header, .read_packet = dual_read,
    .read_seek = dual_seek, .read_close = dual_close,
};

struct FFOutputFormat;
extern void avpriv_register_devices(const struct FFOutputFormat *const *,
                                    const FFInputFormat *const *);
int ijk_lab_register_dual(void)
{
    static const FFInputFormat *const formats[] = {&dual, NULL};
    avpriv_register_devices(NULL, formats);
    return av_find_input_format("puradual") == &dual.p;
}
