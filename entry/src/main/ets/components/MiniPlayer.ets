import { AppColor, AppSpace, AppFont, HomeTheme, AppMotion, AppCurve } from '../theme/Theme';
import { Book } from '../model/Book';
import { PlaybackLoadingIndicator } from './PlaybackLoadingIndicator';
import { CoverImage } from './CoverImage';
import { CoverDecoration } from './CoverDecoration';
import { PlayerBarSurface } from './PlayerBarSurface';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';

@ComponentV2
export struct MiniPlayer {
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';
  @Param playing: boolean = false;
  @Param loading: boolean = false;
  @Param progressPercent: number = 0;
  @Param collapsed: boolean = true;
  @Param verticalStyle: boolean = false;
  /** 新版单行态保留全部播控，封面随系统迷你栏放大。 */
  @Param compactControls: boolean = false;
  @Param transitionCopy: boolean = false;
  @Param dragEnabled: boolean = true;
  @Event onChapters: () => void = () => {};
  @Event onTapBody: () => void = () => {};
  @Event onToggle: () => void = () => {};
  @Event onNext: () => void = () => {};
  @Event onExpand: () => void = () => {};
  @Event onInteract: () => void = () => {};
  @Event onPlayerDragStart: (offsetY: number) => void = () => {};
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local materialWidth: number = 0;
  @Local materialHeight: number = 0;
  private draggingPlayer: boolean = false;

