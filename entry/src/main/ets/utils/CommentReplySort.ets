import { ObservableComment } from '../model/ObservableComment';

/** The reply endpoint pages chronologically; reorder loaded replies without changing its page cursor. */
export function sortCommentReplies(replies: ObservableComment[], byHeat: boolean): ObservableComment[] {
  return replies.slice().sort((a: ObservableComment, b: ObservableComment) => {
    if (byHeat && a.like !== b.like) return b.like - a.like;
    return a.ctime - b.ctime || a.rpid - b.rpid;
  });
}
