import { common } from '@kit.AbilityKit';
import { StartupSplash } from '../components/StartupSplash';
import { image } from '@kit.ImageKit';
import { MainPage } from './MainPage';
import { HiCarPage } from './HiCarPage';
import { HiCarState } from '../model/HiCar';
import { HiCarService } from '../service/HiCarService';
import { WebEngineGate } from '../service/WebEngineGate';
import { WebBookFetchRuntimeHost } from '../service/rulesource/light/WebBookFetchRuntimeHost';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';
import { BookDetailPage, DetailBackInterceptor, DetailTitleBarActions, DetailTitleBarState } from './BookDetailPage';
import { PlayerPage, PlayerBackInterceptor, PlayerEntryDecider } from './PlayerPage';
import { SettingsPage } from './SettingsPage';
import { ReadingSettingsPage } from './ReadingSettingsPage';
import { VoiceManagementPage } from './VoiceManagementPage';
import { FontManagementPage } from './FontManagementPage';
import { SpeechDisplaySettingsPage } from './SpeechDisplaySettingsPage';
import { DialogueHighlightSettingsPage } from './DialogueHighlightSettingsPage';
import { SpeechSynthesisSettingsPage } from './SpeechSynthesisSettingsPage';
import { RoleSpeechSettingsPage } from './RoleSpeechSettingsPage';
import { RoleModelSettingsPage } from './RoleModelSettingsPage';
import { MembershipPage } from './MembershipPage';
import { MembershipSubscriptionPage } from './MembershipSubscriptionPage';
import { MembershipState } from '../model/MembershipState';
import { AboutPage } from './AboutPage';
import { TechnicalSupportPage } from './TechnicalSupportPage';
import { AccountPage } from './AccountPage';
import { AchievementPage } from './AchievementPage';
import { GuidePage } from './GuidePage';
import { ImportPage } from './ImportPage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { SessionHistoryPage } from './SessionHistoryPage';
import { UnfavoritedHistoryPage } from './UnfavoritedHistoryPage';
import { PrivacyPage } from './PrivacyPage';
import { CompliancePage } from './CompliancePage';
import { OpenSourcePage } from './OpenSourcePage';
import { BlockMorePage } from './BlockMorePage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { LogManagementPage } from './LogManagementPage';
import { ComicReaderPage } from './ComicReaderPage';
import { ReaderPage } from './ReaderPage';
import { SearchPage } from './SearchPage';
import { RuleSourcePage } from './RuleSourcePage';
import { RuleSourceLoginPage } from './RuleSourceLoginPage';
import { RuleSourceEditPage } from './RuleSourceEditPage';
import { RuleSourceDebugPage } from './RuleSourceDebugPage';
import { RuleSourcePanelPage } from './RuleSourcePanelPage';
import { TextReaderRouteParams } from '../model/TextReading';
import { ShelfReaderOpenSurface } from '../components/ShelfReaderOpenSurface';
import { ShelfReaderOpenState, ShelfReaderRouteParams } from '../utils/ShelfReaderTransition';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleBrowserLoginCoordinator } from '../service/rulesource/LocalRuleBrowserLoginCoordinator';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_WIDGET_ROUTE, KEY_WIDGET_ROUTE, WidgetRoute } from '../entryability/EntryAbility';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsCompat } from '../utils/HdsCompat';
import { AppRadius, AppTheme, AppMotion, AppCurve } from '../theme/Theme';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { WindowUtils } from '../utils/WindowUtils';
import { JianjianCompanionComponent } from '../components/JianjianCompanionComponent';
import { JianjianAiSettingsPage } from './JianjianAiSettingsPage';
import { JianjianSettingsPage } from './JianjianSettingsPage';
import { JianjianPromptSettingsPage } from './JianjianPromptSettingsPage';
import { JianjianChatPage } from './JianjianChatPage';
import { JianjianCompanionService } from '../service/JianjianCompanionService';
import { JianjianCareService } from '../service/JianjianCareService';
import { JianjianChatRoute } from '../model/JianjianAi';
import { GeneralSettings } from '../model/GeneralSettings';
import { EVT_JIANJIAN_COMPANION_CHANGED } from '../service/PreferenceService';
import { PlatformCompat } from '../utils/PlatformCompat';
import { ReadingExcerptPage } from './ReadingExcerptPage';
import { ReadingExcerptDetailPage } from './ReadingExcerptDetailPage';
import { ReadingExcerptRoute } from '../model/ReadingExcerptRoute';
import { ReadingExcerpt } from '../model/ReadingExcerpt';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { LocalImportRouteParams } from '../utils/FileOpenRouting';
import { RuleSourceImportQueue } from '../service/rulesource/RuleSourceImportQueue';
import {
  BookOneShotPayload,
  NavigationOneShotRunner,
  OneShotLayoutCallback,
  OneShotRect,
  OneShotTransitionCoordinator,
  OneShotTransitionIds
} from '../utils/OneShotTransition';

interface WidgetRouteEvent {
  target: string;
  bookId: string;
  fileType?: string;
  ts?: number;
}

@Entry
@ComponentV2
struct Index {
  @Local hiCarState: HiCarState = HiCarService.instance.state;
  private hiCarBackHandler: (() => boolean) | undefined = undefined;
  private manualCarBackHandler: (() => boolean) | undefined = undefined;
  @Local showStartupSplash: boolean = !AppStorage.get<boolean>('gelStartupSplashShown');
  @Local companionEnabled: boolean = GeneralSettings.current.jianjianCompanionEnabled;
  private readonly companionChangedListener: () => void = (): void => {
    this.getUIContext().runScopedTask((): void => {
      this.companionEnabled = GeneralSettings.current.jianjianCompanionEnabled;
      if (this.companionEnabled) this.companionTemporarilyHidden = false;
    });
  };
  @Local companionActive: boolean = true;
  @Local companionRoute: string = '';
  @Local companionQuiet: boolean = false;
  @Local companionTemporarilyHidden: boolean = false;
  @Local navStack: NavPathStack = new NavPathStack();
  @Local navigationWidth: number = 0;
  @Local parallelNavigation: boolean = false;
  @Local playerRenderGroup: boolean = false;
  @Local playerOpacity: number = 1;
  @Local playerDragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local navigationEnabled: boolean = true;
  @Local detailOpaqueBackground: boolean = true;
  @Local homeCoveredByDetail: boolean = false;
  /**
   * 详情页正文滚动控制器。交给详情 NavDestination 的 bindToScrollable，
   * HDS 才能按滚动量在顶栏绘制沉浸渐变模糊（详情页顶栏的光感就靠这一条）。
   */
  @Local detailScroller: Scroller = new Scroller();
  /**
   * 详情页收藏态。
   * HDS 标题栏内容是一次性渲染的独立子树，详情页把状态写进 DetailTitleBarState
   * 并不会让标题栏里的组件重新 build，所以这里镜像一份 @Local：
   * 桥上的 @Trace 一变就改这个值，Index 重新 build → titleBar 的 stackBuilder 重跑 → 图标刷新。
   */
  @Local titleBarBridge: DetailTitleBarState = DetailTitleBarState.get();
  @Local detailFavorite: boolean = false;
  @Local detailTitleOpacity: number = 1;
  private widgetSubscribed: boolean = false;
  @Local companionCarePulse: number = 0;
  private careTimer: number = -1;
  private careForegroundSince: number = 0;
  private homeBackHandler: (() => boolean) | undefined = undefined;
  private statsBackHandler: (() => boolean) | undefined = undefined;
  private historyBackHandler: (() => boolean) | undefined = undefined;
  private homeShownHandler: (() => void) | undefined = undefined;
  /** 已消费过的路由 ts，避免冷启动时 AppStorage + emitter 两条路径同时触发同一个 push */
  private lastConsumedRouteTs: number = 0;
  private browserLoginOpener: (route: RuleSourceLoginRouteParams) => void = (route: RuleSourceLoginRouteParams): void => {
    this.navStack.pushPathByName('ruleSourceLogin', route);
  };

