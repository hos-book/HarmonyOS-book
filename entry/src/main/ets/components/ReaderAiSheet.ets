import { ReaderAiAction, ReaderAiRequest } from '../model/ReaderAi';
import { ReaderAiService } from '../service/text/ReaderAiService';
import { JianjianAiService } from '../service/JianjianAiService';
import { JianjianAiError, JianjianAiErrorCode } from '../model/JianjianAi';
import { AppColor } from '../theme/Theme';
import { JianjianReplyText } from '../utils/JianjianReplyText';

@ComponentV2
export struct ReaderAiSheet {
  @Param request: ReaderAiRequest = new ReaderAiRequest();
  @Param active: boolean = true;
  @Event getChapter: (index: number) => Promise<string> = async (): Promise<string> => '';
  @Event onClose: () => void = () => {};
  @Event onSettings: () => void = () => {};
  @Local loading: boolean = true;
  @Local needsConfig: boolean = false;
  @Local result: string = '';
  @Local message: ResourceStr = '';
  @Local progress: ResourceStr = '';
  private service: ReaderAiService = new ReaderAiService();
  private alive: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void { this.alive = true; this.generate(); }
  aboutToDisappear(): void { this.alive = false; this.cancel(); }

  @Monitor('active')
  private onActiveChange(): void { if (!this.active) this.cancel(); }

  private cancel(): void { this.generation++; this.service.cancel(); this.loading = false; }

  private async generate(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive || !this.active) return;
    this.cancel();
    const ticket = this.generation;
    this.loading = true; this.needsConfig = false; this.message = ''; this.progress = ''; this.result = '';
    const current = (): boolean => this.alive && this.active && ticket === this.generation;
    try {
      const config = await JianjianAiService.loadConfig(context);
      if (!current()) return;
      JianjianAiService.normalize(config, true);
      let content = this.request.text;
      if (this.request.action === ReaderAiAction.Summarize) {
        try { content = await this.getChapter(this.request.chapterIndex); }
        catch (_error) {
          if (current()) this.message = $r('app.string.reader_ai_content_failed');
          return;
        }
      }
      if (!current()) return;
      if (!ReaderAiService.plain(content)) { this.message = $r('app.string.reader_ai_empty'); return; }
      const result = await this.service.run(config, this.request.action, content,
        (done: number, total: number, merging: boolean): void => {
          if (current()) this.progress = merging ? $r('app.string.reader_ai_merging', done, total) :
            $r('app.string.reader_ai_processing', done, total);
        });
      if (current()) this.result = result;
    } catch (error) {
      if (!current()) return;
      this.needsConfig = error instanceof JianjianAiError &&
        [JianjianAiErrorCode.CONFIG, JianjianAiErrorCode.MODEL, JianjianAiErrorCode.AUTH, JianjianAiErrorCode.ENDPOINT].includes(error.code);
      this.message = JianjianAiService.errorText(error instanceof Error ? error : new Error(String(error)));
    } finally { if (current()) this.loading = false; }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(this.request.action === ReaderAiAction.Dictionary ? $r('app.string.reader_ai_dictionary') : $r('app.string.reader_ai_summarize'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button($r('app.string.common_close')).fontSize(14).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => { this.cancel(); this.onClose(); })
      }.width('100%')
      Text(this.request.chapterTitle).fontSize(13).fontColor($r('sys.color.font_secondary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (this.request.action === ReaderAiAction.Dictionary) {
        Text(this.request.text).fontSize(14).fontColor($r('sys.color.font_secondary'))
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text($r('app.string.reader_ai_dictionary_hint')).fontSize(12).fontColor(AppColor.Brand).width('100%')
      }
      if (this.loading) {
        Column({ space: 16 }) {
          LoadingProgress().width(32).height(32).color(AppColor.Brand)
          Text(this.progress || $r('app.string.jianjian_ai_replying')).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Button($r('app.string.common_cancel')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .onClick((): void => { this.cancel(); this.message = $r('app.string.jianjian_ai_cancelled'); })
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.result) {
        Scroll() {
          Text(JianjianReplyText.display(this.result)).fontSize(17).lineHeight(28).fontColor($r('sys.color.font_primary'))
            .width('100%').padding({ bottom: 28 }).id('reader-ai-result')
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
      } else {
        Column({ space: 16 }) {
          Text(this.message).fontSize(14).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
          if (this.needsConfig) {
            Button($r('app.string.jianjian_ai_settings')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
              .onClick((): void => { this.cancel(); this.onSettings(); })
          } else {
            Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
              .onClick((): void => { this.generate(); })
          }
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 4, bottom: 24 })
      .backgroundColor(Color.Transparent).id('reader-ai-sheet')
  }
}
