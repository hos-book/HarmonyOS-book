import { BookPresentation } from '../model/BookPresentation';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct BookGroupSheet {
  @Param initialGroup: string = '';
  @Param initialGroups: string[] = [];
  @Event onConfirm: (group: string, groups: string[]) => Promise<void> = async (): Promise<void> => {};
  @Local group: string = '';
  @Local groups: string[] = [];
  @Local newGroup: string = '';
  @Local saving: boolean = false;
  @Local failed: boolean = false;

  aboutToAppear(): void {
    this.group = this.initialGroup;
    this.groups = Array.from(new Set(BookPresentation.groups.concat(this.initialGroups)));
  }

  private async save(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    this.failed = false;
    try { await this.onConfirm(this.group, this.groups); }
    catch (_error) { this.failed = true; }
    finally { this.saving = false; }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.shelf_group_settings')).fontSize(22).fontWeight(FontWeight.Bold)
        .width('100%').fontColor($r('sys.color.font_primary'))
      List({ space: 8 }) {
        ForEach(['', ...this.groups], (name: string) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(name || $r('app.string.shelf_group_none')).layoutWeight(1)
                .fontColor(this.group === name ? AppColor.Brand : $r('sys.color.font_primary'))
              if (this.group === name) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([AppColor.Brand])
              }
            }.width('100%').padding(16).borderRadius(12)
              .backgroundColor(this.group === name ? AppColor.BrandSoft : Color.Transparent)
              .enabled(!this.saving).onClick((): void => { this.group = name; })
          }
        }, (name: string): string => name)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        TextInput({ text: this.newGroup, placeholder: $r('app.string.shelf_group_new') })
          .maxLength(40).layoutWeight(1).enabled(!this.saving)
          .onChange((value: string): void => { this.newGroup = value; })
        Button($r('app.string.common_add')).backgroundColor(AppColor.Brand).fontColor(Color.White)
          .enabled(!this.saving && !!this.newGroup.trim() && this.newGroup.trim() !== BookPresentation.UNGROUPED)
          .onClick((): void => {
            const name = this.newGroup.trim();
            if (!this.groups.includes(name)) this.groups = this.groups.concat(name);
            this.group = name;
            this.newGroup = '';
          })
      }.width('100%')
      if (this.failed) {
        Text($r('app.string.rule_source_operation_failed')).fontColor($r('sys.color.font_secondary'))
      }
      Button($r('app.string.common_save')).width('100%').backgroundColor(AppColor.Brand).fontColor(Color.White)
        .enabled(!this.saving).onClick((): void => { this.save(); })
    }.padding({ left: 24, right: 24, top: 16, bottom: 28 }).width('100%').height('100%')
  }
}
