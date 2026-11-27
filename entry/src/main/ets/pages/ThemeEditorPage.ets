import { AppThemeBundle } from '../model/AppThemeBundle';
import { ThemeDocument, ThemeDraft } from '../model/ThemeDocument';
import { ThemeEditorField, ThemeFieldChoice, ThemePackageService } from '../service/ThemePackageService';
import { PreferenceService } from '../service/PreferenceService';
import { ThemeBundles } from '../theme/ThemeBundles';
import { ThemeDocumentResolver } from '../theme/ThemeDocumentResolver';
import { AppColor, AppTheme, AppFont } from '../theme/Theme';
import { ThemeEditorPreview } from '../components/ThemeEditorPreview';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ThemeEditorPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param themeId: string = 'default';
  @Param importedDraft: ThemeDraft | undefined = undefined;
  @Local draft: ThemeDraft = new ThemeDraft();
  @Local fields: ThemeEditorField[] = [];
  @Local previewBundle: AppThemeBundle = new AppThemeBundle('', '', '', '');
  @Local dark: boolean = false;
  @Local section: string = 'basic';
  @Local scene: string = 'home';
  @Local backgroundScene: string = 'common';
  @Local buttonScene: string = 'shelf';
  @Local buttonPreview: string = '';
  @Local ready: boolean = false;
  @Local busy: boolean = false;
  @Local pageWidth: number = 360;
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;

  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { ThemePackageService.discard(this.draft).catch((): void => {}); }

  private label(key: string): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringByNameSync(key) ?? key;
  }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true;
    try {
      this.fields = await ThemePackageService.fields(context);
      this.draft = this.importedDraft ?? await ThemePackageService.draft(context, this.themeId);
      if (!this.importedDraft && !ThemeBundles.resolve(this.themeId).custom) {
        this.draft.document.name = this.label('theme_editor_new_name');
      }
      this.refresh();
      this.ready = true;
    } catch (_error) { this.toast($r('app.string.theme_editor_failed')); }
    finally { this.busy = false; }
  }

  private refresh(): void {
    this.previewBundle = ThemeDocumentResolver.apply(ThemeBundles.fresh(this.draft.document.baseThemeId),
      this.draft.document, this.draft.directory, this.dark);
  }

  private toast(message: Resource): void { this.getUIContext().getPromptAction().showToast({ message: message }); }

  private fieldValue(field: ThemeEditorField): string {
    return ThemeDocument.value(this.dark ? this.draft.document.dark : this.draft.document.light,
      field.key, this.dark ? field.dark : field.light);
  }

  private change(field: ThemeEditorField, value: string): void {
    if (field.section === 'buttons') {
      this.buttonPreview = field.key;
      this.scene = this.buttonScene;
    }
    const document: ThemeDocument = ThemeDocument.copy(this.draft.document);
    if (this.dark) document.dark = ThemeDocument.put(document.dark, field.key, value);
    else document.light = ThemeDocument.put(document.light, field.key, value);
    this.draft = new ThemeDraft(document, this.draft.directory);
    this.refresh();
  }

  private rename(name: string, description: string): void {
    const document: ThemeDocument = ThemeDocument.copy(this.draft.document);
    document.name = name;
    document.description = description;
    this.draft = new ThemeDraft(document, this.draft.directory);
    this.refresh();
  }

  private colorChanged(field: ThemeEditorField, value: string): void {
    if (new RegExp('^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').test(value)) this.change(field, value.toUpperCase());
  }

  private async pick(field: ThemeEditorField): Promise<void> {
    this.busy = true;
    try {
      const path: string = await ThemePackageService.pickImage(this.draft);
      if (path) this.change(field, path);
    } catch (_error) { this.toast($r('app.string.theme_editor_failed')); }
    finally { this.busy = false; }
  }

  private async exportTheme(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true;
    try {
      if (await ThemePackageService.exportPackage(context, this.draft)) this.toast($r('app.string.theme_editor_exported'));
    } catch (_error) { this.toast($r('app.string.theme_editor_failed')); }
    finally { this.busy = false; }
  }

  private async save(): Promise<void> {
    if (this.draft.document.name.trim().length === 0) {
      this.toast($r('app.string.theme_editor_empty_name'));
      return;
    }
    this.busy = true;
    try {
      await ThemePackageService.save(this.draft);
      await PreferenceService.applyThemeBundle(this.draft.document.id);
      this.toast($r('app.string.theme_editor_saved'));
    } catch (error) {
      if (error instanceof Error && error.message === 'MEMBERSHIP_REQUIRED') {
        this.toast($r('app.string.membership_feature_required'));
        this.navStack.pushPathByName('membershipSubscription', undefined);
      } else this.toast($r('app.string.theme_editor_failed'));
    } finally { this.busy = false; }
  }

  private choices(field: ThemeEditorField): SelectOption[] {
    return field.choices.map((choice: ThemeFieldChoice): SelectOption => { return { value: this.label(choice.label) }; });
  }

  private selectedFields(): ThemeEditorField[] {
    return this.fields.filter((field: ThemeEditorField): boolean => field.section === this.section &&
      (this.section !== 'backgrounds' || field.key.startsWith('background.' + this.backgroundScene + '.') ||
        (this.backgroundScene === 'common' && field.key === 'background.coverBackdrop') ||
        (this.backgroundScene === 'profile' && field.key === 'background.profileCard')) &&
      (this.section !== 'buttons' || field.key.startsWith('button.' + this.buttonScene + '.')) && this.fieldVisible(field));
  }

  private fieldVisible(field: ThemeEditorField): boolean {
    const parts: string[] = field.key.split('.');
    if (parts[0] !== 'background' || parts.length !== 3 || parts[2] === 'mode') return true;
    const tokens = this.dark ? this.draft.document.dark : this.draft.document.light;
    const mode: string = ThemeDocument.value(tokens, 'background.' + parts[1] + '.mode',
      parts[1] === 'player' ? 'cover' : parts[1] === 'common' ? 'theme' : 'common');
    if (mode === 'image') return true;
    if (mode === 'solid') return parts[2] === 'color' || parts[2] === 'veil';
    if (mode === 'cover') return parts[2] === 'color' || parts[2] === 'blur' || parts[2] === 'veil';
    return false;
  }

  @Builder
  private fieldEditor(field: ThemeEditorField) {
    Column({ space: 10 }) {
      Row() {
        Text(this.label(field.label)).fontSize(14).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        if (field.type === 'toggle') {
          Toggle({ type: ToggleType.Switch, isOn: this.fieldValue(field) === 'true' }).selectedColor(AppColor.Brand)
            .onChange((enabled: boolean): void => this.change(field, enabled.toString()))
        } else if (field.type === 'range') {
          Text(this.fieldValue(field)).fontSize(12).fontColor(AppTheme.TextSecondary)
        }
      }.width('100%')
      if (field.type === 'color') {
        Row({ space: 12 }) {
          Row().width(36).height(36).borderRadius(12).backgroundColor(this.fieldValue(field))
            .border({ width: 1, color: AppTheme.Divider })
          TextInput({ text: this.fieldValue(field), placeholder: this.label('theme_editor_color_hint') })
            .fontSize(14).layoutWeight(1).fontColor(AppTheme.TextPrimary).backgroundColor(AppTheme.Background)
            .onChange((value: string): void => this.colorChanged(field, value))
        }.width('100%')
        Row({ space: 12 }) {
          ForEach(['#C4475B', '#496D5C', '#516B8A', '#A57746', '#80619A', '#F7F4EF', '#FFFFFF', '#18191B'], (color: string) => {
            Button().width(24).height(24).borderRadius(12).backgroundColor(color)
              .border({ width: 1, color: AppTheme.Divider }).onClick((): void => this.change(field, color))
          }, (color: string): string => color)
        }.width('100%')
      } else if (field.type === 'image') {
        Row({ space: 12 }) {
          if (this.fieldValue(field).length > 0) {
            Image('file://' + this.draft.directory + '/' + this.fieldValue(field)).width(56).height(56)
              .objectFit(ImageFit.Contain).borderRadius(10).backgroundColor(AppTheme.Background)
          }
          Button($r('app.string.theme_editor_pick')).fontSize(13).fontColor(AppColor.Brand)
            .backgroundColor(AppColor.BrandSoft).enabled(!this.busy).onClick((): void => { this.pick(field); })
          Button($r('app.string.theme_editor_clear')).fontSize(12).fontColor(AppTheme.TextSecondary)
            .backgroundColor(Color.Transparent).onClick((): void => this.change(field, ''))
        }.width('100%')
        if (field.section === 'buttons') {
          Button($r('app.string.theme_editor_button_preview')).fontSize(12).fontColor(AppColor.Brand)
            .backgroundColor(AppColor.BrandSoft).alignSelf(ItemAlign.Start)
            .onClick((): void => { this.buttonPreview = field.key; this.scene = this.buttonScene; })
        }
      } else if (field.type === 'range') {
        Slider({ value: Number(this.fieldValue(field)), min: field.min, max: field.max, step: 1 })
          .selectedColor(AppColor.Brand).blockColor(AppColor.Brand).width('100%')
          .onChange((value: number): void => this.change(field, Math.round(value).toString()))
      } else if (field.type === 'select') {
        Select(this.choices(field)).width('100%').fontColor(AppTheme.TextPrimary)
          .selected(field.choices.findIndex((choice: ThemeFieldChoice): boolean => choice.value === this.fieldValue(field)))
          .value(this.label(field.choices.find((choice: ThemeFieldChoice): boolean => choice.value === this.fieldValue(field))?.label ?? field.label))
          .onSelect((index: number): void => this.change(field, field.choices[index].value))
      }
    }.width('100%').padding(16).borderRadius(16).backgroundColor(AppTheme.Surface)
  }

  @Builder
  private basic() {
    Column({ space: 16 }) {
      TextInput({ text: this.draft.document.name, placeholder: this.label('theme_editor_name') })
        .fontColor(AppTheme.TextPrimary).backgroundColor(AppTheme.Surface)
        .onChange((name: string): void => this.rename(name, this.draft.document.description))
      TextArea({ text: this.draft.document.description, placeholder: this.label('theme_editor_description') })
        .height(100).fontColor(AppTheme.TextPrimary).backgroundColor(AppTheme.Surface)
        .onChange((description: string): void => this.rename(this.draft.document.name, description))
      Button($r('app.string.theme_editor_export')).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
        .width('100%').enabled(!this.busy).onClick((): void => { this.exportTheme(); })
    }.width('100%')
  }

  @Builder
  private preview() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button($r('app.string.theme_editor_light')).fontColor(this.dark ? AppTheme.TextSecondary : AppColor.OnBrand)
          .backgroundColor(this.dark ? AppTheme.Surface : AppColor.Brand).layoutWeight(1)
          .onClick((): void => { this.dark = false; this.refresh(); })
        Button($r('app.string.theme_editor_dark')).fontColor(this.dark ? AppColor.OnBrand : AppTheme.TextSecondary)
          .backgroundColor(this.dark ? AppColor.Brand : AppTheme.Surface).layoutWeight(1)
          .onClick((): void => { this.dark = true; this.refresh(); })
      }.width('100%')
      ThemeEditorPreview({ bundle: this.previewBundle, scene: this.scene, night: this.dark, buttonPreview: this.buttonPreview })
      Row({ space: 4 }) {
        ForEach(['home', 'shelf', 'record', 'profile', 'player'], (scene: string) => {
          Button(this.label('theme_editor_' + scene)).fontSize(11).layoutWeight(1).padding(4)
            .fontColor(this.scene === scene ? AppColor.Brand : AppTheme.TextSecondary)
            .backgroundColor(this.scene === scene ? AppColor.BrandSoft : AppTheme.Surface)
            .onClick((): void => { this.scene = scene; })
        }, (scene: string): string => scene)
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: 380 })
  }

  @Builder
  private editors() {
    Column({ space: 12 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(['basic', 'colors', 'backgrounds', 'tabs', 'buttons', 'icons', 'covers', 'player'], (section: string) => {
            Button(this.label('theme_editor_' + section)).fontSize(13)
              .fontColor(this.section === section ? AppColor.OnBrand : AppTheme.TextSecondary)
              .backgroundColor(this.section === section ? AppColor.Brand : AppTheme.Surface)
              .onClick((): void => {
                this.section = section;
                if (section === 'player') this.scene = 'player';
                else if (section === 'buttons') this.scene = this.buttonScene;
              })
          }, (section: string): string => section)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      if (this.section === 'basic') {
        this.basic()
      } else {
        if (this.section === 'buttons') {
          Row({ space: 8 }) {
            ForEach(['shelf', 'record'], (scene: string) => {
              Button(this.label('theme_editor_' + scene)).fontSize(13).layoutWeight(1)
                .fontColor(this.buttonScene === scene ? AppColor.OnBrand : AppTheme.TextSecondary)
                .backgroundColor(this.buttonScene === scene ? AppColor.Brand : AppTheme.Surface)
                .onClick((): void => { this.buttonScene = scene; this.scene = scene; this.buttonPreview = ''; })
            }, (scene: string): string => scene)
          }.width('100%')
          Text($r('app.string.theme_editor_buttons_hint')).fontSize(12).fontColor(AppTheme.TextSecondary).width('100%')
        }
        if (this.section === 'backgrounds') {
          Row({ space: 4 }) {
            ForEach(['common', 'home', 'shelf', 'record', 'profile'], (scene: string) => {
              Button(this.label('theme_editor_' + scene)).fontSize(11).layoutWeight(1).padding(4)
                .fontColor(this.backgroundScene === scene ? AppColor.Brand : AppTheme.TextSecondary)
                .backgroundColor(this.backgroundScene === scene ? AppColor.BrandSoft : AppTheme.Surface)
                .onClick((): void => { this.backgroundScene = scene; this.scene = scene === 'common' ? 'home' : scene; })
            }, (scene: string): string => scene)
          }.width('100%')
        }
        ForEach(this.selectedFields(), (field: ThemeEditorField) => {
          this.fieldEditor(field)
        }, (field: ThemeEditorField): string => field.key)
      }
    }.width('100%')
  }

  @Builder
  private header() {
    FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.theme_editor_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Button($r('app.string.theme_editor_apply')).fontSize(12).fontColor(AppColor.OnBrand)
          .backgroundColor(AppColor.Brand).enabled(this.ready && !this.busy).onClick((): void => { this.save(); })
      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + 8, left: 8, right: 16, bottom: 8 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.ready) {
        if (this.pageWidth >= 760) {
          Row({ space: 24 }) {
            Column() { this.preview() }.width('38%').alignSelf(ItemAlign.Start)
            Scroll() {
              Column() { this.editors() }.width('100%').padding({ bottom: WindowUtils.getBottomSafeVp() + 24 })
            }.layoutWeight(1).height('100%').scrollBar(BarState.Off)
          }.width('100%').height('100%').padding({ top: this.headerHeight + 16, left: 24, right: 24 })
        } else {
          Scroll() {
            Column({ space: 24 }) {
              this.preview()
              this.editors()
            }.width('100%').padding({ top: this.headerHeight + 16, left: 16, right: 16,
              bottom: WindowUtils.getBottomSafeVp() + 24 })
          }.width('100%').height('100%').scrollBar(BarState.Off)
        }
      } else {
        LoadingProgress().width(36).height(36).color(AppColor.Brand).align(Alignment.Center)
      }
      this.header()
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => { this.pageWidth = Number(current.width); })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
