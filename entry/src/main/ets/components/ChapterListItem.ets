import { ChapterCacheIndicator } from './ChapterCacheIndicator';
import { Book, Chapter } from '../model/Book';
/**
 * ChapterListItem - 详情页/播放器章节列表项（复用组件）
 *
 * 所有依赖父页面的派生展示值（播放中、已下载、下载中、失败、已播进度、音长）均为 @Param，
 * 由父组件算好传入，本组件只做静态渲染与点击转发，避免在复用节点上重跑父页面查询逻辑。
 *
 * @ReusableV2 复用与回收自动重置内部状态；本组件无可变 @Local 依赖，
 * aboutToReuse 无需手动清理（官方保证复用前状态已重置）。
 */
import { AppFont, AppSpace, AppRadius, AppColor } from '../theme/Theme';

export enum ChapterBadge {
  None = 0,
  Downloaded = 1,
  Downloading = 2,
  Failed = 3
}

@ComponentV2
@ReusableV2
export struct ChapterListItem {
  @Param book: Book | null = null;
  @Param chapter: Chapter | null = null;
  @Param title: string = '';
  @Param isTextBook: boolean = false;
  @Param isPlaying: boolean = false;
  /** 时长文案；为空则隐藏该行 */
  @Param durationText: string = '';
  /** 已下载体积文案；为空则隐藏 */
  @Param bytesText: string = '';
  /** 已播进度百分比文案；为空则隐藏 */
  @Param progressText: string = '';
  /** 与详情页/播放器正文对齐的水平内边距。 */
  @Param horizontalInset: number = AppSpace.Lg;
  @Param badge: ChapterBadge = ChapterBadge.None;
  @Event onTap: () => void = () => {};

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(AppFont.BodyL)
          .fontColor(this.isPlaying ? AppColor.BrandDark : $r('sys.color.font_primary'))
          .fontWeight(this.isPlaying ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: AppSpace.Xs }) {
          if (this.bytesText.length > 0) {
            Text(this.bytesText)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          if (this.progressText.length > 0) {
            Text(`已播 ${this.progressText}`)
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.BrandDark)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: AppSpace.Xs }) {
        if (this.isPlaying && this.isTextBook) {
          Text($r('app.string.chapter_current_reading'))
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.BrandDark)
            .backgroundColor(AppColor.BrandSoft)
            .borderRadius(AppRadius.Xs)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else if (this.isPlaying) {
          SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
            .fontSize(18).fontColor([AppColor.BrandDark])
        }
        if (this.badge === ChapterBadge.Downloaded) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(18).fontColor([AppColor.Brand])
            .accessibilityText($r('app.string.chapter_downloaded'))
        } else if (this.badge === ChapterBadge.Downloading) {
          Text($r('app.string.chapter_downloading'))
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.BrandDark)
            .backgroundColor(AppColor.BrandSoft)
            .borderRadius(AppRadius.Xs)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else if (this.badge === ChapterBadge.Failed) {
          Text($r('app.string.chapter_download_failed'))
            .fontSize(AppFont.Caption)
            .fontColor('#D03050')
            .backgroundColor('#14D03050')
            .borderRadius(AppRadius.Xs)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        if (this.badge === ChapterBadge.None && this.book !== null && this.chapter !== null) {
          ChapterCacheIndicator({ book: this.book, chapter: this.chapter })
        } else if (this.badge === ChapterBadge.None) {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(18).fontColor([$r('sys.color.font_tertiary')])
            .accessibilityText($r('app.string.chapter_not_cached'))
        }

      }
    }
    .width('100%')
    .padding({ left: this.horizontalInset, right: this.horizontalInset, top: 14, bottom: 14 })
    .onClick(() => this.onTap())
  }
}

/** 便捷工厂：把父页面派生值映射成本组件的 badge 入参。 */
export function mapChapterBadge(downloaded: boolean, downloading: boolean, failed: boolean): ChapterBadge {
  if (downloaded) return ChapterBadge.Downloaded;
  if (downloading) return ChapterBadge.Downloading;
  if (failed) return ChapterBadge.Failed;
  return ChapterBadge.None;
}
