import { ReaderSelectionMenu } from '../utils/ReaderSelectionMenu';

/** 精排正文保留原始字形与拖柄，使用原生 Text 执行系统选区服务（问问小艺、复制等）。 */
@ComponentV2
export struct ReaderNativeSelectionMenu {
  @Param text: string = '';
  @Event onAction: (id: TextMenuItemId) => void = () => {};
  @Local selectionEnd: number = -1;
  private timer: number = -1;

  aboutToDisappear(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
  }

  private menuOptions(): EditMenuOptions {
    return {
      onCreateMenu: (items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(true, items),
      onPrepareMenu: (items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(true, items),
      onMenuItemClick: (item: TextMenuItem): boolean => {
        if (item.id.equals(TextMenuItemId.SELECT_ALL) || ReaderSelectionMenu.isReaderAction(item.id)) {
          // 全选交给正文，不能选中菜单锚点用于隔离系统手柄的前置换行。
          this.onAction(item.id);
          return true;
        }
        // 必须返回 false，让原生组件将选中文字交给小艺等系统服务。
        // 保留原生节点直到正文选区被取消，系统服务可能异步读取选中文字。
        return false;
      }
    };
  }

  build() {
    Text('\n' + this.text)
      // 透明的菜单锚点只承载所选原文，正文仍由测量后的 Paragraph 绘制。
      // 选区手柄由正文绘制；裁剪锚点使系统手柄的完整高度落在可见区域外。
      // caretColor 只能隐藏外圈，不能隐藏系统固定的白色内圈。
      .width('100%').height(1).fontSize(16).lineHeight(16).clip(true).fontColor(Color.Transparent)
      // 禁止默认垂直居中把第二行的系统手柄移回这 1vp 的可见区域。
      .align(Alignment.TopStart)
      .caretColor(Color.Transparent).selectedBackgroundColor(Color.Transparent)
      .copyOption(CopyOptions.LocalDevice).textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      .selection(this.selectionEnd > 0 ? 1 : -1, this.selectionEnd > 0 ? this.selectionEnd + 1 : -1)
      .editMenuOptions(this.menuOptions()).draggable(false)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onAreaChange((): void => {
        if (this.selectionEnd >= 0 || this.timer >= 0 || !this.text) return;
        // 等待真实 Text 节点完成布局后，用 API 11 的 selection 唤起系统菜单，覆盖 API 20 基线。
        this.timer = setTimeout((): void => {
          this.timer = -1;
          this.selectionEnd = this.text.length;
        }, 0);
      })
  }
}