  aboutToAppear(): void {
    AppStorage.setOrCreate<boolean>('gelStartupSplashShown', true);
    this.companionEnabled = GeneralSettings.current.jianjianCompanionEnabled;
    emitter.on(EVT_JIANJIAN_COMPANION_CHANGED, this.companionChangedListener);
    // 详情页顶栏（HDS 标题栏内容）不是本组件的常规子树，收不到外部 @ObservedV2 的刷新，
    // 只能由这里在被通知后改自己的 @Local，重跑 titleBar 的 stackBuilder 来刷新。
    this.titleBarBridge.onChanged = (): void => {
      this.detailFavorite = this.titleBarBridge.isFavorite;
    };
    // 首页常驻原生 NavBar；只切换布局，不搬移/重建首页和目的页。
    this.navStack.setInterception({
      willShow: (): void => { this.updateNavigationLayout(); },
      didShow: (): void => {
        this.updateNavigationLayout();
        this.syncReaderWindowMode();
      }
    });
    LocalRuleBrowserLoginCoordinator.bindNavigation(this.browserLoginOpener);

    this.consumePendingWidgetRoute();
    if (!this.widgetSubscribed) {
      emitter.on(EVT_WIDGET_ROUTE, (data) => {
        const ev = data.data as WidgetRouteEvent | undefined;
        if (!ev) return;
        // 同一次卡片点击会走 AppStorage（冷启动） + emitter（热启动）两条路径，
        // 用 ts 去重，避免同一份 want 被压栈两次产生空白页 / 重叠 PlayerPage。
        const ts = ev.ts ?? 0;
        if (ts > 0 && ts === this.lastConsumedRouteTs) return;
        this.lastConsumedRouteTs = ts;
        AppStorage.setOrCreate<WidgetRoute | undefined>(KEY_WIDGET_ROUTE, undefined);
        this.handleWidgetRoute(ev.target, ev.bookId, ev.fileType ?? '');
      });
      this.widgetSubscribed = true;
    }
  }

  aboutToDisappear(): void {
    this.stopNightCare();
    emitter.off(EVT_JIANJIAN_COMPANION_CHANGED, this.companionChangedListener);
    LocalRuleBrowserLoginCoordinator.unbindNavigation(this.browserLoginOpener);
    if (this.widgetSubscribed) {
      try {
        emitter.off(EVT_WIDGET_ROUTE);
      } catch (_e) { /* ignore */ }
      this.widgetSubscribed = false;
    }
  }

  onPageShow(): void {
    this.companionActive = true;
    this.startNightCare();
  }

  onPageHide(): void {
    this.companionActive = false;
    this.stopNightCare();
    PlayerDragTransition.getInstance().cancel();
  }

  private startNightCare(): void {
    this.stopNightCare();
    this.careForegroundSince = Date.now();
    this.careTimer = setInterval((): void => { this.checkNightCare(); }, 30000);
  }

  private stopNightCare(): void {
    if (this.careTimer !== -1) clearInterval(this.careTimer);
    this.careTimer = -1;
    this.careForegroundSince = 0;
  }

  private nightCareEligible(): boolean {
    return !this.hiCarState.carWindow && this.companionRoute !== 'hicar' &&
      this.companionActive && this.companionEnabled && !this.companionTemporarilyHidden &&
      GeneralSettings.current.jianjianNightCareEnabled && this.careForegroundSince > 0 &&
      Date.now() - this.careForegroundSince >= 30000 && !this.showStartupSplash &&
      !['ruleSourceLogin', 'jianjianSettings', 'jianjianAiSettings', 'jianjianPromptSettings'].includes(this.companionRoute);
  }

