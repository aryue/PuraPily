import { NativeComposerSurface } from './NativeComposerSurface';
// 评论/回复编辑器：多行草稿、工具栏、快捷表情与图片草稿。
import { promptAction, uiMaterial, RectShape, Animator, AnimatorResult } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { logError, errMsg } from '../utils/Logger';
import { VibrateUtils } from '../utils/VibrateUtils';

import { ChatEmote, ChatEmoteItem, ChatEmotePackage } from '../utils/ChatEmote';

/** 评论图片草稿（相册已选、尚未上传） */
export class CommentImageDraft {
  /** 沙箱内绝对路径 */
  path: string = '';
  /** 扩展名（jpg | png | gif） */
  ext: string = '';
  /** MIME 类型 */
  mime: string = '';
}

/** 图片格式探测结果 */
class ImageTypeInfo {
  /** 扩展名（jpg | png | gif） */
  ext: string = '';
  /** MIME 类型 */
  mime: string = '';
}

/**
 * ⭐ 评论输入栏控制器：把"收起表情面板"的能力暴露给**父页**。
 *
 * 使用场景：表情面板展开时，**侧滑返回 / 返回键**的语义应当是"先收起面板"，
 * 而不是退出页面 / 关掉整个输入弹层（父页在 `onWillDismiss` 的 `PRESS_BACK` 分支里用）。
 *
 * 为什么用控制器、而不是"父页自己记一份开合状态"：面板是否展开的**真值在组件内部**
 * （`showEmote` / `emoteH`）。父页自己记一份就会失步 —— 内部因别的原因收起时
 * （点输入框 `onFocus` 瞬时收起、半模态收起重建…）父页仍以为开着，
 * 表现为"返回键第一下没反应、要按两次"。直接问组件本体永远一致。
 *
 * 用法：
 * ```ts
 * private emoteCtrl: CommentInputBarCtrl = new CommentInputBarCtrl();
 * CommentInputBar({ ctrl: this.emoteCtrl, ... })
 * // 返回键分支：
 * if (a.reason === DismissReason.PRESS_BACK && this.emoteCtrl.collapseEmote()) {
 *   return;   // 面板本来开着 → 已收起，吞掉本次返回
 * }
 * ```
 */
export class CommentInputBarCtrl {
  /** 收起实现（由 CommentInputBar 在 aboutToAppear 注册、aboutToDisappear 注销） */
  private collapseImpl: () => boolean = (): boolean => false;

  /** 注册收起实现（仅组件内部调用） */
  bindImpl(impl: () => boolean): void {
    this.collapseImpl = impl;
  }

  /** 注销（仅组件内部调用）：避免父页误调到已销毁实例 */
  unbind(): void {
    this.collapseImpl = (): boolean => false;
  }

  /**
   * 收起表情面板。
   * @returns true = 面板本来展开、本次已收起（调用方应**吞掉**这次返回）；
   *          false = 面板本来就没开（调用方继续走原本的返回逻辑）
   */
  collapseEmote(): boolean {
    try {
      return this.collapseImpl();
    } catch (_e) {
      return false;
    }
  }
}

