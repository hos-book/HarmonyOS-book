import { ReaderFloatingService, ReaderFloatingState } from '../service/text/ReaderFloatingService';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct ReaderFloatingLyrics {
  @Param systemWindow: boolean = false;
  @Local state: ReaderFloatingState = ReaderFloatingService.state;
  @Local dragX: number = 0;
  @Local dragY: number = 0;
  private startX: number = 0;
  private startY: number = 0;

  build() {
    if (this.systemWindow || (this.state.visible && !this.state.native)) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.state.title).fontSize(12).fontColor('#CCFFFFFF').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (!this.systemWindow) {
            Button($r('app.string.tts_close')).fontSize(12).height(28).fontColor('#FFFFFF')
              .backgroundColor(Color.Transparent).onClick((): void => { ReaderFloatingService.close(); })
          }
        }.width('100%')
        Scroll() {
          Text(this.state.paragraph).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFF4DB')
            .textAlign(TextAlign.Center).width('100%').lineHeight(27)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
      .width(this.systemWindow ? '100%' : '88%').height(this.systemWindow ? '100%' : 144)
      .constraintSize({ maxWidth: this.systemWindow ? undefined : 520 })
      .padding({ left: 18, right: this.systemWindow ? 44 : 12, top: 10, bottom: 12 })
      .backgroundColor('#E6222226').borderRadius(20).clip(true)
      .border({ width: 0.5, color: AppColor.Brand })
      .translate({ x: this.systemWindow ? 0 : this.dragX, y: this.systemWindow ? 0 : this.dragY })
      .gesture(PanGesture().onActionStart((): void => {
        this.startX = this.dragX; this.startY = this.dragY;
      }).onActionUpdate((event: GestureEvent): void => {
        if (this.systemWindow) return;
        this.dragX = Math.max(-24, Math.min(24, this.startX + event.offsetX));
        this.dragY = Math.max(-160, Math.min(160, this.startY + event.offsetY));
      }))
    }
  }
}