  private async checkNightCare(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.nightCareEligible()) return;
    if (!await JianjianCareService.claim(context, new Date(), (): boolean => this.nightCareEligible())) return;
    if (this.companionQuiet) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.jianjian_night_toast'), duration: 5000 });
    } else this.companionCarePulse++;
  }

  private updateNavigationLayout(): void {
    const paths: string[] = this.navStack.getAllPathName();
    this.companionRoute = paths.length > 0 ? paths[paths.length - 1] : '';
    this.companionQuiet = this.companionRoute === 'hicar' || JianjianCompanionService.quietRoute(this.companionRoute);
    this.parallelNavigation = AdaptiveLayout.navigationUsesColumns(
      this.navigationWidth, this.navStack.getAllPathName());
    if (this.parallelNavigation || this.navStack.size() === 0) this.homeCoveredByDetail = false;
  }

  onBackPress(): boolean {
    if (this.hiCarState.carWindow) {
      if (this.hiCarBackHandler?.()) return true;
      HiCarService.instance.minimize();
      return true;
    }
    if (this.playerDragState.previewing) {
      PlayerDragTransition.getInstance().cancel();
      return true;
    }
    if (this.navStack.size() > 0) return false;
    if (this.homeBackHandler?.()) return true;
    if (PlatformCompat.desktopWindow) {
      WindowUtils.minimize();
      return true;
    }
    // 根页返回仅移到后台，保留首页状态。
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.moveAbilityToBackground();
      return true;
    } catch (e) {
      console.error(`[Index] moveAbilityToBackground error: ${e}`);
      return false;
    }
  }

  private resolveParam(param: object | null | undefined, key: string): string {
    // 首页搜索等无参入口会传入 null，必须在读取关键词等字段前返回默认值。
    if (param === null || param === undefined || typeof param === 'string') return '';
    const r = param as Record<string, Object>;
    const v = r[key];
    return typeof v === 'string' ? v : '';
  }

  private syncReaderWindowMode(): void {
    // onHidden 也会在退后台触发；阅读路由仍在栈顶时保留系统栏和安全区。
    const paths: string[] = this.navStack.getAllPathName();
    WindowUtils.setReaderActive(!this.hiCarState.carWindow && paths.length > 0 &&
      (paths[paths.length - 1] === 'reader' || paths[paths.length - 1] === 'comicReader'));
  }

  /** EntryAbility.onCreate 写入路由后,Index 首次挂载时消费一次 */
  private consumePendingWidgetRoute(): void {
    const r = AppStorage.get<WidgetRoute>(KEY_WIDGET_ROUTE);
    if (!r) return;
    AppStorage.setOrCreate<WidgetRoute | undefined>(KEY_WIDGET_ROUTE, undefined);
    this.lastConsumedRouteTs = r.ts ?? 0;
    this.handleWidgetRoute(r.target, r.bookId ?? '', r.fileType ?? '');
  }

  private handleWidgetRoute(target: string, bookId: string, fileType: string = ''): void {
    if (target === 'localBookImport') {
      this.navStack.pushPathByName('import', new LocalImportRouteParams(bookId, fileType), false);
      return;
    }
    if (target === 'ruleSourceImport') {
      RuleSourceImportQueue.getInstance().open(this.navStack, bookId);
      return;
    }
    if (target === 'resume') {
      // 软拉起:对齐控制中心交互——只把应用拉到前台,
      // 用户停留在哪个页就保留哪个页,不强制跳到 PlayerPage。
      return;
    }
    if (target === 'player') {
      if (bookId && bookId.length > 0) {
        // 外部续播重复到达时不再压入第二份播放页。
        const cur = this.navStack.getAllPathName();
        if (cur && cur.length > 0 && cur[cur.length - 1] === 'player') return;
        // 首页迁入 NavBar 后不能再依赖旧 geometryTransition 自动匹配封面。
        // 等首帧布局，沿用从底部播控展开的效果，并记录当前窗口里的实际起点。
        this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
          const paths = this.navStack.getAllPathName();
          if (paths.length > 0 && paths[paths.length - 1] === 'player') return;
          if (paths.length === 0) {
            const transition = PlayerDragTransition.getInstance();
            const origin = transition.capture(this.getUIContext());
            if (origin !== undefined) transition.beginTap(origin);
          }
          this.navStack.pushPathByName('player', bookId);
        }));
      }
      // 无 bookId 时停在主页,避免黑屏
    } else if (target === 'reader' || target === 'comicReader') {
      if (!bookId) return;
      const paths = this.navStack.getAllPathName();
      const last = paths.length - 1;
      if (last >= 0 && paths[last] === target) {
        this.navStack.replacePath({ name: target, param: TextReaderRouteParams.of(bookId) }, false);
        return;
      }
      this.navStack.pushPathByName(target, TextReaderRouteParams.of(bookId), false);
    } else if (target === 'detail') {
      if (bookId) this.navStack.pushPathByName('detail', bookId, false);
    } else if (target === 'downloads') {
      const cur = this.navStack.getAllPathName();
      if (cur && cur.length > 0 && cur[cur.length - 1] === 'downloads') return;
      this.navStack.pushPathByName('downloads', null, false);
    }
    // target === 'home' 默认停在 Tab,不需要跳转
  }

  private oneShotNavigationTransition(from: NavContentInfo, to: NavContentInfo,
    operation: NavigationOperation): NavigationAnimatedTransition | undefined {
    if (operation === NavigationOperation.PUSH && to.name === 'reader' &&
      to.param instanceof ShelfReaderRouteParams && to.param.opening.active) {
      OneShotTransitionCoordinator.getInstance().discardPending();
      return to.param.opening.navigationTransition(this.getUIContext());
    }
    if (operation === NavigationOperation.POP && from.name === 'player' &&
      (this.navStack.size() === 0 || PlayerDragTransition.getInstance().canReturnTo(to.name ?? ''))) {
      const drag = PlayerDragTransition.getInstance();
      let finished: boolean = false;
      const animation: NavigationAnimatedTransition = {
        timeout: 1400,
        transition: (proxy: NavigationTransitionProxy): void => {
          this.navigationEnabled = false;
          this.playerRenderGroup = false;
          this.playerOpacity = 1;
          PlayerEntryDecider.markLeaving();
          // POP 后先让来源页恢复布局，再测详情封面或首页播控，不复用入场旧坐标。
          this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
            if (finished) return;
            this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
              if (finished) return;
              // 下拖确认时保留手指位置，不能重新把播放页重置到全屏。
              const origin = drag.state.dismissing ? drag.captureReturnTarget(this.getUIContext())
                : drag.prepareReturn(this.getUIContext());
              this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
                if (finished) return;
                this.getUIContext().animateTo({
                  curve: AppCurve.PlayerCollapse,
                  onFinish: (): void => { if (!finished) proxy.finishTransition(); }
                }, (): void => {
                  if (origin === undefined) this.playerOpacity = 0;
                  else drag.collapseToBar(origin, false);
                });
                // 正文先收起，避免文字与播控一路挤进来源封面；几何完成后再结束导航。
                this.getUIContext().animateTo({ duration: AppMotion.Fast, curve: AppCurve.Accelerate },
                  (): void => { this.playerDragState.contentOpacity = 0; });
              }));
            }));
          }));
        },
        onTransitionEnd: (): void => {
          finished = true;
          drag.complete();
          drag.clearReturnTarget();
          this.playerOpacity = 1;
          this.navigationEnabled = true;
        }
      };
      return animation;
    }
    if (operation === NavigationOperation.PUSH && to.name === 'player' && this.playerDragState.active) {
      const drag = PlayerDragTransition.getInstance();
      let finished: boolean = false;
      const animation: NavigationAnimatedTransition = {
        timeout: 1400,
        transition: (proxy: NavigationTransitionProxy): void => {
          // 点击与上拖确认共用弹簧收敛；以几何动画完成回调结束导航。
          this.navigationEnabled = false;
          this.playerOpacity = 1;
          this.playerRenderGroup = false;
          // 目标封面属于刚创建的子树，必须等布局提交后读取；零尺寸不能作为动画终点。
          this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
            if (finished) return;
            this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
              if (finished) return;
              const viewport = PlayerDragTransition.measure(this.getUIContext(), 'player-drag-surface');
              const cover = PlayerDragTransition.measure(this.getUIContext(), 'player-page-cover');
              if (!viewport.isValid() || !cover.isValid()) {
                this.playerOpacity = 0;
                drag.complete();
                this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
                  if (finished) return;
                  this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Decelerate,
                    onFinish: (): void => { if (!finished) proxy.finishTransition(); }
                  }, (): void => { this.playerOpacity = 1; });
                }));
                return;
              }
              console.info(`[PlayerTransition] target cover=${cover.leftPx},${cover.topPx},` +
                `${cover.widthPx},${cover.heightPx}`);
              this.getUIContext().animateTo({ curve: AppCurve.PlayerExpand,
                onFinish: (): void => {
                  if (finished) return;
                  // 正式封面先提交可见帧，再移除运动封面，避免释放快照与出图之间闪空。
                  this.playerDragState.coverRevealed = true;
                  this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
                    if (finished) return;
                    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
                      if (!finished) proxy.finishTransition();
                    }));
                  }));
                }
              }, (): void => { drag.expandToPlayer(cover, viewport); });
              this.getUIContext().animateTo({ duration: AppMotion.Base,
                delay: this.playerDragState.contentOpacity > 0.1 ? 0 : 60, curve: AppCurve.Decelerate }, (): void => {
                this.playerDragState.contentOpacity = 1;
              });
              this.getUIContext().animateTo({ duration: 80, curve: Curve.Linear }, (): void => {
                this.playerDragState.sourceOpacity = 0;
              });
            }));
          }));
        },
        onTransitionEnd: (success: boolean): void => {
          finished = true;
          drag.complete();
          this.navigationEnabled = true;
          this.playerOpacity = 1;
          this.playerRenderGroup = false;
          if (success) PlayerEntryDecider.markEntered();
          else PlayerEntryDecider.markLeaving();
        }
      };
      return animation;
    }
    const toName = to.name ?? '';
    if (operation === NavigationOperation.PUSH && toName === 'player') {
      PlayerDragTransition.getInstance().clearReturnTarget();
      return this.playerFadeTransition(true);
    }
    if (operation === NavigationOperation.POP && from.name === 'player') {
      return this.playerFadeTransition(false);
    }
    // 全宽播放器已在上方按窗口实际坐标处理。
    if (this.navigationWidth >= 720) {
      OneShotTransitionCoordinator.getInstance().discardPending();
      // 根页进出双栏会改变 NavBar/目的页宽度；不能叠加目的页的百分比平移动画。
      // Navigation 级转场优先于 ProfileMenuDestination，自行完成后只提交最终布局。
      const destinationName: string = from.index === -1 ? (to.name ?? '') : (from.name ?? '');
      if ((from.index === -1 || to.index === -1) &&
        AdaptiveLayout.navigationUsesColumns(this.navigationWidth, [destinationName])) {
        const transition: NavigationAnimatedTransition = {
          transition: (proxy: NavigationTransitionProxy): void => { proxy.finishTransition(); }
        };
        return transition;
      }
      // 同一分栏内的跳转及沉浸页保留原有转场。
      return undefined;
    }
    const coordinator = OneShotTransitionCoordinator.getInstance();
    if (!coordinator.canHandle(from, to, operation)) {
      if (operation === NavigationOperation.PUSH && toName !== 'detail') coordinator.discardPending();
      return undefined;
    }
    const animatedTransition: NavigationAnimatedTransition = {
      timeout: 2400,
      onTransitionEnd: (success: boolean): void => {
        this.navigationEnabled = true;
        if (!success) console.warn('[Index] advanced one-shot transition did not finish successfully');
      },
      transition: (transitionProxy: NavigationTransitionProxy): void => {
        this.navigationEnabled = false;
        coordinator.run(operation, from, to, transitionProxy);
      }
    };
    return animatedTransition;
  }

  private playerFadeTransition(isPush: boolean): NavigationAnimatedTransition {
    let finished: boolean = false;
    const animation: NavigationAnimatedTransition = {
      timeout: 1400,
      transition: (proxy: NavigationTransitionProxy): void => {
        this.navigationEnabled = false;
        this.playerOpacity = isPush ? 0 : 1;
        this.playerRenderGroup = false;
        // 无可见来源时保留原有淡入淡出，不凭空添加新的滑动方向。
        console.info(`[PlayerTransition] ${isPush ? 'open' : 'close'} without visible source`);
        this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
          if (finished) return;
          this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutSlowIn,
            onFinish: (): void => { if (!finished) proxy.finishTransition(); }
          }, (): void => { this.playerOpacity = isPush ? 1 : 0; });
        }));
      },
      onTransitionEnd: (success: boolean): void => {
        finished = true;
        this.playerOpacity = 1;
        this.navigationEnabled = true;
        if (isPush && success) PlayerEntryDecider.markEntered();
      }
    };
    return animation;
  }

  /**
   * 详情页标题栏内容：返回 + 收藏。
   * 只能放在这里——按钮要在 HDS 标题栏内部才既不被模糊盖住、又能点得动，
   * 而按钮的收藏态/动作由详情页通过 DetailTitleBarState 单例同步（组件自己订阅 @Trace）。
   */
  @Builder
  detailTitleBarContent() {
    Row() {
      DetailTitleBarActions({
        isFavorite: this.detailFavorite,
        horizontalPadding: this.titleBarBridge.horizontalPadding
      })
    }
    .width('100%')
    // HDS 标题栏独立于正文子树，必须显式参与同一段退场动画。
    .opacity(this.detailTitleOpacity)
    .hitTestBehavior(this.detailTitleOpacity > 0 ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'detail') {
      HdsNavDestination() {
        DetailPageWrapper({
          navStack: this.navStack,
          bookId: param as Object as string,
          contentScroller: this.detailScroller,
          allowCoverTransition: this.navigationWidth < 720,
          onContentOpacityChange: (value: number): void => { this.detailTitleOpacity = value; },
          onTransitionStarted: (isPush: boolean): void => {
            this.detailOpaqueBackground = isPush;
            this.homeCoveredByDetail = isPush && !this.parallelNavigation;
          },
          onTransitionFinished: (): void => { this.navigationEnabled = true; }
        })
      }
      // 顶栏不能用 hideTitleBar 关掉：HDS 标题栏是详情页唯一能出「沉浸光感」的载体。
      // 详情页属于 NavDestination，AppMaterial / systemMaterial 在这类页面里根本不绘制，
      // 只有 HDS 的 scrollEffect（IMMERSIVE_GRADIENT_BLUR）会随正文上滑在顶部画渐变模糊。
      //
      // 返回/收藏按钮必须放在标题栏内容里，不能由 BookDetailPage 自己画：
      // 实测 dumpLayout，TitleBar 的 zIndex=2 高于 NavDestinationContent，且会阻塞兄弟节点，
      // 页面自己画的顶栏会被模糊盖成灰影、并且完全点不动。
      // 按钮状态（收藏态）通过 DetailTitleBarState 这个 @ObservedV2 单例从详情页同步过来。
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => { this.detailTitleBarContent() }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: HdsCompat.scrollEffect
          },
          // 初态与滚动态都保持透明背景：模糊由系统按滚动量叠加，背景色会盖住效果。
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent }
          },
          thermoCtrl: true
        }
      })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .hideBackButton(true)
      .bindToScrollable([this.detailScroller])
      .backgroundColor(this.detailOpaqueBackground ? $r('sys.color.background_primary') : Color.Transparent)
      // 目录/换源弹层打开时，返回键先关弹层而不是退整页
      .onBackPressed((): boolean => DetailBackInterceptor.consume())
      .onShown((): void => { this.detailTitleOpacity = 1; })
      .onHidden((): void => { this.detailTitleOpacity = 0; })
      // 所有详情转场只由根 Navigation 接管，无封面时由 wrapper 降级淡入。
      // 不再叠加 NavDestination.customTransition，否则整页淡入会和封面动画同时运行。
      .systemTransition(NavigationSystemTransitionType.NONE)
    } else if (name === 'player') {
      NavDestination() {
        PlayerPageWrapper({ navStack: this.navStack, param: param as Object, deferEntry: this.playerDragState.active })
      }
      .hideTitleBar(true)
      // 播放页统一由根 Navigation 调度，避免叠加默认转场和共享元素自动配对。
      .systemTransition(NavigationSystemTransitionType.NONE)
      // 抽屉(章节/定时/跳过)打开时,右滑/返回先关抽屉而不是退整页
      .onBackPressed((): boolean => {
        if (PlayerDragTransition.getInstance().cancel()) return true;
        if (PlayerBackInterceptor.consume()) return true;
        PlayerEntryDecider.markLeaving();
        this.navStack.pop();
        return true;
      })
      .backgroundColor(this.playerDragState.active ? Color.Transparent : '#000000')
      .renderGroup(this.playerRenderGroup)
      .opacity(this.playerOpacity)
    } else if (name === 'comicReader') {
      NavDestination() {
        ComicReaderPage({ navStack: this.navStack,
          params: param instanceof TextReaderRouteParams ? param : new TextReaderRouteParams() })
      }.hideTitleBar(true).backgroundColor('#121212')
      .onShown((): void => { this.syncReaderWindowMode(); WindowUtils.setReaderStatusBarLight(true); })
      .onHidden((): void => { this.syncReaderWindowMode(); })
    } else if (name === 'reader') {
      NavDestination() {
        ReaderPageWrapper({ navStack: this.navStack, param: param as Object })
      }
      .hideTitleBar(true)
      .backgroundColor(param instanceof ShelfReaderRouteParams && param.opening.active ? Color.Transparent : '#F5F2EA')
      .onShown((): void => this.syncReaderWindowMode())
      .onHidden((): void => this.syncReaderWindowMode())
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'search') {
      SearchPage({ navStack: this.navStack, initialKeyword: this.resolveParam(param, 'keyword') })
    } else if (name === 'achievements') {
      AchievementPage({ navStack: this.navStack })
    } else if (name === 'account') {
      AccountPage({ navStack: this.navStack })
    } else if (name === 'settings') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        SettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'jianjianSettings') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        JianjianSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'jianjianPromptSettings') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        JianjianPromptSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'jianjianAiSettings') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        JianjianAiSettingsPage({ navStack: this.navStack,
          active: this.companionActive && this.companionRoute === 'jianjianAiSettings' })
      }
    } else if (name === 'jianjianChat') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        JianjianChatPage({ navStack: this.navStack,
          route: param instanceof JianjianChatRoute ? param : new JianjianChatRoute(),
          active: this.companionActive && this.companionRoute === 'jianjianChat' })
      }
    } else if (name === 'readingExcerpts') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        ReadingExcerptPage({ navStack: this.navStack,
          route: param instanceof ReadingExcerptRoute ? param : new ReadingExcerptRoute() })
      }
    } else if (name === 'readingExcerptDetail') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        ReadingExcerptDetailPage({ navStack: this.navStack,
          excerpt: param instanceof ReadingExcerpt ? param : new ReadingExcerpt() })
      }
    } else if (name === 'readingSettings') {
      ProfileMenuDestination() {
        ReadingSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'speechDisplaySettings') {
      ProfileMenuDestination() {
        SpeechDisplaySettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'dialogueHighlightSettings') {
      ProfileMenuDestination() {
        DialogueHighlightSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'speechSynthesisSettings') {
      ProfileMenuDestination() {
        SpeechSynthesisSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'roleSpeechSettings') {
      ProfileMenuDestination() {
        RoleSpeechSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'roleModelSettings') {
      ProfileMenuDestination() {
        RoleModelSettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'fontManagement') {
      ProfileMenuDestination() {
        FontManagementPage({ navStack: this.navStack })
      }
    } else if (name === 'voiceManagement') {
      ProfileMenuDestination() {
        VoiceManagementPage({ navStack: this.navStack })
      }
    } else if (name === 'membershipSubscription') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        if (MembershipState.featureEnabled) {
          MembershipSubscriptionPage({ navStack: this.navStack })
        } else {
          MembershipPage({ navStack: this.navStack })
        }
      }
    } else if (name === 'membership') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        MembershipPage({ navStack: this.navStack })
      }
    } else if (name === 'ruleSources') {
      // RuleSourcePage 自带 ProfileMenuDestination：页内多级视图需拦截侧滑返回
      RuleSourcePage({ navStack: this.navStack })
    } else if (name === 'ruleSourceLogin') {
      ProfileMenuDestination() {
        RuleSourceLoginPage({
          navStack: this.navStack,
          route: param instanceof RuleSourceLoginRouteParams ?
            param : new RuleSourceLoginRouteParams()
        })
      }
    } else if (name === 'RuleSourceEditPage') {
      RuleSourceEditPage({
        navStack: this.navStack,
        sourceUrl: param ? String((param as Record<string, string>).sourceUrl) : ''
      })
    } else if (name === 'RuleSourceDebugPage') {
      RuleSourceDebugPage({
        navStack: this.navStack,
        sourceUrl: param ? String((param as Record<string, string>).sourceUrl) : ''
      })
    } else if (name === 'ruleSourceExplore' || name === 'ruleSourceLoginPanel') {
      RuleSourcePanelPage({ navStack: this.navStack, sourceUrl: String(param), login: name === 'ruleSourceLoginPanel' })
    } else if (name === 'logs') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        LogManagementPage({ navStack: this.navStack })
      }
    } else if (name === 'downloads') {
      ProfileMenuDestination({ pageBackground: $r('sys.color.background_secondary') }) {
        DownloadManagerPage({ navStack: this.navStack })
      }
    } else if (name === 'about') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        AboutPage({ navStack: this.navStack })
      }
    } else if (name === 'technicalSupport') {
      ProfileMenuDestination() {
        TechnicalSupportPage({ navStack: this.navStack })
      }
    } else if (name === 'guide') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        GuidePage({ navStack: this.navStack })
      }
    } else if (name === 'guideDetail') {
      ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground }) {
        GuidePage({ navStack: this.navStack, topicId: String(param) })
      }
    } else if (name === 'import') {
      ProfileMenuDestination() {
        ImportPage({
          navStack: this.navStack,
          importFileUri: param ? this.resolveParam(param, 'uri') : '',
          importFileType: param ? this.resolveParam(param, 'fileType') : ''
        })
      }
    } else if (name === 'stats') {
      NavDestination() {
        ReadingStatsPage({ navStack: this.navStack,
          onBackHandlerChange: (handler: (() => boolean) | undefined): void => { this.statsBackHandler = handler; } })
      }
      .onBackPressed((): boolean => this.statsBackHandler?.() ?? false)
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'sessionHistory') {
      SessionHistoryPage({ navStack: this.navStack, bookIds: this.resolveParam(param, 'bookIds') })
    } else if (name === 'unfavoriteHistory') {
      NavDestination() {
        UnfavoritedHistoryPage({ navStack: this.navStack,
          onBackHandlerChange: (handler: (() => boolean) | undefined): void => { this.historyBackHandler = handler; } })
      }
      .onBackPressed((): boolean => this.historyBackHandler?.() ?? false)
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'hicar') {
      NavDestination() {
        HiCarPage({ onExit: (): void => { this.navStack.pop(); },
          onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
            this.manualCarBackHandler = handler;
          } })
      }.hideTitleBar(true).backgroundColor('#10151D')
        .onBackPressed((): boolean => this.manualCarBackHandler?.() ?? false)
    } else if (name === 'privacy') {
      ProfileMenuDestination() {
        PrivacyPage({ navStack: this.navStack })
      }
    } else if (name === 'compliance') {
      ProfileMenuDestination() {
        CompliancePage({ navStack: this.navStack })
      }
    } else if (name === 'openSource') {
      ProfileMenuDestination() {
        OpenSourcePage({ navStack: this.navStack })
      }
    } else if (name === 'blockMore') {
      BlockMorePageWrapper({ navStack: this.navStack, param: param })
    }
  }

  build() {
    Stack() {
    if (this.hiCarState.carWindow) {
      HiCarPage({ onExit: (): void => HiCarService.instance.minimize(),
        onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
          this.hiCarBackHandler = handler;
        } })
    } else {
    Navigation(this.navStack) {
      MainPage({
        navStack: this.navStack,
        allowPlayerDrag: this.navigationWidth < 720,
        onHomeShownHandlerChange: (handler: (() => void) | undefined): void => {
          this.homeShownHandler = handler;
        },
        onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
          this.homeBackHandler = handler;
        }
      })
        .visibility(this.homeCoveredByDetail && !this.parallelNavigation ? Visibility.Hidden : Visibility.Visible)
    }
    .backgroundColor($r('sys.color.background_primary'))
    .enabled(this.navigationEnabled)
    .onTouch((event: TouchEvent): void => {
      // 根节点保持挂载，HDS 迷你栏重建/手势竞争时也能收到触摸结束。
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        PlayerDragTransition.getInstance().releaseTouch(event.type === TouchType.Cancel);
      }
    })
    .navDestination(this.routerMap)
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo,
      operation: NavigationOperation): NavigationAnimatedTransition | undefined => {
      return this.oneShotNavigationTransition(from, to, operation);
    })
    .hideTitleBar(true)
    .mode(this.parallelNavigation ? NavigationMode.Split : NavigationMode.Stack)
    // 模式由路由和实际容器宽度决定，避免模式切换动画与页面转场争用布局。
    .enableModeChangeAnimation(false)
    .navBarWidth('42%')
    .navBarWidthRange([320, 440])
    .minContentWidth(400)
    .onNavBarStateChange((visible: boolean): void => {
      if (visible) {
        this.homeCoveredByDetail = false;
        this.homeShownHandler?.();
      }
    })
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      this.navigationWidth = Number(size.width);
      this.updateNavigationLayout();
    })
    .width('100%')
    .height('100%')
    .id(OneShotTransitionIds.ROOT_NAVIGATION)
    if (this.playerDragState.previewing) {
      PlayerPageWrapper({ navStack: this.navStack, param: this.playerDragState.previewBookId,
        deferEntry: true, previewOnly: true })
        .width('100%').height('100%')
        .enabled(false)
        .hitTestBehavior(HitTestMode.None)
        .onAppear((): void => {
          this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
            this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
              const drag = PlayerDragTransition.getInstance();
              if (!drag.state.previewing) return;
              drag.setPreviewTarget(
                PlayerDragTransition.measure(this.getUIContext(), 'player-page-cover'),
                PlayerDragTransition.measure(this.getUIContext(), 'player-drag-surface'));
            }));
          }));
        })
    }
    }
    // Keep the rendering transport active when the home NavDestination is hidden.
    if (WebEngineGate.instance.needRuleBrowser) {
      WebBookFetchRuntimeHost()
    }
    if (this.companionEnabled && !this.hiCarState.carWindow) {
      JianjianCompanionComponent({ active: this.companionActive && !this.companionQuiet && !this.companionTemporarilyHidden,
        carePulse: this.companionCarePulse,
        onOpen: (): void => { this.navStack.pushPathByName('jianjianChat', ''); },
        onNavigate: (route: string): void => { this.navStack.pushPathByName(route, ''); },
        onHide: (): void => {
          this.companionTemporarilyHidden = true;
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.jianjian_hidden_hint') });
        } })
        .visibility(this.companionQuiet || this.companionTemporarilyHidden ? Visibility.Hidden : Visibility.Visible)
        // 通用属性生成的全屏包装节点也必须透传，组件内部 Stack 的设置不会覆盖它。
        .hitTestBehavior(HitTestMode.Transparent)
    }
    if (this.showStartupSplash && !this.hiCarState.carWindow) {
      StartupSplash({ onFinished: (): void => { this.showStartupSplash = false; } })
    }
    }.width('100%').height('100%')
  }
}

