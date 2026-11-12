import { AppBackgroundConfig, AppBackgroundScene } from '../model/AppBackground';
import { AppBackgroundService } from '../service/AppBackgroundService';
import { AppTheme } from '../theme/Theme';

/** App 主页面的自选背景。草稿以 config 显式传入，不写入共享状态。 */
@ComponentV2
export struct AppBackgroundLayerComponent {
  @Param scene: AppBackgroundScene = AppBackgroundScene.Home;
  @Param config: AppBackgroundConfig | undefined = undefined;
  @Param preview: boolean = false;
  @Local backgrounds: AppBackgroundService = AppBackgroundService.instance;
  @Local viewportWidth: number = 1;
  @Local viewportHeight: number = 1;
  @Local sourceWidth: number = 1;
  @Local sourceHeight: number = 1;

  @Computed
  private get selectedConfig(): AppBackgroundConfig {
    // revision 是唯一共享发布点；拖动草稿滑杆只替换显式 config。
    return this.backgrounds.revision >= 0 ? this.config ?? this.backgrounds.resolve(this.scene) :
      new AppBackgroundConfig();
  }

  @Computed
  private get imageSource(): string {
    return this.backgrounds.resolveImage(this.selectedConfig) ?? '';
  }

  private imageWidth(): number {
    const bleed: number = this.selectedConfig.blur * 2;
    const fit: number = Math.max((this.viewportWidth + bleed * 2) / this.sourceWidth,
      (this.viewportHeight + bleed * 2) / this.sourceHeight);
    return this.sourceWidth * fit * this.selectedConfig.scale / 100;
  }

  private imageHeight(): number {
    const bleed: number = this.selectedConfig.blur * 2;
    const fit: number = Math.max((this.viewportWidth + bleed * 2) / this.sourceWidth,
      (this.viewportHeight + bleed * 2) / this.sourceHeight);
    return this.sourceHeight * fit * this.selectedConfig.scale / 100;
  }

  private imageX(): number {
    const bleed: number = this.selectedConfig.blur * 2;
    return -bleed + (this.viewportWidth + bleed * 2 - this.imageWidth()) *
      this.selectedConfig.positionX / 100;
  }

  private imageY(): number {
    const bleed: number = this.selectedConfig.blur * 2;
    return -bleed + (this.viewportHeight + bleed * 2 - this.imageHeight()) *
      this.selectedConfig.positionY / 100;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.selectedConfig.preset !== 'theme') {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.selectedConfig.preset === 'image' && this.imageSource.length > 0) {
            ForEach([this.imageSource], (source: string) => {
              Image(source).width(this.imageWidth()).height(this.imageHeight())
                .objectFit(ImageFit.Fill).autoResize(true)
                .position({ x: this.imageX(), y: this.imageY() })
                .blur(this.selectedConfig.blur)
                .onComplete((event) => {
                  if (source !== this.imageSource || !event || event.width <= 0 || event.height <= 0) return;
                  if (event.width !== this.sourceWidth || event.height !== this.sourceHeight) {
                    this.sourceWidth = event.width;
                    this.sourceHeight = event.height;
                  }
                })
            }, (source: string): string => source)
          } else if (this.selectedConfig.preset === 'mist') {
            Column().width('100%').height('100%')
              .linearGradient({ angle: 160, colors: [
                [$r('app.color.app_background_mist_top'), 0],
                [$r('app.color.app_background_mist_mid'), 0.58],
                [$r('app.color.app_background_mist_bottom'), 1]
              ] })
          } else if (this.selectedConfig.preset === 'paper') {
            Column().width('100%').height('100%')
              .linearGradient({ angle: 150, colors: [
                [$r('app.color.app_background_paper_top'), 0],
                [$r('app.color.app_background_paper_mid'), 0.6],
                [$r('app.color.app_background_paper_bottom'), 1]
              ] })
          }
        }.width('100%').height('100%').clip(true)
          .backgroundColor(AppTheme.Background)
        // 资源自身随深浅色更新，夜间遮罩不依赖非响应式系统模式判断。
        Column().width('100%').height('100%')
          .backgroundColor($r('app.color.app_background_night_scrim'))
        Column().width('100%').height('100%')
          .backgroundColor($r('app.color.app_background_veil')).opacity(this.selectedConfig.veil / 100)
      }
    }.width('100%').height('100%').clip(true)
      .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no')
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        const width: number = Number(size.width);
        const height: number = Number(size.height);
        if (Number.isFinite(width) && width > 0) this.viewportWidth = width;
        if (Number.isFinite(height) && height > 0) this.viewportHeight = height;
      })
      .expandSafeArea(this.preview ? [] : [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        this.preview ? [] : [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
