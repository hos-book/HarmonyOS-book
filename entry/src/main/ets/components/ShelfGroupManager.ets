import { BookPresentation } from '../model/BookPresentation';
import { AppColor } from '../theme/Theme';
import { ListDataSource } from '../utils/ListDataSource';
import { ImmersiveCircleButton } from './ImmersiveCircleButton';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ShelfGroupManager {
  @Param groups: string[] = [];
  @Param initialAssignment: string | undefined = undefined;
  @Event onAssign: (group: string) => Promise<void> = async (): Promise<void> => {};
  @Local assignment: string | undefined = undefined;
  @Param visibleGroups: string[] = [];
  @Param changingVisibility: boolean = false;
  @Event onVisibility: (group: string, visible: boolean) => Promise<void> = async (): Promise<void> => {};
  @Event onClose: () => void = (): void => {};
  @Event onSave: (previous: string, name: string) => Promise<void> = async (): Promise<void> => {};
  @Event onBusy: (busy: boolean) => void = (): void => {};
  @Event onDelete: (group: string) => Promise<void> = async (): Promise<void> => {};
  @Event onReorder: (groups: string[]) => Promise<void> = async (): Promise<void> => {};
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local editingGroup: string | undefined = undefined;
  @Local draftName: string = '';
  private alive: boolean = false;
  private renderedGroups: string[] = [];
  private groupData: ListDataSource<string | undefined> = new ListDataSource<string | undefined>();
  private scroller: Scroller = new Scroller();
  private readonly moveHandler: (from: number, to: number) => void =
    (from: number, to: number): void => { this.reorder(from, to); };

  aboutToAppear(): void { this.alive = true; this.assignment = this.initialAssignment; this.refreshGroups(); }
  aboutToDisappear(): void { this.alive = false; }

  @Monitor('groups')
  private refreshGroups(): void {
    this.renderGroups(this.groups.slice(1));
  }

  private renderGroups(groups: string[]): void {
    this.renderedGroups = groups;
    const rows: (string | undefined)[] = groups.slice();
    if (this.editingGroup === '') rows.push(undefined);
    this.groupData.setItems(rows);
  }

  private canToggle(group: string): boolean {
    return !this.saving && !this.changingVisibility &&
      (!this.visibleGroups.includes(group) || this.visibleGroups.length > 1);
  }

  private async setVisible(group: string, visible: boolean): Promise<void> {
    if (!this.canToggle(group) || this.visibleGroups.includes(group) === visible) return;
    this.failed = false;
    try { await this.onVisibility(group, visible); }
    catch (_error) {
      if (this.alive) this.failed = true;
      else this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_operation_failed') });
    }
  }

  private groupLabel(group: string): string {
    if (group !== '' && group !== BookPresentation.UNGROUPED) return group;
    const label = group === '' ? $r('app.string.collection_all_books') : $r('app.string.shelf_group_none');
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(label.id) ?? '';
  }

  private editGroup(group: string): void {
    if (this.saving || this.changingVisibility || this.editingGroup !== undefined) return;
    this.draftName = group;
    this.editingGroup = group;
    this.failed = false;
    if (group === '') {
      this.refreshGroups();
      this.scroller.scrollToIndex(this.groups.length, false, ScrollAlign.END);
    }
  }

  private cancelEdit(): void {
    if (this.saving) return;
    const adding = this.editingGroup === '';
    this.editingGroup = undefined;
    this.draftName = '';
    this.failed = false;
    if (adding) this.refreshGroups();
  }

  private duplicateName(): boolean {
    const name = this.draftName.trim();
    return name !== this.editingGroup && this.groups.includes(name);
  }

  private canSave(): boolean {
    if (this.saving) return false;
    if (this.editingGroup === undefined) return !this.changingVisibility;
    const name = this.draftName.trim();
    return !this.changingVisibility && name.length > 0 && name !== BookPresentation.UNGROUPED &&
      name !== this.editingGroup && !this.duplicateName();
  }

  private async save(): Promise<void> {
    if (!this.canSave()) return;
    const previous = this.editingGroup;
    if (previous === undefined && this.assignment === undefined) {
      this.onClose();
      return;
    }
    this.saving = true;
    this.failed = false;
    this.onBusy(true);
    try {
      if (previous === undefined) {
        if (this.assignment !== undefined) await this.onAssign(this.assignment);
        this.onClose();
        return;
      }
      const name = this.draftName.trim();
      await this.onSave(previous, name);
      if (this.assignment !== undefined && (previous === '' || this.assignment === previous)) this.assignment = name;
      this.editingGroup = undefined;
      this.draftName = '';
      if (previous === '') this.refreshGroups();
    } catch (_error) {
      this.failed = true;
    } finally {
      this.saving = false;
      this.onBusy(false);
    }
  }

  private async reorder(from: number, to: number): Promise<void> {
    const previous = this.renderedGroups;
    if (this.saving || this.changingVisibility || this.editingGroup !== undefined || from === to || from < 0 || to < 0 ||
      from >= previous.length || to >= previous.length) return;
    const next = previous.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    this.saving = true;
    this.failed = false;
    this.onBusy(true);
    this.renderGroups(next);
    try { await this.onReorder([''].concat(next)); }
    catch (_error) {
      this.renderGroups(previous);
      this.failed = true;
    }
    finally {
      // The parent @Param can still hold the old order when saving completes.
      this.saving = false;
      this.onBusy(false);
    }
  }

  private async deleteGroup(group: string): Promise<void> {
    if (this.saving || this.changingVisibility || this.editingGroup !== undefined || !this.groups.includes(group)) return;
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
      if (this.assignment === group) this.assignment = BookPresentation.UNGROUPED;
    } catch (_error) {
      if (this.alive) this.failed = true;
    } finally {
      this.saving = false;
      this.onBusy(false);
    }
  }

  @LocalBuilder
  private groupAction(icon: Resource, label: Resource, tint: ResourceColor, cancel: boolean, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon).fontSize(20).fontColor([tint])
    }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
      .enabled(!this.saving && (cancel || (!this.changingVisibility && this.editingGroup === undefined)))
      .accessibilityText(label).onClick(action)
  }

  @LocalBuilder
  private groupRow(group: string) {
    Row({ space: 12 }) {
      if (group === '') {
        Blank().width(20)
      } else {
        SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(20)
          .fontColor([$r('sys.color.font_tertiary')]).accessibilityText($r('app.string.shelf_group_drag_hint'))
      }
      if (this.assignment !== undefined && group !== '') {
        Row({ space: 6 }) {
          Radio({ value: group, group: 'shelf-book-assignment' }).checked(this.assignment === group)
            .radioStyle({ checkedBackgroundColor: AppColor.Brand })
            .onChange((checked: boolean): void => { if (checked) this.assignment = group; })
          Text(this.groupLabel(group)).layoutWeight(1).maxLines(2).fontColor($r('sys.color.font_primary'))
        }.layoutWeight(1).constraintSize({ minHeight: 44 })
          .enabled(!this.saving && this.editingGroup === undefined)
          .accessibilityText(this.groupLabel(group)).accessibilitySelected(this.assignment === group)
          .onClick((): void => { this.assignment = group; })
      } else {
        Text(this.groupLabel(group)).layoutWeight(1).maxLines(2).fontColor($r('sys.color.font_primary'))
      }
      if (group !== '' && group !== BookPresentation.UNGROUPED) {
        this.groupAction($r('sys.symbol.square_and_pencil'), $r('app.string.common_edit'), AppColor.Brand,
          false, (): void => this.editGroup(group))
        this.groupAction($r('sys.symbol.trash'), $r('app.string.common_delete'),
          $r('sys.color.ohos_id_color_warning'), false, (): void => { this.deleteGroup(group); })
      }
      Toggle({ type: ToggleType.Switch, isOn: this.visibleGroups.includes(group) })
        .selectedColor(AppColor.Brand).enabled(this.canToggle(group)).accessibilityText(this.groupLabel(group))
        .onChange((visible: boolean): void => { this.setVisible(group, visible); })
    }.width('100%').padding(8)
  }

  @LocalBuilder
  private editRow() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.draftName, placeholder: $r('app.string.shelf_group_new') })
          .id('shelf-group-name-input').layoutWeight(1).maxLength(40).enabled(!this.saving)
          .backgroundColor($r('app.color.shelf_toolbar_background'))
          .onChange((value: string): void => { this.draftName = value; this.failed = false; })
          .onSubmit((): void => { this.save(); })
          .onAppear((): void => {
            setTimeout((): void => {
              if (!this.alive || this.editingGroup === undefined) return;
              try { this.getUIContext().getFocusController().requestFocus('shelf-group-name-input'); }
              catch (_error) { /* The row may have scrolled out of view. */ }
            }, 0);
          })
        this.groupAction($r('sys.symbol.xmark'), $r('app.string.common_cancel'), $r('sys.color.font_secondary'),
          true, (): void => this.cancelEdit())
      }.width('100%')
      if (this.duplicateName()) {
        Text($r('app.string.shelf_group_duplicate')).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(8)
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text(this.assignment === undefined ? $r('app.string.shelf_group_manage') : $r('app.string.shelf_group_settings')).fontSize(22).fontWeight(FontWeight.Bold)
          .layoutWeight(1).fontColor($r('sys.color.font_primary'))
        Row({ space: 12 }) {
          ImmersiveCircleButton({ icon: $r('sys.symbol.plus'), label: $r('app.string.common_add'),
            useMaterial: false, onPress: (): void => this.editGroup('') })
            .enabled(!this.saving && !this.changingVisibility && this.editingGroup === undefined)
          ImmersiveCircleButton({ icon: $r('sys.symbol.checkmark'), label: $r('app.string.common_save'),
            useMaterial: false, iconColor: AppColor.Brand, onPress: (): void => { this.save(); } })
            .enabled(this.canSave())
          ImmersiveCircleButton({ icon: $r('sys.symbol.xmark'), label: $r('app.string.common_close'),
            useMaterial: false, onPress: (): void => { if (!this.saving) this.onClose(); } })
            .enabled(!this.saving)
        }
      }.width('100%')
      Text($r('app.string.shelf_group_keep_one')).fontSize(12).width('100%')
        .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      List({ space: 8, scroller: this.scroller }) {
        ListItem() { this.groupRow('') }
        LazyForEach(this.groupData, (group: string | undefined) => {
          ListItem() {
            if (group === undefined || (group !== '' && this.editingGroup === group)) {
              this.editRow()
            } else {
              this.groupRow(group)
            }
          }
        }, (group: string | undefined): string => group === undefined ? 'draft' : `group:${group}`)
          .onMove(this.saving || this.changingVisibility || this.editingGroup !== undefined ? undefined : this.moveHandler)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).enabled(!this.saving)
      if (this.failed) {
        Text($r('app.string.rule_source_operation_failed')).fontColor($r('sys.color.font_secondary'))
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 16, bottom: WindowUtils.getBottomSafeVp() + 16 })
  }
}
