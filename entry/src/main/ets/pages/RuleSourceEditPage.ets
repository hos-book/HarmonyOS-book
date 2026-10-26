import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { LocalRuleSource, LocalRuleSearchRule, LocalRuleBookInfoRule, LocalRuleTocRule, LocalRuleContentRule } from '../model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleSourceCodec } from '../service/rulesource/LocalRuleSourceCodec';
import { LocalRuleSourceImportParser } from '../service/rulesource/LocalRuleSourceImportParser';
import { SourceDataService } from '../service/SourceDataService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { promptAction } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { NativeSourceForm } from '../components/NativeSourceForm';
import { NativeSourceDraft } from '../service/rulesource/NativeSourceDraft';

interface FormFieldParams {
  label: ResourceStr;
  value: string;
  placeholder?: ResourceStr;
  multiline?: boolean;
  enabled?: boolean;
  onChange: (value: string) => void;
}

@Builder
function FormFieldBuilder(params: FormFieldParams) {
  Column({ space: 4 }) {
    Text(params.label)
      .fontSize(AppFont.Caption)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')

    if (params.multiline || params.value.includes('\n') || new RegExp('(@?js:|<js>)', 'i').test(params.value)) {
      TextArea({ text: params.value, placeholder: params.placeholder || params.label })
        .width('100%')
        .height(144)
        .fontSize(AppFont.Body)
        .fontFamily('monospace')
        .padding(AppSpace.Sm)
        .caretColor(AppColor.Brand)
        .selectedBackgroundColor(AppColor.BrandSoft)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs)
        .enabled(params.enabled !== false)
        .onChange((value: string) => params.onChange(value))
    } else {
      TextInput({ text: params.value, placeholder: params.placeholder || params.label })
        .width('100%')
        .height(48)
        .fontSize(AppFont.Body)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
        .caretColor(AppColor.Brand)
        .selectedBackgroundColor(AppColor.BrandSoft)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs)
        .enabled(params.enabled !== false)
        .onChange((value: string) => params.onChange(value))
    }
  }
  .width('100%')
}

