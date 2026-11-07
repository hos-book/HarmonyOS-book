import { AppMaterial } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';
import { WindowUtils } from '../utils/WindowUtils';

/** 锚点说明层也可用于阅读设置浮层内部，避免嵌套 Popup。 */
@ComponentV2
export struct SettingsHintButton {
  @Param title: ResourceStr = '';
  @Param message: ResourceStr = '';
  @Local hintVisible: boolean = false;
  @Local hintWidth: number = 280;
  @Local hintMaxHeight: number = 220;

  @Builder
  hintContent(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.title).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([$r('sys.color.font_secondary')])
        }.width(32).height(32).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_close'))
          .onClick((): void => { this.hintVisible = false; })
      }.width('100%')
      Scroll() {
        Text(this.message).fontSize(14).fontColor($r('sys.color.font_primary')).width('100%')
      }.width('100%').constraintSize({ maxHeight: this.hintMaxHeight }).scrollBar(BarState.Auto)
    }.width(this.hintWidth).padding(16).alignItems(HorizontalAlign.Start)
  }

  private hintOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.Bottom,
      backgroundColor: AppMaterial.SheetBackground,
      onDisappear: (): void => { this.hintVisible = false; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  private hintDescription(): string {
    if (typeof this.title === 'string') return this.title;
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(this.title.id) ?? '';
    } catch (_error) { return ''; }
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17)
        .fontColor([$r('sys.color.font_secondary')])
    }.width(32).height(32).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.settings_hint_action'))
      .accessibilityDescription(this.hintDescription())
      .onClick((): void => {
        this.hintWidth = Math.max(120, Math.min(280, WindowUtils.getWindowWidthVp() - 48));
        this.hintMaxHeight = Math.max(60, Math.min(220, WindowUtils.getWindowHeightVp() - 180));
        this.hintVisible = !this.hintVisible;
      })
      .bindMenu(this.hintVisible, this.hintContent, this.hintOptions())
  }
}
