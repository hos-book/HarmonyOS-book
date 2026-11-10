/** 致谢页的原生星轨：只动画化合成属性，离屏和后台由宿主控停。 */
@ComponentV2
export struct SupportOrbitComponent {
  @Param running: boolean = true;
  @Param golden: boolean = false;
  @Param compact: boolean = false;
  @Local orbitAngle: number = 0;
  @Local glowPhase: number = 0;
  private mounted: boolean = false;
  private visible: boolean = false;
  private animating: boolean = false;

  @Monitor('running')
  onRunningChanged(): void {
    this.updateMotion();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.animating = false;
  }

  private updateMotion(): void {
    if (!this.mounted) return;
    const next: boolean = this.running && this.visible;
    if (next === this.animating) return;
    this.animating = next;
    if (!next) {
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.orbitAngle = 0;
        this.glowPhase = 0;
      });
      return;
    }
    this.getUIContext().animateTo({ duration: 18000, curve: Curve.Linear, iterations: -1 }, (): void => {
      this.orbitAngle = 360;
    });
    this.getUIContext().animateTo({ duration: 2600, curve: Curve.EaseInOut,
      iterations: -1, playMode: PlayMode.Alternate }, (): void => {
      this.glowPhase = 1;
    });
  }

  @Builder
  orbitRing(gold: boolean) {
    Stack() {
      Stack() {
        Row().borderRadius(999).width(184).height(184).backgroundColor(Color.Transparent)
          .border({ width: 0.8, color: gold ? '#55E8C782' : '#5563DCD4' })
        Row().borderRadius(999).width(6).height(6).backgroundColor(gold ? '#F8D995' : '#8EF5E7')
          .shadow({ radius: 10, color: gold ? '#B3E8C782' : '#B363DCD4' })
          .translate({ x: 92 })
        Row().borderRadius(999).width(3).height(3).backgroundColor(gold ? '#E8C782' : '#63DCD4')
          .translate({ x: -92 })
      }
      .width(196).height(196)
      .rotate({ angle: gold ? -this.orbitAngle : this.orbitAngle })
      .scale({ x: 1, y: gold ? 0.48 : 0.62 })
    }
    .width(196).height(196)
    .rotate({ angle: gold ? -32 : 34 })
  }

  build() {
    Stack() {
      Row().borderRadius(999).width(224).height(224)
        .radialGradient({ center: ['50%', '50%'], radius: 112,
          colors: [[this.golden ? '#48D6AD66' : '#404ABBB3', 0], ['#00FFFFFF', 1]] })
        .scale({ x: 0.85 + this.glowPhase * 0.15, y: 0.85 + this.glowPhase * 0.15 })
        .opacity(0.65 + this.glowPhase * 0.35)
      this.orbitRing(false)
      this.orbitRing(true)
      Row().borderRadius(999).width(100).height(100).backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.golden ? '#30E8C782' : '#3063DCD4' })
        .scale({ x: 1 + this.glowPhase * 0.18, y: 1 + this.glowPhase * 0.18 })
      Stack() {
        Row().borderRadius(999).width(76).height(76)
          .linearGradient({ angle: 145, colors: [[this.golden ? '#705E3B' : '#225650', 0], ['#14292E', 1]] })
          .border({ width: 1, color: this.golden ? '#88E8C782' : '#8863DCD4' })
          .shadow({ radius: 24, color: this.golden ? '#40D6AD66' : '#405ACABD' })
        SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(30)
          .fontColor([this.golden ? '#F4D997' : '#B9F6E9'])
      }
      .translate({ y: -3 + this.glowPhase * 6 })
      .scale({ x: 1 + this.glowPhase * 0.05, y: 1 + this.glowPhase * 0.05 })
      Row().borderRadius(999).width(3).height(3).backgroundColor('#D9F4EF').translate({ x: -86, y: -63 })
      Row().borderRadius(999).width(2).height(2).backgroundColor('#E8C782').translate({ x: 71, y: -81 })
      Row().borderRadius(999).width(3).height(3).backgroundColor('#D9F4EF').translate({ x: 89, y: 59 })
      Row().borderRadius(999).width(2).height(2).backgroundColor('#E8C782').translate({ x: -58, y: 75 })
    }
    .width(240).height(this.compact ? 156 : 208)
    .scale({ x: this.compact ? 0.8 : 1, y: this.compact ? 0.8 : 1 })
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
    .onAppear((): void => { this.mounted = true; this.updateMotion(); })
    .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number): void => {
      this.visible = visible && ratio > 0;
      this.updateMotion();
    })
  }
}