@ComponentV2
export struct RuleSourceEditPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local source: LocalRuleSource = new LocalRuleSource();
  @Local currentTab: number = 0;
  @Local sourceType: number = 1;
  @Local safeTop: number = WindowUtils.getStatusBarHeightVp();
  @Local safeBottom: number = WindowUtils.getBottomSafeVp();
  @Local isLoading: boolean = false;
  @Local isSaving: boolean = false;
  @Local isExporting: boolean = false;
  @Local hasUnsavedChanges: boolean = false;
  @Local originalSnapshot: string = '';
  @Local rawDraft: string = '';
  @Local rawError: string = '';
  @Local exploreDraft: string = '';
  @Local nativeDraft: NativeSourceDraft = new NativeSourceDraft();
  private rawSnapshot: string = '';
  private nativeFormChanged: boolean = false;
  private exploreSnapshot: string = '';
  private isNewSource: boolean = true;
  private formScroller: Scroller = new Scroller();
  private safeAreaListener: (top: number, bottom: number) => void = (top, bottom) => {
    this.safeTop = top;
    this.safeBottom = bottom;
  };

  aboutToAppear(): void {
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    if (this.sourceUrl && this.sourceUrl.length > 0) {
      this.isNewSource = false;
      this.loadSource();
    } else {
      this.isNewSource = true;
      this.source = new LocalRuleSource();
      this.source.bookSourceType = 1; // 默认音频
      this.source.enabled = true;
      this.source.ruleSearch = new LocalRuleSearchRule();
      this.source.ruleBookInfo = new LocalRuleBookInfoRule();
      this.source.ruleToc = new LocalRuleTocRule();
      this.source.ruleContent = new LocalRuleContentRule();
      this.markSaved();
    }
  }

  aboutToDisappear(): void {
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
  }

  private async loadSource(): Promise<void> {
    this.isLoading = true;
    try {
      const loaded = await LocalRuleSourceRepository.findByUrl(this.sourceUrl!);
      if (loaded) {
        if (loaded.isLocked) {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.source_manage_locked_message') });
          this.navStack.pop();
          return;
        }
        this.source = loaded;
        this.sourceType = loaded.bookSourceType;
        this.markSaved();
        if (this.usesNativeEditor()) {
          this.prepareRawDraft();
          if (this.isNativeForm()) this.nativeDraft = new NativeSourceDraft(this.rawDraft);
          else this.currentTab = 7;
        }
      } else {
        promptAction.showToast({ message: '书源不存在' });
        this.navStack.pop();
      }
    } catch (error) {
      promptAction.showToast({ message: $r('app.string.rule_source_read_failed') });
      this.navStack.pop();
    } finally {
      this.isLoading = false;
    }
  }

  private markSaved(): void {
    this.originalSnapshot = this.sourceSnapshot();
    this.hasUnsavedChanges = false;
    this.nativeFormChanged = false;
  }

  private markChanged(): void {
    this.hasUnsavedChanges = this.sourceSnapshot() !== this.originalSnapshot;
  }

  private sourceSnapshot(): string {
    return JSON.stringify(this.source);
  }

  private async saveSource(): Promise<void> {
    if (this.isSaving || this.isLoading) return;
    if (this.source.isLocked) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.source_manage_locked_message') });
      return;
    }
    if (!this.applyEditorDraft()) return;
    if (!this.source.bookSourceUrl || this.source.bookSourceUrl.trim().length === 0) {
      promptAction.showToast({ message: $r('app.string.rule_source_address_required') });
      return;
    }
    if (!this.source.bookSourceName || this.source.bookSourceName.trim().length === 0) {
      promptAction.showToast({ message: $r('app.string.rule_source_name_required') });
      return;
    }

    this.isSaving = true;
    try {
      if (this.isNewSource) {
        await LocalRuleSourceRepository.insert(this.source);
      } else {
        await LocalRuleSourceRepository.update(this.source);
      }
      SourceDataService.invalidateLocalSources(this.source.bookSourceUrl);
      this.markSaved();
      promptAction.showToast({ message: $r('app.string.rule_source_save_success') });
      this.navStack.pop();
    } catch (error) {
      promptAction.showToast({ message: $r('app.string.rule_source_save_failed') });
    } finally {
      this.isSaving = false;
    }
  }

  private applyRawDraft(): boolean {
    if (this.rawDraft === this.rawSnapshot && !this.usesNativeEditor()) return true;
    const report = LocalRuleSourceImportParser.parse(this.rawDraft);
    if (report.sources.length !== 1 || report.rejectedCount > 0) {
      this.rawError = report.message || this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.rule_source_json_single').id) || 'Invalid source JSON';
      return false;
    }
    const parsed = report.sources[0];
    if (!this.isNewSource && parsed.bookSourceUrl !== this.sourceUrl) {
      this.rawError = this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.rule_source_json_identity').id) || 'Source identity cannot change';
      return false;
    }
    parsed.isLocked = this.source.isLocked;
    parsed.isPinned = this.source.isPinned;
    parsed.customOrder = this.source.customOrder;
    this.source = parsed;
    this.sourceType = parsed.bookSourceType;
    if (this.currentTab === 7 && this.isNativeForm()) this.nativeDraft = new NativeSourceDraft(this.rawDraft);
    this.rawError = '';
    this.markChanged();
    return true;
  }

  private usesNativeEditor(): boolean {
    // 原生定义和兼容规则的模型不同，原生表单直接编辑原始定义。
    return this.source.engine === 'light-native' || this.source.engine === 'native-v1' ||
      this.source.nativeRulesJson.length > 0;
  }

  private isNativeForm(): boolean { return this.source.engine === 'light-native'; }

  private nativeSection(): string {
    switch (this.currentTab) {
      case 1: return '/search';
      case 2: return '/detail';
      case 3: return '/toc';
      case 4: return '/content';
      case 5: return '/explore';
      case 6: return '/login';
      default: return '';
    }
  }

  private applyEditorDraft(): boolean {
    if (this.isNativeForm() && this.currentTab !== 7) {
      try { this.rawDraft = this.nativeDraft.serialize(); }
      catch (_error) {
        this.rawError = this.getUIContext().getHostContext()?.resourceManager.getStringSync(
          $r('app.string.native_editor_number_error').id, this.nativeDraft.errorPath()) || this.nativeDraft.errorPath();
        return false;
      }
    }
    if (this.currentTab === 7 || this.usesNativeEditor()) return this.applyRawDraft();
    return this.currentTab !== 5 || this.updateExploreRule(this.exploreDraft);
  }

  private prepareRawDraft(): void {
    this.rawDraft = JSON.stringify(JSON.parse(LocalRuleSourceCodec.stringify(this.source)), null, 2);
    this.rawSnapshot = this.rawDraft;
    this.rawError = '';
  }

  private selectTab(index: number): void {
    if (index === this.currentTab) return;
    if (this.currentTab === 7 && !this.applyRawDraft()) return;
    if (this.currentTab === 5 && !this.isNativeForm() && !this.updateExploreRule(this.exploreDraft)) return;
    if (this.usesNativeEditor() && !this.isNativeForm()) index = 7;
    if (index === 5 && !this.isNativeForm()) {
      const definition: Record<string, Object> = JSON.parse(LocalRuleSourceCodec.stringify(this.source));
      const fields = definition['ruleExplore'];
      this.exploreDraft = JSON.stringify(fields !== null && typeof fields === 'object' && !Array.isArray(fields)
        ? fields : this.source.ruleExplore, null, 2);
      this.exploreSnapshot = this.exploreDraft;
    }
    if (index === 7) {
      if (this.isNativeForm()) {
        // JSON 和表单共用草稿；允许在 JSON 中继续修复未完成的原生定义。
        try { this.rawDraft = JSON.stringify(JSON.parse(this.nativeDraft.serialize()), null, 2); }
        catch (_error) { this.applyEditorDraft(); return; }
        this.rawSnapshot = this.rawDraft;
      } else this.prepareRawDraft();
    }
    this.currentTab = index;
    this.rawError = '';
    if (!this.isNativeForm()) this.formScroller.scrollEdge(Edge.Top);
  }

  private requestBack(): boolean {
    if (this.isSaving) return true;
    if (this.hasUnsavedChanges) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.rule_source_unsaved_title'),
        message: $r('app.string.rule_source_unsaved_message'),
        buttons: [
          { value: $r('app.string.common_cancel'), action: () => {} },
          { value: $r('app.string.rule_source_discard_changes'), action: () => { this.navStack.pop(); } },
          { value: $r('app.string.rule_source_save_and_back'), fontColor: AppColor.Brand,
            action: () => { this.saveSource(); } }
        ]
      });
      return true;
    }
    this.navStack.pop();
    return true;
  }

  private async exportSource(): Promise<void> {
    if (this.isExporting || this.isSaving) return;
    if (!this.applyEditorDraft()) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.isExporting = true;
    try {
      const definition: Object = JSON.parse(LocalRuleSourceCodec.stringify(this.source));
      const text = JSON.stringify(definition, null, 2);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [LocalRuleSourceCodec.exportFileName([this.source])];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) return;
      const file = await fileIo.open(uris[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, text); }
      finally { await fileIo.close(file); }
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_export_saved') });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_report_failed') });
    } finally {
      this.isExporting = false;
    }
  }

  build() {
    ProfileMenuDestination({
      pageBackground: $r('sys.color.background_secondary'),
      onBackRequested: (): boolean => this.requestBack()
    }) {
      Stack() {
        Column() {
          // 顶部标题栏
          Row() {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(24)
                .fontColor([$r('sys.color.font_primary')])
            }
              .width(44)
              .height(44)
              .backgroundColor(Color.Transparent)
              .accessibilityText($r('app.string.common_back'))
              .enabled(!this.isSaving)
              .onClick(() => this.requestBack())

            Text(this.isNewSource ? '新建书源' : '编辑书源')
              .fontSize(AppFont.TitleL)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: AppSpace.Xs })

            if (!this.isLoading) {
              Button($r('app.string.rule_source_export'), { type: ButtonType.Normal })
                .fontSize(AppFont.Body).fontColor(AppColor.Brand).height(44)
                .backgroundColor(Color.Transparent).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
                .enabled(!this.isSaving && !this.isExporting).onClick(() => this.exportSource())
              Button($r('app.string.rule_source_save'), { type: ButtonType.Normal })
                .fontSize(AppFont.Body)
                .fontColor(this.isSaving ? $r('sys.color.font_tertiary') : AppColor.Brand)
                .height(44)
                .constraintSize({ minWidth: 60 })
                .backgroundColor(Color.Transparent)
                .borderRadius(AppRadius.Sm)
                .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
                .enabled(!this.isSaving && !this.isExporting)
                .onClick(() => this.saveSource())
            }
          }
          .width('100%')
          .height(this.safeTop + 56)
          .padding({
            top: this.safeTop,
            left: AppSpace.Xs,
            right: AppSpace.Md
          })
          .backgroundColor($r('sys.color.background_primary'))

          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(AppColor.Brand)
              Text($r('app.string.common_content_loading'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ top: AppSpace.Xs })
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            // Tab栏
            Scroll() {
              Row() {
              if (!this.usesNativeEditor() || this.isNativeForm()) {
                this.TabButton('基本', 0)
                this.TabButton('搜索', 1)
                this.TabButton('详情', 2)
                this.TabButton('目录', 3)
                this.TabButton('正文', 4)
                this.TabButton($r('app.string.rule_source_explore'), 5)
                this.TabButton($r('app.string.rule_source_login_tab'), 6)
              }
              this.TabButton($r('app.string.rule_source_json_tab'), 7)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(44)
            .backgroundColor($r('sys.color.background_primary'))
            .borderWidth({ bottom: 0.5 })
            .borderColor($r('sys.color.comp_divider'))

            // 内容区域
            if (this.isNativeForm() && this.currentTab !== 7) {
              Column() {
                if (this.rawError) {
                  Text(this.rawError).fontSize(AppFont.Caption).fontColor(AppColor.Brand).padding(AppSpace.Sm)
                }
                NativeSourceForm({ draft: this.nativeDraft, section: this.nativeSection(),
                  onChanged: (): void => {
                    this.nativeFormChanged = true; this.hasUnsavedChanges = true; this.rawError = '';
                  } })
                  .layoutWeight(1)
              }.layoutWeight(1).width('100%').padding({ bottom: this.safeBottom })
                .enabled(!this.isSaving)
            } else {
            Scroll(this.formScroller) {
              Column({ space: AppSpace.Md }) {
                if (this.currentTab === 0) {
                  this.BasicTab()
                } else if (this.currentTab === 1) {
                  this.SearchTab()
                } else if (this.currentTab === 2) {
                  this.InfoTab()
                } else if (this.currentTab === 3) {
                  this.TocTab()
                } else if (this.currentTab === 4) {
                  this.ContentTab()
                } else if (this.currentTab === 5) {
                  this.ExploreTab()
                } else if (this.currentTab === 6) {
                  this.LoginTab()
                } else if (this.currentTab === 7) {
                  this.JsonTab()
                }
              }
              .width('100%')
              .padding({
                left: AppSpace.Md,
                right: AppSpace.Md,
                top: AppSpace.Md,
                bottom: AppSpace.Lg + this.safeBottom
              })
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
            .enabled(!this.isSaving)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            }
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_secondary'))

      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }

  }

  @Builder
  TabButton(label: ResourceStr, index: number) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.currentTab === index ? AppColor.Brand : $r('sys.color.font_secondary'))
      .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
      .width(64)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .height('100%')
      .borderWidth({ bottom: this.currentTab === index ? 2 : 0 })
      .borderColor(AppColor.Brand)
      .onClick(() => {
        this.selectTab(index);
      })
  }

  @Builder
  BasicTab() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text($r('app.string.rule_source_cookie_jar')).layoutWeight(1).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.source.enabledCookieJar })
          .selectedColor(AppColor.Brand).onChange((value: boolean) => {
            this.source.enabledCookieJar = value;
            this.markChanged();
          })
      }.width('100%')
      FormFieldBuilder({ label: $r('app.string.rule_source_timeout'), value: String(this.source.respondTime),
        onChange: (value: string) => {
          const parsed = Number(value);
          if (Number.isFinite(parsed) && parsed > 0) this.source.respondTime = parsed;
          this.markChanged();
        } })
      FormFieldBuilder({ label: $r('app.string.rule_source_rate'), value: this.source.concurrentRate,
        onChange: (value: string) => { this.source.concurrentRate = value; this.markChanged(); } })
      FormFieldBuilder({
        label: '书源名称',
        value: this.source.bookSourceName,
        placeholder: $r('app.string.rule_source_name_required'),
        onChange: (value: string) => {
          this.source.bookSourceName = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书源地址',
        value: this.source.bookSourceUrl,
        placeholder: '请输入书源地址（URL）',
        enabled: this.isNewSource,
        onChange: (value: string) => {
          this.source.bookSourceUrl = value;
          this.markChanged();
        }
      })

      Column({ space: 4 }) {
        Text('书源类型')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')

        Row({ space: AppSpace.Xs }) {
          this.TypeButton('文本', 0)
          this.TypeButton('音频', 1)
          this.TypeButton('漫画', 2)
        }
        .width('100%')
      }

      FormFieldBuilder({
        label: '书源分组',
        value: this.source.bookSourceGroup,
        placeholder: '可选，如：玄幻、都市',
        onChange: (value: string) => {
          this.source.bookSourceGroup = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书源备注',
        value: this.source.bookSourceComment,
        placeholder: '可选，备注说明',
        onChange: (value: string) => {
          this.source.bookSourceComment = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '登录地址',
        value: this.source.loginUrl || '',
        placeholder: '可选，需要登录时填写',
        onChange: (value: string) => {
          this.source.loginUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: 'JS库',
        value: this.source.jsLib || '',
        placeholder: '可选，自定义JS函数',
        multiline: true,
        onChange: (value: string) => {
          this.source.jsLib = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '请求头（Header）',
        value: this.source.header || '',
        placeholder: '可选，JSON格式',
        multiline: true,
        onChange: (value: string) => {
          this.source.header = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '变量（Variable）',
        value: this.source.variable || '',
        placeholder: '可选，JSON格式',
        multiline: true,
        onChange: (value: string) => {
          this.source.variable = value;
          this.markChanged();
        }
      })

      Row() {
        Text('启用书源')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
          .selectedColor(AppColor.Brand)
          .onChange((isOn: boolean) => {
            this.source.enabled = isOn;
            this.markChanged();
          })
      }
      .width('100%')
      .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
    }
  }

  @Builder
  TypeButton(label: string, type: number) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.sourceType === type ? AppColor.Brand : $r('sys.color.font_secondary'))
      .layoutWeight(1)
      .height(44)
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .padding({ left: AppSpace.Xs, right: AppSpace.Xs })
      .borderRadius(AppRadius.Sm)
      .backgroundColor(this.sourceType === type ? AppColor.BrandSoft :
        $r('sys.color.comp_background_secondary'))
      .onClick(() => {
        this.source.bookSourceType = type;
        this.sourceType = type;
        this.markChanged();
      })
  }

  @Builder
  SearchTab() {
    Column({ space: AppSpace.Md }) {
      Text('搜索规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '搜索地址',
        value: this.source.searchUrl || '',
        placeholder: '{{key}}为关键词占位符',
        onChange: (value: string) => {
          this.source.searchUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书籍列表规则',
        value: this.source.ruleSearch?.bookList || '',
        placeholder: '定位书籍列表的规则',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.bookList = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书名规则',
        value: this.source.ruleSearch?.name || '',
        placeholder: '提取书名',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.name = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '作者规则',
        value: this.source.ruleSearch?.author || '',
        placeholder: '提取作者',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.author = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '封面规则',
        value: this.source.ruleSearch?.coverUrl || '',
        placeholder: '提取封面URL',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.coverUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '简介规则',
        value: this.source.ruleSearch?.intro || '',
        placeholder: '提取简介',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.intro = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '分类规则',
        value: this.source.ruleSearch?.kind || '',
        placeholder: '提取分类',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.kind = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '详情页地址规则',
        value: this.source.ruleSearch?.bookUrl || '',
        placeholder: '提取详情页URL',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.bookUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '最新章节规则',
        value: this.source.ruleSearch?.lastChapter || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.lastChapter = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  InfoTab() {
    Column({ space: AppSpace.Md }) {
      Text('详情规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '初始化规则',
        value: this.source.ruleBookInfo?.init || '',
        placeholder: '可选，预处理JS',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.init = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书名规则',
        value: this.source.ruleBookInfo?.name || '',
        placeholder: '提取书名',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.name = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '作者规则',
        value: this.source.ruleBookInfo?.author || '',
        placeholder: '提取作者',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.author = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '封面规则',
        value: this.source.ruleBookInfo?.coverUrl || '',
        placeholder: '提取封面URL',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.coverUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '简介规则',
        value: this.source.ruleBookInfo?.intro || '',
        placeholder: '提取简介',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.intro = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '分类规则',
        value: this.source.ruleBookInfo?.kind || '',
        placeholder: '提取分类',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.kind = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '目录页地址规则',
        value: this.source.ruleBookInfo?.tocUrl || '',
        placeholder: '提取目录页URL',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.tocUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '最新章节规则',
        value: this.source.ruleBookInfo?.lastChapter || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.lastChapter = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  TocTab() {
    Column({ space: AppSpace.Md }) {
      Text('目录规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '章节列表规则',
        value: this.source.ruleToc?.chapterList || '',
        placeholder: '定位章节列表',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterList = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '章节名称规则',
        value: this.source.ruleToc?.chapterName || '',
        placeholder: '提取章节名',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterName = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '章节地址规则',
        value: this.source.ruleToc?.chapterUrl || '',
        placeholder: '提取章节URL',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '目录下一页规则',
        value: this.source.ruleToc?.nextTocUrl || '',
        placeholder: '可选，多页目录时使用',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.nextTocUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: 'VIP标记规则',
        value: this.source.ruleToc?.isVip || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.isVip = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '付费标记规则',
        value: this.source.ruleToc?.isPay || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.isPay = value;
          this.markChanged();
        }
      })

      if (this.sourceType === 1) {
        FormFieldBuilder({
          label: '音频时长规则',
          value: this.source.ruleToc?.duration || '',
          placeholder: '可选，提取时长',
          onChange: (value: string) => {
            if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
            this.source.ruleToc.duration = value;
            this.markChanged();
          }
        })
      }
    }
  }

  @Builder
  ContentTab() {
    Column({ space: AppSpace.Md }) {
      Text(this.sourceType === 1 ? '音频规则' : '正文规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      if (this.sourceType === 1) {
        FormFieldBuilder({
          label: '音频地址规则',
          value: this.source.ruleContent?.audioUrl || '',
          placeholder: '提取音频URL',
          onChange: (value: string) => {
            if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
            this.source.ruleContent.audioUrl = value;
            this.markChanged();
          }
        })
      } else {
        FormFieldBuilder({
          label: '正文内容规则',
          value: this.source.ruleContent?.content || '',
          placeholder: '提取正文',
          onChange: (value: string) => {
            if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
            this.source.ruleContent.content = value;
            this.markChanged();
          }
        })
      }

      FormFieldBuilder({
        label: '章节标题规则',
        value: this.source.ruleContent?.title || '',
        placeholder: '可选，重新提取标题',
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.title = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '正文下一页规则',
        value: this.source.ruleContent?.nextContentUrl || '',
        placeholder: '可选，分页正文时使用',
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.nextContentUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '替换净化规则',
        value: this.source.ruleContent?.replaceRegex || '',
        placeholder: '可选，正则替换',
        multiline: true,
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.replaceRegex = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  ExploreTab() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text($r('app.string.rule_source_explore_enabled')).layoutWeight(1).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.source.enabledExplore })
          .selectedColor(AppColor.Brand).onChange((value: boolean) => {
            this.source.enabledExplore = value; this.markChanged();
          })
      }.width('100%')
      FormFieldBuilder({ label: $r('app.string.rule_source_explore_rule'), value: this.source.exploreUrl,
        multiline: true, onChange: (value: string) => { this.source.exploreUrl = value; this.markChanged(); } })
      FormFieldBuilder({ label: $r('app.string.rule_source_explore_fields'),
        value: this.exploreDraft, multiline: true,
        onChange: (value: string) => { this.exploreDraft = value; this.hasUnsavedChanges = true; } })
      if (this.rawError) {
        Text(this.rawError).fontSize(AppFont.Caption).fontColor(AppColor.Brand).width('100%')
      }
    }.width('100%')
  }

  private updateExploreRule(value: string): boolean {
    if (value === this.exploreSnapshot) return true;
    try {
      const fields: Object = JSON.parse(value);
      if (fields === null || typeof fields !== 'object' || Array.isArray(fields)) throw new Error('Invalid ruleExplore');
      const definition: Record<string, Object> = JSON.parse(LocalRuleSourceCodec.stringify(this.source));
      definition['ruleExplore'] = fields;
      const parsed = LocalRuleSourceImportParser.parse(JSON.stringify(definition));
      if (parsed.sources.length !== 1) throw new Error(parsed.message);
      this.source.ruleExplore = parsed.sources[0].ruleExplore;
      this.source.rawSourceJson = parsed.sources[0].rawSourceJson;
      this.rawError = '';
      this.markChanged();
      return true;
    } catch (error) {
      this.rawError = error instanceof Error ? error.message : String(error);
      return false;
    }
  }

  @Builder
  LoginTab() {
    Column({ space: AppSpace.Md }) {
      FormFieldBuilder({ label: $r('app.string.rule_source_login_ui'), value: this.source.loginUi, multiline: true,
        onChange: (value: string) => { this.source.loginUi = value; this.markChanged(); } })
      FormFieldBuilder({ label: $r('app.string.rule_source_login_check'), value: this.source.loginCheckJs, multiline: true,
        onChange: (value: string) => { this.source.loginCheckJs = value; this.markChanged(); } })
      FormFieldBuilder({ label: $r('app.string.rule_source_initial_variable'), value: this.source.variable, multiline: true,
        onChange: (value: string) => { this.source.variable = value; this.markChanged(); } })
    }.width('100%')
  }

  @Builder
  JsonTab() {
    Column({ space: AppSpace.Sm }) {
      TextArea({ text: this.rawDraft })
        .width('100%').height(560).fontFamily('monospace').fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_primary')).caretColor(AppColor.Brand)
        .selectedBackgroundColor(AppColor.BrandSoft).backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs).padding(AppSpace.Sm)
        .onChange((value: string) => {
          this.rawDraft = value;
          this.hasUnsavedChanges = this.nativeFormChanged || this.rawDraft !== this.rawSnapshot ||
            this.sourceSnapshot() !== this.originalSnapshot;
        })
      if (this.rawError) {
        Text(this.rawError).fontSize(AppFont.Caption).fontColor(AppColor.Brand).width('100%')
      }
    }.width('100%')
  }
}
