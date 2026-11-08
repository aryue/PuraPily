/** 首次加载统一从顶栏下方开始，避免频道各自按屏高或轮播高度居中。 */
@Component
export struct HomeInitialLoading {
  @Prop color: string = '#FB7299';
  @Prop topInset: number = 0;
  @Prop refreshing: boolean = false;

  build() {
    Column() {
      Row() {
        // 下拉提示接管加载状态时保留占位，只撤下首次加载的进度环。
        if (!this.refreshing) {
          LoadingProgress().width(40).height(40).color(this.color)
        }
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    }.width('100%').padding({ top: this.topInset })
      .id('home-initial-loading')
      .hitTestBehavior(HitTestMode.None)
  }
}