@ComponentV2
struct DetailPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param allowCoverTransition: boolean = true;
  @Param bookId: string = '';
  /** 由详情 NavDestination 的 bindToScrollable 共用，用来驱动顶栏沉浸渐变模糊。 */
  @Param contentScroller: Scroller = new Scroller();
  @Event onTransitionStarted: (isPush: boolean) => void = () => {};
  @Event onTransitionFinished: () => void = () => {};
  @Event onContentOpacityChange: (value: number) => void = () => {};
  @Local detailOpacity: number = 1;
  @Local coverHidden: boolean = false;
  @Local previewVisible: boolean = false;
  @Local previewX: number = 0;
  @Local previewY: number = 0;
  @Local previewWidth: number = 0;
  @Local previewHeight: number = 0;
  @Local previewBaseWidth: number = 1;
  @Local previewBaseHeight: number = 1;
  @Local previewRadius: number = AppRadius.Md;
  @Local entryReady: boolean = true;

  private payload: BookOneShotPayload | undefined = undefined;
  private snapshot: image.PixelMap | undefined = undefined;
  private running: boolean = false;
  private disposed: boolean = false;
  private watchdog: number = -1;
  private navigationRunner: NavigationOneShotRunner =
    (isPush: boolean, proxy: NavigationTransitionProxy): void => this.runTransition(isPush, proxy);

  aboutToAppear(): void {
    this.onTransitionStarted(true);
    this.setContentOpacity(1);
    OneShotTransitionCoordinator.getInstance().register(this.bookId, this.navigationRunner);
    if (!this.allowCoverTransition) {
      OneShotTransitionCoordinator.getInstance().discardPending();
      return;
    }
    const payload = OneShotTransitionCoordinator.getInstance().claim(this.bookId);
    if (payload === undefined || payload.snapshot === undefined) return;
    this.payload = payload;
    this.entryReady = false;
    this.snapshot = payload.snapshot;
    this.setContentOpacity(0);
    this.coverHidden = true;
    this.previewVisible = false;
    this.applyRect(payload.sourceRect, payload.viewportRect, payload.sourceRadius);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.running = false;
    this.clearWatchdog();
    this.onTransitionFinished();
    this.restoreSource();
    OneShotTransitionCoordinator.getInstance().unregister(this.bookId);
    OneShotTransitionCoordinator.releaseSnapshot(this.snapshot);
    this.snapshot = undefined;
  }

  private clearWatchdog(): void {
    if (this.watchdog >= 0) clearTimeout(this.watchdog);
    this.watchdog = -1;
  }

  private setContentOpacity(value: number): void {
    this.detailOpacity = value;
    // 在同一个 animateTo 闭包内通知标题栏，不能用 Monitor 延后一帧同步。
    this.onContentOpacityChange(value);
  }

  private restoreSource(): void {
    const state = OneShotTransitionCoordinator.getInstance().coverState;
    if (state.hiddenSourceId === this.payload?.sourceNodeId) state.hiddenSourceId = '';
  }

  private measureRect(id: string): OneShotRect | undefined {
    return OneShotRect.measure(this.getUIContext(), id);
  }

  private applyRect(rect: OneShotRect, viewport: OneShotRect, radius: number): void {
    this.previewX = this.getUIContext().px2vp(rect.leftPx - viewport.leftPx);
    this.previewY = this.getUIContext().px2vp(rect.topPx - viewport.topPx);
    this.previewWidth = this.getUIContext().px2vp(rect.widthPx);
    this.previewHeight = this.getUIContext().px2vp(rect.heightPx);
    this.previewRadius = radius;
  }

  private afterLayout(action: () => void): void {
    // 用连续帧确认布局已提交，不等 onIdle：目录加载繁忙时可能连续多帧没有空闲时间。
    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
      if (this.disposed || !this.running) return;
      this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
        if (!this.disposed && this.running) action();
      }));
    }));
  }

  private finish(proxy: NavigationTransitionProxy, isPush: boolean): void {
    if (!this.running) return;
    this.running = false;
    this.clearWatchdog();
    this.onTransitionFinished();
    this.restoreSource();
    this.coverHidden = false;
    this.previewVisible = false;
    this.setContentOpacity(isPush ? 1 : 0);
    proxy.finishTransition();
    if (isPush) this.entryReady = true;
  }

  private runTransition(isPush: boolean, proxy: NavigationTransitionProxy): void {
    if (this.running || this.disposed) {
      this.onTransitionFinished();
      proxy.finishTransition();
      return;
    }
    this.running = true;
    this.onTransitionStarted(isPush);
    if (isPush && this.payload === undefined) this.setContentOpacity(0);
    // 早于 Navigation 的 timeout 清理，布局未就绪/旋转/离屏也不能留下透明页面。
    this.watchdog = setTimeout((): void => this.finish(proxy, isPush), isPush ? 1800 : 1200);
    this.afterLayout((): void => this.prepareTransition(isPush, proxy));
  }

  private prepareTransition(isPush: boolean, proxy: NavigationTransitionProxy): void {
    const payload = this.payload;
    const viewport = this.measureRect(OneShotTransitionIds.DETAIL_SURFACE);
    const target = this.measureRect(OneShotTransitionIds.detailCover(this.bookId));
    if (payload === undefined || viewport === undefined || target === undefined) {
      this.fadeFallback(isPush, proxy);
      return;
    }
    if (isPush) payload.viewportRect = viewport;
    const source = isPush ? payload.sourceRect : this.measureRect(payload.sourceNodeId);
    if (source === undefined || source.topPx + source.heightPx <= viewport.topPx ||
      source.topPx >= viewport.topPx + viewport.heightPx ||
      source.leftPx + source.widthPx <= viewport.leftPx || source.leftPx >= viewport.leftPx + viewport.widthPx ||
      (!isPush && (Math.abs(viewport.widthPx - payload.viewportRect.widthPx) > 2 ||
      Math.abs(viewport.heightPx - payload.viewportRect.heightPx) > 2))) {
      this.fadeFallback(isPush, proxy);
      return;
    }
    if (!isPush) {
      // 返回使用当前详情图片，避免详情刷新封面后倒退成进入前的截图。
      try {
        const snapshot = this.getUIContext().getComponentSnapshot().getSync(OneShotTransitionIds.detailCover(this.bookId));
        OneShotTransitionCoordinator.releaseSnapshot(this.snapshot);
        this.snapshot = snapshot;
      } catch (_error) {
        this.fadeFallback(false, proxy);
        return;
      }
    }
    console.info(`[OneShot] ${isPush ? 'push' : 'pop'} book=${this.bookId} source=${payload.sourceNodeId}` +
      ` rect=${source.leftPx},${source.topPx},${source.widthPx},${source.heightPx}`);
    this.applyRect(isPush ? source : target, viewport, isPush ? payload.sourceRadius : AppRadius.Sm);
    this.previewBaseWidth = Math.max(1, this.previewWidth);
    this.previewBaseHeight = Math.max(1, this.previewHeight);
    this.previewVisible = true;
    this.coverHidden = true;
    OneShotTransitionCoordinator.getInstance().coverState.hiddenSourceId = payload.sourceNodeId;
    // 进入时只绘制详情和运动封面，避免两页材质叠绘和整页离屏合成。
    if (isPush) this.setContentOpacity(1);
    // 起止位置均为最终布局坐标，不再缩放整个详情或在运动途中淡掉封面。
    this.afterLayout((): void => {
      if (!isPush) {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut },
          (): void => { this.setContentOpacity(0); });
      }
      this.getUIContext().animateTo({
        duration: isPush ? 420 : 350,
        curve: Curve.FastOutSlowIn,
        expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        onFinish: (): void => {
          if (!this.running || this.disposed) return;
          if (isPush) this.handoffCover(proxy);
          else this.finish(proxy, false);
        }
      }, (): void => {
        // 圆角保持不变，避免缩放过程中逐帧重建裁剪离屏层。
        this.applyRect(isPush ? target : source, viewport, this.previewRadius);
      });
    });
  }

  private handoffCover(proxy: NavigationTransitionProxy): void {
    this.coverHidden = false;
    // 仅等待显隐提交；慢图使用图片组件的占位，不让网络加载继续锁住导航和详情请求。
    this.afterLayout((): void => this.finish(proxy, true));
  }

  private fadeFallback(isPush: boolean, proxy: NavigationTransitionProxy): void {
    this.coverHidden = false;
    this.previewVisible = false;
    this.restoreSource();
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish(proxy, isPush)
    }, (): void => { this.setContentOpacity(isPush ? 1 : 0); });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      BookDetailPage({ navStack: this.navStack, bookId: this.bookId,
        contentScroller: this.contentScroller,
        transitionCoverHidden: this.coverHidden, deferEntry: !this.entryReady })
        .width('100%')
        .height('100%')
        .opacity(this.detailOpacity)
      if (this.previewVisible && this.snapshot !== undefined) {
        Image(this.snapshot)
          // 尺寸固定，只改变绘制变换，避免每帧重新测量详情页。
          .width(this.previewBaseWidth)
          .height(this.previewBaseHeight)
          .scale({ x: this.previewWidth / this.previewBaseWidth,
            y: this.previewHeight / this.previewBaseHeight, centerX: 0, centerY: 0 })
          .translate({ x: this.previewX, y: this.previewY })
          .borderRadius(this.previewRadius)
          .clip(true)
          .objectFit(ImageFit.Contain)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .id(OneShotTransitionIds.DETAIL_SURFACE)
  }
}

