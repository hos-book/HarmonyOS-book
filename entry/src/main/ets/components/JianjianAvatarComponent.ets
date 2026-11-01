import { JianjianRenderController } from '../service/JianjianRenderController';

/** 原生网格人物：各部位独立权重变形，眼睑跟随同一网格，不使用 Web。 */
@ComponentV2
export struct JianjianAvatarComponent {
  @Param running: boolean = false;
  @Param reacting: boolean = false;
  @Param reactionIndex: number = -1;
  @Local leftClosed: boolean = false;
  @Local rightClosed: boolean = false;
  @Local ready: boolean = false;
  private renderer: JianjianRenderController = new JianjianRenderController();
  private mounted: boolean = false;
  private blinkTimer: number = -1;
  private reopenTimer: number = -1;
  private generation: number = 0;

  aboutToAppear(): void {
    this.renderer.onReady = (): void => { this.ready = true; };
  }

  @Monitor('leftClosed', 'rightClosed')
  onEyesChanged(): void {
    this.renderer.setEyes(this.leftClosed, this.rightClosed);
  }

  @Monitor('running', 'reacting', 'reactionIndex')
  onAnimationChanged(): void {
    this.restart();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearTimers();
    this.renderer.release();
  }

  private clearTimers(): void {
    this.generation++;
    if (this.blinkTimer !== -1) {
      clearTimeout(this.blinkTimer);
      this.blinkTimer = -1;
    }
    if (this.reopenTimer !== -1) {
      clearTimeout(this.reopenTimer);
      this.reopenTimer = -1;
    }
  }

  private restart(): void {
    this.clearTimers();
    this.renderer.update(this.mounted && this.running, this.reacting, this.reactionIndex);
    this.leftClosed = false;
    this.rightClosed = false;
    if (!this.mounted || !this.running) return;
    if (this.reacting && this.reactionIndex === 3) {
      // 困倦表情与气泡同寿命；气泡结束后恢复自然眨眼。
      this.leftClosed = true;
      this.rightClosed = true;
    } else if (this.reacting && (this.reactionIndex === 0 || this.reactionIndex === 6 ||
      this.reactionIndex === 8)) {
      this.blink(this.reactionIndex === 6, 480);
    } else {
      this.scheduleBlink();
    }
  }

  private scheduleBlink(): void {
    if (!this.mounted || !this.running) return;
    const current: number = this.generation;
    // 眨眼只在边界调度；全身网格动画由独立的原生绘制控制器刷新。
    this.blinkTimer = setTimeout((): void => {
      if (current !== this.generation || !this.mounted || !this.running) return;
      this.blinkTimer = -1;
      this.blink(false, 150);
    }, 2600 + Math.random() * 2600);
  }

  private blink(wink: boolean, duration: number): void {
    const current: number = this.generation;
    this.leftClosed = true;
    this.rightClosed = !wink;
    this.reopenTimer = setTimeout((): void => {
      if (current !== this.generation || !this.mounted || !this.running) return;
      this.reopenTimer = -1;
      this.leftClosed = false;
      this.rightClosed = false;
      this.scheduleBlink();
    }, duration);
  }

  build() {
    Stack() {
      if (!this.ready) {
        Image($r('app.media.jianjian_native_idle'))
          .width(96).height(112).objectFit(ImageFit.Contain).draggable(false)
      }
      NodeContainer(this.renderer)
        .width(96).height(112).hitTestBehavior(HitTestMode.None)
    }
    .width(96).height(112)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
    .onAppear((): void => {
      this.mounted = true;
      this.restart();
    })
  }
}
