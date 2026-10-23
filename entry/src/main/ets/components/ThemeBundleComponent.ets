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

  private previewAccent(bundle: AppThemeBundle): ResourceColor {
    return bundle.id === 'paper-study' ? $r('app.color.theme_paper_brand') : $r('app.color.app_brand');
  }

  private previewText(bundle: AppThemeBundle): ResourceColor {
    return bundle.id === 'paper-study' ? $r('app.color.theme_paper_text_primary') : $r('sys.color.font_primary');
  }

  private previewSecondary(bundle: AppThemeBundle): ResourceColor {
    return bundle.id === 'paper-study' ? $r('app.color.theme_paper_text_secondary') : $r('sys.color.font_secondary');
  }

  private previewTitle(resource: Resource): string {
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? '';
    } catch (_error) {
      return '';
    }
  }

  @Builder
  private preview(bundle: AppThemeBundle) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (bundle.id === 'paper-study') {
        Image($r('app.media.theme_paper_background'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      }
      Column({ space: 12 }) {
        Row() {
          Text($r('app.string.theme_bundle_preview_label'))
            .fontSize(10).fontColor(this.previewSecondary(bundle))
          Blank()
          if (bundle.id === 'paper-study') {
            Image($r('app.media.theme_paper_search')).width(17).height(17)
              .fillColor(this.previewAccent(bundle))
            Image($r('app.media.theme_paper_filter')).width(17).height(17)
              .fillColor(this.previewAccent(bundle)).margin({ left: 12 })
          } else {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(17)
              .fontColor([this.previewAccent(bundle)])
            SymbolGlyph($r('sys.symbol.funnel')).fontSize(17)
              .fontColor([this.previewAccent(bundle)]).margin({ left: 12 })
          }
        }.width('100%')
        Column({ space: 4 }) {
          Text($r('app.string.theme_bundle_preview_title')).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(this.previewText(bundle)).width('100%')
          Text($r('app.string.theme_bundle_preview_subtitle')).fontSize(10)
            .fontColor(this.previewSecondary(bundle)).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 16 }) {
          Column({ space: 6 }) {
            CoverImage({ title: this.previewTitle($r('app.string.theme_bundle_preview_book')),
              imgWidth: 66, imgHeight: 92, useFixedHeight: true, radius: 4, themeBundleId: bundle.id })
            Text($r('app.string.theme_bundle_preview_book')).fontSize(10)
              .fontColor(this.previewText(bundle)).maxLines(1)
          }
          Column({ space: 6 }) {
            LocalBookCover({ title: this.previewTitle($r('app.string.theme_bundle_preview_local')),
              imgWidth: 66, imgHeight: 92, useFixedHeight: true, radius: 4, themeBundleId: bundle.id })
            Text($r('app.string.theme_bundle_preview_local')).fontSize(10)
              .fontColor(this.previewText(bundle)).maxLines(1)
          }
          Blank()
        }.width('100%')
        Row({ space: 6 }) {
          if (bundle.id === 'paper-study') {
            Image($r('app.media.theme_paper_shelf')).width(14).height(14)
              .fillColor(this.previewAccent(bundle))
          } else {
            SymbolGlyph($r('sys.symbol.bookshelf')).fontSize(14)
              .fontColor([this.previewAccent(bundle)])
          }
          Text($r('app.string.theme_bundle_preview_collection')).fontSize(10)
            .fontColor(this.previewAccent(bundle))
          Blank()
          if (bundle.id === 'paper-study') {
            Image($r('app.media.theme_paper_home')).width(14).height(14)
              .fillColor(this.previewSecondary(bundle))
            Image($r('app.media.theme_paper_record')).width(14).height(14)
              .fillColor(this.previewSecondary(bundle)).margin({ left: 18 })
            Image($r('app.media.theme_paper_profile')).width(14).height(14)
              .fillColor(this.previewSecondary(bundle)).margin({ left: 18 })
          } else {
            SymbolGlyph($r('sys.symbol.house_fill')).fontSize(14).fontColor([this.previewSecondary(bundle)])
            SymbolGlyph($r('sys.symbol.clock')).fontSize(14).fontColor([this.previewSecondary(bundle)])
              .margin({ left: 18 })
            SymbolGlyph($r('sys.symbol.person_fill')).fontSize(14).fontColor([this.previewSecondary(bundle)])
              .margin({ left: 18 })
          }
        }.width('100%').margin({ top: 2 })
      }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
    }.width('100%').height(262).borderRadius(AppRadius.Md).clip(true)
    .backgroundColor(bundle.id === 'paper-study' ? $r('app.color.theme_paper_background') :
      $r('sys.color.background_primary'))
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  private bundleCard(bundle: AppThemeBundle) {
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
            this.isCurrent(bundle) ? $r('app.string.theme_bundle_applied') : $r('app.string.theme_bundle_apply'))
            .fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
            .fontColor(this.isCurrent(bundle) ? AppTheme.TextSecondary :
              bundle.id === 'paper-study' ? $r('app.color.theme_paper_on_brand') : $r('app.color.app_on_brand'))
        }.justifyContent(FlexAlign.Center)
      }.width('100%').height(44).borderRadius(AppRadius.Sm)
      .backgroundColor(this.isCurrent(bundle) ? AppTheme.Background : this.previewAccent(bundle))
      .enabled(!this.applying && !this.isCurrent(bundle))
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
      GridRow({ columns: { xs: 1, sm: 2, md: 2, lg: 2 }, gutter: { x: 16, y: 16 },
        breakpoints: { value: ['600vp'], reference: BreakpointsReference.ComponentSize } }) {
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
  }
}
