import { common, sendableContextManager } from '@kit.AbilityKit';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { ManagementBatchBar } from '../components/ManagementBatchBar';
import { ReaderFontService, ReaderImportedFont } from '../service/text/ReaderFontService';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { AppColor, AppFont, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct FontManagementPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local fonts: ReaderImportedFont[] = [];
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local busy: boolean = false;
  @Local managing: boolean = false;
  @Local selectedPaths: string[] = [];
  private context: common.UIAbilityContext | null = null;
  private alive: boolean = false;
  private source: HomeRecommendationDataSource<ReaderImportedFont> = new HomeRecommendationDataSource();
  private readonly moveHandler: (from: number, to: number) => void =
    (from: number, to: number): void => { this.moveFont(from, to); };

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getHostContext();
    if (context) this.context = sendableContextManager.convertToUIAbilityContext(
      sendableContextManager.convertFromContext(context));
    this.load();
  }

  aboutToDisappear(): void { this.alive = false; }

  private updateFonts(fonts: ReaderImportedFont[]): void {
    if (!this.alive) return;
    this.fonts = fonts;
    this.selectedPaths = this.selectedPaths.filter((path: string): boolean =>
      fonts.some((font: ReaderImportedFont): boolean => font.path === path));
    this.source.setItems(fonts);
  }

  private async load(): Promise<void> {
    if (!this.context || this.busy) return;
    this.busy = true;
    this.failed = false;
    try {
      this.updateFonts(await ReaderFontService.list(this.context));
      if (this.alive) this.ready = true;
    } catch (_error) { if (this.alive) this.failed = true; }
    finally { if (this.alive) this.busy = false; }
  }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async importFonts(): Promise<void> {
    if (!this.context || this.busy) return;
    this.busy = true;
    try {
      const result = await ReaderFontService.pick(this.context);
      this.updateFonts(await ReaderFontService.list(this.context));
      if (result.failures.length > 0) {
        this.toast($r('app.string.reader_font_partial', result.fonts.length, result.failures.length));
      } else if (result.fonts.length > 0) {
        this.toast($r('app.string.reading_font_import_success', result.fonts.length));
      }
    } catch (_error) { this.toast($r('app.string.reader_import_font_failed')); }
    finally { if (this.alive) this.busy = false; }
  }

  private confirmDelete(font: ReaderImportedFont): void {
    if (this.busy) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.reader_delete_font_option', font.name),
      message: $r('app.string.reader_font_delete_confirm'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.rule_source_delete_action'),
        action: (): void => { this.deleteFonts([font.path]); } }
    });
  }

  private selectItem(path: string, selected: boolean): void {
    if (this.busy) return;
    this.selectedPaths = this.selectedPaths.filter((value: string): boolean => value !== path);
    if (selected) this.selectedPaths = [...this.selectedPaths, path];
  }

  private confirmBatchDelete(): void {
    if (this.busy || this.selectedPaths.length === 0) return;
    const paths = this.selectedPaths.slice();
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tts_batch_delete'),
      message: $r('app.string.reader_font_batch_delete_confirm', paths.length),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.rule_source_delete_action'),
        action: (): void => { this.deleteFonts(paths); } }
    });
  }

  private async deleteFonts(paths: string[]): Promise<void> {
    if (!this.context || this.busy || paths.length === 0) return;
    this.busy = true;
    try {
      const result = await ReaderFontService.removeBatch(this.context, paths);
      this.updateFonts(result.fonts);
      this.toast(result.failedCount > 0 ? $r('app.string.reader_font_delete_partial', result.failedCount) :
        $r('app.string.tts_batch_success'));
    } catch (_error) {
      // 部分文件可能已删除，重新读取目录以保留仍可重试的选择。
      try { this.updateFonts(await ReaderFontService.list(this.context)); } catch (_reloadError) {}
      this.toast($r('app.string.reader_font_delete_failed'));
    } finally { if (this.alive) this.busy = false; }
  }

  private async setEnabled(paths: string[], enabled: boolean): Promise<void> {
    if (!this.context || this.busy || paths.length === 0) return;
    this.busy = true;
    try {
      this.updateFonts(await ReaderFontService.setEnabled(this.context, paths, enabled));
      if (this.alive) this.selectedPaths = [];
    } catch (_error) { this.toast($r('app.string.reader_font_save_failed')); }
    finally { if (this.alive) this.busy = false; }
  }

  private moveFont(from: number, to: number): void {
    if (this.busy || from === to || from < 0 || to < 0 || from >= this.fonts.length || to >= this.fonts.length) return;
    const ordered = this.fonts.slice();
    ordered.splice(to, 0, ordered.splice(from, 1)[0]);
    this.saveOrder(ordered);
  }

  private async saveOrder(ordered: ReaderImportedFont[]): Promise<void> {
    if (!this.context || this.busy) return;
    const previous = this.fonts;
    this.busy = true;
    // 在 onMove 返回前同步落位；持久化失败恢复旧顺序。
    this.updateFonts(ordered);
    try {
      this.updateFonts(await ReaderFontService.reorder(this.context,
        ordered.map((font: ReaderImportedFont): string => font.path)));
    } catch (_error) {
      this.updateFonts(previous);
      this.toast($r('app.string.reader_font_save_failed'));
    }
    finally { if (this.alive) this.busy = false; }
  }

  @Builder
  fontRow(font: ReaderImportedFont) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(22).fontColor([AppTheme.TextSecondary])
        .width(32).height(40).accessibilityText($r('app.string.reader_font_sort_hint'))
        .id(`font-drag-${font.path}`)
      if (this.managing) {
        Checkbox({ name: font.path }).select(this.selectedPaths.includes(font.path))
          .selectedColor(AppColor.Brand).enabled(!this.busy).accessibilityText(font.name)
          .onChange((selected: boolean): void => { this.selectItem(font.path, selected); })
      }
      Text(font.name).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).opacity(font.enabled ? 1 : 0.5)
        .onClick((): void => {
          if (this.managing) this.selectItem(font.path, !this.selectedPaths.includes(font.path));
        })
      if (!this.managing) {
        Toggle({ type: ToggleType.Switch, isOn: font.enabled }).selectedColor(AppColor.Brand)
          .enabled(!this.busy).accessibilityText($r('app.string.reader_font_enabled', font.name))
          .onChange((enabled: boolean): void => {
            if (enabled !== font.enabled) this.setEnabled([font.path], enabled);
          })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([AppTheme.TextSecondary])
        }.width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
          .accessibilityText($r('app.string.reader_delete_font_option', font.name))
          .onClick((): void => { this.confirmDelete(font); })
      }
    }.width('100%').constraintSize({ minHeight: 56 })
      .padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.Surface).borderRadius(16).border({ width: 0.5, color: AppTheme.Divider })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          List({ space: 6 }) {
            ListItem() {
              Column({ space: 4 }) {
                Text($r('app.string.reading_font_import_hint', this.fonts.length))
                  .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
                Text($r('app.string.reader_import_font_hint')).fontSize(AppFont.Caption)
                  .fontColor(AppTheme.TextSecondary)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 8 })
            }
            if (this.fonts.length === 0) {
              ListItem() {
                Text($r('app.string.reader_font_management_empty')).fontSize(AppFont.Body)
                  .fontColor(AppTheme.TextSecondary).width('100%').textAlign(TextAlign.Center).padding(24)
              }
            }
            LazyForEach(this.source, (font: ReaderImportedFont) => {
              ListItem() { this.fontRow(font) }
            }, (font: ReaderImportedFont): string => `${font.path}:${font.enabled}`)
              .onMove(this.busy ? undefined : this.moveHandler)
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
            .padding({ left: 16, right: 16 }).contentStartOffset(this.headerHeight + 4).contentEndOffset(12)
        } else if (this.failed) {
          Text($r('app.string.reader_font_load_failed')).fontColor(AppTheme.TextSecondary).padding(20)
          Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .onClick((): void => { this.load(); })
        } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
      }.width('100%').constraintSize({ maxWidth: 760 }).height('100%')
        .padding({ top: this.ready ? 0 : this.headerHeight, bottom: WindowUtils.getBottomSafeVp() })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.reader_font_management')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!this.managing) {
            Button($r('app.string.reader_import_font')).height(32).fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface).padding({ left: 10, right: 10 })
              .enabled(this.ready && !this.busy).id('font-management-import')
              .onClick((): void => { this.importFonts(); })
          }
          Button(this.managing ? $r('app.string.tts_manage_done') : $r('app.string.tts_batch'))
            .height(32).fontSize(AppFont.Caption).padding({ left: 10, right: 10 })
            .fontColor(this.managing ? AppColor.OnBrand : AppColor.Brand)
            .backgroundColor(this.managing ? AppColor.Brand : AppTheme.Surface)
            .enabled(this.ready && !this.busy && (this.managing || this.fonts.length > 0))
            .onClick((): void => { this.managing = !this.managing; this.selectedPaths = []; })
            .id('font-management-batch')
          if (this.ready && this.busy) { LoadingProgress().width(20).height(20).color(AppColor.Brand) }
        }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
        if (this.managing) {
          ManagementBatchBar({ selectedCount: this.selectedPaths.length, totalCount: this.fonts.length,
            busy: this.busy,
            onSelectAll: (): void => {
              this.selectedPaths = this.selectedPaths.length === this.fonts.length ? [] :
                this.fonts.map((font: ReaderImportedFont): string => font.path);
            },
            onEnable: (): void => { this.setEnabled(this.selectedPaths.slice(), true); },
            onDisable: (): void => { this.setEnabled(this.selectedPaths.slice(), false); },
            onDelete: (): void => { this.confirmBatchDelete(); } })
        }
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