@ComponentV2
struct PlayerPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = '';
  @Param deferEntry: boolean = false;
  @Param previewOnly: boolean = false;
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  private draggingDismiss: boolean = false;

  private readyCoverSource(source: string): ResourceStr {
    if (source.startsWith('/')) return `file://${source}`;
    if (source.startsWith('file://') || source.startsWith('http')) return source;
    return $rawfile(source);
  }

  @Builder
  private decodedTransitionCover(source: string, size: number) {
    // 仅接收播放页已解码成功的同源同尺寸图片，同步复用缓存，截图留在底层作兜底。
    Image(this.readyCoverSource(source))
      .width('100%').height('100%').objectFit(ImageFit.Cover)
      .sourceSize({ width: size, height: size })
      .syncLoad(true)
      .interpolation(ImageInterpolation.Medium)
      .draggable(false)
      .opacity(this.dragState.coverImageOpacity)
      .transition(TransitionEffect.IDENTITY)
      .onComplete((event) => {
        if (event?.loadingStatus !== 1 || !this.dragState.active ||
          this.dragState.coverSource !== source || this.dragState.coverDecodeSize !== size ||
          this.dragState.coverImageOpacity === 1) return;
        this.getUIContext().animateTo({ duration: 80, curve: Curve.Linear }, (): void => {
          this.dragState.coverImageOpacity = 1;
        });
      })
  }

  private resolveBookId(): string {
    if (typeof this.param === 'string') return this.param as string;
    const r = this.param as Record<string, Object>;
    return (r['bookId'] as string) ?? '';
  }

  private resolveChapterId(): string {
    if (typeof this.param === 'string') return '';
    const r = this.param as Record<string, Object>;
    return (r['chapterId'] as string) ?? '';
  }

  private resolveProgressMs(): number {
    if (typeof this.param === 'string') return 0;
    const r = this.param as Record<string, Object>;
    const v = r['progressMs'];
    return typeof v === 'number' ? v : 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dragState.dismissing && this.dragState.backdropSnapshot !== undefined) {
        Image(this.dragState.backdropSnapshot)
          .width('100%').height('100%').objectFit(ImageFit.Fill)
          .hitTestBehavior(HitTestMode.None)
      }
      Stack({ alignContent: Alignment.TopStart }) {
        PlayerPage({
          navStack: this.navStack,
          bookId: this.resolveBookId(),
          deferEntry: this.deferEntry,
          previewOnly: this.previewOnly,
          resumeChapterId: this.resolveChapterId(),
          resumeProgressMs: this.resolveProgressMs()
        })
          .width(this.dragState.active ? this.dragState.viewportWidth : '100%')
          .height(this.dragState.active ? this.dragState.viewportHeight : '100%')
          .translate({ x: this.dragState.active ? -this.dragState.frameX : 0,
            y: this.dragState.active ? -this.dragState.frameY : 0 })
          .opacity(this.dragState.contentOpacity)
        if (this.dragState.active && (this.dragState.snapshot !== undefined || this.dragState.coverSource.length > 0)) {
          Stack() {
            if (this.dragState.snapshot !== undefined) {
              Image(this.dragState.snapshot)
                .width('100%').height('100%').objectFit(ImageFit.Cover)
                .syncLoad(true)
            }
            if (this.dragState.coverSource.length > 0) {
              this.decodedTransitionCover(this.dragState.coverSource, this.dragState.coverDecodeSize)
            }
          }
            .width(this.dragState.coverWidth)
            .height(this.dragState.coverHeight)
            .position({ x: 0, y: 0 })
            .translate({ x: this.dragState.coverX - this.dragState.frameX,
              y: this.dragState.coverY - this.dragState.frameY })
            .borderRadius(this.dragState.coverRadius)
            .clip(true)
            .transition(TransitionEffect.IDENTITY)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.dragState.active ? this.dragState.frameWidth : '100%')
      .height(this.dragState.active ? this.dragState.frameHeight : '100%')
      .translate({ x: this.dragState.active ? this.dragState.frameX : 0,
        y: this.dragState.active ? this.dragState.frameY : 0 })
      .borderRadius(this.dragState.active ? this.dragState.radius : 0)
      // HDS 底栏会采样上层背景，退场时不能留下随胶囊收缩的纯黑底板。
      .backgroundColor(this.dragState.active ? Color.Transparent : '#000000')
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .id('player-drag-surface')
    .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
      .onActionStart((event: GestureEvent): void => {
        this.draggingDismiss = !this.previewOnly && !this.dragState.active && event.offsetY > 0;
        if (!this.draggingDismiss) return;
        const drag = PlayerDragTransition.getInstance();
        drag.beginDismissGesture(this.getUIContext(), event.offsetY,
          (): void => { this.navStack.pop(); },
          (finish: () => void): void => {
            this.getUIContext().animateTo({ curve: AppCurve.GestureSettle, onFinish: finish },
              (): void => drag.restoreDismiss());
          });
      })
      .onActionUpdate((event: GestureEvent): void => {
        if (this.draggingDismiss) PlayerDragTransition.getInstance().update(event.offsetY);
      })
      .onActionEnd((event: GestureEvent): void => {
        if (this.draggingDismiss) PlayerDragTransition.getInstance().end(event.offsetY, event.velocityY);
        this.draggingDismiss = false;
      })
      .onActionCancel((): void => {
        if (this.draggingDismiss) PlayerDragTransition.getInstance().cancel();
        this.draggingDismiss = false;
      }))
  }
}

