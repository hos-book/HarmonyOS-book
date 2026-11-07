import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppAppearance } from '../model/AppAppearance';
import { GeneralSettings } from '../model/GeneralSettings';
import { ThemeIconComponent } from './ThemeIconComponent';
import { ThemeIconRole } from '../theme/ThemeIcons';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { BottomTabIconService } from '../service/BottomTabIconService';

class BottomTabIconOption {
  id: string;
  role: ThemeIconRole;
  label: Resource;
  symbol: Resource;

  constructor(id: string, role: ThemeIconRole, label: Resource, symbol: Resource) {
    this.id = id;
    this.role = role;
    this.label = label;
    this.symbol = symbol;
  }
}

@ComponentV2
export struct BottomTabIconComponent {
  @Local service: BottomTabIconService = BottomTabIconService.instance;
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local previewRole: ThemeIconRole = ThemeIconRole.Home;
  @Local picking: boolean = false;
  @Local loadFailed: boolean = false;
  private alive: boolean = false;
  private request: number = 0;
  private options: BottomTabIconOption[] = [
    new BottomTabIconOption('home', ThemeIconRole.Home, $r('app.string.bottom_tab_icon_home'), $r('sys.symbol.house_fill')),
    new BottomTabIconOption('shelf', ThemeIconRole.Shelf, $r('app.string.bottom_tab_icon_shelf'), $r('sys.symbol.bookshelf')),
    new BottomTabIconOption('record', ThemeIconRole.Record, $r('app.string.bottom_tab_icon_record'), $r('sys.symbol.calendar_fill')),
    new BottomTabIconOption('profile', ThemeIconRole.Profile, $r('app.string.bottom_tab_icon_profile'), $r('sys.symbol.person_fill'))
  ];

  aboutToAppear(): void {
    this.alive = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.request++;
  }

  private async load(): Promise<void> {
    this.loadFailed = false;
    const context = this.getUIContext().getHostContext();
    if (!context) { this.loadFailed = true; return; }
    try { await this.service.init(context); }
    catch (_error) { if (this.alive) this.loadFailed = true; }
  }

  private async selectIcon(option: BottomTabIconOption): Promise<void> {
    if (this.picking || this.service.busy || !this.service.ready) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.picking = true;
    const request = ++this.request;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (!this.alive || request !== this.request || result.photoUris.length === 0) return;
      const saved = await this.service.importIcon(option.role, result.photoUris[0],
        (): boolean => this.alive && request === this.request);
      if (saved && this.alive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.bottom_tab_icon_saved') });
      }
    } catch (_error) {
      if (this.alive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.bottom_tab_icon_failed') });
      }
    } finally { this.picking = false; }
  }

  private async reset(role: ThemeIconRole = ThemeIconRole.None): Promise<void> {
    try { await this.service.reset(role); }
    catch (_error) {
      if (this.alive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.bottom_tab_icon_reset_failed') });
      }
    }
  }

  @Builder
  private icon(option: BottomTabIconOption) {
    if (this.service.resolve(option.role) !== undefined) {
      Image(this.service.resolve(option.role)).width(28).height(28).objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
    } else {
      ThemeIconComponent({ role: option.role, symbol: option.symbol, iconSize: 28,
        themeBundleId: this.appearance.themeBundleId,
        tint: this.previewRole === option.role ? AppColor.Brand : AppTheme.TextSecondary })
    }
  }

  @Builder
  private preview() {
    Column({ space: AppSpace.Sm }) {
      Text($r('app.string.bottom_tab_icon_preview')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        .width('100%')
      Row({ space: AppSpace.Xs }) {
        ForEach(this.options, (option: BottomTabIconOption) => {
          if (option.role !== ThemeIconRole.Record || this.generalSettings.historyEnabled) {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 6 }) {
                this.icon(option)
                Text(option.label).fontSize(AppFont.Caption)
                  .fontColor(this.previewRole === option.role ? AppColor.Brand : AppTheme.TextSecondary)
              }.width('100%').padding({ top: 12, bottom: 12 })
            }.layoutWeight(1).padding(0).borderRadius(AppRadius.Md)
            .backgroundColor(this.previewRole === option.role ? AppColor.BrandSoft : Color.Transparent)
            .accessibilityText(option.label).onClick(() => { this.previewRole = option.role; })
          }
        }, (option: BottomTabIconOption): string => option.id)
      }.width('100%')
    }.width('100%').padding(AppSpace.Md).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
  }

  @Builder
  private optionCard(option: BottomTabIconOption) {
    Row({ space: AppSpace.Sm }) {
      Stack() { this.icon(option) }.width(44).height(44)
      Column({ space: AppSpace.Xs }) {
        Text(option.label).fontSize(AppFont.Body).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
        Text(this.service.resolve(option.role) === undefined ? $r('app.string.bottom_tab_icon_follow_theme') :
          $r('app.string.bottom_tab_icon_custom')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button($r('app.string.bottom_tab_icon_choose')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
        .height(40).padding({ left: 12, right: 12 }).backgroundColor(AppColor.BrandSoft)
        .enabled(this.service.ready && !this.service.busy && !this.picking)
        .id(`bottom-tab-icon-choose-${option.id}`).onClick(() => this.selectIcon(option))
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(18).fontColor([AppTheme.TextSecondary])
      }.width(40).height(40).backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.bottom_tab_icon_reset')).id(`bottom-tab-icon-reset-${option.id}`)
      .enabled(this.service.resolve(option.role) !== undefined && !this.service.busy && !this.picking)
      .onClick(() => this.reset(option.role))
    }.width('100%').padding(AppSpace.Sm).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.bottom_tab_icon_hint')).fontSize(AppFont.Caption).lineHeight(20)
        .fontColor(AppTheme.TextSecondary).width('100%')
      this.preview()
      if (!this.service.ready || this.service.busy || this.picking) {
        if (this.loadFailed) {
          Button($r('app.string.app_icon_retry')).fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
            .onClick(() => this.load())
        } else {
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }
      }
      ForEach(this.options, (option: BottomTabIconOption) => {
        this.optionCard(option)
      }, (option: BottomTabIconOption): string => option.id)
      Button($r('app.string.bottom_tab_icon_reset_all')).fontSize(AppFont.Body)
        .fontColor(AppTheme.TextSecondary).backgroundColor(AppTheme.Surface).width('100%').height(44)
        .enabled(this.service.ready && this.service.hasCustomIcons && !this.service.busy && !this.picking)
        .id('bottom-tab-icon-reset-all').onClick(() => this.reset())
    }.width('100%')
  }
}
