// Exercise production stream attachment through the shipped FFmpeg demuxer.
#include "../ijk_dual_demux_lab.c"
#include <assert.h>

static int packet_index, second = 200;
static InputTrack inputs[2];
static int fixture_header(AVFormatContext *outer)
{
    for (int i = 0; i < 2; i++) {
        inputs[i].input = avformat_alloc_context();
        inputs[i].stream = avformat_new_stream(inputs[i].input, NULL);
        AVStream *st = inputs[i].stream;
        st->time_base = (AVRational){1, i ? 44100 : 16000};
        st->pts_wrap_bits = 64;
        st->codecpar->codec_type = i ? AVMEDIA_TYPE_AUDIO : AVMEDIA_TYPE_VIDEO;
        st->codecpar->codec_id = i ? AV_CODEC_ID_PCM_S16LE : AV_CODEC_ID_RAWVIDEO;
        st->codecpar->sample_rate = 44100;
        st->codecpar->width = 16;
        st->codecpar->height = 16;
        st->start_time = 0;
        st->duration = 269LL * st->time_base.den;
        assert(attach_track(outer, &inputs[i]) == 0);
    }
    return 0;
}
static int fixture_read(AVFormatContext *outer, AVPacket *packet)
{
    int index = packet_index++ % 2;
    assert(av_new_packet(packet, 16) == 0);
    packet->stream_index = index;
    packet->pts = packet->dts = (int64_t)second * outer->streams[index]->time_base.den;
    packet->flags = AV_PKT_FLAG_KEY;
    return 0;
}
static int fixture_seek(AVFormatContext *outer, int stream, int64_t ts, int flags)
{
    second = (int)(ts * av_q2d(outer->streams[stream]->time_base));
    packet_index = 0;
    return 0;
}
static const FFInputFormat fixture = {
    .p.name = "timestamp_fixture", .p.flags = AVFMT_NOFILE,
    .read_header = fixture_header, .read_packet = fixture_read, .read_seek = fixture_seek,
};
int main(void)
{
    AVFormatContext *outer = NULL;
    assert(avformat_open_input(&outer, NULL, &fixture.p, NULL) == 0);
    AVPacket *packet = av_packet_alloc();
    for (int i = 0; i < 2; i++) {
        assert(av_read_frame(outer, packet) == 0);
        assert(packet->pts == 200LL * outer->streams[packet->stream_index]->time_base.den);
        av_packet_unref(packet);
    }
    assert(av_seek_frame(outer, 0, 0, AVSEEK_FLAG_BACKWARD) == 0);
    for (int i = 0; i < 2; i++) {
        assert(av_read_frame(outer, packet) == 0);
        printf("seek-zero stream=%d pts=%lld wrap_bits=%d\n", packet->stream_index,
               (long long)packet->pts, outer->streams[packet->stream_index]->pts_wrap_bits);
        fflush(stdout);
        assert(packet->pts == 0 && packet->dts == 0);
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    avformat_close_input(&outer);
    for (int i = 0; i < 2; i++) {
        av_packet_free(&inputs[i].packet);
        avformat_free_context(inputs[i].input);
    }
    puts("PASS: both tracks retain exact zero timestamps after seeking back from 200s");
    return 0;
}