@Component
export struct CommentInputBar {
  /** ⭐ 父页持有的控制器（见 CommentInputBarCtrl）：供父页在侧滑返回/返回键时先收面板 */
  ctrl: CommentInputBarCtrl = new CommentInputBarCtrl();
  @Prop materialEnabled: boolean = true;
  /** 发送回调：content 为已还原表情标记（[doge] 等）的文本；pictures 为已选图片草稿；
   *  返回 true=发送成功（父页关闭弹层），false=失败（保留内容与已选图） */
  onSend: (content: string, pictures: CommentImageDraft[]) => Promise<boolean> = async () => false;
  /** 表情面板开/关回调 */
  onEmoteChange: (open: boolean) => void = () => {};
  onHeightChange: (height: number) => void = () => {};
  /** 输入框占位文案 */
  @Prop placeholder: string = '发个友善的评论鼓励一下';
  /** 是否显示插入图片按钮（回复评论时隐藏，仅一级评论可用） */
  @Prop showImageButton: boolean = true;
  /**
   * ⭐ 出现时是否自动聚焦（默认 true，保持播放页/评论详情页原有行为）。
   *    传 false 时**不主动弹输入法**：适合"底部悬浮胶囊展开输入区"这类场景——
   *    用户点了胶囊只是想发评论，不该立刻被键盘顶起半屏。
   */
  @Prop autoFocus: boolean = true;
  @State expanded: boolean = false;
  /** 发送中 */
  @State isSending: boolean = false;
  /** 输入内容是否非空（控制占位与发布按钮） */
  @State hasContent: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  /** ⭐ 是否显示表情面板（页面内渲染，动画展开/收起） */
  @State showEmote: boolean = false;
  /** 表情面板高度（0=收起，Animator 逐帧驱动与消息区同步伸缩） */
  @State emoteH: number = 0;
  private emoteAnimator: AnimatorResult | null = null;
  /** 当前选中表情分类索引 */
  @State emotePkgIdx: number = 0;
  @State private emoteGridWidth: number = 0;
  /** 表情表是否已加载（加载后触发面板重建） */
  @State emoteReady: boolean = false;
  /** 已选图片草稿（上限 9 张，发送时由父页上传） */
  @State pictureDrafts: CommentImageDraft[] = [];
  /** 输入框控制器 */
  private richEditorController: RichEditorController = new RichEditorController();
  private editorReady: boolean = false;
  private focusPending: boolean = false;
  private focusTimer: number = -1;

  private requestEditorFocus(attempt: number = 0): void {
    this.focusPending = true;
    if (!this.editorReady) return;
    if (this.focusTimer >= 0) clearTimeout(this.focusTimer);
    this.focusTimer = -1;
    this.getUIContext().getFocusController().requestFocus('comment_rich_editor');
    if (this.focusPending && attempt < 6) {
      // A sheet may have mounted its editor before its focus scope becomes active.
      this.focusTimer = setTimeout(() => { this.requestEditorFocus(attempt + 1); }, 40);
    }
  }

  aboutToAppear(): void {
    // ⭐ 注册"收起面板"实现：父页在侧滑返回/返回键时调 ctrl.collapseEmote()（见 CommentInputBarCtrl）。
    //    返回 true 表示"面板本来开着、已收起"，父页据此吞掉这次返回。
    this.ctrl.bindImpl((): boolean => {
      if (!this.showEmote) {
        return false;
      }
      this.setEmotePanel(false);
      return true;
    });
    // ⭐ 立即预加载表情表；加载完成后置 emoteReady 触发面板刷新（无需手动重试）
    ChatEmote.ensureLoaded().then(() => {
      if (ChatEmote.getPackages().length > 0) {
        this.emoteReady = true;
      }
    });
  }

  aboutToDisappear(): void {
    this.editorReady = false;
    this.focusPending = false;
    if (this.focusTimer >= 0) clearTimeout(this.focusTimer);
    this.focusTimer = -1;
    // ⭐ 解绑（弹层关闭会销毁本组件）：父页再调 collapseEmote() 必须返回 false，
    //    不能去碰已销毁的实例（否则返回键会被无故吞掉）。
    this.ctrl.unbind();
  }

  /**
   * 发送评论（文本 + 已选图片草稿一并交给父页）
   */
  private async sendMessage(): Promise<void> {
    const content = this.buildSendContent().trim();
    if (!content && this.pictureDrafts.length === 0) {
      promptAction.showToast({ message: '输入内容不能为空' });
      return;
    }
    if (this.isSending) {
      return;
    }
    this.isSending = true;
    try {
      const ok = await this.onSend(content, this.pictureDrafts.slice());
      if (ok) {
        this.clearAll();
      }
    } catch (err) {
      logError(`[CommentInputBar] 发送失败: ${errMsg(err)}`);
      promptAction.showToast({ message: '发送失败' });
    }
    this.isSending = false;
  }

  private clearAll(): void {
    try {
      this.richEditorController.deleteSpans({ start: 0, end: 999999 });
    } catch (_) {}
    this.hasContent = false;
    this.pictureDrafts = [];
  }

