import { ThemeBackgroundComponent } from './ThemeBackgroundComponent';
import { ThemeBackgroundScene } from '../model/AppThemeVisual';
import { ThemeIconComponent } from './ThemeIconComponent';
import { ThemeIconRole } from '../theme/ThemeIcons';
import { AppAppearance } from '../model/AppAppearance';
import { AppThemeBundle } from '../model/AppThemeBundle';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { ThemeBundles } from '../theme/ThemeBundles';
import { CoverImage } from './CoverImage';
import { LocalBookCover } from './LocalBookCover';

/** 套装预览只读取候选定义；点击应用后才持久化并通知现有页面。 */
@ComponentV2
export struct ThemeBundleComponent {
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local applying: boolean = false;
  @Local applyingId: string = '';
  @Local previewId: string = 'default';
  @Local showPreview: boolean = false;
  private options: AppThemeBundle[] = ThemeBundles.list();

  private isCurrent(bundle: AppThemeBundle): boolean {
    return this.appearance.themeBundleId === bundle.id;
  }

  private isCustomized(): boolean {
    const bundle: AppThemeBundle = ThemeBundles.resolve(this.appearance.themeBundleId);
    return this.appearance.accent !== bundle.accent || this.appearance.material !== bundle.material;
  }

  private showResult(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面离开或提示上下文不可用时，不改变已经完成的保存结果。
    }
  }

  private async applyBundle(id: string): Promise<void> {
    if (this.applying) return;
    this.applying = true;
    this.applyingId = id;
    try {
      await PreferenceService.applyThemeBundle(id);
      this.showResult($r('app.string.theme_bundle_changed'));
    } catch (_error) {
      this.showResult($r('app.string.theme_bundle_failed'));
    } finally {
      this.applying = false;
      this.applyingId = '';
    }
  }

  private async resetOverrides(): Promise<void> {
    if (this.applying) return;
    this.applying = true;
    this.applyingId = this.appearance.themeBundleId;
    try {
      await PreferenceService.resetThemeBundleOverrides();
      this.showResult($r('app.string.theme_bundle_changed'));
    } catch (_error) {
      this.showResult($r('app.string.theme_bundle_failed'));
    } finally {
      this.applying = false;
      this.applyingId = '';
    }
  }

  @Builder
  private preview(bundle: AppThemeBundle) {
    Stack({ alignContent: Alignment.TopStart }) {
      ThemeBackgroundComponent({ themeBundleId: bundle.id, preview: true, scene: ThemeBackgroundScene.Shelf })
      Column({ space: 12 }) {
        Row() {
          Text($r('app.string.theme_bundle_preview_label'))
            .fontSize(10).fontColor(bundle.visual.colors.textSecondary)
          Blank()
          ThemeIconComponent({ role: ThemeIconRole.Search, symbol: $r('sys.symbol.magnifyingglass'),
            iconSize: 17, tint: bundle.visual.colors.brand, themeBundleId: bundle.id })
          ThemeIconComponent({ role: ThemeIconRole.Filter, symbol: $r('sys.symbol.funnel'),
            iconSize: 17, tint: bundle.visual.colors.brand, themeBundleId: bundle.id }).margin({ left: 12 })
        }.width('100%')
        Column({ space: 4 }) {
          Text($r('app.string.theme_bundle_preview_title')).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(bundle.visual.colors.textPrimary).width('100%')
          Text($r('app.string.theme_bundle_preview_subtitle')).fontSize(10)
            .fontColor(bundle.visual.colors.textSecondary).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 16 }) {
          Column({ space: 6 }) {
            CoverImage({ imgWidth: 66, imgHeight: 92, useFixedHeight: true, radius: 4, themeBundleId: bundle.id })
            Text($r('app.string.theme_bundle_preview_book')).fontSize(10)
              .fontColor(bundle.visual.colors.textPrimary).maxLines(1)
          }
          Column({ space: 6 }) {
            LocalBookCover({ imgWidth: 66, imgHeight: 92, useFixedHeight: true, radius: 4, themeBundleId: bundle.id })
            Text($r('app.string.theme_bundle_preview_local')).fontSize(10)
              .fontColor(bundle.visual.colors.textPrimary).maxLines(1)
          }
          Blank()
        }.width('100%')
        Row({ space: 6 }) {
          ThemeIconComponent({ role: ThemeIconRole.Shelf, symbol: $r('sys.symbol.bookshelf'),
            iconSize: 14, tint: bundle.visual.colors.brand, themeBundleId: bundle.id })
          Text($r('app.string.theme_bundle_preview_collection')).fontSize(10)
            .fontColor(bundle.visual.colors.brand)
          Blank()
          ThemeIconComponent({ role: ThemeIconRole.Home, symbol: $r('sys.symbol.house_fill'),
            iconSize: 14, tint: bundle.visual.colors.textSecondary, themeBundleId: bundle.id })
          ThemeIconComponent({ role: ThemeIconRole.Record, symbol: $r('sys.symbol.clock'),
            iconSize: 14, tint: bundle.visual.colors.textSecondary, themeBundleId: bundle.id }).margin({ left: 18 })
          ThemeIconComponent({ role: ThemeIconRole.Profile, symbol: $r('sys.symbol.person_fill'),
            iconSize: 14, tint: bundle.visual.colors.textSecondary, themeBundleId: bundle.id }).margin({ left: 18 })
        }.width('100%').margin({ top: 2 })
      }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
    }.width('100%').height(262).borderRadius(AppRadius.Md).clip(true)
    .backgroundColor(bundle.visual.colors.background)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  private bundleCard(bundle: AppThemeBundle) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Stack() {
          ThemeBackgroundComponent({ themeBundleId: bundle.id, preview: true })
          CoverImage({ imgWidth: 46, imgHeight: 64, useFixedHeight: true, radius: 4, themeBundleId: bundle.id })
        }.width('100%').height(112).borderRadius(AppRadius.Sm).clip(true)
        Text(bundle.name).fontSize(AppFont.Caption).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.isCurrent(bundle) ? $r('app.string.theme_bundle_applied') :
          $r('app.string.theme_bundle_preview_label')).fontSize(10)
          .fontColor(this.isCurrent(bundle) ? AppColor.Brand : AppTheme.TextSecondary)
      }.width('100%').padding(6)
    }.width('100%').borderRadius(AppRadius.Md).backgroundColor(AppTheme.Surface)
    .border({ width: this.isCurrent(bundle) ? 1.5 : 1,
      color: this.isCurrent(bundle) ? AppColor.Brand : AppTheme.Divider })
    .onClick(() => {
      this.previewId = bundle.id;
      this.showPreview = true;
    })
  }

  @Builder
  private previewSheet() {
    Scroll() {
      this.previewCard(ThemeBundles.resolve(this.previewId))
    }.width('100%').height('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Lg })
    .scrollBar(BarState.Off)
  }

  @Builder
  private previewCard(bundle: AppThemeBundle) {
    Column({ space: AppSpace.Sm }) {
      this.preview(bundle)
      Row({ space: AppSpace.Xs }) {
        Text(bundle.name).fontSize(AppFont.BodyL).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        if (this.isCurrent(bundle)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor([AppColor.Brand])
            Text($r('app.string.theme_bundle_applied')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
          }
        }
      }.width('100%')
      Text(bundle.description).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        .lineHeight(19).width('100%').constraintSize({ minHeight: 38 })
      Button({ type: ButtonType.Normal }) {
        Row({ space: AppSpace.Xs }) {
          if (this.applying && this.applyingId === bundle.id) {
            LoadingProgress().width(18).height(18).color(AppColor.Brand)
          }
          Text(this.applying && this.applyingId === bundle.id ? $r('app.string.theme_bundle_applying') :
            $r('app.string.theme_bundle_apply'))
            .fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
            .fontColor(bundle.visual.colors.onBrand)
        }.justifyContent(FlexAlign.Center)
      }.width('100%').height(44).borderRadius(AppRadius.Sm)
      .backgroundColor(bundle.visual.colors.brand)
      .enabled(!this.applying)
      .onClick(() => this.applyBundle(bundle.id))
    }.width('100%').padding(AppSpace.Sm).borderRadius(AppRadius.Lg)
    .backgroundColor(AppTheme.Surface)
    .border({ width: this.isCurrent(bundle) ? 1.5 : 1,
      color: this.isCurrent(bundle) ? AppColor.Brand : AppTheme.Divider })
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.theme_bundle_hint')).fontSize(AppFont.Caption).lineHeight(20)
        .fontColor(AppTheme.TextSecondary).width('100%')
      GridRow({ columns: 3, gutter: { x: 10, y: 12 } }) {
        ForEach(this.options, (bundle: AppThemeBundle) => {
          GridCol() {
            this.bundleCard(bundle)
          }
        }, (bundle: AppThemeBundle) => bundle.id)
      }
      if (this.isCustomized()) {
        Column({ space: AppSpace.Xs }) {
          Text($r('app.string.theme_bundle_customized')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextSecondary)
          Button($r('app.string.theme_bundle_reset_overrides'))
            .fontSize(AppFont.Body).fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
            .enabled(!this.applying).onClick(() => this.resetOverrides())
        }.width('100%')
      }
      if (this.appearance.themeBundleId !== 'default' || this.isCustomized()) {
        Button($r('app.string.theme_bundle_restore'))
          .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent)
          .enabled(!this.applying).onClick(() => this.applyBundle('default'))
      }
    }.width('100%')
    .bindSheet($$this.showPreview, this.previewSheet(), {
      height: '80%', preferType: SheetType.BOTTOM, dragBar: true, showClose: true,
      backgroundColor: AppTheme.Background,
      onDisappear: (): void => { this.showPreview = false; }
    })
  }
}
