import { promptAction } from '@kit.ArkUI';
import { PlatformCompat } from '../utils/PlatformCompat';
import { WindowUtils } from '../utils/WindowUtils';
import { ImmersiveActionButton } from './ImmersiveActionButton';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
import { AppAppearance } from '../model/AppAppearance';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

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
  new MaterialChoice(AppAppearance.systemMaterial, $r('app.string.appearance_material_system')),
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

/** 主题色先编辑本地草稿，点击应用后才更新共享 V2 外观状态。 */
@ComponentV2
export struct AppearanceSettingsComponent {
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local customHex: string = '';
  @Local accentDraft: string = '';
  @Local colorInvalid: boolean = false;
  @Local saving: boolean = false;
  private accentDialogId: number = -1;
  private accentDialogOpen: boolean = false;

  aboutToDisappear(): void {
    this.closeAccentDialog();
  }

  private async openAccentDialog(): Promise<void> {
    if (this.saving || this.accentDialogOpen) return;
    this.accentDraft = this.appearance.accent;
    this.customHex = this.appearance.accent || AppAppearance.defaultAccent;
    this.colorInvalid = false;
    this.accentDialogOpen = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const options: promptAction.CustomDialogOptions = {
        builder: (): void => { this.accentContent(); },
        alignment: DialogAlignment.Center,
        width: Math.min(320, WindowUtils.getWindowWidthVp() - 32),
        cornerRadius: AppRadius.Xl,
        autoCancel: true,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (!this.saving) action.dismiss();
        },
        onDidDisappear: (): void => {
          this.accentDialogId = -1;
          this.accentDialogOpen = false;
        }
      };
      if (PlatformCompat.immersiveMaterial) {
        options.systemMaterial = AppMaterial.DialogUltraThick;
      } else {
        options.backgroundBlurStyle = BlurStyle.COMPONENT_ULTRA_THICK;
      }
      const dialogId: number = await prompt.openCustomDialog(options);
      if (this.accentDialogOpen) {
        this.accentDialogId = dialogId;
      } else {
        prompt.closeCustomDialog(dialogId);
      }
    } catch (_error) {
      this.accentDialogOpen = false;
    }
  }

  private closeAccentDialog(): void {
    this.accentDialogOpen = false;
    if (this.accentDialogId < 0) return;
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.accentDialogId);
    } catch (_error) { /* 页面退出时弹窗可能已被系统关闭。 */ }
    this.accentDialogId = -1;
  }

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

  private selectAccent(value: string): void {
    if (this.saving) return;
    this.accentDraft = value;
    this.customHex = value || AppAppearance.defaultAccent;
    this.colorInvalid = false;
  }

  private async applyCustomAccent(): Promise<void> {
    if (this.saving) return;
    const normalized: string = AppAppearance.normalizeAccent(this.customHex);
    this.colorInvalid = normalized.length === 0;
    if (!this.colorInvalid) {
      await this.applyAccent(this.accentDraft === '' && normalized === AppAppearance.defaultAccent ? '' : normalized);
    }
  }

  private showSaveError(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.appearance_save_failed') });
    } catch (_e) { /* 页面关闭后无需提示。 */ }
  }

  @Builder
  divider() {
    Divider().color(AppTheme.Divider).strokeWidth(0.5).margin({ left: AppSpace.Md })
  }

  @Builder
  accentContent() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_accent'))
          .fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_cancel')).enabled(!this.saving)
          .onClick((): void => { this.closeAccentDialog(); })
          .id('appearance-accent-close')
      }.width('100%')
      Text($r('app.string.appearance_accent_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      GridRow({ columns: 3, gutter: { x: AppSpace.Xs, y: AppSpace.Xs } }) {
        ForEach(ACCENT_CHOICES, (choice: AccentChoice) => {
          GridCol() {
            Column({ space: AppSpace.Xs }) {
              Stack() {
                Row().width(42).height(42).borderRadius(21).backgroundColor(choice.color || AppAppearance.defaultAccent)
                if ((this.accentDraft || AppAppearance.defaultAccent) === (choice.color || AppAppearance.defaultAccent)) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(20)
                    .fontColor([AppAppearance.foreground(choice.color || AppAppearance.defaultAccent)])
                }
              }
              Text(choice.label).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
            }
            .width('100%')
            .padding({ top: AppSpace.Xs, bottom: AppSpace.Sm })
            .borderRadius(AppRadius.Lg)
            .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
            .enabled(!this.saving)
            .onClick(() => this.selectAccent(choice.color))
          }
        }, (choice: AccentChoice) => choice.color || 'default')
      }
      Row({ space: AppSpace.Sm }) {
        TextInput({ text: this.customHex, placeholder: $r('app.string.appearance_accent_hex_hint') })
          .enabled(!this.saving)
          .layoutWeight(1)
          .maxLength(7)
          .onChange((value: string) => {
            this.customHex = value;
            this.accentDraft = value;
            this.colorInvalid = false;
          })
        ImmersiveActionButton({
          textSize: AppFont.Body,
          onPress: (): void => { this.applyCustomAccent(); }
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
    .padding(20)
    .borderRadius(AppRadius.Xl)
    .clip(true)
    .id('appearance-accent-dialog')
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_material')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        ImmersiveOptionTabs({
          labels: MATERIAL_CHOICES.map((choice: MaterialChoice): ResourceStr => choice.label),
          selected: MATERIAL_CHOICES.findIndex((choice: MaterialChoice): boolean => choice.value === this.appearance.material),
          onSelect: (index: number): void => { this.applyMaterial(MATERIAL_CHOICES[index].value); }
        }).enabled(!this.saving)
      }.width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Xs, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .constraintSize({ minHeight: 56 })
      this.divider()
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_accent')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Row().width(22).height(22).borderRadius(11).backgroundColor(AppColor.Brand)
        Text(this.appearance.accent || $r('app.string.appearance_accent_default')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .constraintSize({ minHeight: 52 })
      .id('appearance-accent-entry')
      .onClick((): void => { this.openAccentDialog(); })
    }
    .width('100%')
  }
}
