import { FavoritePage } from './FavoritePage';
import { ThemeBackgroundComponent } from '../components/ThemeBackgroundComponent';
import { ThemeBackgroundScene } from '../model/AppThemeVisual';
import { AppBackgroundScene } from '../model/AppBackground';
import { ShelfCollectionRoute } from '../model/ShelfCollection';
import { GeneralSettings } from '../model/GeneralSettings';
import { PreferenceService } from '../service/PreferenceService';
import { AppTheme } from '../theme/Theme';
import { OneShotLayoutCallback } from '../utils/OneShotTransition';
import { WindowUtils } from '../utils/WindowUtils';

/** 导航栈中的分组弹层：读听页覆盖它，返回直接恢复原来的列表与封面位置。 */
@ComponentV2
export struct ShelfCollectionPage {
  @Param route: ShelfCollectionRoute = new ShelfCollectionRoute('');
  @Param navStack: NavPathStack = new NavPathStack();
  @Param active: boolean = true;
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Local expanded: boolean = GeneralSettings.current.shelfCollectionExpanded;
  @Local shown: boolean = false;
  @Local widthVp: number = 400;
  @Local heightVp: number = 800;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  private contentBack: (() => boolean) | undefined = undefined;
  private alive: boolean = false;
  private closing: boolean = false;
  private safeAreaListener: (top: number, bottom: number) => void = (top: number, _bottom: number): void => {
    this.topSafe = top;
  };

  aboutToAppear(): void {
    this.alive = true;
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange((): boolean => { this.close(); return true; });
    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
      if (!this.alive) return;
      this.getUIContext().animateTo({ duration: 380, curve: Curve.FastOutSlowIn }, (): void => { this.shown = true; });
    }));
  }

  aboutToDisappear(): void {
    this.alive = false;
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange(undefined);
  }

  private close(): void {
    if (this.closing || !this.active) return;
    if (this.contentBack?.()) return;
    this.closing = true;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.FastOutSlowIn, onFinish: (): void => {
      if (this.alive) this.navStack.pop(false);
    } }, (): void => { this.shown = false; });
  }

  private expand(): void {
    if (this.closing) return;
    const expanded = !this.expanded;
    this.getUIContext().animateTo({ duration: 380, curve: Curve.FastOutSlowIn }, (): void => {
      this.expanded = expanded;
    });
    PreferenceService.setShelfCollectionExpanded(expanded).catch((): void => {
      if (!this.alive) return;
      this.expanded = GeneralSettings.current.shelfCollectionExpanded;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.common_save_failed') });
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height('100%').backgroundColor('#520D1510')
        .opacity(this.shown ? 1 : 0).onClick((): void => this.close())
        .accessibilityLevel('no')
      Stack({ alignContent: Alignment.Top }) {
        ThemeBackgroundComponent({ scene: ThemeBackgroundScene.Shelf, appScene: AppBackgroundScene.Shelf })
        FavoritePage({ collectionGroup: this.route.group, hiddenShelf: this.route.hidden, collectionExpanded: this.expanded,
          visible: this.active, historyEnabled: GeneralSettings.current.historyEnabled,
          navStack: this.navStack, bottomTabInset: 16,
          onCollectionClose: (): void => this.close(), onCollectionExpand: (): void => this.expand(),
          onCollectionDragEnd: (offsetY: number): void => {
            if (offsetY < -28 && !this.expanded) this.expand();
            else if (offsetY > 40) { if (this.expanded) this.expand(); else this.close(); }
          },
          onBookTap: (id: string): void => { this.navStack.pushPathByName('detail', id); },
          onBackHandlerChange: (handler: (() => boolean) | undefined): void => { this.contentBack = handler; } })
      }.width(this.expanded ? this.widthVp : Math.min(720, this.widthVp))
        .height(this.expanded ? Math.max(160, this.heightVp - this.topSafe) : this.heightVp * 0.8)
        .backgroundColor(AppTheme.Background).borderRadius({ topLeft: this.expanded ? 20 : 32, topRight: this.expanded ? 20 : 32 })
        .clip(true).translate({ y: this.shown ? 0 : 96 }).opacity(this.shown ? 1 : 0)
        .id('shelf-collection-panel')
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number' && size.width > 0) this.widthVp = size.width;
        if (typeof size.height === 'number' && size.height > 0) this.heightVp = size.height;
      })
  }
}