  private insertEmote(emote: ChatEmoteItem): void {
    this.richEditorController.addImageSpan(emote.url, {
      offset: this.richEditorController.getCaretOffset(),
      imageStyle: { size: [26, 26] }
    });
    this.hasContent = true;
  }

  /** ⭐ 把富文本内容序列化为发送文本：文字段直取，图片段还原为 [xx] 表情标记 */
  private buildSendContent(): string {
    let content = '';
    const spans = this.richEditorController.getSpans();
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i];
      const textSpan = span as RichEditorTextSpanResult;
      if (textSpan.value) {
        content += textSpan.value;
      } else {
        const imgSpan = span as RichEditorImageSpanResult;
        content += ChatEmote.getTextByUrl(imgSpan.valueResourceStr as string) || '';
      }
    }
    return content;
  }

  /** ⭐ 删除光标前一个字符/表情（退格语义） */
  private deleteLastEmote(): void {
    const caret: number = this.richEditorController.getCaretOffset();
    if (caret > 0) {
      try {
        this.richEditorController.deleteSpans({ start: caret - 1, end: caret });
      } catch (_) {}
    }
    this.hasContent = this.richEditorController.getSpans().length > 0;
  }

  /** ⭐ 逐帧驱动 emoteH（Animator 确定能动画，展开/收起均平滑） */
  private animateEmoteH(to: number): void {
    if (this.emoteAnimator) {
      this.emoteAnimator.cancel();
      this.emoteAnimator = null;
    }
    const from: number = this.emoteH;
    if (Math.abs(from - to) < 0.5) {
      this.emoteH = to;
      return;
    }
    this.emoteAnimator = Animator.create({
      duration: 260,
      easing: 'ease-in-out',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: 0,
      end: 1
    });
    this.emoteAnimator.onframe = (p: number) => {
      this.emoteH = from + (to - from) * p;
    };
    this.emoteAnimator.onfinish = () => {
      this.emoteH = to;
      this.emoteAnimator = null;
    };
    this.emoteAnimator.oncancel = () => {
      this.emoteAnimator = null;
    };
    this.emoteAnimator.play();
  }

  /**
   * ⭐ 开/关表情面板（页面内渲染，260ms 高度动画）：
   *    开面板前清焦点收掉系统键盘（若有）；点输入框时 onFocus 自动收面板
   */
  private setEmotePanel(open: boolean): void {
    if (open) {
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (_) {}
    }
    this.showEmote = open;
    this.onEmoteChange(open);
    this.animateEmoteH(open ? 300 : 0);
  }

  /** ⭐ 轻震动反馈 */
  private triggerHaptic(): void {
    try {
      VibrateUtils.vibrateTime(15);
    } catch (_) {}
  }

  /** ⭐ 当前选中分类的表情列表 */
  private emoteCellWidth(): number {
    if (this.emoteGridWidth <= 0) return 48;
    const visibleColumns = Math.max(1, Math.floor((this.emoteGridWidth + 6) / 54));
    const contentColumns = Math.max(1, Math.ceil(this.currentEmoteList().length / 4));
    const columns = Math.min(visibleColumns, contentColumns);
    return Math.max(48, (this.emoteGridWidth - (columns - 1) * 6) / columns);
  }

  private currentEmoteList(): ChatEmoteItem[] {
    const pkgs = ChatEmote.getPackages();
    if (pkgs.length === 0) {
      return [];
    }
    return pkgs[Math.min(this.emotePkgIdx, pkgs.length - 1)].emotes;
  }

  /**
   * 选择图片加入草稿（选图 → 拷贝到沙箱 → 魔数探测格式；上传在父页发送时进行）
   */
  private async pickImage(): Promise<void> {
    if (this.isSending) {
      return;
    }
    if (this.pictureDrafts.length >= 9) {
      promptAction.showToast({ message: '最多选择9张图片' });
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const photoSelectResult = await photoViewPicker.select(photoSelectOptions);
      if (photoSelectResult.photoUris.length === 0) {
        return; // 用户取消
      }
      const sourceUri = photoSelectResult.photoUris[0];
      // ⚠️ 相册 URI 是媒体库临时授权路径，上传必须先用 fileIo 拷贝到沙箱
      const destUri = `${context.filesDir}/comment_img_${Date.now()}`;
      const srcFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUri, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      const buffer = new ArrayBuffer(4096);
      let readLen = 0;
      while ((readLen = fileIo.readSync(srcFile.fd, buffer)) > 0) {
        fileIo.writeSync(destFile.fd, buffer.slice(0, readLen));
      }
      fileIo.closeSync(srcFile.fd);
      fileIo.closeSync(destFile.fd);
      // 读取文件头判断格式（B站图床仅支持 jpg/png/gif）
      const extMime = this.detectImageType(destUri);
      if (!extMime) {
        promptAction.showToast({ message: '仅支持 jpg/png/gif 图片' });
        return;
      }
      const draft = new CommentImageDraft();
      draft.path = destUri;
      draft.ext = extMime.ext;
      draft.mime = extMime.mime;
      const arr = this.pictureDrafts.slice();
      arr.push(draft);
      this.pictureDrafts = arr;
    } catch (err) {
      logError(`[CommentInputBar] 选择图片失败: ${errMsg(err)}`);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  /** ⭐ 移除某张图片草稿 */
  private removeDraft(idx: number): void {
    const arr = this.pictureDrafts.slice();
    arr.splice(idx, 1);
    this.pictureDrafts = arr;
  }

  /**
   * 探测图片格式（读文件头魔数，仅支持 jpg/png/gif）
   * @returns 格式信息；不支持返回 null
   */
  private detectImageType(filePath: string): ImageTypeInfo | null {
    try {
      const probe = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const head = new ArrayBuffer(8);
      fileIo.readSync(probe.fd, head);
      fileIo.closeSync(probe.fd);
      const bytes = new Uint8Array(head);
      // JPEG: FF D8 FF；PNG: 89 50 4E 47；GIF: 47 49 46 38
      if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
        return { ext: 'jpg', mime: 'image/jpeg' };
      }
      if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
        return { ext: 'png', mime: 'image/png' };
      }
      if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
        return { ext: 'gif', mime: 'image/gif' };
      }
      return null;
    } catch (err) {
      logError(`[CommentInputBar] 探测图片格式失败: ${errMsg(err)}`);
      return null;
    }
  }

  private getCapsuleMaterial(): uiMaterial.ImmersiveMaterial | null {
    return null;
  }

  private composerBg(): ResourceColor {
    return Color.Transparent;
  }

  private quickEmotes(): ChatEmoteItem[] {
    if (!this.emoteReady) return [];
    const packages = ChatEmote.getPackages();
    const standard = packages.find((pkg: ChatEmotePackage) =>
      pkg.emotes.some((emote: ChatEmoteItem) => emote.text === '[doge]'));
    return (standard ? standard.emotes : ChatEmote.getList()).slice(0, 14);
  }

  @Builder
  editorContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      RichEditor({ controller: this.richEditorController })
        .width('100%').height('100%')
        .padding({ left: 0, right: 32, top: 10, bottom: 8 })
        .backgroundColor(Color.Transparent)
        .caretColor('#FB7299')
        .id('comment_rich_editor')
        .defaultFocus(this.autoFocus)
        .enableKeyboardOnFocus(true)
        .onReady(() => {
          this.richEditorController.setTypingStyle({ fontSize: 16,
            fontColor: this.isDarkMode ? '#F1F2F3' : '#18191C' });
          this.richEditorController.setTypingParagraphStyle({ textAlign: TextAlign.Start });
          this.editorReady = true;
          if (this.autoFocus || this.focusPending) this.requestEditorFocus();
        })
        .onFocus(() => {
          this.focusPending = false;
          if (this.focusTimer >= 0) clearTimeout(this.focusTimer);
          this.focusTimer = -1;
          if (this.showEmote) {
            this.emoteAnimator?.cancel();
            this.emoteAnimator = null;
            this.emoteH = 0;
            this.showEmote = false;
            this.onEmoteChange(false);
          }
        })
        .onDidChange(() => {
          this.hasContent = this.richEditorController.getSpans().length > 0;
        })
      if (!this.hasContent) {
        Text(this.placeholder).fontSize(16).fontColor('#797D84')
          .padding({ top: 10, right: 32 }).hitTestBehavior(HitTestMode.None)
      }
      Row() {
        Blank()
        Image(this.expanded ? $r('app.media.comment_editor_collapse') : $r('app.media.ref_fullscreen'))
          .width(18).height(18)
          .fillColor('#797D84').margin(6)
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
              this.expanded = !this.expanded;
            });
          })
          .accessibilityText(this.expanded ? '收起编辑区' : '展开编辑区')
      }.width('100%')
    }.width('100%').height(this.expanded ? 220 : 92)
  }

  @Builder
  toolIcon(icon: Resource, label: string, action: () => void) {
    Button() {
      Image(icon).width(24).height(24).fillColor('#92969D')
    }.width(40).height(40).padding(8).backgroundColor(Color.Transparent)
      .accessibilityText(label).enabled(!this.isSending).onClick(action)
  }

  build() {
    NativeComposerSurface({ active: this.materialEnabled }) {
    Column() {
      this.editorContent()
      if (this.pictureDrafts.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.pictureDrafts, (draft: CommentImageDraft, idx: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image('file://' + draft.path).width(56).height(56)
                  .objectFit(ImageFit.Cover).borderRadius(6)
                Text('×').width(20).height(20).textAlign(TextAlign.Center)
                  .fontColor(Color.White).backgroundColor('#99000000').borderRadius(10)
                  .onClick(() => { this.removeDraft(idx); })
              }
            }, (draft: CommentImageDraft) => draft.path)
          }
        }.width('100%').height(64).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      Row({ space: 6 }) {
        this.toolIcon($r('app.media.expression'), '表情', () => {
          this.emoteReady = true;
          this.setEmotePanel(!this.showEmote);
        })
        this.toolIcon($r('app.media.at_outline'), '插入@', () => {
          this.richEditorController.addTextSpan('@', { offset: this.richEditorController.getCaretOffset() });
          this.hasContent = true;
          this.getUIContext().getFocusController().requestFocus('comment_rich_editor');
        })
        if (this.showImageButton) {
          this.toolIcon($r('app.media.plus'), '添加图片', () => { this.pickImage(); })
        }
        Blank()
        // 显式内容与内边距，避免系统 Button 默认内边距挤掉自定义字体文字。
        Button() {
          Text(this.isSending ? '发布中' : '发布')
            .fontSize(14).fontColor(Color.White).maxLines(1)
        }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .constraintSize({ minWidth: 64, minHeight: 32 }).flexShrink(0)
          .id('comment-publish').accessibilityText(this.isSending ? '发布中' : '发布')
          .backgroundColor('#FB7299').borderRadius(18)
          .opacity((this.hasContent || this.pictureDrafts.length > 0) ? 1 : 0.4)
          .enabled(!this.isSending && (this.hasContent || this.pictureDrafts.length > 0))
          .onClick(() => { this.sendMessage(); })
      }.width('100%').height(48)
      if (this.quickEmotes().length > 0) {
        Scroll() {
          Row({ space: 16 }) {
            ForEach(this.quickEmotes(), (emote: ChatEmoteItem) => {
              Image(emote.url).width(28).height(28).objectFit(ImageFit.Contain)
                .accessibilityText(emote.text).onClick(() => { this.insertEmote(emote); })
            }, (emote: ChatEmoteItem) => emote.text)
          }.padding({ left: 4, right: 4 })
        }.width('100%').height(44).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .border({ width: { top: 0.5 }, color: this.isDarkMode ? '#292C30' : '#EEEEEE' })
      }
      Column() {
        if (this.emoteH > 0) { this.emotePanel() }
      }.width('100%').height(this.emoteH).clip(true)
    }.width('100%').padding({ left: 12, right: 12 })
      .onAreaChange((_old: Area, area: Area) => { this.onHeightChange(Number(area.height)); })
    }
  }

  /** ⭐ 表情面板（页面内弹出层：分类 tab + 表情网格 + 删除按钮；emoteH 驱动动画） */
  @Builder
  emotePanel() {
    Column() {
      if (ChatEmote.getPackages().length > 0) {
        Column() {
          Row() {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(ChatEmote.getPackages(), (pkg: ChatEmotePackage, idx: number) => {
                  Column() {
                    if (pkg.url) {
                      Image(pkg.url)
                        .width(26).height(26)
                        .objectFit(ImageFit.Contain)
                    } else {
                      Text(pkg.name).fontSize(11).fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
                    }
                  }
                  .width(40).height(40)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor(idx === this.emotePkgIdx
                    ? 'rgba(0,174,236,0.25)'
                    : (this.isDarkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)'))
                  .borderRadius(10)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.82 })
                  .onClick(() => { this.triggerHaptic(); this.emotePkgIdx = idx; })
                }, (pkg: ChatEmotePackage) => pkg.id.toString())
              }
              .padding({ left: 12, right: 12 })
            }
            .scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart)
            .scrollBar(BarState.Off)
            .height(44)
            .layoutWeight(1)

            // ⭐ 删除按钮：删除输入框最后一个表情/字符
            Column() {
              Image($r('app.media.backspace_1'))
                .width(22).height(22)
                .fillColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            }
            .width(40).height(40)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)')
            .borderRadius(10)
            .margin({ right: 22 })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.82 })
            .onClick(() => { this.triggerHaptic(); this.deleteLastEmote(); })
          }
          .width('100%')

          // Keep four-row horizontal scrolling; distribute visible columns across the actual width.
          Grid() {
            ForEach(this.currentEmoteList(), (emote: ChatEmoteItem) => {
              GridItem() {
                Column() {
                  if (emote.url) {
                    Image(emote.url)
                      .width(42).height(42)
                      .objectFit(ImageFit.Contain)
                  } else {
                    Text(emote.text)
                      .fontSize(12)
                      .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
                  }
                }
                .width(this.emoteCellWidth())
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.82 })
                .onClick(() => { this.triggerHaptic(); this.insertEmote(emote); })
              }.width(this.emoteCellWidth())
            }, (emote: ChatEmoteItem) => emote.text)
          }
          .rowsTemplate('repeat(4, 1fr)')
          .columnsGap(6)
          .rowsGap(6)
          // ⭐ 高度同私信表情框（4行*42 + 3*6 间距 + 上下 4/10 padding = 234）
          .height(234)
          .width('100%')
          // ⚠️ 横向滚动时 Grid 自身 padding 对滚动内容不生效（2026-09-24 用户实测）
          //    ⇒ 左右安全边距只保留在面板根节点，网格按实际可见宽度计算列宽。
          .padding({ top: 4, bottom: 10 })
          .id('comment-emote-grid')
          .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
            const width = Number(size.width);
            if (width > 0 && Math.abs(width - this.emoteGridWidth) > 0.5) this.emoteGridWidth = width;
          })
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height(300)
        .clip(true)
        .clipShape(new RectShape({ width: '100%', height: '100%', radius: 22 }))
        .borderRadius(22)
        .systemMaterial(this.getCapsuleMaterial())
        .backgroundColor(this.composerBg())
        .border({ width: { top: 0.5 }, color: this.isDarkMode ? '#292C30' : '#EEEEEE' })
        // ⭐ 左右 8vp 安全边距加在面板根上（与私信表情面板同款）：表情改为横向滚动后
        //    Grid 自身的横向 padding 不生效，靠这里保证内容在任意滚动位置都不出圆角框
        .padding({ left: 8, right: 8, top: 4 })
      } else {
        // 未加载 / 未登录
        Column() {
          Text('表情加载中或未登录').fontSize(13).fontColor('#999999')
          Button() { Text('重试').fontSize(13).fontColor('#007DFF') }
            .height(32)
            .margin({ top: 8 })
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              ChatEmote.waitForLoaded().then(() => { this.emoteReady = true; });
            })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .clip(true)
        .clipShape(new RectShape({ width: '100%', height: '100%', radius: 22 }))
        .borderRadius(22)
        .systemMaterial(this.getCapsuleMaterial())
        .backgroundColor(this.composerBg())
        .border({ width: { top: 0.5 }, color: this.isDarkMode ? '#292C30' : '#EEEEEE' })
      }
    }
    .width('100%')
    .height(300)
    .padding({ bottom: 12 })
  }
}
