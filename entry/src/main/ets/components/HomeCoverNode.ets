import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { fmtCount } from '../utils/NumberFormat';

export interface CoverArtwork {
  id: string;
  url: string;
  count: number;
  duration: string;
}

interface CoverParams {
  art: CoverArtwork;
  badge: number;
  loaded: (url: string) => void;
}

@Builder
function coverContent($$: CoverParams) {
  Stack({ alignContent: Alignment.Bottom }) {
    Image($$.art.url).width('100%').height('100%').objectFit(ImageFit.Cover)
      .autoResize(true).draggable(false).id('home-card-cover-image-' + $$.art.id)
      .onComplete(() => $$.loaded($$.art.url))
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height(36)
        .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#99000000', 1]] })
      Row({ space: 8 }) {
        Row({ space: 3 }) {
          Image($r('app.media.ref_play')).width(14).height(14).fillColor('#FFFFFF')
          Text(fmtCount($$.art.count)).fontSize(10).fontColor('#FFFFFF')
        }
        Blank()
        Text($$.art.duration).fontSize(10).fontColor('#FFFFFF')
      }.width('100%').padding({ left: 6, right: 6, bottom: 6 })
    }.width('100%').height('100%').opacity($$.badge)
  }.width('100%').height('100%').clip(true)
}

// Each flight keeps the original artwork even if the WaterFlow reuses its cell.
export class CoverFlight extends NodeController {
  private away: boolean = false;
  private detaching: boolean = false;
  private ready: boolean = false;
  private badge: number = 1;
  private node: BuilderNode<[CoverParams]>;
  private home: CoverHomeHost;
  readonly art: CoverArtwork;

  constructor(ui: UIContext, home: CoverHomeHost, art: CoverArtwork) {
    super();
    this.home = home;
    this.art = art;
    this.node = new BuilderNode<[CoverParams]>(ui);
    this.node.build(wrapBuilder(coverContent), this.params());
  }

  private params(): CoverParams {
    return { art: this.art, badge: this.badge, loaded: (url: string) => {
      if (url === this.art.url) this.ready = true;
    } };
  }

  setBadge(value: number): void {
    if (value === this.badge) return;
    this.badge = value;
    this.node.update(this.params());
  }

  available(id: string): boolean { return this.ready && !this.away && this.art.id === id; }

  homeNode(): FrameNode | null { return this.away ? null : this.node.getFrameNode(); }

  makeNode(_ui: UIContext): FrameNode | null {
    if (this.detaching) return null;
    if (!this.away) {
      this.away = true;
      this.home.refresh(this);
    }
    return this.node.getFrameNode();
  }

  restore(): void {
    if (!this.away) return;
    this.away = false;
    // Detach this container before rebuilding the source container.
    this.detaching = true;
    this.rebuild();
    this.detaching = false;
    this.setBadge(1);
    this.home.refresh(this);
  }

}

export class CoverHomeHost extends NodeController {
  private artwork: CoverArtwork;
  private current?: CoverFlight;
  private mounted: boolean = false;

  constructor(artwork: CoverArtwork) {
    super();
    this.artwork = artwork;
  }

  makeNode(ui: UIContext): FrameNode | null {
    if (!ui) return null;
    this.mounted = true;
    if (!this.current) this.current = new CoverFlight(ui, this, this.artwork);
    return this.current?.homeNode() ?? null;
  }

  aboutToDisappear(): void { this.mounted = false; this.current = undefined; }

  refresh(expected?: CoverFlight): void {
    if (this.mounted && (!expected || this.current === expected)) this.rebuild();
  }

  flight(id: string): CoverFlight | undefined {
    return this.mounted && this.current?.available(id) ? this.current : undefined;
  }
}
