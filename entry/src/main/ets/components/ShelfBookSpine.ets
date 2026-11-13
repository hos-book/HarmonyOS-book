import { CoverImage } from './CoverImage';
import { AppColor } from '../theme/Theme';
import { CoverTheme } from '../theme/CoverTheme';

/** 固定命中区域，只有书脊展示层抽出；手势和书架菜单由宿主处理。 */
@ComponentV2
export struct ShelfBookSpine {
  @Param cover: string = '';
  @Param localPlaceholder: boolean = false;
  @Param spineWidth: number = 34;
  @Param spineHeight: number = 174;
  @Param spineColor: string = '#345B58';
  @Param pulled: boolean = false;
  @Param managing: boolean = false;
  @Param selected: boolean = false;
  @Param pinned: boolean = false;
  @Param coverId: string = '';
  @Param coverHidden: boolean = false;

  @Builder
  buildBindingGroove() {
    Stack() {
      // 上缘压暗、下缘微亮，线头收进两端暗槽；随书封一起缓存，不使用模糊阴影。
      Row().width('100%').height(3).borderRadius(1.5)
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [['#28000000', 0], ['#A6000000', 0.3], ['#82000000', 0.58],
            ['#38FFFFFF', 0.84], ['#00FFFFFF', 1]] })
      Row().width('80%').height(0.65).borderRadius(0.4)
        .backgroundColor('#8CD6C3A1').translate({ y: 0.15 })
    }.width('64%').height(3)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Top }) {
        if (this.cover) {
          if (this.cover.startsWith('http') || this.cover.startsWith('file://') || this.cover.startsWith('/data/')) {
            CoverImage({ url: this.cover, imgWidth: this.spineWidth - 1, imgHeight: this.spineHeight,
              useFixedHeight: true, radius: 2, themedDecoration: false, themeBundleId: 'default' })
          } else {
            Image($rawfile(this.cover)).width('100%').height('100%')
              .objectFit(ImageFit.Cover).autoResize(true).draggable(false)
          }
        } else if (this.localPlaceholder) {
          Image(CoverTheme.localPlaceholder()).width('100%').height('100%')
            .objectFit(ImageFit.Fill).draggable(false)
        }
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#65000000', 0], ['#12FFFFFF', 0.16], ['#00000000', 0.36],
              ['#22000000', 0.78], ['#88000000', 1]] })
        Column() {
          this.buildBindingGroove()
          Blank().layoutWeight(1)
          this.buildBindingGroove()
        }.width('100%').height('100%').padding({ left: 4, right: 4, top: 13, bottom: 12 })
        if (this.pinned && !this.managing) {
          SymbolGlyph($r('sys.symbol.pin_fill')).fontSize(10).fontColor(['#FFF8ED'])
            .position({ x: this.spineWidth / 2 - 5, y: 2 })
        }
        if (this.managing) {
          Stack() {
            Row().width(22).height(22).borderRadius(11)
              .backgroundColor(this.selected ? AppColor.Brand : '#EFFFFFFF')
            if (this.selected) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([Color.White])
            }
          }.position({ x: (this.spineWidth - 23) / 2, y: 5 })
        }
      }
      .width(this.spineWidth - 1).height(this.spineHeight)
      .backgroundColor(this.spineColor).borderRadius(2).clip(true)
      .border({ width: this.managing && this.selected ? 2 : 0, color: AppColor.Brand, radius: 2 })
      // 保留轻量滑动修复：缓存静态书封，抽出只平移；书名提示由书架行显示。
      .renderGroup(!this.managing)
      .translate({ y: this.pulled ? -16 : 0 })
      .animation({ duration: this.pulled ? 100 : 160, curve: Curve.EaseOut })
      .id(this.coverId).opacity(this.coverHidden ? 0 : 1)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
    }
    .width(this.spineWidth).height(216).clip(false)
  }
}
