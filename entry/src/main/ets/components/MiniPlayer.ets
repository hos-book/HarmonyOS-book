import { AppColor, AppSpace, AppFont, HomeTheme } from '../theme/Theme';
import { Book } from '../model/Book';
import { PlaybackLoadingIndicator } from './PlaybackLoadingIndicator';
import { CoverImage } from './CoverImage';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';

@ComponentV2
export struct MiniPlayer {
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';
  @Param playing: boolean = false;
  @Param loading: boolean = false;
  @Param progressPercent: number = 0;
  @Param collapsed: boolean = true;
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
        CoverImage({ url: this.book.cover, useFixedHeight: true, imgHeight: '100%', radius: 0 })
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
          .sourceSize({ width: 300, height: 400 })
          .id('mini-player-cover-image')
      } else if (this.book.cover) {
        // rawfile 分支不设 sourceSize:列表(BookCard/FavoritePage)的 rawfile 分支也没设,保持缓存一致
        Image($rawfile(this.book.cover))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .id('mini-player-cover-image')
      } else {
        CoverImage({ title: this.book.title, author: this.book.author,
          localPlaceholder: this.book.id.startsWith('import_'), radius: 0,
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
          }
          .width('92%')
          .height('92%')
          .borderRadius(this.collapsed ? 999 : 22)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .clip(true)
          .opacity(this.dragState.active ? 0 : 1)
        }
        .width(this.collapsed ? '100%' : 44)
        .height(this.collapsed ? '100%' : 44)
        .geometryTransition('player-cover')
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
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.chapterTitle || '--')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.onTapBody())

          Stack() {
            if (this.loading) {
              PlaybackLoadingIndicator({ indicatorSize: 24 })
            } else {
              SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
                .fontSize(24).fontColor([$r('sys.color.font_primary')])
            }
          }.width(24).height(24).id('mini-player-toggle')
            .hitTestBehavior(HitTestMode.Block)
            .accessibilityText(this.playing || this.loading ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onToggle())

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
            .hitTestBehavior(HitTestMode.Block)
            .id('mini-player-next').accessibilityText($r('app.string.tts_next'))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onNext())
        }
      }
      .width('100%')
      .height('100%')
      .id('mini-player-bar')
      .opacity(this.dragState.sourceOpacity)
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
        left: this.collapsed ? 0 : AppSpace.Xs,
        right: this.collapsed ? 0 : AppSpace.Md
      })
    }
  }
}
