import { ReaderPalette } from '../model/ReaderTheme';
import { AppFont, AppTheme } from '../theme/Theme';

/** 三种标记均以正文颜色和纸张底色预览，高亮与正文绘制共用 20% 不透明度。 */
@ComponentV2
export struct ReaderSpeechStylePreview {
  @Param color: string = new ReaderPalette().accent;
  @Param foreground: string = new ReaderPalette().primary;
  @Param paperColor: string = new ReaderPalette().background;

  build() {
    Column({ space: 10 }) {
      Text($r('app.string.reader_speech_style_preview')).fontSize(AppFont.Caption)
        .fontColor(AppTheme.TextSecondary).width('100%')
      Column({ space: 12 }) {
        ForEach(['color', 'highlight', 'underline'], (mark: string) => {
          Row({ space: 12 }) {
            Text(mark === 'color' ? $r('app.string.reader_mark_color') : mark === 'highlight' ?
              $r('app.string.reader_mark_highlight') : $r('app.string.reader_mark_underline'))
              .fontSize(12).fontColor(this.foreground).opacity(0.65).width(60)
            Text($r('app.string.reader_speech_preview_sample')).fontSize(16)
              .fontColor(mark === 'color' ? this.color : this.foreground)
              .backgroundColor(mark === 'highlight' ? `#33${this.color.substring(1)}` : Color.Transparent)
              .decoration({ type: mark === 'underline' ? TextDecorationType.Underline : TextDecorationType.None,
                color: this.color })
              .id(`reader-speech-preview-${mark}`)
          }.width('100%')
        }, (mark: string): string => mark)
      }.width('100%').padding(12).backgroundColor(this.paperColor).borderRadius(12)
    }.width('100%')
  }
}
