import { AppTheme } from '../theme/Theme';
import { ThemeBackgroundKind, ThemeBackgroundScene } from '../model/AppThemeVisual';
import { AppBackgroundScene } from '../model/AppBackground';
import { AppBackgroundLayerComponent } from './AppBackgroundLayerComponent';
import { ThemeBackdropComponent } from './ThemeBackdropComponent';
import { AppAppearance } from '../model/AppAppearance';

/** 同一背景解析用于页面与候选预览；显式 id 不会修改全局外观。 */
@ComponentV2
export struct ThemeBackgroundComponent {
  @Param warmMid: number = 0.35;
  @Param themeBundleId: string = '';
  @Param preview: boolean = false;
  @Param scene: ThemeBackgroundScene = ThemeBackgroundScene.Home;
  /** 仅主页面显式启用自选背景；套装候选预览仍使用其自身资源。 */
  @Param appScene: AppBackgroundScene | undefined = undefined;

  private sceneName(): string {
    if (this.appScene === AppBackgroundScene.Profile) return 'profile';
    if (this.scene === ThemeBackgroundScene.Shelf) return 'shelf';
    if (this.scene === ThemeBackgroundScene.Record) return 'record';
    return 'home';
  }

  build() {
    Stack() {
      if (AppTheme.resolve(this.themeBundleId).visual.background.kind === ThemeBackgroundKind.Image) {
        Image(AppTheme.resolve(this.themeBundleId).visual.background.resolveImage(this.scene) ?? '')
          .width('100%').height('100%').objectFit(ImageFit.Cover)
          .opacity(AppTheme.resolve(this.themeBundleId).visual.background.imageOpacity)
      } else if (!this.preview &&
        AppTheme.resolve(this.themeBundleId).visual.background.kind === ThemeBackgroundKind.Gradient) {
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeTop, 0],
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeMid, this.warmMid],
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeBottom, 1]
          ] })
      }
      if (AppTheme.pageBackground(this.sceneName(), this.themeBundleId).mode !== 'theme') {
        ThemeBackdropComponent({ backdrop: AppTheme.pageBackground(this.sceneName(), this.themeBundleId),
          night: AppAppearance.current.darkMode })
      } else if (AppAppearance.current.useLegacyThemeOverrides && !AppTheme.resolve(this.themeBundleId).custom &&
        !this.preview && this.themeBundleId.length === 0 && this.appScene !== undefined) {
        AppBackgroundLayerComponent({ scene: this.appScene })
      }
    }.width('100%').height('100%')
      .backgroundColor(AppTheme.resolve(this.themeBundleId).visual.colors.background)
      .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no')
      .expandSafeArea(this.preview ? [] : [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        this.preview ? [] : [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
