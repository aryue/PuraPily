import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getVideoDetail, getVideoPlayUrl, PlayUrlResult, VideoDetail } from '../api/BilibiliApi';
import { DashPlayerBridge } from '../services/DashPlayerBridge';
import { WarmSurfaceHost } from '../services/WarmSurfaceHost';

const TAG: string = 'SurfaceLab';
const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

/**
 * 实验页：验证「已 prepare 的播放器能否把 surfaceId 改绑到另一个 XComponent」。
 *
 * A 组：在隐藏 surface 上 prepare → 改绑到可见 surface → play，量「改绑 → 首帧」。
 * B 组（对照）：新建播放器直接绑可见 surface → prepare → play，量「prepare → 首帧」。
 *
 * 只做测量，不参与正式播放链路。入口：aa start --ps surfaceLab <bvid>
 */
@Entry
@Component
struct SurfaceRebindLab {
  @State private lines: string[] = [];
  @State private phase: string = '准备中';
  @State private running: boolean = false;
  @State private warmReady: boolean = false;
  @State private mainReady: boolean = false;
  private warmCtl: XComponentController = new XComponentController();
  private mainCtl: XComponentController = new XComponentController();
  private warmSurface: string = '';
  private mainSurface: string = '';
  private bvid: string = '';
  private autoStarted: boolean = false;
  private origin: number = 0;
  private playerA: media.AVPlayer | null = null;
  private bridge: DashPlayerBridge | null = null;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, string> | null;
    const passed: string = params !== null && params !== undefined ? (params['bvid'] as string) : '';
    // 默认用模拟器/真机都验证过能播的一次推荐流条目（数字 aid 也可被 getVideoDetail 归一）。
    this.bvid = passed !== undefined && passed !== null && passed.length > 0 ? passed : '117444957970302';
    this.note(`bvid=${this.bvid}`);
  }

  private note(text: string): void {
    const at: number = this.origin > 0 ? Date.now() - this.origin : 0;
    const line: string = `${at}ms ${text}`;
    this.lines = this.lines.concat([line]);
    hilog.info(0x0000, TAG, '%{public}s', line);
  }

  private waitState(av: media.AVPlayer, target: string, timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      let done: boolean = false;
      const timer: number = setTimeout(() => {
        if (done) return;
        done = true;
        resolve(false);
      }, timeoutMs);
      av.on('stateChange', (state: string) => {
        if (done || state !== target) return;
        done = true;
        clearTimeout(timer);
        resolve(true);
      });
    });
  }

  private waitFrame(av: media.AVPlayer, timeoutMs: number): Promise<number> {
    return new Promise<number>((resolve: (at: number) => void) => {
      let done: boolean = false;
      const timer: number = setTimeout(() => {
        if (done) return;
        done = true;
        resolve(-1);
      }, timeoutMs);
      av.on('startRenderFrame', () => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(Date.now());
      });
    });
  }

  private async source(): Promise<string> {
    const detail: VideoDetail | null = await getVideoDetail(this.bvid);
    const cid: number = detail?.cid || detail?.pages?.[0]?.cid || 0;
    this.note(`detail cid=${cid} bv=${detail?.bvid || '-'}`);
    if (cid <= 0) return '';
    const result: PlayUrlResult = await getVideoPlayUrl(detail?.bvid || this.bvid, cid,
      AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.note(`playurl qn=${result.actualQn} dash=${result.dash !== undefined && result.dash !== null}`);
    const referer: string = result.mediaReferer ?? 'https://www.bilibili.com/';
    const agent: string = result.mediaUserAgent || UA;
    if (result.dash !== undefined && result.dash !== null && result.audioUrl) {
      this.bridge = new DashPlayerBridge(null);
      const url: string | null = await this.bridge.buildAndStart(result.dash, referer, agent, '', 0);
      this.note(`bridge ${url !== null ? 'ok' : 'fail'}`);
      if (url !== null) return url;
    }
    return result.url;
  }

  private async run(): Promise<void> {
    if (this.running) return;
    if (!this.warmSurface || !this.mainSurface) {
      this.phase = '等 surface';
      return;
    }
    this.running = true;
    this.lines = [];
    this.origin = Date.now();
    this.phase = '取流';
    this.note(`start warm=${this.warmSurface.slice(-6)} main=${this.mainSurface.slice(-6)}`);
    try {
      const url: string = await this.source();
      if (url.length === 0) {
        this.note('abort: no url');
        this.running = false;
        this.phase = '无地址';
        return;
      }
      const headers: Record<string, string> = { 'User-Agent': UA, 'Referer': 'https://www.bilibili.com/' };
      const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);

      // ---- A: 隐藏 surface 上 prepare，然后改绑 ----
      this.phase = 'A: prepare(隐藏 surface)';
      const a: media.AVPlayer = await media.createAVPlayer();
      this.playerA = a;
      let preparedAt: number = 0;
      a.on('stateChange', async (state: string) => {
        this.note(`A: state=${state}`);
        if (state === 'initialized') {
          try {
            const hostSurface: string = WarmSurfaceHost.get();
            const target: string = hostSurface.length > 0 ? hostSurface : this.warmSurface;
            this.note(`A: bind ${hostSurface.length > 0 ? 'HOST' : 'page'} ${target.slice(-6)} age=${WarmSurfaceHost.ageMs()}ms`);
            a.surfaceId = target;
          } catch (e) {
            this.note(`A: surface throw ${(e as BusinessError).message}`);
          }
          try {
            await a.prepare();
          } catch (e) {
            this.note(`A: prepare throw ${(e as BusinessError).message}`);
          }
        } else if (state === 'prepared') {
          preparedAt = Date.now();
          this.note('A: prepared');
        }
      });
      a.on('error', (e: BusinessError) => {
        this.note(`A: error ${e.code} ${e.message}`);
      });
      this.note(`A: before setMediaSource state=${a.state}`);
      await a.setMediaSource(source);
      this.note(`A: after setMediaSource state=${a.state}`);
      for (let i = 0; i < 10; i++) {
        await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 400));
        this.note(`A: poll ${i} state=${a.state} surf=${(a.surfaceId || '').slice(-6)}`);
        if (a.state === 'prepared' || a.state === 'error') {
          break;
        }
      }
      let okPrepared: boolean = a.state === 'prepared';
      if (!okPrepared) {
        okPrepared = await this.waitState(a, 'prepared', 6000);
      }
      this.note(`A: prepared ok=${okPrepared}`);
      if (!okPrepared) {
        a.release();
        this.playerA = null;
        this.running = false;
        this.phase = 'A 失败';
        return;
      }

      // 试探：对已 prepared 的播放器再次调用 prepare()，是否会重新派发 prepared 事件。
      this.note('A: re-prepare probe');
      try {
        await a.prepare();
      } catch (e) {
        this.note(`A: re-prepare throw ${(e as BusinessError).message}`);
      }
      await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 400));
      this.note(`A: after re-prepare state=${a.state}`);

      const rebindAt: number = Date.now();
      let rebindError: string = '';
      try {
        a.surfaceId = this.mainSurface;
      } catch (e) {
        rebindError = (e as BusinessError).message;
      }
      this.note(`A: rebind ${rebindError.length > 0 ? 'throw ' + rebindError : 'ok'} ${Date.now() - rebindAt}ms`);
      const framePromise: Promise<number> = this.waitFrame(a, 8000);
      try {
        await a.play();
      } catch (e) {
        this.note(`A: play throw ${(e as BusinessError).message}`);
      }
      const frameAt: number = await framePromise;
      if (frameAt > 0) {
        this.note(`A: frame after rebind ${frameAt - rebindAt}ms; prepare→frame ${frameAt - preparedAt}ms`);
      } else {
        this.note('A: frame timeout (8s)');
      }
      this.phase = `A 完成 rebind→frame ${frameAt > 0 ? frameAt - rebindAt : -1}ms`;

      // ---- B: 对照，直接建在可见 surface ----
      await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 6000));
      try {
        await a.stop();
      } catch (e) { }
      a.release();
      this.playerA = null;

      this.phase = 'B: 直接建在可见 surface';
      const b: media.AVPlayer = await media.createAVPlayer();
      this.playerA = b;
      let bPreparedAt: number = 0;
      b.on('stateChange', async (state: string) => {
        this.note(`B: state=${state}`);
        if (state === 'initialized') {
          try {
            b.surfaceId = this.mainSurface;
          } catch (e) {
            this.note(`B: surface throw ${(e as BusinessError).message}`);
          }
          try {
            await b.prepare();
          } catch (e) {
            this.note(`B: prepare throw ${(e as BusinessError).message}`);
          }
        } else if (state === 'prepared') {
          bPreparedAt = Date.now();
          this.note('B: prepared');
        }
      });
      const bSource: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
      await b.setMediaSource(bSource);
      let bOk: boolean = b.state === 'prepared';
      for (let i = 0; i < 20 && !bOk; i++) {
        await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 200));
        this.note(`B: poll ${i} state=${b.state}`);
        bOk = b.state === 'prepared';
      }
      if (!bOk) {
        bOk = await this.waitState(b, 'prepared', 4000);
      }
      this.note(`B: prepared ok=${bOk}`);
      if (bOk) {
        const playback: Promise<number> = this.waitFrame(b, 8000);
        await b.play();
        const bFrame: number = await playback;
        this.note(`B: prepare→frame ${bFrame > 0 ? bFrame - bPreparedAt : -1}ms`);
        this.phase = `B 完成 prepare→frame ${bFrame > 0 ? bFrame - bPreparedAt : -1}ms`;
      }
    } catch (e) {
      this.note(`error ${(e as BusinessError).message}`);
      this.phase = '异常';
    } finally {
      this.running = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      Text('Surface 改绑实验').fontSize(18).fontColor('#FFFFFF').width('100%')
      Text(this.phase).fontSize(13).fontColor('#9FE1CB').width('100%')
      Stack({ alignContent: Alignment.TopStart }) {
        XComponent({ id: 'lab_main_xc', type: XComponentType.SURFACE, controller: this.mainCtl })
          .onLoad(() => {
            this.mainSurface = this.mainCtl.getXComponentSurfaceId();
            this.mainReady = this.mainSurface.length > 0;
            this.note(`main surface ${this.mainSurface.slice(-6)}`);
            this.maybeRun();
          })
          .width('100%')
          .height(190)
          .backgroundColor('#101010')
        XComponent({ id: 'lab_warm_xc', type: XComponentType.SURFACE, controller: this.warmCtl })
          .onLoad(() => {
            this.warmSurface = this.warmCtl.getXComponentSurfaceId();
            this.warmReady = this.warmSurface.length > 0;
            this.note(`warm surface ${this.warmSurface.slice(-6)}`);
            this.maybeRun();
          })
          .width(2)
          .height(2)
          .opacity(0.01)
      }.width('100%')

      Row({ space: 10 }) {
        Button('重跑').onClick(() => { this.run(); })
        Button('停止').onClick(() => {
          const p = this.playerA;
          this.playerA = null;
          if (p !== null) { p.release(); }
          this.phase = '已停止';
        })
      }.width('100%')

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.lines, (line: string, index: number) => {
            Text(line).fontSize(11).fontColor('#D3D1C7').width('100%')
          }, (line: string, index: number) => `${index}`)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .backgroundColor('#17181A')
  }

  private maybeRun(): void {
    if (this.warmReady && this.mainReady && !this.autoStarted) {
      this.autoStarted = true;
      this.run();
    }
  }
}
