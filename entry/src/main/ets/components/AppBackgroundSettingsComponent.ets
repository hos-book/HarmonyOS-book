import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppAppearance } from '../model/AppAppearance';
import {
  AppBackgroundConfig, AppBackgroundImportError, AppBackgroundImportReason,
  AppBackgroundScene, AppBackgroundSelection
} from '../model/AppBackground';
import { ThemeBackgroundScene } from '../model/AppThemeVisual';
import { AppBackgroundService } from '../service/AppBackgroundService';
import { BottomTabIconService } from '../service/BottomTabIconService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { ThemeIconRole } from '../theme/ThemeIcons';
import { SliderGestureModifier } from '../utils/SliderGestureModifier';
import { AppBackgroundLayerComponent } from './AppBackgroundLayerComponent';
import { CoverImage } from './CoverImage';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
import { ThemeBackgroundComponent } from './ThemeBackgroundComponent';
import { ThemeIconComponent } from './ThemeIconComponent';

class BackgroundPageOption {
  scene: AppBackgroundScene;
  label: Resource;
  role: ThemeIconRole;
  symbol: Resource;

  constructor(scene: AppBackgroundScene, label: Resource, role: ThemeIconRole, symbol: Resource) {
    this.scene = scene;
    this.label = label;
    this.role = role;
    this.symbol = symbol;
  }
}

class BackgroundPresetOption {
  id: string;
  label: Resource;

  constructor(id: string, label: Resource) {
    this.id = id;
    this.label = label;
  }
}

enum BackgroundAdjustment { Veil, Blur, PositionX, PositionY, Scale }

/** 本地草稿与已应用背景分离；被跟随开关隐藏的独立配置仍保留。 */
@ComponentV2
export struct AppBackgroundSettingsComponent {
  @Local service: AppBackgroundService = AppBackgroundService.instance;
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local tabIcons: BottomTabIconService = BottomTabIconService.instance;
  @Local draft: AppBackgroundSelection = new AppBackgroundSelection();
  @Local scene: AppBackgroundScene = AppBackgroundScene.Common;
  @Local dirty: boolean = false;
  @Local picking: boolean = false;
  @Local saving: boolean = false;
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;
  @Local showAdvanced: boolean = false;
  private alive: boolean = false;
  private request: number = 0;
  private importedImages: string[] = [];
  private pages: BackgroundPageOption[] = [
    new BackgroundPageOption(AppBackgroundScene.Home, $r('app.string.bottom_tab_icon_home'),
      ThemeIconRole.Home, $r('sys.symbol.house_fill')),
    new BackgroundPageOption(AppBackgroundScene.Shelf, $r('app.string.bottom_tab_icon_shelf'),
      ThemeIconRole.Shelf, $r('sys.symbol.bookshelf')),
    new BackgroundPageOption(AppBackgroundScene.Record, $r('app.string.bottom_tab_icon_record'),
      ThemeIconRole.Record, $r('sys.symbol.calendar_fill')),
    new BackgroundPageOption(AppBackgroundScene.Profile, $r('app.string.bottom_tab_icon_profile'),
      ThemeIconRole.Profile, $r('sys.symbol.person_fill'))
  ];
  private presets: BackgroundPresetOption[] = [
    new BackgroundPresetOption('theme', $r('app.string.app_background_preset_theme')),
    new BackgroundPresetOption('paper', $r('app.string.app_background_preset_paper')),
    new BackgroundPresetOption('mist', $r('app.string.app_background_preset_mist'))
  ];

