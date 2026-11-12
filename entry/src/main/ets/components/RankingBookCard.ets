import { curves, FrameCallback } from '@kit.ArkUI';
import { RankingBook } from '../model/Ranking';
import { Book, Chapter } from '../model/Book';
import { ReadingSession, SessionLocation } from '../service/ReadingSessionService';
import { CoverImage } from './CoverImage';
import { AppColor, AppRadius, AppTheme, AppCurve, AppMotion } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { PlayerDragTransition } from '../utils/PlayerDragTransition';
import { CardOrigin } from './RankingShelf';
import { RankingCardStyle } from './RankingCardStyle';
import { RankingMatch } from '../service/ranking/BookMatchService';
import { RankingMatchPanel } from './RankingMatchPanel';
import { RankingBookDetail } from './RankingBookDetail';
import { GeneralSettings } from '../model/GeneralSettings';
import { ReaderHoldingHandService } from '../service/text/ReaderHoldingHandService';
import { ImmersiveCircleButton } from './ImmersiveCircleButton';
import { RankingReaderCloseState, RankingReaderTransition } from '../utils/RankingReaderTransition';
import { ComicReaderService } from '../service/ComicReaderService';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { BookSourceService } from '../service/BookSourceService';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { OnlineTextPaginator } from '../service/text/OnlineTextPaginator';
import { AudioService } from '../service/AudioService';

const CARD_MAX_WIDTH: number = 400;

class RankingCardReturnFrame extends FrameCallback {
  private action: () => void;
  constructor(action: () => void) { super(); this.action = action; }
  onFrame(): void { this.action(); }
}
/** 飞向书源面板小封面的落点尺寸与边距。 */
const SHEET_COVER_W: number = 54;
const SHEET_COVER_X: number = 54;
const SHEET_COVER_TOP: number = 96;
/** 卡片与底栏之间保留的最小余量。 */
const CARD_EDGE_GAP: number = 12;
/** 卡片展开：官方跟手曲线，响应 0.45s 更从容，阻尼 0.68 保留一点回弹。 */
const OPEN_CURVE: ICurve = curves.responsiveSpringMotion(0.45, 0.68);
/** 卡片缩向书源面板小封面：沿用原来的弹簧。 */
const ZOOM_CURVE: ICurve = curves.springMotion(0.3, 0.55);

function argbWithAlpha(argb: number, alpha: number): string {
  const a: number = Math.round(Math.max(0, Math.min(1, alpha)) * 255);
  const rgb: string = (argb & 0x00FFFFFF).toString(16).padStart(6, '0');
  return '#' + a.toString(16).padStart(2, '0') + rgb;
}

/**
 * 榜单书籍卡片：整张封面铺满，下半段模糊后渐变到底色，文字压在底色上。
 * 开合由 scale + translate 自绘，内容整体同步缩放；位移以自身容器中心为基准，
 * 避免页面有底栏/安全区时落点偏移。
 */
