import { OneShotLayoutCallback } from '../utils/OneShotTransition';

/** 原生单次开屏；不创建 WebView，不等待网络或阻塞首页初始化。 */
@ComponentV2
export struct StartupSplash {
  @Event onFinished: () => void = (): void => {};
  @Local glowVisible: boolean = false;
  @Local titleVisible: boolean = false;
  @Local taglineVisible: boolean = false;
  @Local splashOpacity: number = 1;
  @Local viewportHeight: number = 667;
  @Local artworkScale: number = 1;
  private timers: number[] = [];
  private disposed: boolean = false;
  private started: boolean = false;

  aboutToDisappear(): void {
    this.disposed = true;
    this.timers.forEach((timer: number): void => clearTimeout(timer));
    this.timers = [];
  }

  private later(delay: number, action: () => void): void {
    this.timers.push(setTimeout((): void => {
      if (!this.disposed) action();
    }, delay));
  }

  private start(): void {
    if (this.started) return;
    this.started = true;
    // 首帧提交后再启动，避免初始透明态被合并进动画终态。
    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
      if (this.disposed) return;
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
        this.glowVisible = true;
      });
      this.later(580, (): void => {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
          this.titleVisible = true;
        });
      });
      this.later(660, (): void => {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
          this.taglineVisible = true;
        });
      });
      this.later(1120, (): void => {
        this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
          this.splashOpacity = 0;
        });
      });
      this.later(1300, (): void => this.onFinished());
    }));
    // 即使首帧回调异常也释放遮罩。
    this.later(1700, (): void => this.onFinished());
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.splash_gel_glow'))
        // 画布比光晕主体多出三倍模糊半径，边缘完全透明，避免顶部矩形断层。
        .width(720 * this.artworkScale).height(720 * this.artworkScale)
        .objectFit(ImageFit.Contain)
        .position({ x: '50%', y: '43%' })
        .translate({ x: -360 * this.artworkScale, y: -360 * this.artworkScale })
        .scale({ x: this.glowVisible ? 1.05 : 0.72, y: this.glowVisible ? 1.05 : 0.72 })
        .opacity(this.glowVisible ? 0.45 : 0)
      Stack() {
        StartupSplashBar({ artwork: $r('app.media.splash_gel_bar1'), delayMs: 150 })
        StartupSplashBar({ artwork: $r('app.media.splash_gel_bar2'), delayMs: 270 })
        StartupSplashBar({ artwork: $r('app.media.splash_gel_bar3'), delayMs: 390 })
        StartupSplashBar({ artwork: $r('app.media.splash_gel_bar4'), delayMs: 510 })
      }
      .width(132 * this.artworkScale).height(132 * this.artworkScale)
      .position({ x: '50%', y: '43%' })
      .translate({ x: -66 * this.artworkScale, y: -63 * this.artworkScale })
      Column({ space: 12 }) {
        Text($r('app.string.splash_brand_name'))
          .fontSize(26).fontWeight(FontWeight.Medium).letterSpacing(3)
          .fontColor($r('app.color.splash_brand_text'))
          .textAlign(TextAlign.Center).width('100%')
          .translate({ y: this.titleVisible ? 0 : 14 }).opacity(this.titleVisible ? 1 : 0)
        Text($r('app.string.splash_brand_tagline'))
          .fontSize(14).letterSpacing(3)
          .fontColor($r('app.color.splash_brand_caption'))
          .textAlign(TextAlign.Center).width('100%')
          .translate({ y: this.taglineVisible ? 0 : 14 }).opacity(this.taglineVisible ? 1 : 0)
      }
      .width('100%')
      .position({ x: 0, y: this.viewportHeight * 0.43 + 101 * this.artworkScale })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.start_window_background'))
    .opacity(this.splashOpacity).clip(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
      this.viewportHeight = Number(current.height);
      this.artworkScale = Math.min(1.25, Number(current.width) / 300, this.viewportHeight / 667);
    })
    .onAppear((): void => this.start())
    .hitTestBehavior(HitTestMode.Block)
  }
}

@ComponentV2
struct StartupSplashBar {
  @Param artwork: Resource = $r('app.media.splash_gel_bar1');
  @Param delayMs: number = 0;
  @Local illuminated: boolean = false;
  private timer: number = -1;

  aboutToDisappear(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
  }

  build() {
    Image(this.artwork)
      .width('100%').height('100%').objectFit(ImageFit.Contain)
      .opacity(this.illuminated ? 1 : 0)
      .translate({ y: this.illuminated ? 0 : 10 })
      .onAppear((): void => {
        this.timer = setTimeout((): void => {
          this.getUIContext().animateTo({ duration: 144, curve: Curve.EaseOut }, (): void => {
            this.illuminated = true;
          });
        }, this.delayMs);
      })
  }
}
