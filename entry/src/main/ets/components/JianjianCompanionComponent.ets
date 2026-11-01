import { AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { JianjianAvatarComponent } from './JianjianAvatarComponent';

/** 根导航上的单实例人物；空白区域透传，路由切换时保留位置。 */
@ComponentV2
export struct JianjianCompanionComponent {
  @Param active: boolean = true;
  @Local dragging: boolean = false;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local characterX: number = 0;
  @Local characterY: number = 0;
  // -1 左边、0 自由位置、1 右边；互动展开期间仍保留停靠侧。
  @Local dockSide: number = 0;
  @Local peeking: boolean = false;
  private positioned: boolean = false;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private suppressClickUntil: number = 0;
  @Local inViewport: boolean = false;
  @Local delighted: boolean = false;
  @Local phraseIndex: number = -1;
  @Local bubbleHeight: number = 76;
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

  @Monitor('active', 'dragging')
  onActiveChanged(): void {
    if (!this.active) {
      this.stopReaction();
      this.finishDrag(false);
    }
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
    this.positionAtDock(false);
  }

  private clampX(positionX: number): number {
    return Math.max(8, Math.min(positionX, this.viewportWidth - 112));
  }

  private positionAtDock(animated: boolean): void {
    if (this.dockSide === 0 || this.viewportWidth <= 0) return;
    // 热区仍露出 52vp；人物另向外平移并绕脚底倾斜，只让头部探进窗口。
    const target: number = this.delighted ? this.clampX(this.dockSide < 0 ? 8 : this.viewportWidth - 112) :
      (this.dockSide < 0 ? -52 : this.viewportWidth - 52);
    if (animated && this.active && this.inViewport) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.characterX = target;
        this.peeking = !this.delighted;
      });
    } else {
      this.characterX = target;
      this.peeking = !this.delighted;
    }
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
    this.finishDrag(false);
    if (this.dockSide === 0) {
      this.characterX = this.clampX(this.characterX);
    } else {
      this.positionAtDock(false);
    }
    this.characterY = this.clampY(this.characterY);
  }

  private beginDrag(): void {
    // 从当前显示位置拉出；不要先收起展开中的人物，避免按下时跳回边缘。
    this.clearReaction();
    this.delighted = false;
    this.peeking = false;
    this.dockSide = 0;
    this.dragStartX = this.characterX;
    this.dragStartY = this.characterY;
    this.dragging = true;
  }

  private moveDrag(event: GestureEvent): void {
    if (!this.dragging) return;
    this.characterX = Math.max(-52, Math.min(this.dragStartX + event.offsetX, this.viewportWidth - 52));
    this.characterY = this.clampY(this.dragStartY + event.offsetY);
  }

  private finishDrag(animated: boolean = true): void {
    if (!this.dragging) return;
    this.suppressClickUntil = Date.now() + 300;
    this.dragging = false;
    const center: number = this.characterX + 52;
    // 距完整显示边界 24vp 内松手才吸附；中间区域保留自由放置。
    if (center <= Math.min(76, this.viewportWidth / 2)) {
      this.dockSide = -1;
    } else if (center >= Math.max(this.viewportWidth - 76, this.viewportWidth / 2)) {
      this.dockSide = 1;
    } else {
      this.dockSide = 0;
      this.characterX = this.clampX(this.characterX);
    }
    this.positionAtDock(animated);
  }

  private bubbleX(): number {
    return Math.max(8, Math.min(this.characterX + 52 - this.bubbleWidth() / 2,
      this.viewportWidth - this.bubbleWidth() - 8));
  }

  private bubbleWidth(): number {
    return Math.min(216, Math.max(128, this.viewportWidth - 16));
  }

  private bubbleY(): number {
    const top: number = WindowUtils.getStatusBarHeightVp() + 8;
    const desired: number = this.bubbleAbove() ? this.characterY - this.bubbleHeight - 16 : this.characterY + 140;
    return Math.max(top, Math.min(desired, this.viewportHeight - this.bubbleHeight - WindowUtils.getBottomSafeVp() - 8));
  }

  private bubbleAbove(): boolean {
    return this.characterY - this.bubbleHeight - 16 >= WindowUtils.getStatusBarHeightVp() + 8;
  }

  private bubbleTailX(): number {
    return Math.max(28, Math.min(this.characterX + 52 - this.bubbleX() - 8, this.bubbleWidth() - 44));
  }

  private interact(): void {
    if (!this.active || this.dragging || Date.now() < this.suppressClickUntil) return;
    this.clearReaction();
    this.phraseIndex = (this.phraseIndex + 1) % this.phrases.length;
    this.delighted = true;
    this.positionAtDock(true);
    this.resetTimer = setTimeout((): void => {
      this.resetTimer = -1;
      this.delighted = false;
      this.positionAtDock(true);
    }, 4000);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.delighted) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 尾巴与正文同色，接缝藏在圆角气泡内部，始终朝向简简。
          Column() {}
            .width(16).height(16).borderRadius(3)
            .backgroundColor(AppTheme.Surface)
            .rotate({ angle: 45 })
            .position({ x: this.bubbleTailX(), y: this.bubbleAbove() ? this.bubbleHeight - 10 : -6 })
          Row({ space: 10 }) {
            Image(this.expressions[this.phraseIndex])
              .width(40).height(40).objectFit(ImageFit.Contain).draggable(false)
              .accessibilityLevel('no')
            Text(this.phrases[this.phraseIndex])
              .fontSize(14).fontColor(AppTheme.TextPrimary)
              .maxLines(5).layoutWeight(1)
          }
          .padding({ left: 14, right: 16, top: 14, bottom: 14 })
          .width(this.bubbleWidth()).constraintSize({ minHeight: 76 }).borderRadius(24)
          .backgroundColor(AppTheme.Surface)
          .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
            const height: number = Number(newSize.height);
            if (Number.isFinite(height) && height > 0 && Math.abs(height - this.bubbleHeight) > 0.5) {
              this.bubbleHeight = height;
            }
          })
        }
        .width(this.bubbleWidth())
        .position({ x: this.bubbleX(), y: this.bubbleY() })
        .hitTestBehavior(HitTestMode.None)
      }
      Button({ type: ButtonType.Normal }) {
        Stack() {
          JianjianAvatarComponent({
            running: this.active && this.inViewport && !this.dragging,
            reacting: this.delighted,
            reactionIndex: this.phraseIndex
          })
            .rotate({ angle: this.peeking ? -42 * this.dockSide : 0,
              centerX: '50%', centerY: '100%' })
            .translate({ x: this.peeking ? 40 * this.dockSide : 0 })
        }
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
        PanGesture({ direction: PanDirection.All, distance: 5 })
          .onActionStart((event: GestureEvent): void => {
            this.beginDrag();
            this.moveDrag(event);
          })
          .onActionUpdate((event: GestureEvent): void => this.moveDrag(event))
          .onActionEnd((event: GestureEvent): void => {
            this.moveDrag(event);
            this.finishDrag();
          })
          .onActionCancel((): void => this.finishDrag(false))
      )
      .onTouch((event: TouchEvent): void => {
        // Up 由 PanGesture 的最终 offset 收尾，避免原始 Touch 提前结束拖动。
        if (event.type === TouchType.Cancel) this.finishDrag(false);
      })
    }
    .width('100%').height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => this.resize(newSize))
    .onVisibleAreaChange([0, 1], (visible: boolean): void => {
      this.inViewport = visible;
      if (!visible) {
        this.stopReaction();
        this.finishDrag(false);
      }
    })
  }
}
