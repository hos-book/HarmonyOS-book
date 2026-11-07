import { AppColor, AppFont, AppTheme } from '../theme/Theme';

/** 管理页顶栏内的批量操作；与列表滚动区域分离。 */
@ComponentV2
export struct ManagementBatchBar {
  @Param selectedCount: number = 0;
  @Param totalCount: number = 0;
  @Param busy: boolean = false;
  @Event onSelectAll: () => void = () => {};
  @Event onEnable: () => void = () => {};
  @Event onDisable: () => void = () => {};
  @Event onDelete: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Text($r('app.string.tts_batch_selected', this.selectedCount))
        .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      Row({ space: 8 }) {
        Button(this.totalCount > 0 && this.selectedCount === this.totalCount ?
          $r('app.string.tts_batch_clear') : $r('app.string.tts_batch_all'))
          .layoutWeight(1).height(36).fontSize(AppFont.Caption).padding({ left: 4, right: 4 })
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
          .enabled(!this.busy && this.totalCount > 0).onClick((): void => this.onSelectAll())
          .id('management-select-all')
        Button($r('app.string.tts_batch_enable'))
          .layoutWeight(1).height(36).fontSize(AppFont.Caption).padding({ left: 4, right: 4 })
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
          .enabled(!this.busy && this.selectedCount > 0).onClick((): void => this.onEnable())
          .id('management-enable')
        Button($r('app.string.tts_batch_disable'))
          .layoutWeight(1).height(36).fontSize(AppFont.Caption).padding({ left: 4, right: 4 })
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
          .enabled(!this.busy && this.selectedCount > 0).onClick((): void => this.onDisable())
          .id('management-disable')
        Button($r('app.string.tts_batch_delete'))
          .layoutWeight(1).height(36).fontSize(AppFont.Caption).padding({ left: 4, right: 4 })
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Surface)
          .enabled(!this.busy && this.selectedCount > 0).onClick((): void => this.onDelete())
          .id('management-delete')
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: 760 }).alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 2, bottom: 10 })
  }
}
