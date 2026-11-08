import { PageWallpaper } from '../components/PageWallpaper';
// 整页和横屏分栏共用消息实现，保持接收、历史分页和内容渲染一致。
import { router } from '@kit.ArkUI';
import { WhisperChatView } from '../components/WhisperChatView';

@Entry
@Component
struct WhisperDetailPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @State talkerId: number = 0;
  @State talkerName: string = '';
  @State talkerFace: string = '';
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.talkerId = (params['talkerId'] as number) || 0;
      this.talkerName = (params['name'] as string) || '';
      this.talkerFace = (params['face'] as string) || '';
    }
  }



  build() {
    Stack() {
      PageWallpaper()
    Stack() {
      WhisperChatView({
        talkerId: this.talkerId,
        talkerName: this.talkerName,
        talkerFace: this.talkerFace,
        statusBarHeight: this.statusBarHeight
      })
    }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
