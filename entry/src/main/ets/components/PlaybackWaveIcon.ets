/** 原生缩放动画，仅在播放且图标可见时运行，不采样或处理音频。 */
@ComponentV2
export struct PlaybackWaveIcon {
  @Param playing: boolean = false;
  @Local visible: boolean = false;

  aboutToDisappear(): void { this.visible = false; }

  build() {
    Stack() {
      Row({ space: 1.5 }) {
        ForEach([0, 1, 2, 3, 4], (bar: number) => {
          Column().width(2).height(bar === 2 ? 13 : (bar % 2 === 0 ? 6 : 10))
            .backgroundColor(Color.White).borderRadius(1)
            .scale({ y: this.playing && this.visible ? (bar % 2 === 0 ? 0.35 : 1.3) : 1 })
            .animation({ duration: this.playing && this.visible ? 360 + bar * 85 : 0,
              iterations: this.playing && this.visible ? -1 : 1,
              playMode: PlayMode.Alternate, curve: Curve.EaseInOut })
        }, (bar: number): string => `wave-${bar}`)
      }.alignItems(VerticalAlign.Center)
    }.width(24).height(24).borderRadius(12).border({ width: 1.6, color: Color.White })
      .hitTestBehavior(HitTestMode.None)
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
  }
}
