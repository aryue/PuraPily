import { getVideoPlayUrl } from '../api/BilibiliApi';
import { IjkPlaybackSession, IjkSourceFactory } from '../services/IjkPlaybackSession';
import probe from 'libpurapily_ijk.so';

class NativeSourceFactory implements IjkSourceFactory {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  create(video: string, audio: string): string {
    return probe.source(this.directory, video, audio);
  }
}

@Entry
@Component
struct IjkLab {
  @State status: string = '准备播放';
  @State playing: boolean = false;
  @State playbackPosition: number = 0;
  @State duration: number = 0;
  @State ready: boolean = false;
  @State speed: number = 1;
  private session: IjkPlaybackSession | null = null;
  private surface: object | null = null;
  private generation: number = 0;

  private async open(context: object): Promise<void> {
    const generation = ++this.generation;
    this.surface = context;
    this.ready = false;
    this.status = '获取最新播放地址';
    try {
      const result = await getVideoPlayUrl('BV1hb411c7RQ', 62384983, 32);
      if (generation !== this.generation || this.surface !== context) return;
      this.session?.release();
      const session = new IjkPlaybackSession({
        prepared: (duration: number): void => {
          this.duration = duration; this.ready = true;
          this.playing = true; this.status = '双轨直连';
        },
        time: (playbackPosition: number): void => { this.playbackPosition = playbackPosition; },
        rendered: (): void => { this.status = '播放中'; },
        completed: (): void => { this.playing = false; this.status = '播放结束'; },
        failed: (code: number): void => {
          this.ready = false; this.playing = false;
          this.status = '播放失败 ' + code;
        }
      }, new NativeSourceFactory(this.getUIContext().getHostContext()!.cacheDir));
      this.session = session;
      session.setSpeed(this.speed);
      session.open(context, 'ijk_main_surface', result);
    } catch (_) {
      if (generation === this.generation) {
        this.ready = false; this.status = '获取或准备播放失败，可刷新重试';
      }
    }
  }

  private stop(): void {
    this.generation++;
    this.surface = null;
    this.session?.release();
    this.session = null;
  }

  build() {
    Column({ space: 12 }) {
      XComponent({ id: 'ijk_main_surface', type: XComponentType.SURFACE, libraryname: 'ijkplayer_napi' })
        .width('100%').aspectRatio(16 / 9)
        .onLoad((context: object) => { this.open(context); })
        .onDestroy(() => { this.stop(); })
      Text('IJK 播放会话验证').fontColor(Color.White).fontSize(22)
      Text(this.status).fontColor(Color.White)
      Text(Math.floor(this.playbackPosition / 1000) + ' / ' + Math.floor(this.duration / 1000) + ' 秒').fontColor(Color.White)
      Row({ space: 12 }) {
        Button('后退15秒').enabled(this.ready).onClick(() => this.session?.seek(this.playbackPosition - 15000))
        Button(this.playing ? '暂停' : '播放').enabled(this.ready).onClick(() => {
          if (this.playing) this.session?.pause(); else this.session?.play();
          this.playing = !this.playing;
        })
        Button('前进15秒').enabled(this.ready).onClick(() => this.session?.seek(Math.min(this.duration - 500, this.playbackPosition + 15000)))
      }
      Row({ space: 12 }) {
        Button('刷新重试').onClick(() => { if (this.surface) this.open(this.surface); })
        Button(this.speed + ' 倍速').onClick(() => {
          this.speed = this.speed === 1 ? 1.5 : this.speed === 1.5 ? 2 : 1;
          this.session?.setSpeed(this.speed);
        })
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
      }
    }.width('100%').height('100%').backgroundColor(Color.Black).justifyContent(FlexAlign.Center)
  }
}