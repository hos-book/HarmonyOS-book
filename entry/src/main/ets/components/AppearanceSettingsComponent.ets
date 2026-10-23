import { ImmersiveActionButton } from './ImmersiveActionButton';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
import { AppAppearance } from '../model/AppAppearance';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace } from '../theme/Theme';

class MaterialChoice {
  value: number;
  label: Resource;
  constructor(value: number, label: Resource) {
    this.value = value;
    this.label = label;
  }
}

class AccentChoice {
  color: string;
  label: Resource;
  constructor(color: string, label: Resource) {
    this.color = color;
    this.label = label;
  }
}

const MATERIAL_CHOICES: MaterialChoice[] = [
  new MaterialChoice(2, $r('app.string.appearance_material_strong')),
  new MaterialChoice(3, $r('app.string.appearance_material_balanced')),
  new MaterialChoice(4, $r('app.string.appearance_material_weak'))
];

const ACCENT_CHOICES: AccentChoice[] = [
  new AccentChoice('#FF6B3D', $r('app.string.appearance_accent_orange')),
  new AccentChoice('', $r('app.string.appearance_accent_rose')),
  new AccentChoice('#8E55B8', $r('app.string.appearance_accent_purple')),
  new AccentChoice('#2869B8', $r('app.string.appearance_accent_blue')),
  new AccentChoice('#008577', $r('app.string.appearance_accent_teal')),
  new AccentChoice('#557C36', $r('app.string.appearance_accent_green'))
];

/** 仅由系统设置页使用；通过共享 V2 外观状态即时刷新控件。 */
@ComponentV2
export struct AppearanceSettingsComponent {
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local showAccent: boolean = false;
  @Local customHex: string = '';
  @Local colorInvalid: boolean = false;
  @Local saving: boolean = false;

  private async applyMaterial(value: number): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await PreferenceService.setMaterialStyle(value);
    } catch (_e) {
      this.showSaveError();
    } finally {
      this.saving = false;
    }
  }

  private async applyAccent(value: string): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await PreferenceService.setAccentColor(value);
      this.customHex = value || AppAppearance.defaultAccent;
      this.colorInvalid = false;
    } catch (_e) {
      this.showSaveError();
    } finally {
      this.saving = false;
    }
  }

  private applyCustomAccent(): void {
    const normalized: string = AppAppearance.normalizeAccent(this.customHex);
    this.colorInvalid = normalized.length === 0;
    if (!this.colorInvalid) this.applyAccent(normalized);
  }

  private showSaveError(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.appearance_save_failed') });
    } catch (_e) { /* 页面关闭后无需提示。 */ }
  }

  @Builder
  divider() {
    Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: AppSpace.Md })
  }

  @Builder
  accentSheet() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.appearance_accent_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(ACCENT_CHOICES, (choice: AccentChoice) => {
          Column({ space: AppSpace.Xs }) {
            Stack() {
              Row().width(42).height(42).borderRadius(21).backgroundColor(choice.color || AppAppearance.defaultAccent)
              if ((this.appearance.accent || AppAppearance.defaultAccent) === (choice.color || AppAppearance.defaultAccent)) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(20)
                  .fontColor([AppAppearance.foreground(choice.color || AppAppearance.defaultAccent)])
              }
            }
            Text(choice.label).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
          }
          .width('30%')
          .padding({ top: AppSpace.Xs, bottom: AppSpace.Sm })
          .borderRadius(AppRadius.Lg)
          .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
          .enabled(!this.saving)
          .onClick(() => this.applyAccent(choice.color))
        }, (choice: AccentChoice) => choice.color || 'default')
      }
      Row({ space: AppSpace.Sm }) {
        TextInput({ text: this.customHex, placeholder: $r('app.string.appearance_accent_hex_hint') })
          .layoutWeight(1)
          .maxLength(7)
          .onChange((value: string) => {
            this.customHex = value;
            this.colorInvalid = false;
          })
          .onSubmit(() => this.applyCustomAccent())
        ImmersiveActionButton({
          textSize: AppFont.Body,
          onPress: (): void => this.applyCustomAccent()
        }).width(72).enabled(!this.saving)
      }
      .width('100%')
      if (this.colorInvalid) {
        Text($r('app.string.appearance_accent_invalid'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg })
  }

  build() {
    Column() {
      this.divider()
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_material')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        ImmersiveOptionTabs({
          labels: MATERIAL_CHOICES.map((choice: MaterialChoice): ResourceStr => choice.label),
          selected: MATERIAL_CHOICES.findIndex((choice: MaterialChoice): boolean => choice.value === this.appearance.material),
          onSelect: (index: number): void => { this.applyMaterial(MATERIAL_CHOICES[index].value); }
        })
      }.width('100%').padding(AppSpace.Md)
      this.divider()
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_accent')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Row().width(22).height(22).borderRadius(11).backgroundColor(AppColor.Brand)
        Text(this.appearance.accent || $r('app.string.appearance_accent_default')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%').padding(AppSpace.Md).constraintSize({ minHeight: 56 })
      .onClick(() => {
        this.customHex = this.appearance.accent || AppAppearance.defaultAccent;
        this.colorInvalid = false;
        this.showAccent = true;
      })
      .bindSheet($$this.showAccent, this.accentSheet(), {
        height: SheetSize.FIT_CONTENT,
        detents: [SheetSize.FIT_CONTENT, '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM,
        title: { title: $r('app.string.appearance_accent') },
        backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.SheetBlur,
        systemMaterial: AppMaterial.Sheet
      })
    }
    .width('100%')
  }
}
