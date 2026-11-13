import { ComponentContent, promptAction, UIContext } from '@kit.ArkUI';
import { GeneralSettings } from '../model/GeneralSettings';
import { ReaderSelectionSettings } from '../model/ReaderSelectionSettings';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppMaterial, AppRadius } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';
import { WindowUtils } from '../utils/WindowUtils';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';

@ComponentV2
export struct ReaderSelectionSettingsPanel {
  @Local order: string[] = ReaderSelectionSettings.order(GeneralSettings.current.selectionMenuOrder);
  @Local hidden: string[] = ReaderSelectionSettings.hidden(GeneralSettings.current.selectionMenuHidden);
  @Local saving: boolean = false;
  @Event onClose: () => void = () => {};
  private source: HomeRecommendationDataSource<string> = new HomeRecommendationDataSource();
  private readonly moveHandler: (from: number, to: number) => void =
    (from: number, to: number): void => this.move(from, to);

  aboutToAppear(): void { this.source.setItems(this.order); }

  private async save(order: string[], hidden: string[]): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    const previousOrder = this.order;
    const previousHidden = this.hidden;
    // 原生拖拽要求在落位回调返回前同步更新，持久化失败再回滚。
    this.order = order;
    this.hidden = hidden;
    this.source.setItems(order);
    try {
      await PreferenceService.setSelectionMenu(order.join(','), hidden.join(','));
    } catch (_error) {
      this.order = previousOrder;
      this.hidden = previousHidden;
      this.source.setItems(previousOrder);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally { this.saving = false; }
  }

  private move(from: number, to: number): void {
    if (this.saving || from === to || from < 0 || to < 0 ||
      from >= this.order.length || to >= this.order.length) return;
    const order = this.order.slice();
    order.splice(to, 0, order.splice(from, 1)[0]);
    this.save(order, this.hidden.slice());
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.selection_settings')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button($r('app.string.selection_done')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => this.onClose()).enabled(!this.saving)
      }.width('100%')
      Text($r('app.string.selection_settings_hint')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      List({ space: 4 }) {
          LazyForEach(this.source, (key: string) => {
            ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(20)
                .fontColor([$r('sys.color.font_tertiary')])
                .accessibilityText($r('app.string.selection_drag_sort'))
              Text(ReaderSelectionSettings.label(key)).fontSize(14).fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: !this.hidden.includes(key) }).selectedColor(AppColor.Brand)
                .enabled(!this.saving).accessibilityText(ReaderSelectionSettings.label(key))
                .onChange((enabled: boolean): void => {
                  const hidden = this.hidden.filter((value: string): boolean => value !== key);
                  if (!enabled) hidden.push(key);
                  this.save(this.order.slice(), hidden);
                }).id('selection-enabled-' + key)
            }.width('100%').height(48)
            }.id('selection-row-' + key).borderRadius(8)
          }, (key: string): string => key)
            .onMove(this.saving ? undefined : this.moveHandler)
          ListItem() {
          Button($r('app.string.selection_reset')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .enabled(!this.saving).onClick((): void => { this.save(ReaderSelectionSettings.defaults.slice(), []); })
          }
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).contentEndOffset(12)
    }.width(Math.min(420, WindowUtils.getWindowWidthVp() - 32))
      .height(Math.min(640, WindowUtils.getWindowHeightVp() * 0.8)).padding(20)
      .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Xl)
  }
}

class SelectionSettingsDialogParams {
  onClose: () => void = () => {};
}

@Builder
function selectionSettingsContent(params: SelectionSettingsDialogParams) {
  ReaderSelectionSettingsPanel({ onClose: params.onClose })
}

export class ReaderSelectionSettingsDialog {
  static async open(context: UIContext): Promise<void> {
    const prompt = context.getPromptAction();
    const params = new SelectionSettingsDialogParams();
    let dialog: ComponentContent<SelectionSettingsDialogParams> | null = null;
    params.onClose = (): void => {
      if (dialog !== null) prompt.closeCustomDialog(dialog).catch((): void => {});
    };
    const content = new ComponentContent(context, wrapBuilder(selectionSettingsContent), params);
    dialog = content;
    const options: promptAction.BaseDialogOptions = {
      alignment: DialogAlignment.Center,
      autoCancel: true,
      onDidDisappear: (): void => content.dispose()
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.DialogUltraThick;
    try { await prompt.openCustomDialog(content, options); }
    catch (_error) { content.dispose(); prompt.showToast({ message: $r('app.string.settings_save_failed') }); }
  }
}
