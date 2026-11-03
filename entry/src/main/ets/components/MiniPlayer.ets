import { AppColor, AppSpace, AppFont, HomeTheme, AppMotion, AppCurve } from '../theme/Theme';
import { Book } from '../model/Book';
import { PlaybackLoadingIndicator } from './PlaybackLoadingIndicator';
import { CoverImage } from './CoverImage';
import { CoverDecoration } from './CoverDecoration';
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
  @Event onChapters: () => void = () => {};
  @Event onTapBody: () => void = () => {};
  @Event onToggle: () => void = () => {};
  @Event onNext: () => void = () => {};
  @Event onExpand: () => void = () => {};
  @Event onPlayerPanStart: (offsetY: number) => void = () => {};
  @Event onPlayerPanUpdate: (offsetY: number) => void = () => {};
  @Event onPlayerPanEnd: (offsetY: number, velocityY: number) => void = () => {};
  @Event onPlayerPanCancel: () => void = () => {};
  private draggingPlayer: boolean = false;
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;

  @Builder
  coverImageBuilder(): void {
    if (this.book) {
      if (this.book.cover && this.book.cover.startsWith('http')) {
        CoverImage({ url: this.book.cover, useFixedHeight: true, imgHeight: '100%', radius: 0,
          themedDecoration: false })
          .width('100%')
          .height('100%')
          .id('mini-player-cover-image')
      } else if (this.book.cover
        && (this.book.cover.startsWith('/') || this.book.cover.startsWith('file://'))) {
        // 判断条件与 BookCard.isLocalFile 对齐:file:// 前缀的本地封面不能掉进 $rawfile 分支
        Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(true)
          .interpolation(ImageInterpolation.Medium)
          .id('mini-player-cover-image')
      } else if (this.book.cover) {
        // 本地封面同样按迷你播放器的实际尺寸解码。
        Image($rawfile(this.book.cover))
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
            this.coverImageBuilder()
            CoverDecoration({ radius: this.collapsed ? 999 : 22, compact: true })
          }
          .width('92%')
          .height('92%')
          .borderRadius(this.collapsed ? 999 : 22)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .clip(true)
          .opacity(this.dragState.active && this.dragState.sourceNodeId === 'mini-player-bar' ? 0 : 1)
        }
        .width(this.collapsed ? '100%' : this.verticalStyle && !this.compactControls ? 32 : 44)
        .height(this.collapsed ? '100%' : this.verticalStyle && !this.compactControls ? 32 : 44)
        .animation(this.verticalStyle ? { duration: AppMotion.Slow, curve: AppCurve.Standard } : undefined)
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
          .transition(this.verticalStyle ? TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast }) : undefined)

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
            }
          }.width(this.verticalStyle ? 30 : 24).height(this.verticalStyle ? 30 : 24)
            .id('mini-player-toggle')
            .hitTestBehavior(HitTestMode.Block)
            .accessibilityText(this.playing || this.loading ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onToggle())
            .transition(this.verticalStyle ? TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast }) : undefined)

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
            .hitTestBehavior(HitTestMode.Block)
            .id('mini-player-next').accessibilityText($r('app.string.tts_next'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onNext())
            .transition(this.verticalStyle ? TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast }) : undefined)

          if (this.verticalStyle) {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(22).fontColor([$r('sys.color.font_primary')])
              .width(28).height(32).hitTestBehavior(HitTestMode.Block)
              .id('mini-player-chapters').accessibilityText($r('app.string.reader_catalog'))
              .onClick((): void => this.onChapters())
              .transition(TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast }))
          }
        }
      }
      .width('100%')
      .height('100%')
      .id('mini-player-bar')
      .opacity(this.dragState.sourceNodeId === 'mini-player-bar' ? this.dragState.sourceOpacity : 1)
      .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
        .onActionStart((event: GestureEvent): void => {
          this.draggingPlayer = event.offsetY < 0;
          if (this.draggingPlayer) this.onPlayerPanStart(event.offsetY);
        })
        .onActionUpdate((event: GestureEvent): void => {
          if (this.draggingPlayer) this.onPlayerPanUpdate(event.offsetY);
        })
        .onActionEnd((event: GestureEvent): void => {
          if (this.draggingPlayer) this.onPlayerPanEnd(event.offsetY, event.velocityY);
          this.draggingPlayer = false;
        })
        .onActionCancel((): void => {
          if (this.draggingPlayer) this.onPlayerPanCancel();
          this.draggingPlayer = false;
        }))
      .padding({
        left: this.collapsed ? 0 : this.verticalStyle ? (this.compactControls ? 8 : 4) : AppSpace.Xs,
        right: this.collapsed ? 0 : AppSpace.Md
      })
    }
  }
}