  aboutToAppear(): void {
    this.alive = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.request++;
    if (!this.saving) this.discardImports();
  }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    this.loading = true;
    this.loadFailed = false;
    if (!context) {
      this.loading = false;
      this.loadFailed = true;
      return;
    }
    try {
      await this.service.init(context);
      if (this.alive) {
        this.draft = this.service.snapshot();
        this.dirty = false;
      }
    } catch (_error) {
      if (this.alive) this.loadFailed = true;
    } finally {
      if (this.alive) this.loading = false;
    }
  }

  private current(): AppBackgroundConfig {
    return this.draft.resolve(this.scene);
  }

  private mutableConfig(selection: AppBackgroundSelection): AppBackgroundConfig {
    return this.scene === AppBackgroundScene.Common ? selection.common : selection.page(this.scene).config;
  }

  private get following(): boolean {
    return this.scene !== AppBackgroundScene.Common && this.draft.page(this.scene).followCommon;
  }

  private get canEdit(): boolean {
    return !this.loading && this.service.ready && !this.saving && !this.picking && !this.service.busy;
  }

  private previewScene(): AppBackgroundScene {
    return this.scene === AppBackgroundScene.Common ? AppBackgroundScene.Home : this.scene;
  }

  private previewThemeScene(): ThemeBackgroundScene {
    switch (this.previewScene()) {
      case AppBackgroundScene.Shelf: return ThemeBackgroundScene.Shelf;
      case AppBackgroundScene.Record: return ThemeBackgroundScene.Record;
      default: return ThemeBackgroundScene.Home;
    }
  }

  private sceneLabel(): Resource {
    if (this.scene === AppBackgroundScene.Common) return $r('app.string.app_background_common');
    return this.pages.find((option: BackgroundPageOption): boolean => option.scene === this.scene)?.label ??
      $r('app.string.bottom_tab_icon_home');
  }

  private pageLabel(): Resource {
    return this.pages.find((option: BackgroundPageOption): boolean => option.scene === this.previewScene())?.label ??
      $r('app.string.bottom_tab_icon_home');
  }

  private selectScene(scene: AppBackgroundScene): void {
    if (!this.canEdit) return;
    this.scene = scene;
    this.showAdvanced = false;
    this.request++;
  }

  private setFollowing(value: boolean): void {
    if (!this.canEdit || this.scene === AppBackgroundScene.Common || value === this.following) return;
    const next = this.draft.copy();
    next.page(this.scene).followCommon = value;
    this.draft = next;
    this.dirty = true;
  }

  private selectPreset(id: string): void {
    if (!this.canEdit || this.following) return;
    const next = this.draft.copy();
    this.mutableConfig(next).preset = id;
    this.draft = next;
    this.dirty = true;
  }

  private changeValue(adjustment: BackgroundAdjustment, value: number): void {
    if (!this.canEdit || this.following) return;
    const next = this.draft.copy();
    const config = this.mutableConfig(next);
    switch (adjustment) {
      case BackgroundAdjustment.Veil: config.veil = Math.round(value); break;
      case BackgroundAdjustment.Blur: config.blur = Math.round(value); break;
      case BackgroundAdjustment.PositionX: config.positionX = Math.round(value); break;
      case BackgroundAdjustment.PositionY: config.positionY = Math.round(value); break;
      case BackgroundAdjustment.Scale: config.scale = Math.round(value); break;
    }
    this.draft = next;
    this.dirty = true;
  }

  private resetAdjustments(): void {
    if (!this.canEdit || this.following) return;
    const next = this.draft.copy();
    const config = this.mutableConfig(next);
    const defaults = new AppBackgroundConfig();
    config.veil = defaults.veil;
    config.blur = defaults.blur;
    config.positionX = defaults.positionX;
    config.positionY = defaults.positionY;
    config.scale = defaults.scale;
    this.draft = next;
    this.dirty = true;
  }

  private toast(message: Resource): void {
    if (!this.alive) return;
    try { this.getUIContext().getPromptAction().showToast({ message: message }); }
    catch (_error) { /* 保存结果不依赖页面提示上下文。 */ }
  }

  private async discardImports(): Promise<void> {
    const images = this.importedImages;
    this.importedImages = [];
    await this.service.cleanupDraftImages(images).catch((): void => {});
  }

  private async cancel(): Promise<void> {
    if (!this.canEdit || !this.dirty) return;
    this.request++;
    this.draft = this.service.snapshot();
    this.dirty = false;
    await this.discardImports();
    this.toast($r('app.string.app_background_cancelled'));
  }

  private async apply(): Promise<void> {
    if (!this.canEdit || !this.dirty) return;
    this.saving = true;
    try {
      await this.service.apply(this.draft.copy());
      if (this.alive) {
        this.draft = this.service.snapshot();
        this.dirty = false;
      }
      await this.discardImports();
      this.toast($r('app.string.app_background_applied'));
    } catch (_error) {
      this.toast($r('app.string.app_background_save_failed'));
    } finally {
      this.saving = false;
      if (!this.alive) await this.discardImports();
    }
  }

  private async pickImage(): Promise<void> {
    if (!this.canEdit || this.following) return;
    this.picking = true;
    const request = ++this.request;
    const scene = this.scene;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (!this.alive || request !== this.request || result.photoUris.length === 0) return;
      const name = await this.service.importImage(result.photoUris[0],
        (): boolean => this.alive && request === this.request && scene === this.scene);
      if (!name) return;
      this.importedImages.push(name);
      if (!this.alive || request !== this.request || scene !== this.scene) {
        await this.discardImports();
        return;
      }
      const next = this.draft.copy();
      const config = this.mutableConfig(next);
      config.imageFile = name;
      config.preset = 'image';
      config.positionX = 50;
      config.positionY = 50;
      config.scale = 100;
      this.draft = next;
      this.dirty = true;
    } catch (error) {
      if (request === this.request) this.toast(this.importErrorText(error));
    } finally { this.picking = false; }
  }

  private importErrorText(error: Error): Resource {
    if (!(error instanceof AppBackgroundImportError)) return $r('app.string.app_background_import_failed');
    switch (error.reason) {
      case AppBackgroundImportReason.InputTooLarge: return $r('app.string.app_background_import_too_large');
      case AppBackgroundImportReason.InvalidImage: return $r('app.string.app_background_import_invalid');
      case AppBackgroundImportReason.DimensionsTooLarge: return $r('app.string.app_background_import_dimensions');
      case AppBackgroundImportReason.ReadFailed: return $r('app.string.app_background_import_read_failed');
      case AppBackgroundImportReason.DecodeFailed: return $r('app.string.app_background_import_decode_failed');
      case AppBackgroundImportReason.EncodeFailed: return $r('app.string.app_background_import_encode_failed');
      case AppBackgroundImportReason.SaveFailed: return $r('app.string.app_background_import_save_failed');
    }
  }

  private removeImage(): void {
    if (!this.canEdit || this.following) return;
    const next = this.draft.copy();
    const config = this.mutableConfig(next);
    config.imageFile = '';
    if (config.preset === 'image') config.preset = 'theme';
    this.draft = next;
    this.dirty = true;
  }

  private presetConfig(id: string): AppBackgroundConfig {
    const config = new AppBackgroundConfig();
    config.preset = id;
    return config;
  }

  private sceneLabels(): ResourceStr[] {
    const labels: ResourceStr[] = [$r('app.string.app_background_common')];
    for (const page of this.pages) labels.push(page.label);
    return labels;
  }

  private selectSceneIndex(index: number): void {
    const scenes: AppBackgroundScene[] = [AppBackgroundScene.Common, AppBackgroundScene.Home,
      AppBackgroundScene.Shelf, AppBackgroundScene.Record, AppBackgroundScene.Profile];
    this.selectScene(scenes[index] ?? AppBackgroundScene.Common);
  }

  private adjustmentLabel(adjustment: BackgroundAdjustment): Resource {
    switch (adjustment) {
      case BackgroundAdjustment.Veil: return $r('app.string.app_background_veil');
      case BackgroundAdjustment.Blur: return $r('app.string.app_background_blur');
      case BackgroundAdjustment.PositionX: return $r('app.string.app_background_position_x');
      case BackgroundAdjustment.PositionY: return $r('app.string.app_background_position_y');
      case BackgroundAdjustment.Scale: return $r('app.string.app_background_scale');
      default: return $r('app.string.app_background_veil');
    }
  }

  private adjustmentValue(adjustment: BackgroundAdjustment): number {
    switch (adjustment) {
      case BackgroundAdjustment.Veil: return this.current().veil;
      case BackgroundAdjustment.Blur: return this.current().blur;
      case BackgroundAdjustment.PositionX: return this.current().positionX;
      case BackgroundAdjustment.PositionY: return this.current().positionY;
      case BackgroundAdjustment.Scale: return this.current().scale;
      default: return this.current().veil;
    }
  }

  private adjustmentMinimum(adjustment: BackgroundAdjustment): number {
    return adjustment === BackgroundAdjustment.Scale ? 100 : 0;
  }

  private adjustmentMaximum(adjustment: BackgroundAdjustment): number {
    switch (adjustment) {
      case BackgroundAdjustment.Veil: return 80;
      case BackgroundAdjustment.Blur: return 16;
      case BackgroundAdjustment.Scale: return 180;
      default: return 100;
    }
  }

  @Builder
  private previewIcon(option: BackgroundPageOption) {
    if (this.tabIcons.resolve(option.role) !== undefined) {
      Image(this.tabIcons.resolve(option.role)).width(22).height(22).objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
    } else {
      ThemeIconComponent({ role: option.role, symbol: option.symbol, iconSize: 22,
        themeBundleId: this.appearance.themeBundleId,
        tint: this.previewScene() === option.scene ? AppColor.Brand : AppTheme.TextSecondary })
    }
  }

  @Builder
  private previewBook(useLocal: boolean = false) {
    Column({ space: 6 }) {
      CoverImage({ imgWidth: 48, imgHeight: 70, useFixedHeight: true, radius: 4,
        themeBundleId: this.appearance.themeBundleId })
      Text(useLocal ? $r('app.string.theme_bundle_preview_local') : $r('app.string.theme_bundle_preview_book'))
        .fontSize(AppFont.Caption).fontColor(AppTheme.TextPrimary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.layoutWeight(1)
  }

  @Builder
  private previewBody() {
    if (this.previewScene() === AppBackgroundScene.Shelf) {
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.app_background_preview_recent')).fontSize(AppFont.Caption)
          .fontColor(AppTheme.TextSecondary).width('100%')
        Row({ space: AppSpace.Sm }) {
          this.previewBook()
          this.previewBook(true)
          this.previewBook()
        }.width('100%')
      }.width('100%').padding(AppSpace.Sm).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
    } else if (this.previewScene() === AppBackgroundScene.Record) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.app_background_preview_total')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextPrimary).padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(AppTheme.Surface).borderRadius(20).clip(true)
          Text($r('app.string.app_background_preview_streak')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextPrimary).padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(AppTheme.Surface).borderRadius(20).clip(true)
        }.width('100%')
        Row({ space: AppSpace.Sm }) {
          CoverImage({ imgWidth: 40, imgHeight: 56, useFixedHeight: true, radius: 4,
            themeBundleId: this.appearance.themeBundleId })
          Column({ space: 4 }) {
            Text($r('app.string.theme_bundle_preview_book')).fontSize(AppFont.Body)
              .fontColor(AppTheme.TextPrimary).maxLines(1)
            Text($r('app.string.theme_bundle_preview_subtitle')).fontSize(AppFont.Caption)
              .fontColor(AppTheme.TextSecondary).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%').padding(12).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
      }.width('100%')
    } else if (this.previewScene() === AppBackgroundScene.Profile) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.person_fill')).fontSize(34).fontColor([AppColor.Brand])
          Text($r('app.string.app_background_preview_profile')).fontSize(AppFont.Body)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        }.width('100%').padding(12).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
        Row() {
          Text($r('app.string.app_background_title')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([AppTheme.TextSecondary])
        }.width('100%').padding(12).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
      }.width('100%')
    } else {
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.theme_bundle_preview_title')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).width('100%').maxLines(2)
        Row({ space: AppSpace.Sm }) {
          CoverImage({ imgWidth: 44, imgHeight: 62, useFixedHeight: true, radius: 4,
            themeBundleId: this.appearance.themeBundleId })
          Column({ space: 4 }) {
            Text($r('app.string.theme_bundle_preview_book')).fontSize(AppFont.Body)
              .fontColor(AppTheme.TextPrimary).maxLines(1)
            Text($r('app.string.theme_bundle_preview_subtitle')).fontSize(AppFont.Caption)
              .fontColor(AppTheme.TextSecondary).maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(12).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
      }.width('100%')
    }
  }

  @Builder
  private preview() {
    Column({ space: AppSpace.Xs }) {
      Stack() {
        ThemeBackgroundComponent({ scene: this.previewThemeScene(), preview: true,
          themeBundleId: this.appearance.themeBundleId })
        AppBackgroundLayerComponent({ scene: this.previewScene(), config: this.current(), preview: true })
        Column({ space: AppSpace.Sm }) {
          Row() {
            Text(this.pageLabel()).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TextPrimary).layoutWeight(1)
            Text($r('app.string.app_background_preview')).fontSize(AppFont.Caption)
              .fontColor(AppTheme.TextSecondary)
          }.width('100%')
          this.previewBody()
          Blank()
          Row({ space: 4 }) {
            ForEach(this.pages, (option: BackgroundPageOption) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 3 }) {
                  this.previewIcon(option)
                  Text(option.label).fontSize(AppFont.Caption).maxLines(1)
                    .fontColor(this.previewScene() === option.scene ? AppColor.Brand : AppTheme.TextSecondary)
                }.width('100%').padding({ top: 8, bottom: 8 })
              }.layoutWeight(1).padding(0).borderRadius(24)
                .backgroundColor(this.previewScene() === option.scene ? AppColor.BrandSoft : Color.Transparent)
                .enabled(this.canEdit).accessibilityText(option.label)
                .id(`app-background-preview-${option.scene}`)
                .onClick((): void => this.selectScene(option.scene))
            }, (option: BackgroundPageOption): string => option.scene.toString())
          }.width('100%').padding(4).backgroundColor(AppTheme.Surface).borderRadius(28).clip(true)
        }.width('100%').height('100%').padding(AppSpace.Md)
      }.width('100%').height(300).backgroundColor(AppTheme.Background).borderRadius(AppRadius.Lg).clip(true)
        .border({ width: 0.5, color: AppTheme.Divider })
      Text(this.sceneLabel()).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
    }.width('100%')
  }

  @Builder
  private presetButton(option: BackgroundPresetOption) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        Stack() {
          ThemeBackgroundComponent({ preview: true, themeBundleId: this.appearance.themeBundleId })
          AppBackgroundLayerComponent({ scene: this.previewScene(), config: this.presetConfig(option.id), preview: true })
          if (this.current().preset === option.id) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(22).fontColor([AppColor.Brand])
          }
        }.width('100%').height(64).borderRadius(AppRadius.Sm).clip(true)
        Text(option.label).fontSize(AppFont.Caption).fontColor(AppTheme.TextPrimary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding(6)
    }.width('100%').padding(0).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md)
      .border({ width: this.current().preset === option.id ? 1.5 : 0.5,
        color: this.current().preset === option.id ? AppColor.Brand : AppTheme.Divider })
      .id(`app-background-preset-${option.id}`)
      .onClick((): void => this.selectPreset(option.id))
  }

  @Builder
  private slider(adjustment: BackgroundAdjustment) {
    Column({ space: 4 }) {
      Row() {
        Text(this.adjustmentLabel(adjustment)).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Text(adjustment === BackgroundAdjustment.Blur ? `${Math.round(this.adjustmentValue(adjustment))}` :
          `${Math.round(this.adjustmentValue(adjustment))}%`)
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      }.width('100%')
      Slider({ value: this.adjustmentValue(adjustment), min: this.adjustmentMinimum(adjustment),
        max: this.adjustmentMaximum(adjustment), step: 1 })
        .width('100%').selectedColor(AppColor.Brand).trackColor(AppTheme.Divider)
        .attributeModifier(new SliderGestureModifier(this.adjustmentMinimum(adjustment),
          this.adjustmentMaximum(adjustment)))
        .accessibilityText(this.adjustmentLabel(adjustment))
        .id(`app-background-adjustment-${adjustment}`)
        .onChange((next: number): void => this.changeValue(adjustment, next))
    }.width('100%')
  }

  @Builder
  private imageControls() {
    Column({ space: AppSpace.Sm }) {
      if (this.current().imageFile.length > 0) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Normal }) {
            Image(this.service.resolveImage(this.current())).width(52).height(64).objectFit(ImageFit.Cover)
              .borderRadius(6).accessibilityLevel('no')
          }.padding(0).backgroundColor(Color.Transparent).borderRadius(6)
            .border({ width: this.current().preset === 'image' ? 1.5 : 0,
              color: this.current().preset === 'image' ? AppColor.Brand : Color.Transparent })
            .accessibilityText($r('app.string.app_background_preset_image'))
            .onClick((): void => this.selectPreset('image'))
          Text($r('app.string.app_background_preset_image')).fontSize(AppFont.Body)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Button($r('app.string.app_background_remove_image')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent).height(40)
            .id('app-background-remove-image').onClick((): void => this.removeImage())
        }.width('100%')
      }
      Button({ type: ButtonType.Normal }) {
        Row({ space: AppSpace.Sm }) {
          if (this.picking) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([AppColor.Brand])
          }
          Text(this.current().imageFile.length > 0 ? $r('app.string.app_background_change_image') :
            $r('app.string.app_background_choose_image')).fontSize(AppFont.Body).fontColor(AppColor.Brand)
        }.justifyContent(FlexAlign.Center)
      }.width('100%').height(44).backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Md)
        .enabled(this.canEdit && !this.following).id('app-background-choose-image')
        .onClick((): void => { this.pickImage(); })
      Text($r('app.string.app_background_image_hint')).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor(AppTheme.TextSecondary).width('100%')
    }.width('100%')
  }

  @Builder
  private controls() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.app_background_scope')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary)
          .width('100%')
        ImmersiveOptionTabs({ labels: this.sceneLabels(),
          selected: this.scene, fillWidth: true,
          onSelect: (index: number): void => { this.selectSceneIndex(index); } })
          .enabled(this.canEdit).id('app-background-scene')
      }.width('100%')
      if (this.scene !== AppBackgroundScene.Common) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.app_background_follow_common')).fontSize(AppFont.Body)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.following }).selectedColor(AppColor.Brand)
            .enabled(this.canEdit).id('app-background-follow-common')
            .onChange((follow: boolean): void => this.setFollowing(follow))
        }.width('100%').constraintSize({ minHeight: 44 })
      }
      Text(this.scene === AppBackgroundScene.Common ? $r('app.string.app_background_common_hint') :
        this.following ? $r('app.string.app_background_follow_hint') :
        $r('app.string.app_background_independent_hint')).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor(AppTheme.TextSecondary).width('100%')
      Column({ space: AppSpace.Md }) {
        GridRow({ columns: 3, gutter: { x: 8, y: 8 } }) {
          ForEach(this.presets, (option: BackgroundPresetOption) => {
            GridCol() { this.presetButton(option) }
          }, (option: BackgroundPresetOption): string => option.id)
        }
        this.imageControls()
        if (this.current().preset !== 'theme') {
          this.slider(BackgroundAdjustment.Veil)
          if (this.current().preset === 'image') {
            this.slider(BackgroundAdjustment.Blur)
            Button({ type: ButtonType.Normal }) {
              Row() {
                Text($r('app.string.app_background_advanced')).fontSize(AppFont.Body)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                SymbolGlyph(this.showAdvanced ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                  .fontSize(14).fontColor([AppTheme.TextSecondary])
              }.width('100%')
            }.width('100%').height(44).padding(0).backgroundColor(Color.Transparent)
              .id('app-background-advanced').onClick((): void => { this.showAdvanced = !this.showAdvanced; })
            if (this.showAdvanced) {
              this.slider(BackgroundAdjustment.PositionX)
              this.slider(BackgroundAdjustment.PositionY)
              this.slider(BackgroundAdjustment.Scale)
            }
          }
          Button($r('app.string.app_background_reset_adjustments')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent).height(40)
            .id('app-background-reset-adjustments').onClick((): void => this.resetAdjustments())
        }
      }.width('100%').enabled(this.canEdit && !this.following).opacity(this.following ? 0.45 : 1)
    }.width('100%').padding(AppSpace.Md).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Row({ space: AppSpace.Xs }) {
        Text($r('app.string.app_background_title')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button($r('app.string.app_background_cancel')).fontSize(AppFont.Caption)
          .fontColor(AppTheme.TextSecondary).backgroundColor(AppTheme.Surface).height(40)
          .padding({ left: 12, right: 12 }).enabled(this.canEdit && this.dirty)
          .id('app-background-cancel').onClick((): void => { this.cancel(); })
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            if (this.saving) { LoadingProgress().width(16).height(16).color(AppColor.Brand) }
            Text($r('app.string.app_background_apply')).fontSize(AppFont.Caption).fontColor(AppColor.OnBrand)
          }.justifyContent(FlexAlign.Center)
        }.height(40).padding({ left: 12, right: 12 }).borderRadius(20).backgroundColor(AppColor.Brand)
          .enabled(this.canEdit && this.dirty).id('app-background-apply')
          .onClick((): void => { this.apply(); })
      }.width('100%')
      Text($r('app.string.app_background_hint')).fontSize(AppFont.Caption).lineHeight(20)
        .fontColor(AppTheme.TextSecondary).width('100%')
      if (this.loading) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      } else if (this.loadFailed) {
        Text($r('app.string.app_background_loading_failed')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        Button($r('app.string.app_icon_retry')).fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
          .onClick((): void => { this.load(); })
      } else {
        this.preview()
        this.controls()
        if (this.dirty) {
          Text($r('app.string.app_background_unsaved')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
            .width('100%')
        }
      }
    }.width('100%')
  }
}