@ComponentV2
export struct RankingBookCard {
  @Require @Param book: RankingBook = new RankingBook();
  @Param platformName: Resource = $r('app.string.ranking_home');
  /** 被点卡片在窗口中的位置与宽度（vp）。 */
  @Param origin: CardOrigin = new CardOrigin(0, 0, 88);
  /** 卡片容器在窗口中的中心（vp），由页面在点击时量好传入，保证首帧基准正确。 */
  @Param baseCx: number = 0;
  @Param baseCy: number = 0;
  /** 底部占用高度（系统避让区 + 底栏），由 MainPage 计算后逐层透传。 */
  @Param bottomTabInset: number = 0;
  @Param topBoundary: number = 0;
  @Param hostTop: number = 0;
  @Param refreshToken: number = 0;
  @Event onExit: () => void = () => {};
  @Event onRestoreSource: () => void = () => {};
  @Local returnOrigin: CardOrigin | undefined = undefined;
  @Event onStartRead: (book: RankingBook) => void = () => {};
  /** 用户在面板里确认了某条书源。 */
  @Event onConfirmMatch: (match: RankingMatch) => void = () => {};
  /** 选中书源后先缓存/记住，不导航。 */
  @Event onPrepareMatch: (match: RankingMatch) => Promise<void> = async (): Promise<void> => {};
  /** 详情态确认打开阅读；resourceIndex 用于目录点章，返回时回调 onReturn 让卡片缩回。 */
  @Event onOpenReader: (book: Book, onReturn: () => void, resourceIndex?: number) => void = () => {};
  /** 阅读/收听记录。 */
  @Event onOpenHistory: (book: Book) => void = () => {};
  /** 将记录中的位置交给现有阅读路由恢复。 */
  @Event onHistoryJump: (session: ReadingSession, location: SessionLocation) => void = () => {};
  /** 把卡片内部的返回处理交给页面，供侧边手势/返回键使用。 */
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Event onManageSources: () => void = () => {};
  @Local expanded: boolean = false;
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local holdingHandLeft: boolean = false;
  @Local primaryWidth: number = 0;
  private holdingHand: ReaderHoldingHandService = new ReaderHoldingHandService();
  @Local entered: boolean = false;
  @Local closing: boolean = false;
  @Local leaving: boolean = false;
  @Local textShown: boolean = false;
  @Local maskShown: boolean = false;
  /** 是否已切到书源匹配面板。 */
  @Local matchMode: boolean = false;
  /** 匹配模式的白底是否已经升满。 */
  @Local surfaceUp: boolean = false;
  /** 面板内容是否已淡入。 */
  @Local panelShown: boolean = false;
  /** 选中的结果键（sourceUrl + bookUrl）。 */
  @Local selectedKey: string = '';
  @Local matchPreparing: boolean = false;
  /** 是否已切到书籍详情。 */
  @Local detailMode: boolean = false;
  /** 详情内的子视图：info / catalog / group。 */
  @Local detailView: string = 'info';
  /** 阅读器转场：白底补满整卡的进度（0-1）。 */
  @Local whiteFill: number = 0;
  /** 阅读器转场：详情内容已淡出。 */
  @Local contentFade: boolean = false;
  /** 阅读器转场：整卡正在扩张到全屏。 */
  @Local expanding: boolean = false;
  /** 已触发 push，等阅读页 take 后复位卡片。 */
  @Local awaitingPush: boolean = false;
  /** 本次榜单阅读会话尚未走完收尾：吞掉阅读页 pop 后紧跟的同一次返回，避免卡片连退两级。 */
  @Local readerSessionOpen: boolean = false;
  private readerMotionToken: number = 0;
  private readerReturnedSeen: number = 0;
  private awaitingPushTimer: number = -1;
  /** 阅读页返回时由页面置位，卡片在背后垫白并缩回。 */
  @Local closeState: RankingReaderCloseState = RankingReaderTransition.closeState;
  private detailBook: Book | undefined = undefined;
  /** 漫画点击开始阅读后先在卡片里加载第一屏，准备好再播放白色展开。 */
  @Local readerPreparing: boolean = false;
  private prepareToken: number = 0;
  private prepareTimer: number = -1;
  private alive: boolean = true;
  /** 实时窗口尺寸（vp），横竖屏切换时由 onAreaChange 更新。 */
  @Local vpW: number = 0;
  @Local vpH: number = 0;
  private selectedMatch: RankingMatch | undefined = undefined;
  /** 遮罩渐变的色标，用主题色本身的透明度做插值，不会产生灰边。 */
  @Local veil: Array<[ResourceColor, number]> = [];
  /** 匹配模式白块的顶边渐变：只在最上面一小段过渡，下面全是实色。 */
  @Local matchVeil: Array<[ResourceColor, number]> = [];
  /** 实时状态栏/挖孔高度：阅读器显隐状态栏时卡片要重新对齐顶部。 */
  @Local topInsetVp: number = WindowUtils.getStatusBarHeightVp();
  private readonly safeAreaListener = (topVp: number, _bottomVp: number): void => {
    if (Math.abs(topVp - this.topInsetVp) > 0.5) this.topInsetVp = topVp;
  };
  private surfaceArgb: number = 0xFFFFFFFF;
  /** 深浅色切换时重新取主题 surface 色，重建两组渐变。 */
  private readonly surfaceThemeListener = (): void => { this.refreshSurfaceColors(); };

  private refreshSurfaceColors(): void {
    const context = this.getUIContext().getHostContext();
    try {
      if (context !== undefined) {
        this.surfaceArgb = context.resourceManager.getColorSync(AppTheme.Surface.id);
      }
    } catch (_error) {
      this.surfaceArgb = 0xFFFFFFFF;
    }
    this.veil = [[argbWithAlpha(this.surfaceArgb, 0), 0], [argbWithAlpha(this.surfaceArgb, 0), 0.24],
      [argbWithAlpha(this.surfaceArgb, 0.1), 0.34], [argbWithAlpha(this.surfaceArgb, 0.3), 0.42],
      [argbWithAlpha(this.surfaceArgb, 0.6), 0.49], [argbWithAlpha(this.surfaceArgb, 0.88), 0.55],
      [argbWithAlpha(this.surfaceArgb, 1), 0.60], [argbWithAlpha(this.surfaceArgb, 1), 1]];
    // 白块顶边 10% 做过渡，其余为实色
    this.matchVeil = [[argbWithAlpha(this.surfaceArgb, 0), 0], [argbWithAlpha(this.surfaceArgb, 0.35), 0.05],
      [argbWithAlpha(this.surfaceArgb, 0.9), 0.10], [argbWithAlpha(this.surfaceArgb, 1), 0.16],
      [argbWithAlpha(this.surfaceArgb, 1), 1]];
  }