  private controlTransition(delay: number): TransitionEffect {
    // 自绘副本与双层栏直接显示完整播控，内容透明度统一交给转场面板。
    if (this.transitionCopy || this.verticalStyle || this.dragState.active) return TransitionEffect.IDENTITY;
    // 展开时轻移入场；收起立即淡出，避免控件拖在收拢的胶囊外。
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ x: 10 }))
        .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate, delay: delay }),
      TransitionEffect.opacity(0).animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })
    );
  }

  @Builder
  coverImageBuilder(): void {
    if (this.book) {
      if (this.book.cover && this.book.cover.startsWith('http')) {
        CoverImage({ url: this.book.cover, useFixedHeight: true, imgHeight: '100%', radius: 0,
          themedDecoration: false, eagerLoad: true })
          .width('100%')
          .height('100%')
          .id('mini-player-cover-image')
      } else if (this.book.cover
        && (this.book.cover.startsWith('/') || this.book.cover.startsWith('file://'))) {
        // 判断条件与 BookCard.isLocalFile 对齐:file:// 前缀的本地封面不能掉进 $rawfile 分支
        Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(true)
          .interpolation(ImageInterpolation.Medium)
          .id('mini-player-cover-image')
      } else if (this.book.cover) {
        // 本地封面同样按迷你播放器的实际尺寸解码。
        Image($rawfile(this.book.cover))
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(true)
          .interpolation(ImageInterpolation.Medium)
          .id('mini-player-cover-image')
      } else {
        CoverImage({ title: this.book.title, author: this.book.author,
          localPlaceholder: this.book.id.startsWith('import_'), radius: 0, themedDecoration: false,
          useFixedHeight: true, imgHeight: '100%' })
          .width('100%')
          .height('100%')
          .id('mini-player-cover-image')
      }
    }
  }

  build() {
    if (this.book) {
      Stack() {
        if (!this.transitionCopy) {
          PlayerBarSurface({ surfaceWidth: this.materialWidth, surfaceHeight: this.materialHeight })
        }
        Row({ space: this.collapsed ? 0 : AppSpace.Sm }) {
          Stack() {
            Progress({ value: this.progressPercent, total: 100, type: ProgressType.Ring })
              .width('100%')
              .height('100%')
              .color(AppColor.Brand)
              .backgroundColor(HomeTheme.ProgressTrack)
              .style({
                strokeWidth: 1.5,
                enableSmoothEffect: false,
                enableScanEffect: false,
                shadow: false
              })

            Stack() {
              if (!this.transitionCopy) {
                this.coverImageBuilder()
              }
              CoverDecoration({ radius: this.collapsed ? 999 : 22, compact: true })
            }
            .width('92%')
            .height('92%')
            .borderRadius(this.collapsed ? 999 : 22)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .clip(true)
            .opacity(this.dragState.active && this.dragState.sourceNodeId === 'mini-player-bar' &&
              !this.dragState.miniBarRevealed ? 0 : 1)
          }
          .width(this.collapsed ? '100%' : this.verticalStyle && !this.compactControls ? 32 : 44)
          .height(this.collapsed ? '100%' : this.verticalStyle && !this.compactControls ? 32 : 44)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => {
            if (this.collapsed) {
              this.onExpand();
            } else {
              this.onTapBody();
            }
          })

          if (!this.collapsed) {
            Column({ space: 2 }) {
              Text(this.book.title)
                .fontSize(this.verticalStyle ? 14 : AppFont.Body)
                .fontColor($r('sys.color.font_primary'))
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.chapterTitle || '--')
                .fontSize(this.verticalStyle ? 11 : AppFont.Caption)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .onClick(() => this.onTapBody())
            .transition(this.controlTransition(0))

            Stack() {
              if (this.loading) {
                PlaybackLoadingIndicator({ indicatorSize: 24 })
              } else if (this.verticalStyle) {
                SymbolGlyph(this.playing
                  ? $r('sys.symbol.pause_round_triangle_fill')
                  : $r('sys.symbol.play_round_triangle_fill'))
                  .fontSize(30)
                  .fontWeight(this.playing ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor([$r('sys.color.font_primary')])
                  .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.playing ? 1 : 0)
              } else {
                SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.font_primary')])
                  .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.playing ? 1 : 0)
              }
            }.width(this.verticalStyle ? 30 : 24).height(this.verticalStyle ? 30 : 24)
              .id(this.transitionCopy ? 'player-transition-toggle' : 'mini-player-toggle')
              .hitTestBehavior(HitTestMode.Block)
              .accessibilityText(this.playing || this.loading ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
              .onClick(() => this.onToggle())
              .transition(this.controlTransition(25))

            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(22)
              .fontColor([$r('sys.color.font_primary')])
              .hitTestBehavior(HitTestMode.Block)
              .id(this.transitionCopy ? 'player-transition-next' : 'mini-player-next')
              .accessibilityText($r('app.string.tts_next'))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
              .onClick(() => this.onNext())
              .transition(this.controlTransition(45))

            if (this.verticalStyle) {
              SymbolGlyph($r('sys.symbol.music_note_list'))
                .fontSize(22).fontColor([$r('sys.color.font_primary')])
                .width(28).height(32).hitTestBehavior(HitTestMode.Block)
                .id(this.transitionCopy ? 'player-transition-chapters' : 'mini-player-chapters')
                .accessibilityText($r('app.string.reader_catalog'))
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
                .onClick((): void => this.onChapters())
                .transition(this.controlTransition(65))
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          left: this.collapsed ? 0 : this.verticalStyle ? (this.compactControls ? 8 : 4) : AppSpace.Xs,
          right: this.collapsed ? 0 : AppSpace.Md
        })
      }
      .width('100%')
      .height('100%')
      .borderRadius(999)
      .id(this.transitionCopy ? 'player-transition-mini-bar' : 'mini-player-bar')
      .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
        this.materialWidth = Number(current.width);
        this.materialHeight = Number(current.height);
      })
      .transition(TransitionEffect.IDENTITY)
      .opacity(!this.transitionCopy && this.dragState.active &&
        this.dragState.sourceNodeId === 'mini-player-bar' && !this.dragState.miniBarRevealed ? 0 : 1)
      // 原生栏保持挂载并接收完整手势，自绘副本只负责呈现。
      .hitTestBehavior(this.transitionCopy ? HitTestMode.None : HitTestMode.Default)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) this.onInteract();
        if (this.draggingPlayer && (event.type === TouchType.Up || event.type === TouchType.Cancel)) {
          PlayerDragTransition.getInstance().releaseTouch(event.type === TouchType.Cancel);
        }
      })
      .priorityGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 }).tag('mini-player-pan')
        .onActionStart((event: GestureEvent): void => {
          this.draggingPlayer = this.dragEnabled && !this.transitionCopy && event.offsetY < 0;
          if (this.draggingPlayer) this.onPlayerDragStart(event.offsetY);
        })
        .onActionUpdate((event: GestureEvent): void => {
          if (this.draggingPlayer) PlayerDragTransition.getInstance().update(event.offsetY);
        })
        .onActionEnd((event: GestureEvent): void => {
          if (this.draggingPlayer) PlayerDragTransition.getInstance().end(event.offsetY, event.velocityY);
          this.draggingPlayer = false;
        })
        .onActionCancel((): void => {
          if (this.draggingPlayer) PlayerDragTransition.getInstance().cancel();
          this.draggingPlayer = false;
        }))
      .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult =>
        info.tag === 'mini-player-pan' && (!this.dragEnabled || this.transitionCopy) ?
          GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE)
    }
  }
}
