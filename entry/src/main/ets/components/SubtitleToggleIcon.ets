/** 字幕开启时循环上移横条，边框保持静止；隐藏后停止动画。 */
@ComponentV2
export struct SubtitleToggleIcon {
  @Param active: boolean = false;
  @Local visible: boolean = false;

  aboutToDisappear(): void { this.visible = false; }

  build() {
    Stack() {
      Stack({ alignContent: Alignment.Top }) {
        Column({ space: 4.2 }) {
          ForEach([0, 1, 2], (_line: number) => {
            Row({ space: 2 }) {
              Column().width(5).height(1.8).borderRadius(0.9).backgroundColor(Color.White)
              Column().width(4).height(1.8).borderRadius(0.9).backgroundColor(Color.White)
            }.height(1.8)
          }, (line: number): string => `subtitle-line-${line}`)
        }.width(11).height(13.8)
        .translate({ y: this.active && this.visible ? -6 : 0 })
        .animation({ duration: this.active && this.visible ? 1200 : 0,
          iterations: this.active && this.visible ? -1 : 1,
          playMode: PlayMode.Normal, curve: Curve.Linear })
      }.width(11).height(7.8).clip(true)
    }.width(20).height(16).borderRadius(3).border({ width: 1.8, color: Color.White })
      .hitTestBehavior(HitTestMode.None)
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
  }
}