  aboutToAppear(): void {
    // 把返回逻辑交给页面，侧边手势与返回键都走这里，避免直接退出 App。
    this.alive = true;
    this.holdingHand.onChange = (left: boolean): void => {
      if (!this.alive || !this.generalSettings.adaptiveHandedness) return;
      this.getUIContext().animateTo({ curve: curves.springMotion(0.4, 1) }, (): void => {
        this.holdingHandLeft = left;
      });
    };
    this.syncHoldingHand();
    this.readerPreparing = false;
    this.readerSessionOpen = false;
    this.readerReturnedSeen = this.closeState.returned;
    this.onBackHandlerChange((): boolean => this.handleBack());
    WindowUtils.addReaderColorListener(this.surfaceThemeListener);
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.refreshSurfaceColors();

    // 先渲染一帧初始态，再启动动画。
    setTimeout((): void => {
      if (!this.alive || this.closing) return;
      // 弹簧曲线自带响应时长，duration 参数对它无效。
      this.getUIContext().animateTo({ curve: OPEN_CURVE }, (): void => {
        this.entered = true;
      });
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut, delay: 90 }, (): void => {
        this.maskShown = true;
      });
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut, delay: 150 }, (): void => {
        this.textShown = true;
      });
    }, 0);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.holdingHand.setVisible(false);
    this.readerMotionToken++;
    this.prepareToken++;
    this.readerPreparing = false;
    if (this.prepareTimer !== -1) {
      clearTimeout(this.prepareTimer);
      this.prepareTimer = -1;
    }
    if (this.awaitingPushTimer !== -1) {
      clearTimeout(this.awaitingPushTimer);
      this.awaitingPushTimer = -1;
    }
    RankingReaderTransition.clear();
    WindowUtils.removeReaderColorListener(this.surfaceThemeListener);
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange(undefined);
  }

  private screenW(): number {
    if (this.vpW > 0) return this.vpW;
    const value: number = WindowUtils.getWindowWidthVp();
    return Number.isFinite(value) && value > 0 ? value : 393;
  }

  private screenH(): number {
    if (this.vpH > 0) return this.vpH;
    const value: number = WindowUtils.getWindowHeightVp();
    return Number.isFinite(value) && value > 0 ? value : 852;
  }

  /** 共享元素的书 id：详情态用匹配后的书，封面态用榜单书。 */
  private coverBookId(): string {
    return this.detailMode && this.detailBook !== undefined ? this.detailBook.id : this.book.id;
  }

  /** 详情态优先用匹配书的封面，保证与阅读器首帧是同一张图。 */
  private coverUrlNow(): string {
    if (this.closing) return this.book.coverUrl;
    if (this.detailMode && this.detailBook !== undefined && this.detailBook.cover.length > 0) {
      return this.detailBook.cover;
    }
    return this.book.coverUrl;
  }

  private cardMaxWidth(): number {
    if (this.screenW() >= 840 && this.screenH() >= 900) return 560;
    if (this.screenW() >= 600) return 460;
    return CARD_MAX_WIDTH;
  }

  private cardWidth(): number { return Math.min(this.cardMaxWidth(), this.screenW() * 0.88); }

  /** 底部必须让出的高度；没有页面透传值时退回系统避让区 + 实际浮动底栏。 */
  private bottomReserve(): number {
    if (this.bottomTabInset > 0) return this.bottomTabInset;
    return Math.max(WindowUtils.getBottomSafeVp() + 64,
      WindowUtils.getFloatingTabBottomVp());
  }

  /** 顶部避让区（状态栏/挖孔），由系统避让区换算，按设备自适应。 */
  private topInset(): number { return Math.max(0, this.topInsetVp - this.hostTop, this.topBoundary); }

  private cardHeight(): number {
    // 顶边避开状态栏，底边停在底栏上方，底部留 CARD_EDGE_GAP。
    const usable: number = this.screenH() - this.topInset() - this.bottomReserve() - CARD_EDGE_GAP;
    return Math.max(1, usable);
  }

  /** 展开态顶边落在状态栏下方，底部与底栏之间留 CARD_EDGE_GAP。 */
  private vBias(): number {
    return (this.screenH() - this.cardHeight()) / 2 - this.topInset();
  }

  private anchorX(): number { return this.baseCx > 0 ? this.baseCx : this.screenW() / 2; }

  private anchorY(): number { return this.baseCy > 0 ? this.baseCy : this.screenH() / 2; }

  /** 顶部按钮：卡片已经避开状态栏，按钮回到卡内 12vp。 */
  private topControlsY(): number { return 12; }

  /** 关闭按钮放在右边。 */
  private closeButtonX(): number { return this.cardWidth() - 48; }

  private originScale(): number {
    return Math.max(0.08, Math.min(1, this.sourceOrigin().width / this.cardWidth()));
  }

  private sourceOrigin(): CardOrigin { return this.returnOrigin ?? this.origin; }

  /** 只为单张过渡封面调整裁剪框，让方形有声封面收回时恢复原比例。 */
  private frameHeight(): number {
    if (this.entered && !this.closing) return this.cardHeight();
    const source: CardOrigin = this.sourceOrigin();
    const height: number = source.height > 0 ? source.height :
      source.width / (this.book.contentType === 'audio' ? 1 : RankingCardStyle.COVER_ASPECT);
    return height / this.originScale();
  }

  private measureReturnOrigin(): void {
    if (this.origin.key.length === 0) return;
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), this.origin.key);
      if (!rect.isValid()) return;
      this.returnOrigin = new CardOrigin(WindowUtils.pxToVp(rect.leftPx + rect.widthPx / 2),
        WindowUtils.pxToVp(rect.topPx + rect.heightPx / 2), WindowUtils.pxToVp(rect.widthPx),
        this.origin.key, WindowUtils.pxToVp(rect.heightPx));
    } catch (_error) { /* 保留打开时的原始卡位。 */ }
  }

  /** 恰好铺满屏幕的缩放，1.04 留出圆角溢出余量。 */
  private expandScale(): number {
    return Math.max(this.screenW() / this.cardWidth(), this.screenH() / this.cardHeight()) * 1.04;
  }

  private scaleNow(): number {
    if (this.expanding) return this.expandScale();
    if (this.leaving) return SHEET_COVER_W / this.cardWidth();
    if (this.closing) return this.originScale();
    return this.entered ? 1 : this.originScale();
  }

  private txNow(): number {
    if (this.expanding) return 0;
    if (this.leaving) return SHEET_COVER_X - this.anchorX();
    if (this.closing) return this.sourceOrigin().centerX - this.anchorX();
    return this.entered ? 0 : this.sourceOrigin().centerX - this.anchorX();
  }

  private tyNow(): number {
    if (this.expanding) return 0;
    if (this.leaving) return this.screenH() * 0.08 + SHEET_COVER_TOP - this.anchorY();
    // 起手/收回只对齐被点的卡片；bias 只用于展开态的顶部对齐。
    if (this.closing) return this.sourceOrigin().centerY - this.anchorY();
    return this.entered ? -this.vBias() : this.sourceOrigin().centerY - this.anchorY();
  }

  private close(): void {
    if (this.closing || this.leaving || this.expanding) return;
    this.measureReturnOrigin();
    // 先把面板摘掉再收缩，否则卡片会带着匹配内容一路缩回书架。
    this.matchMode = false;
    this.panelShown = false;
    this.surfaceUp = false;
    this.selectedKey = '';
    this.selectedMatch = undefined;
    this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Accelerate,
      onFinish: (): void => {
        if (!this.alive) return;
        this.onRestoreSource();
        this.getUIContext().postFrameCallback(new RankingCardReturnFrame((): void => {
          this.getUIContext().postFrameCallback(new RankingCardReturnFrame((): void => {
            if (this.alive && this.closing) this.onExit();
          }));
        }));
      } }, (): void => {
      this.closing = true;
      this.textShown = false;
      this.maskShown = false;
    });
  }

  /**
   * 进入书源匹配：白底先升满整卡，内容随后淡入上浮。
   * 三个阶段错开，同一帧只让一个东西在动。
   */
  private enterMatch(): void {
    if (this.matchMode) return;
    this.matchMode = true;
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 300, curve: AppCurve.Decelerate }, (): void => {
        this.surfaceUp = true;
      });
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, (): void => {
        this.textShown = false;
      });
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut, delay: 240 }, (): void => {
        this.panelShown = true;
      });
    }, 0);
  }

  private async pick(match: RankingMatch): Promise<void> {
    if (this.matchPreparing) return;
    this.matchPreparing = true;
    this.selectedKey = `${match.book.sourceUrl}\u001f${match.book.bookUrl}`;
    this.selectedMatch = match;
    try {
      await this.onPrepareMatch(match);
    } catch (_error) {
      this.selectedKey = '';
      this.selectedMatch = undefined;
      return;
    } finally {
      this.matchPreparing = false;
    }
    if (!this.alive || this.selectedMatch !== match || !this.matchMode) return;
    this.detailBook = match.book;
    this.detailView = 'info';
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.detailMode = true;
      this.panelShown = false;
    });
  }

  /** 换源：从详情退回匹配面板。 */
  private backToPanel(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.detailMode = false;
      this.detailView = 'info';
      this.panelShown = true;
    });
  }

  /** 返回一级：子视图 → 详情 → 匹配 → 封面 → 关闭。 */
  private handleBack(): boolean {
    // 预加载中返回只取消加载，卡片留在详情态。
    if (this.readerPreparing) {
      this.cancelReaderPrepare();
      return true;
    }
    // 阅读页 pop 的同一个返回事件可能继续冒到卡片；此时不能把详情再退一级。
    if (this.readerSessionOpen) {
      this.readerSessionOpen = false;
      return true;
    }
    if (this.closing || this.leaving || this.expanding) return true;
    if (this.detailMode && this.detailView !== 'info') {
      this.detailView = 'info';
      return true;
    }
    if (this.detailMode) {
      this.backToPanel();
      return true;
    }
    if (this.matchMode) {
      this.exitMatch();
      return true;
    }
    this.close();
    return true;
  }

  /** 从匹配退回封面：白块落下、封面文字淡回，最后卸载面板。 */
  private exitMatch(): void {
    this.panelShown = false;
    this.getUIContext().animateTo({ duration: 220, curve: AppCurve.Decelerate }, (): void => {
      this.surfaceUp = false;
    });
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut, delay: 120 }, (): void => {
      this.textShown = true;
    });
    setTimeout((): void => {
      if (this.closing || this.leaving) return;
      this.matchMode = false;
      this.detailMode = false;
      this.selectedKey = '';
      this.selectedMatch = undefined;
    }, 240);
  }

  /** 统一的白色展开：白底补满 → 整卡扩张 → 执行 action；等阅读页接管后复位。 */
  private bloomAndThen(bookId: string, action: () => void): void {
    if (this.expanding) return;
    this.readerSessionOpen = true;
    if (this.closeState.closing) this.closeState.closing = false;
    RankingReaderTransition.begin(bookId);
    this.awaitingPush = true;
    if (this.awaitingPushTimer !== -1) clearTimeout(this.awaitingPushTimer);
    // 兜底：跳转失败/没有 push 时，不要把卡片卡在满屏白色。
    this.awaitingPushTimer = setTimeout((): void => {
      this.awaitingPushTimer = -1;
      if (!this.awaitingPush) return;
      this.awaitingPush = false;
      this.readerSessionOpen = false;
      this.resetReaderOpen();
    }, 2000);
    this.getUIContext().animateTo({ duration: AppMotion.Fast, curve: AppCurve.Decelerate }, (): void => {
      this.whiteFill = 1;
      this.contentFade = true;
    });
    this.getUIContext().animateTo({ duration: AppMotion.Slow, curve: AppCurve.Decelerate,
      delay: AppMotion.Fast, onFinish: (): void => { action(); } }, (): void => {
      this.expanding = true;
    });
  }

  /** 详情态确认打开阅读。 */
  private openReader(book: Book): void {
    const action = (): void => { this.openReaderNow(book); };
    if (book.contentType === 'comic' && book.chapters.length > 0) {
      this.prepareComicReader(book, -1, -1, action);
      return;
    }
    if (book.contentType === 'audio' && book.chapters.length > 0) {
      this.prepareAudioReader(book, -1, action);
      return;
    }
    if (book.chapters.length > 0 && (book.sourceUrl.length > 0 || book.id.startsWith('import_'))) {
      this.prepareTextReader(book, -1, action);
      return;
    }
    action();
  }

  private openReaderNow(book: Book): void {
    this.bloomAndThen(book.id, (): void => {
      this.onOpenReader(book, (): void => { this.resetReaderOpen(); });
    });
  }

  private cancelReaderPrepare(): void {
    this.prepareToken++;
    this.readerPreparing = false;
    if (this.prepareTimer !== -1) {
      clearTimeout(this.prepareTimer);
      this.prepareTimer = -1;
    }
  }

  private finishPrepareAndOpen(token: number, action: () => void): void {
    if (!this.alive || token !== this.prepareToken) return;
    if (this.prepareTimer !== -1) {
      clearTimeout(this.prepareTimer);
      this.prepareTimer = -1;
    }
    this.readerPreparing = false;
    action();
  }

  /** 漫画先在卡片里预热目标章节页表和目标页图片，准备好再播放白色展开。 */
  private prepareComicReader(book: Book, chapterIndex: number, page: number, action: () => void,
    maxWaitMs: number = 1200): void {
    if (this.readerPreparing) return;
    this.readerPreparing = true;
    const token: number = ++this.prepareToken;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.readerPreparing = false;
      action();
      return;
    }
    this.prepareTimer = setTimeout((): void => {
      this.prepareTimer = -1;
      if (!this.alive || token !== this.prepareToken) return;
      this.prepareToken++;
      this.readerPreparing = false;
      action();
    }, maxWaitMs);
    const run = async (): Promise<void> => {
      try {
        let index: number = chapterIndex;
        let targetPage: number = page;
        if (index < 0 || targetPage < 0) {
          const position = await TextReadingProgressService.get(context, book.id);
          if (!this.alive || token !== this.prepareToken) return;
          if (index < 0) index = position !== null ? position.resourceIndex : 0;
          if (targetPage < 0) targetPage = position !== null ? position.pageOffset : 0;
        }
        index = Math.max(0, Math.min(book.chapters.length - 1, index));
        const pages = await ComicReaderService.load(book, book.chapters[index], context, false);
        if (!this.alive || token !== this.prepareToken) return;
        if (pages.length === 0) throw new Error('No comic images');
        targetPage = Math.max(0, Math.min(pages.length - 1, targetPage));
        await ComicReaderService.preloadNearbyImages(pages, targetPage - 1, 2, context,
          (): boolean => !this.alive || token !== this.prepareToken || !this.readerPreparing);
        if (!this.alive || token !== this.prepareToken) return;
        this.finishPrepareAndOpen(token, action);
      } catch (_error) {
        if (!this.alive || token !== this.prepareToken) return;
        this.finishPrepareAndOpen(token, action);
      }
    };
    run();
  }

  /** 小说先在卡片里把目标章节正文写入磁盘缓存，准备好再白色展开。 */
  private prepareTextReader(book: Book, chapterIndex: number, action: () => void,
    maxWaitMs: number = 1200): void {
    if (this.readerPreparing) return;
    this.readerPreparing = true;
    const token: number = ++this.prepareToken;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.readerPreparing = false;
      action();
      return;
    }
    this.prepareTimer = setTimeout((): void => {
      this.prepareTimer = -1;
      if (!this.alive || token !== this.prepareToken) return;
      this.prepareToken++;
      this.readerPreparing = false;
      action();
    }, maxWaitMs);
    const run = async (): Promise<void> => {
      try {
        let index: number = chapterIndex;
        if (index < 0) {
          const position = await TextReadingProgressService.get(context, book.id);
          if (!this.alive || token !== this.prepareToken) return;
          index = position !== null ? position.resourceIndex : 0;
        }
        index = Math.max(0, Math.min(book.chapters.length - 1, index));
        const chapter: Chapter = book.chapters[index];
        if (chapter === undefined) throw new Error('No chapter');
        const chapterUrl: string = chapter.originSourceValue ?? chapter.source.value;
        const key: string = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id, chapterUrl);
        const saved = await OnlineTextContentCache.readChapter(context, key);
        if (!this.alive || token !== this.prepareToken) return;
        if (saved === undefined || saved.content.trim().length === 0) {
          const value = await BookSourceService.getTextChapterContent(book, chapterUrl, chapter.title,
            chapter.variables);
          if (!this.alive || token !== this.prepareToken) return;
          const content: string = value.commentsLoaded ? value.content :
            OnlineTextPaginator.normalizeContent(value.content);
          await OnlineTextContentCache.write(context, key, content, value.comments, value.commentsLoaded);
          if (!this.alive || token !== this.prepareToken) return;
        }
        this.finishPrepareAndOpen(token, action);
      } catch (_error) {
        if (!this.alive || token !== this.prepareToken) return;
        this.finishPrepareAndOpen(token, action);
      }
    };
    run();
  }

  /**
   * 听书只准备书/章节数据和书源规则；不改播放状态、不解析音频、不缓冲。
   * 音频 URL 和第一段缓冲仍由 PlayerPage 自己完成。
   */
  private prepareAudioReader(book: Book, chapterIndex: number, action: () => void): void {
    if (this.readerPreparing) return;
    this.readerPreparing = true;
    const token: number = ++this.prepareToken;
    this.prepareTimer = setTimeout((): void => {
      this.prepareTimer = -1;
      if (!this.alive || token !== this.prepareToken) return;
      this.prepareToken++;
      this.readerPreparing = false;
      action();
    }, 12000);
    const run = async (): Promise<void> => {
      try {
        await AudioService.getInstance().whenReady(3000);
        if (!this.alive || token !== this.prepareToken) return;
        // 统一加载卡的最短展示，避免听书数据命中缓存时一闪而过。
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 350); });
        if (!this.alive || token !== this.prepareToken) return;
        this.finishPrepareAndOpen(token, action);
      } catch (_error) {
        if (!this.alive || token !== this.prepareToken) return;
        this.finishPrepareAndOpen(token, action);
      }
    };
    run();
  }

  private booksChapter(book: Book, chapterIndex: number): Chapter | undefined {
    if (book.chapters.length === 0) return undefined;
    const index: number = Math.max(0, Math.min(book.chapters.length - 1, chapterIndex));
    return book.chapters[index];
  }

  /** 阅读记录跳回：同样先白色展开，再由 MainPage 完成定位与 push。 */
  private jumpFromHistory(session: ReadingSession, location: SessionLocation): void {
    // 跳转实际打开的是 location.bookId，pending 必须用同一个 id。
    const bookId: string = location.bookId.length > 0 ? location.bookId
      : (this.detailBook !== undefined ? this.detailBook.id : '');
    if (bookId.length === 0) {
      this.onHistoryJump(session, location);
      return;
    }
    const action = (): void => {
      this.bloomAndThen(bookId, (): void => { this.onHistoryJump(session, location); });
    };
    const book = this.detailBook;
    if (book !== undefined && book.id === bookId && book.chapters.length > 0) {
      if (book.contentType === 'comic') {
        this.prepareComicReader(book, location.chapterIndex, location.pageOffset, action);
        return;
      }
      if (book.contentType === 'audio') {
        this.prepareAudioReader(book, location.chapterIndex, action);
        return;
      }
      if (book.sourceUrl.length > 0 || book.id.startsWith('import_')) {
        this.prepareTextReader(book, location.chapterIndex, action);
        return;
      }
    }
    action();
  }

  /** 目录点章：同一套白色展开后直接打开该章。 */
  private jumpToChapter(chapter: Chapter, index: number): void {
    const book = this.detailBook;
    if (book === undefined) return;
    const action = (): void => {
      this.bloomAndThen(book.id, (): void => {
        this.onOpenReader(book, (): void => { this.resetReaderOpen(); }, index);
      });
    };
    if (book.chapters.length > 0) {
      if (book.contentType === 'comic') {
        this.prepareComicReader(book, index, 0, action, 600);
        return;
      }
      if (book.contentType === 'audio') {
        this.prepareAudioReader(book, index, action);
        return;
      }
      if (book.sourceUrl.length > 0 || book.id.startsWith('import_')) {
        this.prepareTextReader(book, index, action, 600);
        return;
      }
    }
    action();
  }

  /** 阅读页已接管（take 命中）：等目标页画出首帧后再在背后复位。 */
  @Monitor('closeState.pushed')
  private onReaderPushed(): void {
    if (!this.awaitingPush) return;
    this.awaitingPush = false;
    if (this.awaitingPushTimer !== -1) {
      clearTimeout(this.awaitingPushTimer);
      this.awaitingPushTimer = -1;
    }
    // 目标页自己的白底还没绘制时先别缩，避免闪一帧详情卡。
    setTimeout((): void => {
      if (this.alive && !this.closeState.closing) this.resetReaderOpen();
    }, 80);
  }

  private resetReaderOpen(): void {
    this.expanding = false;
    this.whiteFill = 0;
    this.contentFade = false;
  }

  /** 阅读页仍在前景时先垫满纯色，等导航退场完成才收回卡片。 */
  @Monitor('closeState.closing', 'closeState.returned')
  private onReaderClosing(): void {
    const returned: boolean = this.readerReturnedSeen !== this.closeState.returned;
    this.readerReturnedSeen = this.closeState.returned;
    const token: number = ++this.readerMotionToken;
    if (!this.closeState.closing) {
      if (this.readerSessionOpen) {
        this.readerSessionOpen = false;
        this.resetReaderOpen();
      }
      return;
    }
    this.readerSessionOpen = true;
    this.expanding = true;
    this.whiteFill = 1;
    this.contentFade = true;
    if (!returned) return;
    setTimeout((): void => {
      if (!this.alive || token !== this.readerMotionToken || !this.closeState.closing) return;
      this.collapseFromReader(token);
    }, 40);
  }

  private collapseFromReader(token: number): void {
    this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.readerMotionToken) return;
        this.getUIContext().animateTo({ duration: AppMotion.Fast, curve: AppCurve.Decelerate,
          onFinish: (): void => {
            if (!this.alive || token !== this.readerMotionToken) return;
            this.readerSessionOpen = false;
            RankingReaderTransition.completeClose();
          } }, (): void => {
          this.whiteFill = 0;
          this.contentFade = false;
        });
      } }, (): void => {
        this.expanding = false;
    });
  }

  /** 常驻胶囊：封面模式进匹配；详情态确认打开阅读。 */
  private onPrimary(): void {
    if (!this.matchMode) {
      this.enterMatch();
      return;
    }
    const book = this.detailBook;
    if (this.detailMode && book !== undefined) this.openReader(book);
  }

  private primaryEnabled(): boolean { return !this.matchMode || this.detailMode; }

  private primaryLabel(): Resource {
    const contentType: string = this.detailMode ? this.detailBook?.contentType ?? this.book.contentType
      : this.book.contentType;
    return contentType === 'audio' ? $r('app.string.book_detail_start_listen')
      : $r('app.string.book_detail_start_read');
  }

  @Monitor('generalSettings.adaptiveHandedness', 'closing', 'expanding', 'closeState.closing', 'readerSessionOpen')
  private syncHoldingHand(): void {
    this.holdingHand.setVisible(this.alive && !this.closing && !this.expanding &&
      !this.readerSessionOpen && this.generalSettings.adaptiveHandedness);
    if (!this.generalSettings.adaptiveHandedness) this.holdingHandLeft = false;
  }

  /** 目录/阅读记录页不需要“开始阅读”，把底部空间让给内容。 */
  private primaryPillShown(): boolean {
    if (this.contentFade || !(this.textShown || this.matchMode)) return false;
    return this.detailView !== 'catalog' && this.detailView !== 'history';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .opacity(this.entered && !this.closing && !this.leaving ? 1 : 0)
        .onClick((): void => this.close())

      Stack({ alignContent: Alignment.Bottom }) {
        if (this.coverUrlNow().length > 0) {
          // 复用缓存封面并按卡片尺寸异步解码，避免同步加载阻塞展开首帧。
          CoverImage({ url: this.coverUrlNow(), title: this.book.title,
            author: this.book.author, imgWidth: this.cardWidth(), imgHeight: this.frameHeight(),
            useFixedHeight: true, imageFit: ImageFit.Cover, radius: 0,
            themedDecoration: false, eagerLoad: true })
            .width('100%').height(this.frameHeight())
        } else {
          Column().width('100%').height('100%').backgroundColor(AppTheme.Surface)
        }

        // 单层渐变，色标全部来自主题色本身（只改透明度），过渡连续无灰边
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: this.veil })
          .opacity(this.maskShown ? 1 : 0)

        // 匹配模式白块：占卡片 95%，顶边一小段渐变；用位移升起，避免每帧重绘渐变。
        if (this.matchMode) {
          Column().width('100%').height(this.cardHeight() * 0.95)
            .linearGradient({ angle: 180, colors: this.matchVeil })
            .translate({ y: this.surfaceUp ? 0 : this.cardHeight() * 0.95 })
        }

        // 阅读器转场：白底补满整卡（含顶部渐变和封面），随后整卡扩张成满屏纯色。
        Column().width('100%').height(this.cardHeight()).backgroundColor(AppTheme.Surface)
          .opacity(this.whiteFill)
          .hitTestBehavior(HitTestMode.None)

        Column({ space: 7 }) {
          Text(this.book.title).fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 8 }) {
            Text(this.book.author || this.book.narrator).fontSize(12)
              .fontColor(AppTheme.TextSecondary).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(this.platformName).fontSize(11).fontColor(AppTheme.TextTertiary).maxLines(1)
          }.width('100%')
          Row({ space: 10 }) {
            if (this.book.rank > 0) {
              Text(`#${this.book.rank}`).fontSize(11).fontWeight(FontWeight.Medium)
                .fontColor(AppColor.Brand)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Pill)
            }
            if (this.book.rating > 0) {
              Text('★ ' + this.book.rating.toFixed(1))
                .fontSize(12).fontColor(AppTheme.TextSecondary)
            }
          }.width('100%')
          if (this.book.intro.length > 0) {
            Column({ space: 7 }) {
              Text(this.book.intro).fontSize(12.5).lineHeight(18).fontColor(AppTheme.TextSecondary)
                .maxLines(this.expanded ? 6 : 2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.expanded ? $r('app.string.reader_tap_collapse') : $r('app.string.reader_tap_expand'))
                .fontSize(11.5).fontColor(AppColor.Brand)
            }.width('100%').alignItems(HorizontalAlign.Start)
              .onClick((): void => { this.expanded = !this.expanded; })
          }
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 68 }).alignItems(HorizontalAlign.Start)
        .opacity(this.contentFade ? 0 : (this.textShown ? 1 : 0))

        if (this.matchMode && !this.detailMode) {
          RankingMatchPanel({ book: this.book, selectedKey: this.selectedKey,
            refreshToken: this.refreshToken,
            compact: this.cardHeight() < 520,
            onSelect: (match: RankingMatch): void => { this.pick(match); },
            onManageSources: (): void => this.onManageSources() })
            .width('100%').height(this.cardHeight() * 0.95)
            .opacity(this.contentFade ? 0 : (this.panelShown ? 1 : 0))
            .translate({ y: this.panelShown ? 0 : 12 })
        }

        if (this.matchMode && this.detailMode) {
          RankingBookDetail({ book: this.detailBook, intro: this.book.intro,
            view: this.detailView, compact: this.cardHeight() < 520,
            onViewChange: (view: string): void => { this.detailView = view; },
            onSwitchSource: (): void => this.backToPanel(),
            onHistoryJump: (session: ReadingSession, location: SessionLocation): void => {
              this.jumpFromHistory(session, location);
            },
            onChapterTap: (chapter: Chapter, index: number): void => {
              this.jumpToChapter(chapter, index);
            },
            onOpenHistory: (): void => {
              const target = this.detailBook;
              if (target !== undefined) this.onOpenHistory(target);
            } })
            .width('100%').height(this.cardHeight() * 0.95)
            .opacity(this.contentFade ? 0 : 1)

        }

        // 仅按钮悬浮，透明容器不阻断列表；左右位置跟随智感握姿。
        Row() {
          Blank()
          Row() {
            Text(this.primaryLabel()).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(AppColor.OnBrand)
          }
          .height(40).padding({ left: 24, right: 24 })
          .borderRadius(AppRadius.Pill)
          .linearGradient({ angle: 90, colors: [[AppColor.Brand, 0], [AppColor.BrandDark, 1]] })
          .shadow({ radius: 12, color: '#33FF6A00', offsetY: 5 })
          .opacity(this.primaryEnabled() ? 1 : 0.45)
          .enabled(this.primaryEnabled())
          .accessibilityText(this.primaryLabel())
          .translate({ x: this.holdingHandLeft ? -Math.max(0, this.cardWidth() - 40 - this.primaryWidth) : 0 })
          .onSizeChange((_old: SizeOptions, size: SizeOptions): void => { this.primaryWidth = Number(size.width); })
          .onClick((): void => this.onPrimary())
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 18 })
        .opacity(this.primaryPillShown() ? 1 : 0)
        .hitTestBehavior(this.primaryPillShown() ? HitTestMode.Transparent : HitTestMode.None)

        if (this.readerPreparing) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(AppColor.Brand)
            Text($r('app.string.ranking_reader_loading')).fontSize(13)
              .fontColor(AppTheme.TextSecondary)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(AppTheme.Surface)
          .hitTestBehavior(HitTestMode.Default)
          .transition(TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast,
            curve: AppCurve.Decelerate }))
        }

        ImmersiveCircleButton({ icon: $r('sys.symbol.xmark'), diameter: 36, iconSize: 18,
          useMaterial: true, iconColor: AppTheme.TextPrimary,
          onPress: (): void => this.close() })
        .position({ x: this.closeButtonX(), y: this.topControlsY() })
        .opacity(this.contentFade ? 0 : (this.textShown || this.matchMode ? 1 : 0))

        // 上一级：详情 → 匹配 → 封面；封面态没有上一级，隐藏
        if (this.matchMode) {
          ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), diameter: 36, iconSize: 18,
            useMaterial: true, iconColor: AppTheme.TextPrimary,
            onPress: (): void => { this.handleBack(); } })
          .position({ x: 12, y: this.topControlsY() })
          .opacity(this.contentFade ? 0 : 1)
          // 官方转场：进场减速、退场加速，配官方时长令牌
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.86, y: 0.86 }))
              .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate }),
            TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.86, y: 0.86 }))
              .animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })))
        }
      }
      .width(this.cardWidth())
      .height(this.frameHeight())
      .borderRadius(RankingCardStyle.RADIUS / this.scaleNow()).clip(true)
      .backgroundColor(AppTheme.Surface)
      .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
        offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
      .scale({ x: this.scaleNow(), y: this.scaleNow() })
      .translate({ x: this.txNow(), y: this.tyNow() })
      .id('rankingCardHost')
    }
    .width('100%').height('100%')
    .onAreaChange((_old: Area, next: Area): void => {
      const w: number = Number(next.width);
      const h: number = Number(next.height);
      if (w > 0 && Math.abs(w - this.vpW) > 0.5) this.vpW = w;
      if (h > 0 && Math.abs(h - this.vpH) > 0.5) this.vpH = h;
    })
  }
}
