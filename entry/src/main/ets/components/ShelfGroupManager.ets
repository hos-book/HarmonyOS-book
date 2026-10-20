import { BookPresentation } from '../model/BookPresentation';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct ShelfGroupManager {
  @Param groups: string[] = [];
  @Event onSave: (previous: string, name: string) => Promise<void> = async (): Promise<void> => {};
  @Event onBusy: (busy: boolean) => void = (): void => {};
  @Event onDelete: (group: string) => Promise<void> = async (): Promise<void> => {};
  @Local previous: string = '';
  @Local name: string = '';
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; }

  private async deleteGroup(group: string): Promise<void> {
    if (this.saving || !this.groups.includes(group)) return;
    this.saving = true;
    this.failed = false;
    this.onBusy(true);
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.shelf_group_delete_title'),
        message: $r('app.string.shelf_group_delete_message', group),
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('sys.color.font_primary') },
          { text: $r('app.string.common_delete'), color: $r('sys.color.ohos_id_color_warning') }
        ]
      });
      if (result.index !== 1 || !this.alive) return;
      await this.onDelete(group);
      if (this.previous === group) { this.previous = ''; this.name = ''; }
    } catch (_error) {
      if (this.alive) this.failed = true;
    } finally {
      this.saving = false;
      this.onBusy(false);
    }
  }

  private validName(): boolean {
    const name = this.name.trim();
    return name.length > 0 && name !== BookPresentation.UNGROUPED &&
      name !== this.previous && !this.groups.includes(name);
  }

  private async save(): Promise<void> {
    if (this.saving || !this.validName()) return;
    this.saving = true;
    this.failed = false;
    this.onBusy(true);
    try {
      await this.onSave(this.previous, this.name.trim());
      this.previous = '';
      this.name = '';
    } catch (_error) {
      this.failed = true;
    } finally {
      this.saving = false;
      this.onBusy(false);
    }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.shelf_group_manage')).fontSize(22).fontWeight(FontWeight.Bold)
        .width('100%').fontColor($r('sys.color.font_primary'))
      List({ space: 8 }) {
        ForEach(this.groups, (group: string) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(group).layoutWeight(1).maxLines(2).fontColor($r('sys.color.font_primary'))
              Button($r('app.string.common_edit')).fontColor(AppColor.Brand)
                .backgroundColor(Color.Transparent).enabled(!this.saving)
                .onClick((): void => { this.previous = group; this.name = group; this.failed = false; })
              Button($r('app.string.common_delete')).fontColor($r('sys.color.ohos_id_color_warning'))
                .backgroundColor(Color.Transparent).enabled(!this.saving)
                .onClick((): void => { this.deleteGroup(group); })
            }.width('100%').padding(8)
          }
        }, (group: string): string => group)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Text(this.previous ? $r('app.string.shelf_group_rename') : $r('app.string.shelf_group_new'))
        .width('100%').fontColor($r('sys.color.font_secondary'))
      TextInput({ text: this.name, placeholder: $r('app.string.shelf_group_new') })
        .maxLength(40).enabled(!this.saving).onChange((value: string): void => { this.name = value; })
      if (this.groups.includes(this.name.trim()) && this.name.trim() !== this.previous) {
        Text($r('app.string.shelf_group_duplicate')).fontColor($r('sys.color.font_secondary'))
      }
      if (this.failed) {
        Text($r('app.string.rule_source_operation_failed')).fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 12 }) {
        if (this.previous) {
          Button($r('app.string.common_cancel')).layoutWeight(1).enabled(!this.saving)
            .onClick((): void => { this.previous = ''; this.name = ''; this.failed = false; })
        }
        Button(this.previous ? $r('app.string.common_save') : $r('app.string.common_add'))
          .layoutWeight(1).backgroundColor(AppColor.Brand).fontColor(Color.White)
          .enabled(!this.saving && this.validName()).onClick((): void => { this.save(); })
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 16, bottom: 28 })
  }
}
