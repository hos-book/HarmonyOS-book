import { ReaderReplaceRule } from '../model/ReaderTools';
import { ReaderToolsService } from '../service/text/ReaderToolsService';
import { ReaderReplaceImport } from '../service/text/ReaderReplaceImport';
import { ListDataSource } from '../utils/ListDataSource';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct ReaderReplaceSheet {
  @Param bookId: string = '';
  @Param sample: string = '';
  @Event onChanged: () => Promise<void> = async (): Promise<void> => {};
  @Local rules: ReaderReplaceRule[] = [];
  @Local editing: boolean = false;
  @Local draftId: string = '';
  @Local name: string = '';
  @Local pattern: string = '';
  @Local replacement: string = '';
  @Local regex: boolean = false;
  @Local allBooks: boolean = false;
  @Local draftEnabled: boolean = true;
  @Local busy: boolean = false;
  @Local failed: ResourceStr = '';
  @Local preview: string = '';
  @Local previewReady: boolean = false;
  @Local importing: ReaderReplaceRule[] = [];
  @Local importAllBooks: boolean = false;
  @Local importMessage: string = '';
  private data: ListDataSource<ReaderReplaceRule> = new ListDataSource<ReaderReplaceRule>();
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; }

  private async load(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const rules = await ReaderToolsService.rules(context);
      if (!this.alive) return;
      this.rules = rules.filter((rule): boolean => !rule.bookId || rule.bookId === this.bookId);
      this.data.setItems(this.rules);
    } catch (_error) { this.failed = $r('app.string.reader_tools_storage_error'); }
  }

  private edit(rule?: ReaderReplaceRule): void {
    this.draftId = rule?.id ?? ReaderToolsService.newId();
    this.name = rule?.name ?? '';
    this.pattern = rule?.pattern ?? '';
    this.replacement = rule?.replacement ?? '';
    this.regex = rule?.isRegex ?? false;
    this.allBooks = rule !== undefined && !rule.bookId;
    this.draftEnabled = rule?.enabled ?? true;
    this.failed = ''; this.previewReady = false; this.editing = true;
  }

  private draft(): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = this.draftId; rule.name = this.name.trim(); rule.pattern = this.pattern;
    rule.replacement = this.replacement; rule.isRegex = this.regex; rule.enabled = this.draftEnabled;
    rule.bookId = this.allBooks ? '' : this.bookId;
    return rule;
  }

  private async change(rule: ReaderReplaceRule, remove: boolean = false): Promise<void> {
    if (this.busy) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true; this.failed = '';
    try {
      if (remove) await ReaderToolsService.deleteRule(context, rule.id);
      else await ReaderToolsService.saveRule(context, rule);
      await this.load();
      this.editing = false;
      await this.onChanged();
    } catch (error) {
      this.failed = error instanceof Error && error.message === 'reader_replace_invalid' ?
        $r('app.string.reader_replace_invalid') : $r('app.string.reader_tools_storage_error');
    } finally { this.busy = false; }
  }

  private toggle(rule: ReaderReplaceRule, enabled: boolean): void {
    if (rule.enabled === enabled || this.busy) return;
    const copy: ReaderReplaceRule = JSON.parse(JSON.stringify(rule));
    copy.enabled = enabled;
    this.change(copy);
  }

  private async showPreview(): Promise<void> {
    if (this.busy || !this.pattern) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true; this.failed = ''; this.previewReady = false;
    try {
      const rule = this.draft(); rule.enabled = true;
      const result = await ReaderToolsService.render(context, this.bookId, this.sample, [rule]);
      if (result.failed) this.failed = $r('app.string.reader_replace_invalid');
      else { this.preview = result.content.substring(0, 2000); this.previewReady = true; }
    } catch (_error) { this.failed = $r('app.string.reader_replace_invalid'); }
    finally { this.busy = false; }
  }

  private importError(error: Error): void {
    this.failed = error.message === 'reader_replace_import_scope_error' ? $r('app.string.reader_replace_import_scope_error') :
      error.message === 'reader_tools_limit' ? $r('app.string.reader_replace_import_limit') :
      error.message === 'reader_tools_storage_error' ? $r('app.string.reader_tools_storage_error') :
      error.message === 'reader_replace_invalid' ? $r('app.string.reader_replace_invalid') :
      $r('app.string.reader_replace_import_invalid');
  }

  private async pickRules(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.busy) return;
    this.busy = true; this.failed = ''; this.importMessage = '';
    try {
      const rules = await ReaderReplaceImport.pick(context);
      if (this.alive) { this.importing = rules; this.importAllBooks = false; }
    } catch (error) { if (this.alive) this.importError(error instanceof Error ? error : new Error('import')); }
    finally { if (this.alive) this.busy = false; }
  }

  private async saveImportedRules(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.busy || this.importing.length === 0) return;
    this.busy = true; this.failed = '';
    try {
      const count = await ReaderToolsService.importRules(context, this.importing, this.importAllBooks ? '' : this.bookId);
      this.importing = [];
      await this.load();
      if (this.alive) this.importMessage = context.resourceManager.getStringSync($r('app.string.reader_replace_import_success').id, count);
      if (count > 0) await this.onChanged();
    } catch (error) { if (this.alive) this.importError(error instanceof Error ? error : new Error('import')); }
    finally { if (this.alive) this.busy = false; }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(this.editing ? $r('app.string.reader_replace_edit') : $r('app.string.reader_replace_rules'))
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        if (!this.editing && this.importing.length === 0) {
          Button($r('app.string.common_add'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontColor($r('sys.color.font_primary'))
            .flexShrink(0).enabled(!this.busy).onClick((): void => this.edit())
        }
      }.width('100%').padding({ right: 56 }) // 为系统弹层右上角的关闭按钮留出独立区域。
      if (this.failed !== '') { Text(this.failed).fontSize(14).fontColor($r('sys.color.ohos_id_color_warning')) }
      if (this.importing.length > 0) {
        Text($r('app.string.reader_replace_import_preview', this.importing.length)).fontColor($r('sys.color.font_primary'))
        Text($r('app.string.reader_replace_import_hint')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Row() {
          Text($r('app.string.reader_replace_all_books')).layoutWeight(1).fontColor($r('sys.color.font_primary'))
          Toggle({ type: ToggleType.Switch, isOn: this.importAllBooks }).selectedColor(AppColor.Brand)
            .enabled(!this.busy).onChange((value: boolean): void => { this.importAllBooks = value; })
        }.width('100%')
        Scroll() {
          Text(this.importing.map((rule): string => rule.name || rule.pattern).join('\n'))
            .fontColor($r('sys.color.font_primary')).width('100%')
        }.layoutWeight(1).width('100%')
        Row({ space: 12 }) {
          Button($r('app.string.common_cancel')).layoutWeight(1).enabled(!this.busy)
            .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
            .onClick((): void => { this.importing = []; this.failed = ''; })
          Button($r('app.string.reader_replace_import')).layoutWeight(1).enabled(!this.busy)
            .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
            .onClick((): void => { this.saveImportedRules(); })
        }.width('100%')
      } else if (this.editing) {
        Scroll() {
          Column({ space: 12 }) {
            TextInput({ text: this.name, placeholder: $r('app.string.reader_replace_name') }).maxLength(80)
              .onChange((value: string): void => { this.name = value; })
            TextArea({ text: this.pattern, placeholder: $r('app.string.reader_replace_pattern') }).height(96).maxLength(2048)
              .onChange((value: string): void => { this.pattern = value; this.previewReady = false; })
            TextArea({ text: this.replacement, placeholder: $r('app.string.reader_replace_replacement') }).height(96).maxLength(2048)
              .onChange((value: string): void => { this.replacement = value; this.previewReady = false; })
            Row() {
              Text($r('app.string.reader_replace_regex')).layoutWeight(1).fontColor($r('sys.color.font_primary'))
              Toggle({ type: ToggleType.Switch, isOn: this.regex }).selectedColor($r('sys.color.font_primary'))
                .switchPointColor($r('sys.color.ohos_id_color_foreground_contrary'))
                .onChange((value: boolean): void => { this.regex = value; this.previewReady = false; })
            }.width('100%')
            Row() {
              Text($r('app.string.reader_replace_all_books')).layoutWeight(1).fontColor($r('sys.color.font_primary'))
              Toggle({ type: ToggleType.Switch, isOn: this.allBooks }).selectedColor($r('sys.color.font_primary'))
                .switchPointColor($r('sys.color.ohos_id_color_foreground_contrary'))
                .onChange((value: boolean): void => { this.allBooks = value; })
            }.width('100%')
            Text($r('app.string.reader_replace_hint')).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
            Button($r('app.string.reader_replace_preview')).backgroundColor(AppColor.Brand)
              .fontColor(AppColor.OnBrand).enabled(!!this.pattern && !this.busy)
              .onClick((): void => { this.showPreview(); })
            if (this.previewReady) {
              Text(this.preview || $r('app.string.reader_replace_preview_empty')).fontSize(15)
                .fontColor($r('sys.color.font_primary')).width('100%')
            }
          }.width('100%').enabled(!this.busy)
        }.layoutWeight(1).width('100%')
        Row({ space: 12 }) {
          Button($r('app.string.common_cancel')).layoutWeight(1).enabled(!this.busy)
            .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
            .onClick((): void => { this.editing = false; this.failed = ''; })
          Button($r('app.string.common_save')).layoutWeight(1).backgroundColor(AppColor.Brand)
            .fontColor(AppColor.OnBrand)
            .enabled(!this.busy && !!this.pattern).onClick((): void => { this.change(this.draft()); })
        }.width('100%')
      } else {
        Button($r('app.string.reader_replace_import')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
          .enabled(!this.busy).onClick((): void => { this.pickRules(); })
        if (this.importMessage) { Text(this.importMessage).fontSize(13).fontColor($r('sys.color.font_secondary')) }
        Text($r('app.string.reader_replace_scope_hint')).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
        if (this.rules.length === 0) {
          Text($r('app.string.reader_replace_empty')).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        } else {
          List({ space: 12 }) {
            LazyForEach(this.data, (rule: ReaderReplaceRule) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row({ space: 12 }) {
                    Text(rule.name || rule.pattern).fontSize(17).fontColor($r('sys.color.font_primary')).layoutWeight(1).maxLines(2)
                    Toggle({ type: ToggleType.Switch, isOn: rule.enabled }).selectedColor($r('sys.color.font_primary'))
                      .switchPointColor($r('sys.color.ohos_id_color_foreground_contrary')).enabled(!this.busy)
                      .onChange((enabled: boolean): void => this.toggle(rule, enabled))
                  }.width('100%')
                  Text(rule.bookId ? $r('app.string.reader_replace_this_book') : $r('app.string.reader_replace_all_books'))
                    .fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
                  Row({ space: 12 }) {
                    Button($r('app.string.common_edit'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                      .fontColor($r('sys.color.font_primary')).enabled(!this.busy)
                      .onClick((): void => this.edit(rule))
                    Button($r('app.string.common_delete'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                      .fontColor($r('sys.color.font_primary')).enabled(!this.busy)
                      .onClick((): void => { this.change(rule, true); })
                  }.width('100%').justifyContent(FlexAlign.End)
                }.width('100%').padding({ top: 8, bottom: 8 })
              }
            }, (rule: ReaderReplaceRule): string => `${rule.id}:${rule.enabled}`)
          }.width('100%').layoutWeight(1)
        }
      }
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 20, bottom: 28 })
  }
}
