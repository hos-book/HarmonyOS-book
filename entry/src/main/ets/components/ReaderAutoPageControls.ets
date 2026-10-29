import { ImmersiveActionButton } from './ImmersiveActionButton';
import { ImmersiveCircleButton } from './ImmersiveCircleButton';

@ComponentV2
export struct ReaderAutoPageControls {
  @Param paused: boolean = false;
  @Param scrolling: boolean = false;
  @Event onToggle: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      ImmersiveActionButton({
        label: this.paused ? $r('app.string.reader_auto_page_resume') : $r('app.string.reader_auto_page_pause'),
        buttonHeight: 40,
        onPress: (): void => this.onToggle()
      }).width(88).id('reader-auto-page-toggle')
      ImmersiveCircleButton({
        icon: $r('sys.symbol.xmark'), iconSize: 18, diameter: 40,
        label: this.scrolling ? $r('app.string.reader_auto_scroll_stop') : $r('app.string.reader_auto_page_stop'),
        onPress: (): void => this.onClose()
      }).id('reader-auto-page-close')
    // Default 允许子按钮命中并阻挡底层正文；Block 会连子按钮一起屏蔽。
    }.width(136).height(40).hitTestBehavior(HitTestMode.Default)
  }
}
