import { getFollowStatus, getVideoDetail, getVideoIntroCard, getVideoIntroTags, getVideoUserStatus,
  VideoDetail, VideoIntroCard, VideoIntroTag } from '../api/BilibiliApi';
import { logWarn } from '../utils/Logger';

export interface PlaybackIntroUpdates {
  current: () => boolean;
  reset: () => void;
  card: (card: VideoIntroCard | null) => void;
  tags: (tags: VideoIntroTag[]) => void;
}

export interface PlaybackInteractionStatus {
  liked: boolean;
  disliked: boolean;
  coined: boolean;
  favorited: boolean;
}

export interface PlaybackInteractionUpdates {
  current: () => boolean;
  follow: (followed: boolean) => void;
  status: (status: PlaybackInteractionStatus) => void;
}

export interface PlaybackDetailUpdates {
  current: () => boolean;
  apply: (detail: VideoDetail) => void;
  settled: () => void;
}

export class PlaybackIntro {
  private requestedBvid: string = '';
  private request: number = 0;
  private detailRequest: number = 0;
  private interactionRequest: number = 0;

  async loadDetail(bvid: string, preloaded: VideoDetail | undefined, updates: PlaybackDetailUpdates): Promise<void> {
    const request = ++this.detailRequest;
    const current = (): boolean => request === this.detailRequest && updates.current();
    try {
      const detail = preloaded ?? await getVideoDetail(bvid);
      if (detail && current()) updates.apply(detail);
    } catch (error) {
      if (current()) logWarn('[VideoPlayer] 视频详情加载失败', error);
    } finally {
      if (request === this.detailRequest) updates.settled();
    }
  }

  loadInteractions(bvid: string, detail: VideoDetail, updates: PlaybackInteractionUpdates): void {
    if (!updates.current()) return;
    const request = ++this.interactionRequest;
    const current = (): boolean => request === this.interactionRequest && updates.current();
    if (detail.owner.mid) {
      getFollowStatus(detail.owner.mid).then((followed: boolean) => {
        if (current()) updates.follow(followed);
      }).catch((error: Error) => { logWarn('[VideoPlayer] 关注状态加载失败', error); });
    }
    if (detail.req_user && detail.req_user.dislike !== undefined) {
      updates.status({ liked: !!detail.req_user.like, disliked: !!detail.req_user.dislike,
        coined: (detail.req_user.coin || 0) > 0, favorited: !!detail.req_user.favorite });
      return;
    }
    getVideoUserStatus(bvid, detail.aid).then((status) => {
      if (!current() || !status) return;
      updates.status({ liked: status.like, disliked: status.dislike || false,
        coined: status.coin > 0, favorited: status.favorite });
    }).catch((error: Error) => { logWarn('[VideoPlayer] 互动状态加载失败', error); });
  }

  load(bvid: string, mid: number, updates: PlaybackIntroUpdates): void {
    if (this.requestedBvid === bvid) return;
    this.requestedBvid = bvid;
    const request = ++this.request;
    updates.reset();
    getVideoIntroCard(mid).then((card) => {
      if (request === this.request && updates.current()) updates.card(card);
    });
    getVideoIntroTags(bvid).then((tags) => {
      if (request === this.request && updates.current()) updates.tags(tags);
    });
  }
}