@ComponentV2
struct BlockMorePageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = '';

  private str(key: string): string {
    if (typeof this.param === 'string') return '';
    const r = this.param as Record<string, Object>;
    const v = r[key];
    return typeof v === 'string' ? v : '';
  }

  build() {
    BlockMorePage({
      navStack: this.navStack,
      sourceUrl: this.str('sourceUrl'),
      sourceName: this.str('sourceName'),
      title: this.str('title'),
      moreUrl: this.str('moreUrl'),
      keyword: this.str('keyword')
    })
  }
}

@ComponentV2
struct ReaderPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = new TextReaderRouteParams();
  private inactiveOpening: ShelfReaderOpenState = new ShelfReaderOpenState();

  private openingState(): ShelfReaderOpenState {
    return this.param instanceof ShelfReaderRouteParams ? this.param.opening : this.inactiveOpening;
  }

  private resolveBookId(): string {
    if (this.param instanceof TextReaderRouteParams) return this.param.bookId;
    const value = this.param as Record<string, Object>;
    const bookId = value['bookId'];
    return typeof bookId === 'string' ? bookId : '';
  }

  private resolveResourceIndex(): number {
    if (this.param instanceof TextReaderRouteParams) return this.param.resourceIndex;
    const value = this.param as Record<string, Object>;
    const index = value['resourceIndex'];
    return typeof index === 'number' ? index : -1;
  }

  private resolveDomPos(): string {
    if (this.param instanceof TextReaderRouteParams) return this.param.domPos;
    const value = this.param as Record<string, Object>;
    const domPos = value['domPos'];
    return typeof domPos === 'string' ? domPos : '';
  }

  build() {
    ShelfReaderOpenSurface({ motion: this.openingState() }) {
      ReaderPage({
        navStack: this.navStack,
        bookId: this.resolveBookId(),
        targetResourceIndex: this.resolveResourceIndex(),
        targetDomPos: this.resolveDomPos()
      })
    }
  }
}
