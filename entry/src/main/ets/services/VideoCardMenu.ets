import { UIContext, promptAction } from '@kit.ArkUI';
import { VideoCardFeedback } from './VideoCardFeedback';

/** All video-card entry points share one system window and action ordering. */
export class VideoCardMenu {
  static async show(context: UIContext, title: string, videoId: string, ownerMid: string,
    dark: boolean): Promise<void> {
    const actions = VideoCardFeedback.actions(videoId, ownerMid);
    if (actions.length === 0) return;
    const prompt = context.getPromptAction();
    const color = dark ? '#E7E9EB' : '#18191C';
    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?,
      promptAction.Button?, promptAction.Button?, promptAction.Button?] = [
      { text: actions[0], color: color }
    ];
    for (let index = 1; index < actions.length; index++) {
      buttons.push({ text: actions[index], color: color });
    }
    try {
      const result = await prompt.showActionMenu({ title: title, buttons: buttons });
      if (result.index >= 0 && result.index < actions.length) {
        const message = await VideoCardFeedback.perform(actions[result.index], videoId, ownerMid);
        prompt.showToast({ message: message, duration: 1500 });
      }
    } catch (_) {
      // Dismissing the system window leaves the card unchanged.
    }
  }
}
