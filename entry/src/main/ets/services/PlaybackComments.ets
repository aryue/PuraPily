import { AddCommentResult, addVideoComment, getCommentReplies, getVideoComments, uploadCommentImage } from '../api/BilibiliApi';
import { ObservableComment } from '../model/ObservableComment';
import { logError } from '../utils/Logger';

export interface PlaybackCommentPage {
  comments: ObservableComment[];
  nextCursor: number;
  isEnd: boolean;
}

export interface PlaybackCommentSearch {
  find: () => number;
  current: () => boolean;
  reloadLatest: (() => Promise<void>) | null;
  loadMore: () => Promise<boolean>;
}

export interface PlaybackCommentTarget {
  aid: number;
  root: number;
  parent: number;
}

export interface PlaybackCommentImage {
  path: string;
  mime: string;
  ext: string;
}

interface PlaybackCommentImagePayload {
  img_src: string;
  img_width: number;
  img_height: number;
}

export class PlaybackComments {
  private sequence: number = 0;
  private key: string = '';

  begin(generation: number, aid: number, cursor: number, sort: number, loading: boolean): number {
    const key = `${generation}:${aid}:${cursor}:${sort}`;
    if (loading && this.key === key) return 0;
    this.key = key;
    return ++this.sequence;
  }

  isLatest(request: number): boolean {
    return request === this.sequence;
  }

  async send(target: PlaybackCommentTarget, content: string, pictures: PlaybackCommentImage[],
    current: () => boolean): Promise<AddCommentResult | null> {
    if (!current()) return null;
    const images: PlaybackCommentImagePayload[] = [];
    for (const picture of pictures) {
      const uploaded = await uploadCommentImage(picture.path, picture.mime, picture.ext);
      if (!current()) return null;
      if (!uploaded?.url) return { ok: false, code: -1, message: '图片上传失败' };
      images.push({ img_src: uploaded.url, img_width: uploaded.width, img_height: uploaded.height });
    }
    return addVideoComment(target.aid, content, target.root, target.parent,
      images.length ? JSON.stringify(images) : '');
  }

  async loadInlineReplies(aid: number, comment: ObservableComment, first: boolean,
    current: () => boolean): Promise<boolean> {
    if (!current() || comment.loadingReplies) return false;
    if (first && comment.rcount <= comment.replies.length) {
      comment.hasMoreReplies = false;
      return true;
    }
    const page = first ? 1 : (comment.replyPage || 0) + 1;
    comment.loadingReplies = true;
    try {
      const replies = await getCommentReplies(aid, comment.rpid, page, 20);
      if (!current()) return false;
      if (!replies?.length) {
        comment.hasMoreReplies = false;
        return false;
      }
      if (first) {
        comment.updateReplies(replies);
      } else {
        const existing = new Set<number>(comment.replies.map((reply: ObservableComment) => reply.rpid));
        comment.updateReplies([...comment.replies.map((reply: ObservableComment) => reply.toCommentItem()),
          ...replies.filter(reply => !existing.has(reply.rpid))]);
      }
      comment.replyPage = page;
      comment.hasMoreReplies = replies.length >= 20 && (!first || comment.rcount > replies.length);
      return true;
    } catch (error) {
      logError('加载回复失败:', error);
      if (first && current()) comment.hasMoreReplies = false;
      return false;
    } finally {
      comment.loadingReplies = false;
    }
  }

  async fetch(aid: number, cursor: number, sort: number): Promise<PlaybackCommentPage | null> {
    const result = await getVideoComments(aid, cursor, 20, sort === 2 ? 3 : 2);
    if (!result) return null;
    return {
      comments: result.comments?.map((item) => ObservableComment.from(item)) ?? [],
      nextCursor: result.nextCursor,
      isEnd: result.isEnd
    };
  }

  async locate(search: PlaybackCommentSearch): Promise<number> {
    let index = search.find();
    if (index >= 0 || !search.reloadLatest) return index;
    await search.reloadLatest();
    if (!search.current()) return -1;
    index = search.find();
    for (let page = 0; index < 0 && page < 5; page++) {
      if (!await search.loadMore() || !search.current()) return -1;
      index = search.find();
    }
    return index;
  }
}
