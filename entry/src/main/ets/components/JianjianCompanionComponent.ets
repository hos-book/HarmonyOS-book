import { AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

/** 根导航上的单实例人物；空白区域透传，路由切换时保留位置。 */
@ComponentV2
export struct JianjianCompanionComponent {
  @Param active: boolean = true;
  @Local dragging: boolean = false;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local characterX: number = 0;
  @Local characterY: number = 0;
  private positioned: boolean = false;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private suppressClickUntil: number = 0;
  @Local inViewport: boolean = false;
  @Local delighted: boolean = false;
  @Local raised: boolean = false;
  @Local idleLifted: boolean = false;
  private idleAnimationRunning: boolean = false;
  @Local phraseIndex: number = -1;
  private resetTimer: number = -1;
  private readonly phrases: Resource[] = [
    $r('app.string.jianjian_reply_hello'),
    $r('app.string.jianjian_reply_shy'),
    $r('app.string.jianjian_reply_surprised'),
    $r('app.string.jianjian_reply_rest'),
    $r('app.string.jianjian_reply_crying'),
    $r('app.string.jianjian_reply_angry'),
    $r('app.string.jianjian_reply_wink'),
    $r('app.string.jianjian_reply_reading'),
    $r('app.string.jianjian_reply_heart')
  ];
  private readonly expressions: Resource[] = [
    $r('app.media.jianjian_red_happy'),
    $r('app.media.jianjian_red_shy'),
    $r('app.media.jianjian_red_surprised'),
    $r('app.media.jianjian_red_sleepy'),
    $r('app.media.jianjian_red_crying'),
    $r('app.media.jianjian_red_angry'),
    $r('app.media.jianjian_red_wink'),
    $r('app.media.jianjian_red_reading'),
    $r('app.media.jianjian_red_heart')
  ];

  aboutToDisappear(): void {
    this.clearReaction();
  }

  @Monitor('active')
  onActiveChanged(): void {
    if (!this.active) {
      this.stopReaction();
      this.finishDrag();
    }
    this.syncIdleAnimation();
  }

  private syncIdleAnimation(): void {
    const running: boolean = this.active && this.inViewport;
    if (running === this.idleAnimationRunning) return;
    this.idleAnimationRunning = running;
    // 交给渲染侧做轻微呼吸起伏，隐藏时取消，不用 JS 定时器逐帧驱动。
    this.getUIContext().animateTo({ duration: running ? 1800 : 0,
      iterations: running ? -1 : 1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut }, (): void => {
      this.idleLifted = running;
    });
  }

  private clearReaction(): void {
    if (this.resetTimer !== -1) {
      clearTimeout(this.resetTimer);
      this.resetTimer = -1;
    }
  }

  private stopReaction(): void {
    this.clearReaction();
    this.delighted = false;
    this.raised = false;
  }

  private clampX(positionX: number): number {
    return Math.max(8, Math.min(positionX, this.viewportWidth - 112));
  }

  private clampY(positionY: number): number {
    const top: number = WindowUtils.getStatusBarHeightVp() + 8;
    const bottom: number = Math.max(top, this.viewportHeight - 124 - WindowUtils.getBottomSafeVp() - 8);
    return Math.max(top, Math.min(positionY, bottom));
  }

  private resize(newSize: SizeOptions): void {
    const nextWidth: number = Number(newSize.width);
    const nextHeight: number = Number(newSize.height);
    if (!Number.isFinite(nextWidth) || !Number.isFinite(nextHeight) || nextWidth <= 0 || nextHeight <= 0) return;
    this.viewportWidth = nextWidth;
    this.viewportHeight = nextHeight;
    if (!this.positioned) {
      this.characterX = nextWidth - 116;
      this.characterY = nextHeight - 124 - WindowUtils.getFloatingTabBottomVp() - 16;
      this.positioned = true;
    }
    this.characterX = this.clampX(this.characterX);
    this.characterY = this.clampY(this.characterY);
    this.finishDrag();
  }

  private beginDrag(): void {
    this.stopReaction();
    this.dragStartX = this.characterX;
    this.dragStartY = this.characterY;
    this.dragging = true;
  }

  private moveDrag(event: GestureEvent): void {
    if (!this.dragging) return;
    this.characterX = this.clampX(this.dragStartX + event.offsetX);
    this.characterY = this.clampY(this.dragStartY + event.offsetY);
  }

  private finishDrag(): void {
    if (this.dragging) this.suppressClickUntil = Date.now() + 300;
    this.dragging = false;
  }

  private bubbleX(): number {
    return Math.max(8, Math.min(this.characterX + 52 - this.bubbleWidth() / 2,
      this.viewportWidth - this.bubbleWidth() - 8));
  }

  private bubbleWidth(): number {
    return Math.min(216, Math.max(128, this.viewportWidth - 16));
  }

  private bubbleY(): number {
    const above: number = this.characterY - 108;
    const desired: number = above >= WindowUtils.getStatusBarHeightVp() + 8 ? above : this.characterY + 128;
    return Math.max(8, Math.min(desired, this.viewportHeight - 108 - WindowUtils.getBottomSafeVp()));
  }

  private interact(): void {
    if (this.dragging || Date.now() < this.suppressClickUntil) return;
    this.clearReaction();
    this.phraseIndex = (this.phraseIndex + 1) % this.phrases.length;
    this.delighted = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut,
      iterations: 2, playMode: PlayMode.Alternate }, (): void => {
      this.raised = !this.raised;
    });
    this.resetTimer = setTimeout((): void => {
      this.resetTimer = -1;
      this.delighted = false;
      this.raised = false;
    }, 4000);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.delighted) {
        Row({ space: 8 }) {
          Image(this.expressions[this.phraseIndex])
            .width(48).height(48).objectFit(ImageFit.Contain).draggable(false)
            .accessibilityLevel('no')
          Text(this.phrases[this.phraseIndex])
            .fontSize(13).fontColor(AppTheme.TextPrimary)
            .maxLines(4).layoutWeight(1)
        }
        .padding(12).width(this.bubbleWidth()).height(100).borderRadius(18)
        .backgroundColor(AppTheme.Surface)
        .position({ x: this.bubbleX(), y: this.bubbleY() })
        .hitTestBehavior(HitTestMode.None)
      }
      Button({ type: ButtonType.Normal }) {
        Stack() {
          Image($r('app.media.jianjian_red_idle'))
            .width(96).height(112).objectFit(ImageFit.Contain).draggable(false)
            .translate({ y: this.idleLifted ? -2 : 0 })
        }
        .translate({ y: this.raised ? -5 : 0 })
        .rotate({ angle: this.raised ? -5 : 0 })
        .scale({ x: this.dragging ? 1.06 : 1, y: this.dragging ? 1.06 : 1 })
      }
      .width(104).height(124).padding(0).backgroundColor(Color.Transparent)
      .stateEffect(false)
      .position({ x: this.characterX, y: this.characterY })
      .visibility(this.viewportWidth > 0 ? Visibility.Visible : Visibility.Hidden)
      .accessibilityText($r('app.string.jianjian_interact'))
      .id('jianjian-companion')
      .onClick((): void => this.interact())
      .priorityGesture(
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ duration: 450, repeat: false })
            .onAction((): void => this.beginDrag()),
          PanGesture({ direction: PanDirection.All, distance: 1 })
            .onActionUpdate((event: GestureEvent): void => this.moveDrag(event))
            .onActionEnd((): void => this.finishDrag())
        ).onCancel((): void => this.finishDrag())
      )
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.finishDrag();
      })
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => this.resize(newSize))
    .onVisibleAreaChange([0, 1], (visible: boolean): void => {
      this.inViewport = visible;
      if (!visible) {
        this.stopReaction();
        this.finishDrag();
      }
      this.syncIdleAnimation();
    })
  }
}
