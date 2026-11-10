import { common, sendableContextManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { ReadingExcerpt } from '../model/ReadingExcerpt';
import { ReadingExcerptService } from '../service/text/ReadingExcerptService';
import { ReadingExcerptShareService } from '../service/text/ReadingExcerptShareService';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { AppColor, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ReadingExcerptDetailPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param excerpt: ReadingExcerpt = new ReadingExcerpt();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local busy: boolean = false;
  private alive: boolean = false;
  private context: common.UIAbilityContext | undefined = undefined;
  private shareController: systemShare.ShareController | undefined = undefined;
  private readonly dismissShare: () => void = (): void => {
    try { if (this.shareController) this.shareController.off('dismiss', this.dismissShare); } catch (_error) {}
    this.shareController = undefined;
    if (this.alive) this.busy = false;
  };

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getHostContext();
    if (context) this.context = sendableContextManager.convertToUIAbilityContext(
      sendableContextManager.convertFromContext(context));
  }

  aboutToDisappear(): void { this.alive = false; this.dismissShare(); }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async copy(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        ReadingExcerptShareService.text(this.excerpt)));
      this.toast($r('app.string.reader_excerpt_copied'));
    } catch (_error) { this.toast($r('app.string.reader_excerpt_copy_failed')); }
  }

  private async share(asImage: boolean): Promise<void> {
    if (!this.context || this.busy || !this.excerpt.text) return;
    this.busy = true;
    try {
      if (asImage) {
        const files = await ReadingExcerptShareService.cards(this.context, this.excerpt, (): boolean => !this.alive);
        if (!this.alive) return;
        this.shareController = ReadingExcerptShareService.imageController(files, this.excerpt.bookTitle);
      } else {
        const data = new systemShare.SharedData({ utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
          content: ReadingExcerptShareService.text(this.excerpt), title: this.excerpt.bookTitle });
        this.shareController = new systemShare.ShareController(data);
      }
      this.shareController.on('dismiss', this.dismissShare);
      await this.shareController.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: asImage ? systemShare.SharePreviewMode.DETAIL : systemShare.SharePreviewMode.DEFAULT });
    } catch (error) {
      this.dismissShare();
      this.toast(error instanceof Error && error.message === 'reading_excerpt_card_limit' ?
        $r('app.string.reader_excerpt_card_limit') : $r('app.string.reader_excerpt_share_failed'));
    }
  }

  private confirmDelete(): void {
    if (this.busy) return;
    this.getUIContext().showAlertDialog({ title: $r('app.string.reader_excerpt_delete'),
      message: $r('app.string.reader_excerpt_delete_confirm'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(); } } });
  }

  private async remove(): Promise<void> {
    if (!this.context || this.busy) return;
    this.busy = true;
    try {
      await ReadingExcerptService.remove(this.context, this.excerpt.id);
      if (this.alive) { this.toast($r('app.string.reader_excerpt_deleted')); this.navStack.pop(); }
    } catch (_error) { this.toast($r('app.string.reader_excerpt_delete_failed')); }
    finally { if (this.alive) this.busy = false; }
  }

  @Builder
  private shareMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.reader_excerpt_share') })
        .onClick((): void => { this.share(true); })
      MenuItem({ content: $r('app.string.reader_excerpt_share_text') })
        .onClick((): void => { this.share(false); })
    }
  }

  @Builder
  private card() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image($r('app.media.reading_excerpt_pattern')).width(180).height(136)
        .objectFit(ImageFit.Fill).draggable(false).hitTestBehavior(HitTestMode.None)
      Column({ space: 22 }) {
        Text($r('app.string.reader_excerpt_date', ReadingExcerptShareService.date(this.excerpt.createdAt)))
          .fontSize(14).fontColor('#7B8487').width('100%')
        Text(this.excerpt.text).fontSize(21).lineHeight(35).fontColor('#20262C').width('100%')
          .copyOption(CopyOptions.LocalDevice)
        Text(ReadingExcerptShareService.attribution(this.excerpt)).fontSize(15).lineHeight(24)
          .fontColor('#7B8487').width('100%')
        Row({ space: 10 }) {
          Image($r('app.media.app_icon_legacy')).width(32).height(32)
            .objectFit(ImageFit.Contain).interpolation(ImageInterpolation.High).borderRadius(8).clip(true).draggable(false)
          Text($r('app.string.reader_excerpt_brand')).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#50585D')
        }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 64 })
      }.width('100%').padding(28).alignItems(HorizontalAlign.Start)
    }.width('100%').backgroundColor('#FFFFFF').borderRadius(22).clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Scroll() {
          Column({ space: 18 }) {
            this.card()
            if (this.excerpt.chapterTitle) {
              Text(this.excerpt.chapterTitle).fontSize(13).fontColor(AppTheme.TextSecondary).width('100%')
            }
          }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: WindowUtils.getBottomSafeVp() + 24 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').constraintSize({ maxWidth: 760 })
        .padding({ top: this.headerHeight })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.reader_excerpt_detail')).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.reader_excerpt_copy')).width(21).height(21).fillColor(AppTheme.TextSecondary)
          }.width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
            .accessibilityText($r('app.string.reader_excerpt_copy')).onClick((): void => { this.copy(); })
          Button({ type: ButtonType.Circle }) {
            if (this.busy) {
              LoadingProgress().width(22).height(22).color(AppColor.Brand)
            } else {
              Image($r('app.media.reader_excerpt_share')).width(22).height(22).fillColor(AppTheme.TextSecondary)
            }
          }.width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
            .accessibilityText($r('app.string.reader_excerpt_share')).bindMenu(this.shareMenu())
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([AppTheme.TextSecondary])
          }.width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
            .accessibilityText($r('app.string.reader_excerpt_delete')).onClick((): void => this.confirmDelete())
        }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
