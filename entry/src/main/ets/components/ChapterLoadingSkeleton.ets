/**
 * ChapterLoadingSkeleton - 章节目录加载骨架屏
 *
 * 用于详情页在 `loadingToc` 期间占位，避免「空白 → 章节突然闪现」。
 * 行高与 `ChapterListItem` 对齐（BodyL + Caption + 上下 14 padding ≈ 65vp），
 * 目录到位后真实列表替换骨架时不产生跳动。
 *
 * 动效：整体呼吸式明暗（与 HomeLoadingSkeleton 一致），叠加逐行渐显，
 * 使等待过程有方向感而不是一块静态灰条。
 */
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion } from '../theme/Theme';

/** 与 ChapterListItem 单行实际高度对齐 */
const SKELETON_ROW_HEIGHT: number = 65;
/** 骨架行标题宽度序列，制造长短参差的真实感 */
const TITLE_WIDTHS: string[] = ['68%', '54%', '76%', '46%', '62%', '72%', '50%', '66%'];

@ComponentV2
export struct ChapterLoadingSkeleton {
  /** 与详情页正文对齐的水平内边距 */
  @Param horizontalInset: number = AppSpace.Lg;
  /** 是否为文本书（影响提示文案） */
  @Param isTextBook: boolean = false;
  /** 渲染的骨架行数 */
  @Param rowCount: number = 8;
  @Local pulsing: boolean = false;

  onDidBuild(): void {
    if (!this.pulsing) this.pulsing = true;
  }

  /** 显式构建行索引数组；ArkTS 下不用 Array.from({length}) 那套 ArrayLike 推断。 */
  private rowIndices(): number[] {
    const total: number = this.rowCount > 0 ? this.rowCount : 8;
    const list: number[] = [];
    for (let i = 0; i < total; i++) {
      list.push(i);
    }
    return list;
  }

  @Builder
  skeletonRow(index: number) {
    Column() {
      Row() {
        Column({ space: 6 }) {
          // 标题占位
          Row()
            .width(TITLE_WIDTHS[index % TITLE_WIDTHS.length])
            .height(15)
            .borderRadius(AppRadius.Xs)
            .backgroundColor(AppColor.Divider)
          // 时长占位
          Row()
            .width(52)
            .height(11)
            .borderRadius(AppRadius.Xs)
            .backgroundColor(AppColor.Divider)
            .opacity(0.6)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(SKELETON_ROW_HEIGHT - 0.5)
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(AppColor.Divider)
        .margin({ left: this.horizontalInset, right: this.horizontalInset })
    }
    .width('100%')
    .height(SKELETON_ROW_HEIGHT)
    .padding({ left: this.horizontalInset, right: this.horizontalInset })
  }

  build() {
    Column() {
      // 顶部提示：明确告诉用户正在做什么
      Row({ space: AppSpace.Xs }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(AppColor.Brand)
        Text(this.isTextBook ? $r('app.string.chapter_catalog_loading') : $r('app.string.chapter_program_loading'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding({ left: this.horizontalInset, right: this.horizontalInset, bottom: AppSpace.Sm })
      .justifyContent(FlexAlign.Start)

      Column() {
        ForEach(
          this.rowIndices(),
          (index: number) => {
            this.skeletonRow(index)
          },
          (index: number) => `chapter-skeleton-${index}`
        )
      }
      .width('100%')
      // 呼吸式明暗：无限交替，等待期间保持"活着"的感觉
      .opacity(this.pulsing ? 0.42 : 0.85)
      .animation({
        duration: 900,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      })
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    // 骨架本身入场淡入，避免自己也"闪"一下
    .transition(TransitionEffect.opacity(0).animation({ duration: AppMotion.Fast }))
  }
}
