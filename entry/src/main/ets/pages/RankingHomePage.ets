import { HdsNavigation, HdsNavigationTitleMode, HideMode, TitleBarContentOptions, BottomBuilderParams, BuilderOptions } from '@kit.UIDesignKit';
import { RankingBoard, RankingBook, RankingPlatform } from '../model/Ranking';
import { ImmersiveTabComponent } from '../components/ImmersiveTabComponent';
import { FrameCallback, LengthMetrics, curves } from '@kit.ArkUI';
import { CoverImage } from '../components/CoverImage';
import { BookRatingBadge } from '../components/BookRatingBadge';
import { RankingPosterBackground } from '../components/RankingPosterBackground';
import { AppColor, AppMaterial, HomeTheme, AppSpace, AppRadius, AppTheme, AppCurve, AppMotion } from '../theme/Theme';
import { ThemeIconRole } from '../theme/ThemeIcons';
import { ThemeIconComponent } from '../components/ThemeIconComponent';
import { HdsCompat } from '../utils/HdsCompat';
import { GeneralSettings } from '../model/GeneralSettings';
import { WindowUtils } from '../utils/WindowUtils';
import { PlayerDragTransition } from '../utils/PlayerDragTransition';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { RankingBoardOrderComponent } from '../components/RankingBoardOrderComponent';
import { SearchCache } from '../utils/SearchCache';
import { RankingService } from '../service/ranking/RankingService';
import { RankingComicMetadata } from '../service/ranking/RankingComicMetadata';
import { RankingCoverResolver } from '../service/ranking/RankingCoverResolver';
import { RankingPreferences, RankingCategorySetting } from '../service/ranking/RankingPreferences';
import { BookMatchService, RankingMatch, RankingMatchProgress } from '../service/ranking/BookMatchService';
import { DataService } from '../service/DataService';
import { SourceDataService } from '../service/SourceDataService';
import { BookSource } from '../model/BookSource';
import { Book } from '../model/Book';
import { ReadingSession, SessionLocation } from '../service/ReadingSessionService';
import { BookPosterCarousel, BookPosterItem, BOOK_POSTER_HEIGHT, BOOK_POSTER_DECK_HEIGHT, BOOK_POSTER_COVER_WIDTH } from '../components/BookPosterCarousel';
import { RankingShelf, RankingGatherCell, CardOrigin } from '../components/RankingShelf';
import { RankingCardActions, rankingCardStore } from '../utils/RankingCardStore';
import { RankingCardStyle, RankingCardClip } from '../components/RankingCardStyle';

/** 使用本机时区展示真实获取时间，避免系统区域设置改变年月日顺序或省略秒。 */
function rankingUpdateTime(timestamp: number): Resource {
  const date = new Date(timestamp);
  return $r('app.string.ranking_updated', date.getFullYear().toString(),
    (date.getMonth() + 1).toString().padStart(2, '0'), date.getDate().toString().padStart(2, '0'),
    date.getHours().toString().padStart(2, '0'), date.getMinutes().toString().padStart(2, '0'),
    date.getSeconds().toString().padStart(2, '0'));
}

// 轮播、骨架、导航收起范围和正文占位共用同一高度。
const RANKING_POSTER_HEIGHT: number = BOOK_POSTER_HEIGHT;
const RANKING_DECK_HEIGHT: number = BOOK_POSTER_DECK_HEIGHT;
// 折叠与展开共用封面尺寸，窗口增加的宽度分配给介绍，避免图片随窗口放大。
const RANKING_COVER_WIDTH: number = BOOK_POSTER_COVER_WIDTH;
const RANKING_SEARCH_HEIGHT: number = 56;
// 榜单区块：每列上下两本，最多六本；按容器宽度显示一至三列。
const RANKING_SECTION_COLUMN_SIZE: number = 2;
const RANKING_SECTION_ROW_HEIGHT: number = 94;
const RANKING_SECTION_ROW_GAP: number = 4;
const RANKING_SECTION_COLUMN_GAP: number = 12;
const RANKING_SECTION_HEIGHT: number = RANKING_SECTION_COLUMN_SIZE * RANKING_SECTION_ROW_HEIGHT +
  RANKING_SECTION_ROW_GAP;
// 左侧内边距 24vp，有未展示的列时右侧露出 28vp，全部同屏时两侧对齐。
const RANKING_SECTION_EDGE: number = 24;
const RANKING_SECTION_PEEK: number = 28;
/** 完整榜单页：卡片网格与 TOP5 焦点区。 */
const BOARD_EDGE: number = 24;
const BOARD_GRID_GAP: number = 10;
const BOARD_ROW_GAP: number = 14;
const PODIUM_CENTER_W: number = 134;
const PODIUM_INNER_SCALE: number = 0.80;
const PODIUM_OUTER_SCALE: number = 0.64;
const PODIUM_INNER_STEP: number = 0.42;
const PODIUM_OUTER_STEP: number = 0.80;
/** 宽屏只把卡片间距拉开，卡片本身保持同一尺寸。
 *  步距按投影宽度反推，让中心/内圈、内圈/外圈都保留同样的约 0.08 卡宽重合。 */
const PODIUM_INNER_STEP_WIDE: number = 0.80;
const PODIUM_OUTER_STEP_WIDE: number = 1.39;
const PODIUM_PERSPECTIVE: number = 900;
/** 中心卡先让出约三成空间，下一张再进场回正。 */
const PODIUM_CENTER_DELAY: number = 0.3;
/** 查看榜单转场节奏。 */
const FLOW_BAR_GAP: number = 12;
const FLOW_GATHER_MS: number = 320;
const FLOW_GATHER_HOLD_MS: number = 90;
/** 封面身份转换在牌堆静止时完成。 */
const FLOW_DECK_FADE_MS: number = 180;
/** 封面淡化完成后，先让 TOP5 牌堆形状停住一小段，再开始抽卡。 */
const FLOW_DECK_HOLD_MS: number = 180;
/** 封面淡化完成后立刻抽卡，不再等浮动。 */
const FLOW_DECK_PREPARE_MS: number = 200;
const FLOW_PULL_CARD_MS: number = 280;
const FLOW_PULL_STAGGER_MS: number = 150;
/** 抽卡飞行用无过冲的标准曲线；落位后的回弹单独用阻尼波表现。 */
const FLOW_PULL_CURVE = curves.cubicBezierCurve(0.2, 0, 0, 1);
/** 每张卡落位后的轻微惯性尾巴。 */
const FLOW_PULL_SETTLE_MS: number = 160;
const FLOW_PULL_SPAN_MS: number =
  FLOW_PULL_CARD_MS + FLOW_PULL_STAGGER_MS * 4 + FLOW_PULL_SETTLE_MS;
/** 五卡落位后只留一个很短的呼吸，就继续发牌。 */
const FLOW_FAN_PAUSE_MS: number = 60;
const FLOW_GRID_CARD_MS: number = 240;
const FLOW_GRID_STAGGER_MS: number = 45;
/** 中心卡后面的白卡：白背出现比翻面快，翻面一张张慢慢跟上。 */
const FLOW_WHITE_APPEAR_STAGGER_MS: number = 90;
const FLOW_FLIP_STAGGER_MS: number = 150;
const FLOW_FLIP_MS: number = 340;
const FLOW_WHITE_FADE_MS: number = 220;
const FLOW_WHITE_FADE_STAGGER_MS: number = 50;
const FLOW_TEXT_MS: number = 200;
/** 榜单标题/更新时间在抽卡过程中同步淡入。 */
const FLOW_TITLE_MS: number = 650;
const FLOW_CENTER_MS: number = 260;
const FLOW_SCROLL_MAX_ROWS: number = 8;

class BoardSwipeSample {
  x: number;
  time: number;

  constructor(x: number, time: number) {
    this.x = x;
    this.time = time;
  }
}

/** 打开/关闭查看榜单时，封面在首页货架和榜单五卡之间飞行的矩形（vp）。 */
class BoardFlowRect {
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;

  constructor(x: number = 0, y: number = 0, w: number = 0, h: number = 0) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

/** 首页牌堆里某张真实卡的中心和宽度，用于交接给榜单五卡。 */
class DeckStartCell {
  cx: number = 0;
  cy: number = 0;
  width: number = 0;
  cover: string = '';
  angle: number = 0;
  z: number = 0;

  constructor(cx: number, cy: number, width: number, cover: string = '',
    angle: number = 0, z: number = 0) {
    this.cx = cx;
    this.cy = cy;
    this.width = width;
    this.cover = cover;
    this.angle = angle;
    this.z = z;
  }
}

/** 查看榜单转场的独立牌堆卡：只有起点/终点两套实测 rect，不再经过 podium 的缩放链。 */
class BoardDeckCardData {
  key: string = '';
  hostX: number = 0;
  hostY: number = 0;
  sourceCx: number = 0;
  sourceCy: number = 0;
  sourceW: number = 0;
  sourceH: number = 0;
  startCx: number = 0;
  startCy: number = 0;
  startW: number = 0;
  startH: number = 0;
  startAngle: number = 0;
  startZ: number = 0;
  endCx: number = 0;
  endCy: number = 0;
  endW: number = 0;
  endH: number = 0;
  endAngle: number = 0;
  endZ: number = 0;
  startCover: string = '';
  endCover: string = '';
  order: number = 0;
}

/** TOP 卡本身负责抽牌，落位后保留同一节点和同一套变换，不再换成另一套封面。 */
@ComponentV2
struct RankingPodiumCard {
  @Param book: RankingBook = new RankingBook();
  @Param cover: string = '';
  @Param nodeId: string = '';
  @Param cardWidth: number = 134;
  @Param cardHeight: number = 180;
  @Param frameX: number = 0;
  @Param frameY: number = 0;
  @Param cardScale: number = 1;
  @Param cardAngle: number = 0;
  @Param perspective: number = 900;
  @Param layer: number = 0;
  @Param cardOpacity: number = 1;
  @Param infoOpacity: number = 1;
  @Param infoScale: number = 1;
  @Param entry: BoardDeckCardData = new BoardDeckCardData();
  @Param prepareToken: number = 0;
  @Param pullToken: number = 0;
  @Param cancelToken: number = 0;
  @Param coverFade: number = 1;
  @Param flowToken: number = 0;
  @Param lastOrder: number = 4;
  @Event onArrived: (token: number) => void = () => {};
  @Event onReturned: (token: number) => void = () => {};
  @Event onChoose: () => void = () => {};
  @Event onLoadError: () => void = () => {};
  @Local landed: boolean = true;
  @Local prepared: boolean = false;
  @Local flying: boolean = false;
  private alive: boolean = true;
  private motionToken: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.prepare();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.motionToken++;
  }

  @Monitor('prepareToken')
  private prepare(): void {
    this.motionToken++;
    this.prepared = this.prepareToken > 0 && this.entry.key.length > 0;
    this.landed = !this.prepared;
    this.flying = false;
  }

  @Monitor('pullToken')
  private pull(): void {
    if (!this.prepared || this.pullToken <= 0 || this.cancelToken > 0) return;
    const motion: number = ++this.motionToken;
    const flow: number = this.flowToken;
    this.flying = true;
    this.getUIContext().animateTo({ duration: FLOW_PULL_CARD_MS,
      delay: this.entry.order * FLOW_PULL_STAGGER_MS, curve: FLOW_PULL_CURVE,
      onFinish: (): void => {
        if (!this.alive || motion !== this.motionToken) return;
        this.flying = false;
        if (this.entry.order === this.lastOrder) this.onArrived(flow);
      } }, (): void => { this.landed = true; });
  }

  @Monitor('cancelToken')
  private returnToStack(): void {
    if (!this.prepared || this.cancelToken <= 0) return;
    const motion: number = ++this.motionToken;
    const cancel: number = this.cancelToken;
    this.flying = true;
    this.getUIContext().animateTo({ duration: 240, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || motion !== this.motionToken) return;
        this.flying = false;
        if (this.entry.order === this.lastOrder) this.onReturned(cancel);
      } }, (): void => { this.landed = false; });
  }

  private xNow(): number {
    return this.landed ? this.frameX : this.entry.startCx - this.entry.hostX - this.cardWidth / 2;
  }

  private yNow(): number {
    // 与货架及旋转共用中心锚点，卡片基准尺寸不同也保持同一个 window 中心。
    return this.landed ? this.frameY : this.entry.startCy - this.entry.hostY - this.cardHeight / 2;
  }

  private scaleX(): number { return this.landed ? this.cardScale : this.entry.startW / this.cardWidth; }
  private scaleY(): number { return this.landed ? this.cardScale : this.entry.startH / this.cardHeight; }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      CoverImage({ url: this.cover, title: this.book.title, author: this.book.author || this.book.narrator,
        imgWidth: this.cardWidth, imgHeight: this.cardHeight, useFixedHeight: true,
        radius: 0, imageFit: ImageFit.Cover, themedDecoration: true, eagerLoad: true,
        onLoadError: (): void => this.onLoadError() })
      if (this.prepared && this.entry.startCover !== this.cover) {
        CoverImage({ url: this.entry.startCover, title: this.book.title,
          imgWidth: this.cardWidth, imgHeight: this.cardHeight, useFixedHeight: true,
          radius: 0, imageFit: ImageFit.Cover, themedDecoration: true, eagerLoad: true })
          .opacity(1 - this.coverFade)
      }
      Text(this.book.rank.toString().padStart(2, '0')).fontSize(9 * this.infoScale)
        .fontWeight(FontWeight.Bold).fontColor(Color.White)
        .backgroundColor(AppColor.Brand).borderRadius(8)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin(6)
        .opacity(this.infoOpacity)
    }.width(this.cardWidth).height(this.cardHeight)
    .attributeModifier(new RankingCardClip())
    .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
      offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
    .position({ x: 0, y: 0 })
    .translate({ x: this.xNow(), y: this.yNow() })
    .scale({ x: this.scaleX(), y: this.scaleY(), centerX: '50%', centerY: '50%' })
    .rotate({ x: 0, y: 1, z: 0, angle: this.landed ? this.cardAngle : this.entry.startAngle,
      centerX: '50%', centerY: '50%', perspective: this.landed ? this.perspective : 900 })
    .opacity(this.cardOpacity)
    .zIndex(this.flying ? 1000 + this.entry.startZ : this.landed ? this.layer : 500 + this.entry.startZ)
    .id(this.nodeId)
    .onClick((): void => this.onChoose())
    .accessibilityGroup(true).accessibilityText(this.book.title)
  }
}

/** 五张过渡牌独立提交原生属性动画，封面尺寸在整个飞行中保持不变。 */
@ComponentV2
struct RankingDeckCard {
  @Param card: BoardDeckCardData = new BoardDeckCardData();
  @Param rootX: number = 0;
  @Param rootY: number = 0;
  @Param coverFade: number = 0;
  @Param pullToken: number = 0;
  @Param gatherToken: number = 0;
  @Param gatherFirst: boolean = false;
  @Param cancelToken: number = 0;
  @Param flowToken: number = 0;
  @Param lastOrder: number = 4;
  @Event onArrived: (token: number) => void = () => {};
  @Event onGathered: (token: number) => void = () => {};
  @Event onReturned: (token: number) => void = () => {};
  @Local arrived: boolean = false;
  @Local flying: boolean = false;
  @Local gathered: boolean = true;
  private alive: boolean = true;
  private motionToken: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.gathered = !this.gatherFirst;
  }

  @Monitor('gatherToken')
  private gather(): void {
    if (this.gatherToken <= 0 || !this.gatherFirst) return;
    const motion: number = ++this.motionToken;
    const flow: number = this.flowToken;
    this.getUIContext().animateTo({ duration: FLOW_GATHER_MS, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || motion !== this.motionToken) return;
        if (this.card.order === this.lastOrder) this.onGathered(flow);
      } }, (): void => { this.gathered = true; });
  }

  private originCx(): number { return this.gathered ? this.card.startCx : this.card.sourceCx; }
  private originCy(): number { return this.gathered ? this.card.startCy : this.card.sourceCy; }
  private originW(): number { return this.gathered ? this.card.startW : this.card.sourceW; }
  private originH(): number { return this.gathered ? this.card.startH : this.card.sourceH; }

  aboutToDisappear(): void {
    this.alive = false;
    this.motionToken++;
  }

  @Monitor('pullToken')
  private pull(): void {
    if (this.pullToken <= 0 || this.cancelToken > 0) return;
    const motion: number = ++this.motionToken;
    const flow: number = this.flowToken;
    this.flying = true;
    this.getUIContext().animateTo({ duration: FLOW_PULL_CARD_MS,
      delay: this.card.order * FLOW_PULL_STAGGER_MS, curve: FLOW_PULL_CURVE,
      onFinish: (): void => {
        if (!this.alive || motion !== this.motionToken) return;
        this.flying = false;
        if (this.card.order === this.lastOrder) this.onArrived(flow);
      } }, (): void => { this.arrived = true; });
  }

  @Monitor('cancelToken')
  private returnToStack(): void {
    if (this.cancelToken <= 0) return;
    const motion: number = ++this.motionToken;
    const cancel: number = this.cancelToken;
    this.flying = true;
    // 新动画从当前视觉位置接管，等待中的错峰动画也立即失效。
    this.getUIContext().animateTo({ duration: 240, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || motion !== this.motionToken) return;
        this.flying = false;
        if (this.card.order === this.lastOrder) this.onReturned(cancel);
      } }, (): void => { this.arrived = false; });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      CoverImage({ url: this.card.startCover, title: '', author: '',
        imgWidth: this.card.endW, imgHeight: this.card.endH,
        useFixedHeight: true, imageFit: ImageFit.Cover, radius: 0,
        compositeEdges: true, themedDecoration: true, eagerLoad: true })
        .width(this.card.endW).height(this.card.endH)
        .opacity(this.card.startCover === this.card.endCover ? 1 : 1 - this.coverFade)
      if (this.card.startCover !== this.card.endCover) {
        CoverImage({ url: this.card.endCover, title: '', author: '',
          imgWidth: this.card.endW, imgHeight: this.card.endH,
          useFixedHeight: true, imageFit: ImageFit.Cover, radius: 0,
          compositeEdges: true, themedDecoration: true, eagerLoad: true })
          .width(this.card.endW).height(this.card.endH).opacity(this.coverFade)
      }
    }
    .width(this.card.endW).height(this.card.endH)
    .borderRadius(RankingCardStyle.RADIUS).clip(true)
    .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
      offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
    .position({ x: this.card.endCx - this.rootX - this.card.endW / 2,
      y: this.card.endCy - this.rootY - this.card.endH / 2 })
    .scale({ x: this.arrived ? 1 : this.originW() / Math.max(1, this.card.endW),
      y: this.arrived ? 1 : this.originH() / Math.max(1, this.card.endH) })
    .translate({ x: this.arrived ? 0 : this.originCx() - this.card.endCx,
      y: this.arrived ? 0 : this.originCy() - this.card.endCy })
    .rotate({ x: 0, y: 1, z: 0, angle: this.arrived ? this.card.endAngle :
      (this.gathered ? this.card.startAngle : 0),
      centerX: '50%', centerY: '50%', perspective: 900 })
    .zIndex(this.flying ? 1000 + this.card.startZ :
      (this.arrived ? 100 + this.card.endZ : 500 + this.card.startZ))
  }
}

/** 每帧回调：逐帧推进 fanPosition，让五卡始终按环绕函数重算，避免跨多张时属性直线插值。 */
class RankingBoardSnapFrame extends FrameCallback {
  private action: (timeInNano: number) => void;

  constructor(action: (timeInNano: number) => void) {
    super();
    this.action = action;
  }

  onFrame(timeInNano: number): void {
    this.action(timeInNano);
  }
}

@ComponentV2
struct RankingBoardCard {
  @Param book: RankingBook = new RankingBook();
  @Param boardId: string = '';
  @Param hiddenId: string = '';
  @Param coverAspect: number = 0.75;
  /** 卡片变宽时文字同步放大；手机窄卡为 1.0。 */
  @Param fontScale: number = 1;
  /** 查看榜单：网格卡从牌堆发牌 / 中心卡后面的卡 3D 翻面。 */
  @Param flowDealToken: number = 0;
  @Param flowFlipToken: number = 0;
  /** 中心卡落位过程中先让白背淡入，落位完成后再用 flowFlipToken 翻面。 */
  @Param flowWhiteToken: number = 0;
  /** 榜单列表当前滚动偏移：目标格位随滚动移动，飞牌终点要实时跟。 */
  @Param flowScrollOffset: number = 0;
  @Param flowMode: string = '';
  @Param flowCenterRank: number = 0;
  @Param flowFirstRank: number = 0;
  @Param flowLastRank: number = 0;
  /** 中心卡后面的白卡范围：只让这一页的卡先白后翻。 */
  @Param flowFlipLastRank: number = 0;
  @Param flowFromX: number = 0;
  @Param flowFromY: number = 0;
  @Param flowFromW: number = 0;
  @Param flowCenterReady: boolean = true;
  @Event onChoose: (book: RankingBook, nodeId: string) => void = () => {};
  @Local displayCover: string = '';
  @Local hydrating: boolean = false;
  /** 发牌进度 / 翻面角度 / 文字透明度。 */
  @Local flowT: number = 0;
  @Local flowStarted: boolean = false;
  @Local flipAngle: number = 0;
  /** 白背是否已经出现；false 时这张卡在格子里完全不可见。 */
  @Local flipRevealed: boolean = false;
  /** 白背淡入透明度。 */
  @Local whiteAlpha: number = 1;
  @Local textAlpha: number = 1;
  @Local centerCoverVisible: boolean = true;
  /** 封面已经有可用 URL 后再参与飞牌，避免空白占位面被放大飞行。 */
  @Local coverReady: boolean = false;
  private flowAnimToken: number = 0;
  private whiteAnimToken: number = 0;
  private flowTargetCx: number = 0;
  private flowTargetCy: number = 0;
  private flowTargetW: number = 0;
  private flowStartScroll: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void {
    this.alive = true;
    this.hydrateCover(false);
    // 懒加载的卡如果在转场途中才挂载，先保持文字/中心封面隐藏。
    if (this.flowMode.length > 0) {
      this.textAlpha = 0;
      if (this.isDealActive() && !this.flowStarted) {
        setTimeout((): void => {
          if (this.alive && this.isDealActive() && !this.flowStarted) this.startDeal();
        }, 16);
      }
      if (this.isFlipCard() && this.flowWhiteToken > 0 && !this.flipRevealed) {
        setTimeout((): void => {
          if (this.alive && this.isFlipCard() && this.flowWhiteToken > 0 &&
            !this.flipRevealed) {
            this.revealWhite();
          }
        }, 16);
      }
      if (this.isFlipCard() && this.flowFlipToken > 0) {
        setTimeout((): void => {
          if (this.alive && this.isFlipCard() && this.flowFlipToken > 0) {
            this.startFlipSequence();
          }
        }, 16);
      }
    }
    if (this.isCenterCard() && !this.flowCenterReady) this.centerCoverVisible = false;
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.flowAnimToken++;
  }

  private inFlowRange(): boolean {
    return this.flowMode.length > 0 && this.book.rank >= this.flowFirstRank &&
      this.book.rank <= this.flowLastRank;
  }

  private isCenterCard(): boolean {
    return this.flowMode === 'pivot' && this.book.rank === this.flowCenterRank;
  }

  /** 中心卡之前的卡都属于发牌候选：未起飞前隐藏，避免先出现在格位。 */
  private isDealCard(): boolean {
    if (this.flowMode === 'dealAll') return this.inFlowRange();
    return this.flowMode === 'pivot' && this.book.rank < this.flowCenterRank;
  }

  /** 当前这一行的发牌范围；只有这一行的候选卡会在本 token 起飞。 */
  private isDealActive(): boolean {
    if (!this.isDealCard()) return false;
    if (this.flowMode === 'dealAll') return true;
    return this.book.rank >= this.flowFirstRank && this.book.rank <= this.flowLastRank;
  }

  private isFlipCard(): boolean {
    return this.flowMode === 'pivot' && this.book.rank > this.flowCenterRank &&
      (this.flowFlipLastRank <= 0 || this.book.rank <= this.flowFlipLastRank);
  }

  private measureCover(): BoardFlowRect | undefined {
    try {
      const id: string = this.coverId();
      const rect = this.getUIContext().getComponentUtils().getRectangleById(id);
      const scaleX: number = rect.scale.x > 0 ? rect.scale.x : 1;
      const scaleY: number = rect.scale.y > 0 ? rect.scale.y : 1;
      const scaleGapX: number = WindowUtils.vpToPx(rect.scale.centerX) * (1 - scaleX);
      const scaleGapY: number = WindowUtils.vpToPx(rect.scale.centerY) * (1 - scaleY);
      const w: number = px2vp(rect.size.width * scaleX);
      const h: number = px2vp(rect.size.height * scaleY);
      const x: number = px2vp(rect.windowOffset.x + WindowUtils.vpToPx(rect.translate.x) + scaleGapX);
      const y: number = px2vp(rect.windowOffset.y + WindowUtils.vpToPx(rect.translate.y) + scaleGapY);
      if (!(w > 0) || !(h > 0) || !Number.isFinite(x) || !Number.isFinite(y)) return undefined;
      return new BoardFlowRect(x, y, w, h);
    } catch (_error) {
      return undefined;
    }
  }

  private orderInFlow(): number {
    if (this.isFlipCard()) {
      return Math.max(0, this.book.rank - this.flowCenterRank - 1);
    }
    return Math.max(0, this.book.rank - this.flowFirstRank);
  }

  @Monitor('flowDealToken')
  onDealToken(): void {
    // 不在本批范围的卡不要动自己正在飞的动画；已经发过的卡也不重发。
    if (!this.isDealActive() || this.flowStarted) return;
    this.startDeal();
  }

  /** 发牌：封面没就绪或节点还没布局时重试，绝不直接跳过飞行。 */
  private startDeal(): void {
    const token: number = ++this.flowAnimToken;
    this.textAlpha = 0;
    setTimeout((): void => this.dealWhenReady(token, 0), 16);
  }

  private dealWhenReady(token: number, attempt: number): void {
    if (!this.alive || token !== this.flowAnimToken || !this.isDealCard()) return;
    // 不再等封面 URL：封面没就绪也先让卡片从牌堆飞出去，图片在飞行中/落位后补上。
    this.hydrateCover(false);
    const target = this.measureCover();
    if (target === undefined) {
      if (attempt < 10) {
        setTimeout((): void => this.dealWhenReady(token, attempt + 1), 30);
      }
      return;
    }
    this.textAlpha = 0;
    this.flowT = 0;
    this.flowStarted = true;
    this.flowTargetCx = target.x + target.w / 2;
    this.flowTargetCy = target.y + target.h / 2;
    this.flowTargetW = target.w;
    this.flowStartScroll = this.flowScrollOffset;
    setTimeout((): void => {
      if (!this.alive || token !== this.flowAnimToken) return;
      this.getUIContext().animateTo({
        duration: FLOW_GRID_CARD_MS, curve: AppCurve.Decelerate,
        onFinish: (): void => {
          if (!this.alive || token !== this.flowAnimToken) return;
          this.fadeFlowText(token);
        }
      }, (): void => {
        this.flowT = 1;
      });
    }, this.orderInFlow() * FLOW_GRID_STAGGER_MS);
  }

  @Monitor('flowWhiteToken')
  onWhiteToken(): void {
    if (!this.isFlipCard()) return;
    this.revealWhite();
  }

  /** 中心卡落位过程中白背先从左往右淡入，不翻面。 */
  private revealWhite(): void {
    if (!this.alive || !this.isFlipCard()) return;
    const token: number = ++this.whiteAnimToken;
    const order: number = this.orderInFlow();
    this.flipRevealed = true;
    this.whiteAlpha = 0;
    setTimeout((): void => {
      if (!this.alive || token !== this.whiteAnimToken) return;
      this.getUIContext().animateTo({
        duration: FLOW_WHITE_FADE_MS, curve: AppCurve.Standard
      }, (): void => {
        if (token === this.whiteAnimToken) this.whiteAlpha = 1;
      });
    }, 16 + order * FLOW_WHITE_FADE_STAGGER_MS);
  }

  @Monitor('flowFlipToken')
  onFlipToken(): void {
    if (!this.isFlipCard()) return;
    this.startFlipSequence();
  }

  /** 中心卡落位完成后才开始翻；白背已经在落位过程中淡入。 */
  private startFlipSequence(): void {
    if (!this.alive || !this.isFlipCard()) return;
    const token: number = ++this.flowAnimToken;
    if (!this.flipRevealed) {
      this.flipRevealed = true;
      this.whiteAlpha = 1;
    }
    this.flipAngle = 0;
    this.textAlpha = 0;
    const order: number = this.orderInFlow();
    setTimeout((): void => {
      if (!this.alive || token !== this.flowAnimToken) return;
      this.getUIContext().animateTo({
        duration: FLOW_FLIP_MS, curve: AppCurve.Standard,
        onFinish: (): void => {
          if (!this.alive || token !== this.flowAnimToken) return;
          this.fadeFlowText(token);
        }
      }, (): void => {
        this.flipAngle = 180;
      });
    }, 16 + order * FLOW_FLIP_STAGGER_MS);
  }

  @Monitor('flowCenterReady')
  onCenterReadyChanged(): void {
    if (!this.isCenterCard()) return;
    if (!this.flowCenterReady) {
      this.centerCoverVisible = false;
      this.textAlpha = 0;
      return;
    }
    this.centerCoverVisible = true;
    const token: number = ++this.flowAnimToken;
    this.fadeFlowText(token);
  }

  @Monitor('flowMode')
  onFlowModeChanged(): void {
    if (this.flowMode.length > 0) {
      this.textAlpha = 0;
      this.flipRevealed = false;
      this.whiteAlpha = 0;
      if (this.isFlipCard()) this.flipAngle = 0;
      if (this.isCenterCard()) {
        this.centerCoverVisible = this.flowCenterReady;
      }
      return;
    }
    this.flowAnimToken++;
    this.whiteAnimToken++;
    // flowT 保持 1：位移/缩放归零，不会在收尾时又飞回牌堆。
    this.flowT = 1;
    this.flowStarted = false;
    this.flipAngle = 0;
    this.flipRevealed = true;
    this.whiteAlpha = 1;
    this.centerCoverVisible = true;
    if (this.textAlpha < 1) this.fadeFlowText(this.flowAnimToken);
    else this.textAlpha = 1;
  }

  private fadeFlowText(token: number): void {
    setTimeout((): void => {
      if (!this.alive || token !== this.flowAnimToken) return;
      this.getUIContext().animateTo({
        duration: 150, curve: AppCurve.Decelerate
      }, (): void => {
        this.textAlpha = 1;
      });
    }, 80);
  }

  private flowDx(): number {
    if (!this.flowStarted) return 0;
    return (this.flowFromX - this.flowTargetCx) * (1 - this.flowT);
  }

  private flowDy(): number {
    if (!this.flowStarted) return 0;
    // 列表在滚动，格位会跟着移动；终点用“起飞时的目标 − 滚动增量”实时修正。
    const targetY: number = this.flowTargetCy -
      (this.flowScrollOffset - this.flowStartScroll);
    return (this.flowFromY - targetY) * (1 - this.flowT);
  }

  private flowScale(): number {
    if (!this.flowStarted || !(this.flowTargetW > 0) || !(this.flowFromW > 0)) return 1;
    const start: number = this.flowFromW / this.flowTargetW;
    return start + (1 - start) * this.flowT;
  }

  /** 榜单网格自己补封面，避免 04 之后大量停在 App logo。 */
  private hydrateCover(force: boolean): void {
    if (this.hydrating || this.displayCover.length > 0) {
      if (this.displayCover.length > 0) this.coverReady = true;
      return;
    }
    if (!force && this.book.coverUrl.length > 0) {
      this.coverReady = true;
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.hydrating = true;
    RankingCoverResolver.resolve(context, this.book, force).then((cover: string): void => {
      this.hydrating = false;
      if (!this.alive || cover.length === 0) return;
      this.book.coverUrl = cover;
      this.displayCover = cover;
      this.coverReady = true;
    }).catch((): void => {
      this.hydrating = false;
    });
  }

  private coverUrl(): string {
    return this.displayCover.length > 0 ? this.displayCover : this.book.coverUrl;
  }

  private coverId(): string {
    return `rankingBoardCard-${this.boardId}-${this.book.rank}-${this.book.id}`;
  }

  private rankText(): string { return this.book.rank.toString().padStart(2, '0'); }

  private authorText(): string { return this.book.author || this.book.narrator || ''; }

  private ratingText(): string { return this.book.rating > 0 ? this.book.rating.toFixed(1) : ''; }

  build() {
    Column({ space: this.fontScale > 1.1 ? 6 : 5 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        CoverImage({ url: this.coverUrl(), title: this.book.title, author: this.authorText(),
          imgWidth: '100%', aspectRatioValue: this.coverAspect, useOriginalRatio: false,
          radius: 12, imageFit: ImageFit.Cover, themedDecoration: true, compositeEdges: true,
          onLoadError: (): void => { this.hydrateCover(true); } })
          .opacity(this.isFlipCard() ?
            (this.flipRevealed && this.flipAngle >= 90 ? 1 : 0) : 1)
          .rotate({ x: 0, y: 1, z: 0, angle: this.isFlipCard() ? 180 : 0,
            centerX: '50%', centerY: '50%' })
        // 只有翻面阶段才创建卡背，普通滚动不携带透明的背面层。
        if (this.isFlipCard()) {
          Column()
            .width('100%').height('100%')
            .borderRadius(12)
            .backgroundColor(AppTheme.Surface)
            .borderWidth(1)
            .borderColor(AppTheme.Divider)
            .opacity(this.flipRevealed && this.flipAngle < 90 ? this.whiteAlpha : 0)
        }
        Text(this.rankText()).fontSize(9 * this.fontScale).fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(AppColor.Brand)
          .borderRadius(8).padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin(6)
          .opacity(this.textAlpha)
      }.width('100%').aspectRatio(this.coverAspect)
        // CoverImage 已把占位、图片与装饰统一圆角合成，外层只负责阴影和变换。
        .borderRadius(12)
        .shadow({ radius: 10, color: RankingCardStyle.SHADOW_COLOR, offsetY: 4 })
        .id(this.coverId())
        .translate({ x: this.flowDx(), y: this.flowDy() })
        .scale({ x: this.flowScale(), y: this.flowScale(), centerX: '50%', centerY: '50%' })
        .rotate({ x: 0, y: 1, z: 0, angle: this.flipAngle,
          centerX: '50%', centerY: '50%', perspective: 900 })
        .opacity(this.hiddenId === this.coverId() ? 0 : this.isDealCard() && !this.flowStarted ? 0 :
          (this.isFlipCard() && !this.flipRevealed ? 0 :
            (this.centerCoverVisible ? 1 : 0)))
      Text(this.book.title).fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TextPrimary).maxLines(2).height(34 * this.fontScale)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(this.textAlpha)
      Row({ space: 4 }) {
        Text(this.authorText()).fontSize(10 * this.fontScale).fontColor(AppTheme.TextSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (this.book.rating > 0) {
          Text(this.ratingText()).fontSize(9 * this.fontScale).fontColor(AppColor.Brand)
        }
      }.width('100%').height(14 * this.fontScale)
      .opacity(this.textAlpha)
    }.width('100%').alignItems(HorizontalAlign.Start)
    .onVisibleAreaChange([0], (visible: boolean): void => {
      if (visible) this.hydrateCover(false);
    })
    .onClick((): void => this.onChoose(this.book, this.coverId()))
    .accessibilityGroup(true).accessibilityText(this.book.title)
  }
}

/** 完整榜单顶部 TOP5：五卡循环、可横滑；焦点信息在卡片下方居中并随焦点联动。 */
@ComponentV2
struct RankingBoardPodium {
  @Param books: RankingBook[] = [];
  @Param boardId: string = '';
  @Param hiddenId: string = '';
  @Param coverAspect: number = 0.75;
  /** 递增后五卡按同一套交接动画回到 TOP1。 */
  @Param topToken: number = 0;
  /** 查看榜单转场：arrival 从卡片集散开，exit 飞回首页槽位，空串为正常。 */
  @Param flowMode: string = '';
  @Param flowProgress: number = 0;
  @Param flowDx: number[] = [];
  @Param flowDy: number[] = [];
  /** 接力时的目标视觉宽度：arrival 是卡片集宽度，exit 是首页槽位宽度。 */
  @Param flowRelayWidths: number[] = [];
  /** 逐张抽出：总时长、单卡时长、相邻卡间隔。 */
  @Param flowSpanMs: number = 460;
  @Param flowCardMs: number = 260;
  @Param flowStaggerMs: number = 50;
  /** 牌堆中心的 window 坐标/宽度：到组件内再换算成局部坐标，避免目标卡旋转后量偏。 */
  @Param flowStartWindowX: number = 0;
  @Param flowStartWindowY: number = 0;
  @Param flowStartWindowW: number = 0;
  /** 首页牌堆五张真实卡的相对错位/宽度。 */
  @Param flowStartOffsetsX: number[] = [];
  @Param flowStartOffsetsY: number[] = [];
  @Param flowStartWidths: number[] = [];
  /** 首页五张真实卡的实测中心（window），用于起飞前做最终落点校正。 */
  @Param flowStartCentersX: number[] = [];
  @Param flowStartCentersY: number[] = [];
  /** 新转场期间先把真实扇形整体隐藏，避免和过渡牌堆叠在一起。 */
  @Param fanOpacity: number = 1;
  /** 交接时先显示的首页封面。 */
  @Param flowStartCovers: string[] = [];
  /** 牌堆起始层级/起始角度/抽卡顺序：必须和首页牌堆完全一致。 */
  @Param flowStartZ: number[] = [];
  @Param flowStartOrder: number[] = [];
  @Param flowStartAngles: number[] = [];
  /** 五卡右上角排名最后淡入；焦点标题由页面独立控制。 */
  @Param infoOpacity: number = 1;
  @Param arrivalCards: BoardDeckCardData[] = [];
  @Param arrivalPrepareToken: number = 0;
  @Param arrivalPullToken: number = 0;
  @Param arrivalCancelToken: number = 0;
  @Param arrivalCoverFade: number = 1;
  @Param arrivalFlowToken: number = 0;
  @Event onArrived: (token: number) => void = () => {};
  @Event onReturned: (token: number) => void = () => {};
  /** 取消转场时让首页封面层重新淡回来。 */
  @Param coverBackToken: number = 0;
  /** 中心 02–05 时，把扇形转到对应名次。 */
  @Param focusRankToken: number = 0;
  @Param focusRank: number = 1;
  @Event onChoose: (book: RankingBook, nodeId: string) => void = () => {};
  /** 当前扇形焦点变化时通知页面，焦点标题由页面独立渲染在更低层级。 */
  @Event onFocusInfo: (book: RankingBook, index: number) => void =
    (_book: RankingBook, _index: number): void => {};
  /** 横拖开始时通知页面锁住列表纵向滚动，松手后恢复。 */
  @Event onFanDragChange: (dragging: boolean) => void = () => {};
  @Local podiumWidth: number = Math.max(280, WindowUtils.getWindowWidthVp() -
    WindowUtils.getLeftSafeVp() - WindowUtils.getRightSafeVp());
  /** 连续位置：0 表示第 1 本居中，1 表示第 2 本居中，可一次跨多张。 */
  @Local fanPosition: number = 0;
  /** 当前位移方向：1 位置增大（卡片左移），-1 位置减小，0 静止。 */
  @Local fanMovingSign: number = 0;
  /** 下方焦点信息用的整数索引：拖动时实时跟，甩动落位后更新。 */
  @Local infoFocus: number = 0;
  /** 焦点信息交叉淡入淡出：旧一层 + 新一层。 */
  @Local captionOpacity: number = 1;
  @Local prevCaptionOpacity: number = 0;
  @Local prevInfoFocus: number = -1;
  /** 交接封面淡化：0 显示首页封面，1 完全换成榜单封面。 */
  @Local deckCoverFade: number = 1;
  /** 榜单五卡底座封面：book.coverUrl 为空时补解析，避免淡出后露出方形 App logo。 */
  @Local podiumCovers: string[] = [];
  private startX: number = 0;
  private startY: number = 0;
  private dragStartPosition: number = 0;
  private dragging: boolean = false;
  private vertical: boolean = false;
  private snapToken: number = 0;
  private snapActive: boolean = false;
  private snapStartAt: number = -1;
  private snapFrom: number = 0;
  private snapTarget: number = 0;
  private snapDuration: number = 0;
  private captionToken: number = 0;
  private lastCaptionAt: number = 0;
  private lastSwipe: number = 0;
  private alive: boolean = true;
  private moveSamples: BoardSwipeSample[] = [];
  /** 五卡组件自身的 window 原点：牌堆中心换算成本地坐标用。 */
  private podiumOriginX: number = 0;
  private podiumOriginY: number = 0;
  private podiumOriginReady: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    if (this.books.length > 0) {
      this.onFocusInfo(this.books[this.modIndex(this.infoFocus)], this.modIndex(this.infoFocus));
    }
    this.hydratePodiumCovers();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.onFanDragChange(false);
  }

  private podiumCoverAt(index: number, fallback: string): string {
    return index < this.podiumCovers.length && this.podiumCovers[index].length > 0 ?
      this.podiumCovers[index] : fallback;
  }

  private podiumStartCoverAt(index: number, fallback: string): string {
    if (index < this.flowStartCovers.length && this.flowStartCovers[index].length > 0) {
      return this.flowStartCovers[index];
    }
    return this.podiumCoverAt(index, fallback);
  }

  private resolvePodiumCover(index: number, force: boolean): void {
    const book: RankingBook | undefined = this.books[index];
    if (book === undefined) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    RankingCoverResolver.resolve(context, book, force).then((cover: string): void => {
      if (!this.alive || cover.length === 0) return;
      if (index >= this.books.length || this.books[index].id !== book.id) return;
      const next: string[] = this.podiumCovers.slice();
      while (next.length < this.books.length) next.push('');
      next[index] = cover;
      this.podiumCovers = next;
    }).catch((): void => {});
  }

  private hydratePodiumCovers(): void {
    for (let index: number = 0; index < this.books.length; index++) {
      const book: RankingBook = this.books[index];
      if (this.podiumCoverAt(index, book.coverUrl).length > 0) continue;
      this.resolvePodiumCover(index, false);
    }
  }

  @Monitor('topToken')
  onTopTokenChanged(): void {
    this.returnToTopFan();
  }

  @Monitor('focusRankToken')
  onFocusRankChanged(): void {
    this.snapToBook(this.focusRank - 1);
  }

  /** 牌堆交接：聚拢静止后先只淡换封面，牌堆几何保持不动，之后再开始抽卡。 */
  @Monitor('flowMode')
  onFlowModeChanged(): void {
    if (this.flowMode !== 'arrival') {
      this.deckCoverFade = 1;
      return;
    }
    this.deckCoverFade = 0;
    setTimeout((): void => {
      if (!this.alive || this.flowMode !== 'arrival') return;
      this.getUIContext().animateTo({
        duration: FLOW_DECK_FADE_MS, curve: AppCurve.Standard
      }, (): void => {
        this.deckCoverFade = 1;
      });
    }, 20);
  }

  /** 取消转场：把榜单牌堆的封面淡回首页封面，和首页牌堆交接时不会突然换图。 */
  @Monitor('coverBackToken')
  onCoverBackTokenChanged(): void {
    if (this.flowMode !== 'arrival') return;
    this.getUIContext().animateTo({
      duration: FLOW_DECK_FADE_MS, curve: AppCurve.Standard
    }, (): void => {
      this.deckCoverFade = 0;
    });
  }

  /** 把指定名次转到五卡中心，复用现有逐帧切换动画。 */
  private snapToBook(index: number): void {
    const count: number = this.books.length;
    if (count === 0) return;
    const current: number = Math.round(this.fanPosition);
    let delta: number = this.modIndex(index - current);
    if (delta > count / 2) delta -= count;
    this.startFanSnap(current + delta);
  }

  /** 五卡全设备自适应：跟内容宽度放大，同时按窗口高度收住，横屏不会顶满。 */
  /** 官方断点与实测宽度的共同分档：任一未就绪时退回实测判断，避免首帧跳动。 */
  private isWidePodium(): boolean {
    return this.podiumWidth >= AdaptiveLayout.MEDIUM_WIDTH;
  }

  private flowT(): number {
    return Math.max(0, Math.min(1, this.flowProgress));
  }

  /** 每张卡的抽卡顺序由首页牌堆的堆叠顺序给定，不再按名次。 */
  private flowOrder(bookIndex: number): number {
    return bookIndex < this.flowStartOrder.length ? this.flowStartOrder[bookIndex] : bookIndex;
  }

  /** 每张卡独立的起飞时间；单卡用官方 Standard 曲线。 */
  private flowLocalT(bookIndex: number): number {
    if (this.flowMode !== 'arrival') return this.flowT();
    const elapsed: number = this.flowT() * this.flowSpanMs;
    const raw: number = (elapsed - this.flowOrder(bookIndex) * this.flowStaggerMs) /
      Math.max(1, this.flowCardMs);
    const clamped: number = Math.max(0, Math.min(1, raw));
    return FLOW_PULL_CURVE.interpolate(clamped);
  }

  private flowMoveFactor(bookIndex: number): number {
    if (this.flowMode === 'arrival') return 1 - this.flowLocalT(bookIndex);
    if (this.flowMode === 'exit') return this.flowT();
    return 0;
  }

  private flowScaleFactor(bookIndex: number): number {
    const t: number = this.flowLocalT(bookIndex);
    if (this.flowMode === 'arrival') return 0.55 + 0.45 * t;
    if (this.flowMode === 'exit') return 1 - 0.45 * this.flowT();
    return 1;
  }

  private ensurePodiumOrigin(): void {
    if (this.podiumOriginReady) return;
    // 先用布局公式算：List 内容起点 + 头部高度 + 行间距；节点 windowOffset 在 List 内不可靠。
    try {
      const header = this.getUIContext().getComponentUtils()
        .getRectangleById(`rankingBoardHeader-${this.boardId}`);
      const headerH: number = px2vp(header.size.height);
      if (headerH > 0) {
        const left: number = WindowUtils.getLeftSafeVp();
        const top: number = WindowUtils.getStatusBarHeightVp() +
          RANKING_SEARCH_HEIGHT + headerH + BOARD_ROW_GAP;
        if (top > 10) {
          this.podiumOriginX = left;
          this.podiumOriginY = top;
          this.podiumOriginReady = true;
          return;
        }
      }
    } catch (_error) { /* 继续用节点测量 */ }
    try {
      const id: string = `rankingBoardPodiumHost-${this.boardId}`;
      const rect = this.getUIContext().getComponentUtils().getRectangleById(id);
      let x: number = px2vp(rect.windowOffset.x + WindowUtils.vpToPx(rect.translate.x));
      let y: number = px2vp(rect.windowOffset.y + WindowUtils.vpToPx(rect.translate.y));
      // 组件根节点偶尔量到 0,0；用中心卡的真实 window 位置反推组件原点。
      if (!(y > 10) && this.books.length > 0) {
        const cardRect = this.getUIContext().getComponentUtils().getRectangleById(this.coverId(this.books[0]));
        const cardX: number = px2vp(cardRect.windowOffset.x + WindowUtils.vpToPx(cardRect.translate.x));
        const cardY: number = px2vp(cardRect.windowOffset.y + WindowUtils.vpToPx(cardRect.translate.y));
        if (Number.isFinite(cardX) && Number.isFinite(cardY) && cardY > 10) {
          x = cardX - this.cardFrameXAt(0);
          y = cardY - this.cardFrameYAt(0);
        }
      }
      if (!Number.isFinite(x) || !Number.isFinite(y) || !(y > 10)) return;
      this.podiumOriginX = x;
      this.podiumOriginY = y;
      this.podiumOriginReady = true;
    } catch (_error) { /* 量不到时退回目标位置 */ }
  }

  private flowStartLocalX(bookIndex: number): number {
    this.ensurePodiumOrigin();
    const base: number = this.podiumOriginReady ? this.flowStartWindowX - this.podiumOriginX :
      this.cardFrameXAt(0) + this.centerW() / 2;
    return base + (bookIndex < this.flowStartOffsetsX.length ? this.flowStartOffsetsX[bookIndex] : 0);
  }

  private flowStartLocalY(bookIndex: number): number {
    this.ensurePodiumOrigin();
    const base: number = this.podiumOriginReady ? this.flowStartWindowY - this.podiumOriginY :
      this.cardFrameYAt(0) + this.centerH() / 2;
    return base + (bookIndex < this.flowStartOffsetsY.length ? this.flowStartOffsetsY[bookIndex] : 0);
  }

  private flowTargetCenterX(bookIndex: number): number {
    return this.cardFrameXAt(bookIndex) + this.centerW() / 2;
  }

  private flowTargetCenterY(bookIndex: number): number {
    return this.cardFrameYAt(bookIndex) + this.centerH() -
      this.centerH() * this.cardScaleAt(bookIndex) / 2;
  }

  private arrivalRelayWidth(bookIndex: number): number {
    if (bookIndex < this.flowStartWidths.length && this.flowStartWidths[bookIndex] > 0) {
      return this.flowStartWidths[bookIndex];
    }
    return this.flowStartWindowW;
  }

  /** 接力宽高与榜单卡自身槽位尺寸可能不同，缩放后要让视觉中心仍落在接力点上。 */
  private flowScaleShiftY(bookIndex: number): number {
    if (this.centerW() <= 0) return 0;
    const relay: number = this.flowMode === 'arrival' ?
      this.arrivalRelayWidth(bookIndex) :
      (bookIndex < this.flowRelayWidths.length ? this.flowRelayWidths[bookIndex] : 0);
    if (!(relay > 0)) return 0;
    const aspect: number = this.cardAspect();
    const baseWidth: number = this.centerW() * this.cardScaleAt(bookIndex);
    return (relay - baseWidth) / (2 * aspect);
  }

  /** 起飞前把牌堆卡真正放到首页真实卡的实测中心；随抽卡进度淡出。 */
  private flowStartCorrectionX(bookIndex: number): number {
    if (this.flowMode !== 'arrival' || bookIndex >= this.flowStartCentersX.length) return 0;
    this.ensurePodiumOrigin();
    if (!this.podiumOriginReady) return 0;
    const actual: number = this.podiumOriginX + this.cardFrameXAt(bookIndex) +
      this.centerW() / 2 + this.flowShiftX(bookIndex);
    return (this.flowStartCentersX[bookIndex] - actual) * this.flowMoveFactor(bookIndex);
  }

  private flowStartCorrectionY(bookIndex: number): number {
    if (this.flowMode !== 'arrival' || bookIndex >= this.flowStartCentersY.length) return 0;
    this.ensurePodiumOrigin();
    if (!this.podiumOriginReady) return 0;
    const scale: number = this.flowVisualScale(bookIndex);
    const actual: number = this.podiumOriginY + this.cardFrameYAt(bookIndex) + this.centerH() -
      this.centerH() * scale / 2 + this.flowShiftY(bookIndex) +
      this.flowScaleShiftY(bookIndex) * this.flowMoveFactor(bookIndex);
    return (this.flowStartCentersY[bookIndex] - actual) * this.flowMoveFactor(bookIndex);
  }

  private flowCardScale(bookIndex: number): number {
    const base: number = this.cardScaleAt(bookIndex);
    if (this.centerW() <= 0) return base;
    const relay: number = this.flowMode === 'arrival' ?
      this.arrivalRelayWidth(bookIndex) :
      (bookIndex < this.flowRelayWidths.length ? this.flowRelayWidths[bookIndex] : 0);
    if (!(relay > 0)) return base * this.flowScaleFactor(bookIndex);
    const t: number = this.flowLocalT(bookIndex);
    const baseWidth: number = this.centerW() * base;
    if (this.flowMode === 'arrival') {
      // 先保持牌堆里的宽度把卡抽起来，后半段再长到扇形尺寸，避免一启动中心卡就变大。
      const grow: number = t * t;
      return (relay + (baseWidth - relay) * grow) / this.centerW();
    }
    if (this.flowMode === 'exit') {
      return (baseWidth + (relay - baseWidth) * this.flowT()) / this.centerW();
    }
    return base;
  }

  /** arrival：从首页牌堆的残余角度转到扇形角度；exit：转回平放/首页姿态。 */
  private flowAngleAt(bookIndex: number): number {
    const base: number = this.cardAngleAt(bookIndex);
    if (this.flowMode === 'arrival') {
      const t: number = this.flowLocalT(bookIndex);
      const start: number = bookIndex < this.flowStartAngles.length ?
        this.flowStartAngles[bookIndex] : 0;
      return start * (1 - t) + base * t;
    }
    if (this.flowMode === 'exit') return base * (1 - this.flowT());
    return base;
  }

  private flowPerspectiveAt(bookIndex: number): number {
    if (this.flowMode === 'arrival') {
      const t: number = this.flowLocalT(bookIndex);
      return 900 + (this.podiumPerspective() - 900) * t;
    }
    return this.podiumPerspective();
  }

  private flowShiftX(bookIndex: number): number {
    if (this.flowMode === 'arrival') {
      const t: number = this.flowLocalT(bookIndex);
      // 先从牌堆原位垂直升起，后半段才向左右散开；dx 是这张卡从牌堆屏幕位置到扇形目标的差值。
      const spread: number = t * t;
      const dx: number = bookIndex < this.flowDx.length ? this.flowDx[bookIndex] : 0;
      return dx * (1 - spread);
    }
    return bookIndex < this.flowDx.length ? this.flowDx[bookIndex] * this.flowMoveFactor(bookIndex) : 0;
  }

  /** 未起飞的卡保持首页牌堆的层级；起飞后回到扇形层级。 */
  private flowZAt(bookIndex: number): number {
    if (this.flowMode === 'arrival') {
      if (this.flowLocalT(bookIndex) <= 0.001) {
        const startZ: number = bookIndex < this.flowStartZ.length ?
          this.flowStartZ[bookIndex] : (5 - bookIndex);
        return 100 + startZ;
      }
      return 500 + this.cardZAt(bookIndex);
    }
    return this.cardZAt(bookIndex);
  }

  private flowShiftY(bookIndex: number): number {
    if (this.flowMode === 'arrival') {
      const t: number = this.flowLocalT(bookIndex);
      const dy: number = bookIndex < this.flowDy.length ? this.flowDy[bookIndex] : 0;
      const base: number = dy * (1 - t);
      // 中点抬高一点，卡片像被“抽”上去而不是直线平移。
      return base - Math.min(90, this.centerW() * 0.45) * Math.sin(Math.PI * Math.min(1, t));
    }
    return bookIndex < this.flowDy.length ? this.flowDy[bookIndex] * this.flowMoveFactor(bookIndex) : 0;
  }

  /**
   * 落位后的轻微惯性：飞行本身不回弹，只有到槽位后的一段阻尼波。
   * 每张卡从自己的飞行结束时刻开始，幅度随卡片尺寸自适应。
   */
  private flowSettleWave(bookIndex: number): number {
    if (this.flowMode !== 'arrival') return 0;
    const elapsed: number = this.flowT() * this.flowSpanMs;
    const start: number = this.flowOrder(bookIndex) * this.flowStaggerMs + this.flowCardMs;
    const u: number = (elapsed - start) / Math.max(1, FLOW_PULL_SETTLE_MS);
    if (u <= 0 || u >= 1) return 0;
    return Math.sin(Math.PI * 2 * u) * Math.exp(-3.2 * u);
  }

  private flowSettleY(bookIndex: number): number {
    return this.flowSettleWave(bookIndex) * Math.min(4, this.centerW() * 0.03);
  }

  private flowVisualScale(bookIndex: number): number {
    const base: number = this.flowCardScale(bookIndex);
    if (this.flowMode !== 'arrival') return base;
    return base * (1 + this.flowSettleWave(bookIndex) * 0.012);
  }

  private podiumScale(): number {
    if (this.podiumWidth <= 0) return 1;
    const aspect: number = this.cardAspect();
    const baseHeight: number = PODIUM_CENTER_W / aspect;
    const widthScale: number = this.podiumWidth / 360;
    const heightScale: number = (WindowUtils.getWindowHeightVp() * 0.50) / baseHeight;
    return Math.max(0.85, Math.min(2.1, widthScale, heightScale));
  }

  /** 非有声书完全对齐首页货架的卡片比例；有声书保留方图。 */
  private cardAspect(): number {
    return this.coverAspect >= 1 ? 1 : RankingCardStyle.COVER_ASPECT;
  }

  private centerW(): number { return PODIUM_CENTER_W * this.podiumScale(); }

  private centerH(): number { return this.centerW() / this.cardAspect(); }

  /** 卡片每次只挪一个槽位；五卡时中心到内圈的距离。 */
  private step(): number {
    if (this.books.length < 5) return this.centerW() * 0.55;
    const wide: boolean = this.isWidePodium();
    return this.centerW() * (wide ? PODIUM_INNER_STEP_WIDE : PODIUM_INNER_STEP);
  }

  /** 五卡时内圈到外圈的距离；宽屏只拉大间距，不放大卡片。 */
  private outerStep(): number {
    const projectedHalf: number = this.centerW() * PODIUM_OUTER_SCALE *
      Math.cos(28 * Math.PI / 180) / 2;
    const fit: number = this.podiumWidth / 2 - projectedHalf - 6;
    const factor: number = this.isWidePodium() ?
      PODIUM_OUTER_STEP_WIDE : PODIUM_OUTER_STEP;
    return Math.max(this.step(), Math.min(this.centerW() * factor, fit));
  }

  private fanCenterX(): number { return this.podiumWidth / 2; }

  /** 焦点信息跟着扇形适度放大，避免大屏上字还停在手机字号。 */
  private infoScale(): number {
    return Math.min(1.25, Math.max(1, this.podiumScale() * 0.7));
  }

  private podiumPerspective(): number {
    return PODIUM_PERSPECTIVE * Math.min(1.8, Math.max(1, this.podiumScale()));
  }

  /** 扇形区域本身的高度（不含下方焦点信息）。 */
  private fanHeight(): number { return this.centerH() + 12; }

  private infoHeight(): number { return 36 * this.infoScale(); }

  private heroHeight(): number { return this.fanHeight() + 8 + this.infoHeight(); }

  private modIndex(value: number): number {
    const count: number = this.books.length;
    if (count === 0) return 0;
    return ((value % count) + count) % count;
  }

  private hasFive(): boolean { return this.books.length >= 5; }

  /** 中心到最外侧槽位的整数距离：五卡 2，三卡 1。 */
  private maxSlot(): number { return Math.floor(this.books.length / 2); }

  /** 环绕半圈的距离：五卡 2.5，三卡 1.5。 */
  private halfSpan(): number { return this.books.length / 2; }

  /** 把书映射到 [-n/2, n/2) 的连续距离，0 就是正中间。 */
  private wrappedDistance(bookIndex: number): number {
    const count: number = this.books.length;
    if (count === 0) return 0;
    let distance: number = (bookIndex - this.fanPosition) % count;
    if (distance < 0) distance += count;
    if (distance >= count / 2) distance -= count;
    return distance;
  }

  /** 绕到背后的进度：0 在外圈，1 在正后方。 */
  private backProgress(absDistance: number): number {
    const span: number = this.halfSpan() - this.maxSlot();
    if (span <= 0) return 0;
    return Math.min(1, Math.max(0, (absDistance - this.maxSlot()) / span));
  }

  /** 进入中心的那张延后：中心卡先走，等它让出约三成空间后再进场回正。 */
  private visualDistance(bookIndex: number): number {
    const raw: number = this.wrappedDistance(bookIndex);
    const abs: number = Math.abs(raw);
    if (abs >= 1 || this.fanMovingSign === 0) return raw;
    const entering: boolean = (this.fanMovingSign > 0 && raw > 0) ||
      (this.fanMovingSign < 0 && raw < 0);
    if (!entering) return raw;
    const eased: number = this.centerEnterProgress(1 - abs);
    return (raw > 0 ? 1 : -1) * (1 - eased);
  }

  private centerEnterProgress(q: number): number {
    if (q <= PODIUM_CENTER_DELAY) return 0;
    const t: number = (q - PODIUM_CENTER_DELAY) / (1 - PODIUM_CENTER_DELAY);
    return t * t * (3 - 2 * t);
  }

  /** 画面上离中心最近的那张，用来在拖动时决定标题什么时候换。 */
  private visualCenterIndex(): number {
    let best: number = this.infoFocus;
    let bestAbs: number = Number.MAX_VALUE;
    for (let index = 0; index < this.books.length; index++) {
      const abs: number = Math.abs(this.visualDistance(index));
      if (abs < bestAbs) {
        bestAbs = abs;
        best = index;
      }
    }
    return best;
  }

  private cardOffsetAt(bookIndex: number): number {
    const distance: number = this.visualDistance(bookIndex);
    const abs: number = Math.abs(distance);
    const sign: number = distance < 0 ? -1 : 1;
    let magnitude: number = 0;
    if (abs <= this.maxSlot()) {
      if (this.hasFive()) {
        magnitude = abs <= 1 ? this.step() * abs :
          this.step() + (this.outerStep() - this.step()) * (abs - 1);
      } else {
        magnitude = this.step() * abs;
      }
    } else {
      const base: number = this.hasFive() ? this.outerStep() : this.step();
      magnitude = base * (1 - this.backProgress(abs));
    }
    return sign * magnitude;
  }

  private cardScaleAt(bookIndex: number): number {
    const abs: number = Math.abs(this.visualDistance(bookIndex));
    if (abs <= this.maxSlot()) {
      if (this.hasFive()) {
        return abs <= 1 ? 1 - 0.20 * abs :
          PODIUM_INNER_SCALE - (PODIUM_INNER_SCALE - PODIUM_OUTER_SCALE) * (abs - 1);
      }
      return 1 - 0.24 * abs;
    }
    const base: number = this.hasFive() ? PODIUM_OUTER_SCALE : 0.76;
    const dip: number = this.hasFive() ? 0.26 : 0.34;
    return base - (base - dip) * Math.sin(Math.PI / 2 * this.backProgress(abs));
  }

  private cardAngleAt(bookIndex: number): number {
    const distance: number = this.visualDistance(bookIndex);
    const abs: number = Math.abs(distance);
    const edge: number = this.hasFive() ? 28 : 20;
    if (abs <= this.maxSlot()) {
      const magnitude: number = this.hasFive()
        ? (abs <= 1 ? 16 * abs : 16 + 12 * (abs - 1))
        : edge * abs;
      return distance < 0 ? magnitude : -magnitude;
    }
    // 绕边卡在背后翻到 180°，再从另一侧转回来；落位角度和槽位完全一致。
    const t: number = this.backProgress(abs);
    return distance > 0 ? -edge + (180 + edge) * t : edge + (180 - edge) * t;
  }

  private cardLiftAt(bookIndex: number): number {
    const abs: number = Math.abs(this.visualDistance(bookIndex));
    if (abs > this.maxSlot()) return 0;
    if (this.hasFive()) {
      return abs <= 1 ? 12 - 6 * abs : 6 - 6 * (abs - 1);
    }
    return 12 - 12 * abs;
  }

  private cardOpacityAt(bookIndex: number): number {
    const abs: number = Math.abs(this.visualDistance(bookIndex));
    if (abs <= this.maxSlot()) return 1;
    return 1 - 0.86 * Math.sin(Math.PI / 2 * this.backProgress(abs));
  }

  private cardZAt(bookIndex: number): number {
    const abs: number = Math.abs(this.visualDistance(bookIndex));
    return Math.round(200 - 80 * abs);
  }

  private cardFrameXAt(bookIndex: number): number {
    return this.fanCenterX() + this.cardOffsetAt(bookIndex) - this.centerW() / 2;
  }

  private cardFrameYAt(bookIndex: number): number {
    return this.fanHeight() - this.centerH() - this.cardLiftAt(bookIndex);
  }

  private focusIndex(): number { return this.modIndex(this.infoFocus); }

  private bookAt(index: number): RankingBook | undefined {
    return this.books[this.modIndex(index)];
  }

  private rankAt(index: number): string {
    const book: RankingBook | undefined = this.bookAt(index);
    return book !== undefined ? book.rank.toString().padStart(2, '0') : '';
  }

  private titleAt(index: number): string {
    const book: RankingBook | undefined = this.bookAt(index);
    return book !== undefined ? book.title : '';
  }

  private authorAt(index: number): string {
    const book: RankingBook | undefined = this.bookAt(index);
    return book !== undefined ? (book.author || book.narrator || '') : '';
  }

  private ratingAt(index: number): string {
    const book: RankingBook | undefined = this.bookAt(index);
    return book !== undefined && book.rating > 0 ? book.rating.toFixed(1) : '';
  }

  private focusBook(): RankingBook { return this.books[this.focusIndex()]; }

  private focusRankText(): string { return this.rankAt(this.infoFocus); }

  private focusTitle(): string { return this.titleAt(this.infoFocus); }

  private focusAuthor(): string { return this.authorAt(this.infoFocus); }

  private focusRating(): string { return this.ratingAt(this.infoFocus); }

  /** 焦点切换：页面用 current/prev 两层做淡入淡出，这里只负责更新索引并通知。 */
  private setInfoFocus(next: number, _forceFade: boolean = false): void {
    const normalized: number = this.modIndex(next);
    if (normalized === this.infoFocus) return;
    this.infoFocus = normalized;
    const book: RankingBook | undefined = this.books[normalized];
    if (book !== undefined) this.onFocusInfo(book, normalized);
  }

  private coverId(book: RankingBook): string {
    return `rankingBoardPodium-${this.boardId}-${book.rank}-${book.id}`;
  }

  private authorText(book: RankingBook): string { return book.author || book.narrator || ''; }

  @Builder
  private podiumCard(book: RankingBook, bookIndex: number) {
    RankingPodiumCard({ book: book, cover: this.podiumCoverAt(bookIndex, book.coverUrl),
      nodeId: this.coverId(book), cardWidth: this.centerW(), cardHeight: this.centerH(),
      frameX: this.cardFrameXAt(bookIndex) + this.flowShiftX(bookIndex) + this.flowStartCorrectionX(bookIndex),
      frameY: this.cardFrameYAt(bookIndex) + this.flowShiftY(bookIndex) + this.flowSettleY(bookIndex) +
        this.flowScaleShiftY(bookIndex) * this.flowMoveFactor(bookIndex) + this.flowStartCorrectionY(bookIndex),
      cardScale: this.flowVisualScale(bookIndex), cardAngle: this.flowAngleAt(bookIndex),
      perspective: this.flowPerspectiveAt(bookIndex), layer: this.flowZAt(bookIndex),
      cardOpacity: this.hiddenId === this.coverId(book) ? 0 : this.cardOpacityAt(bookIndex),
      infoOpacity: this.infoOpacity, infoScale: this.infoScale(),
      entry: bookIndex < this.arrivalCards.length ? this.arrivalCards[bookIndex] : new BoardDeckCardData(),
      prepareToken: this.arrivalPrepareToken, pullToken: this.arrivalPullToken,
      cancelToken: this.arrivalCancelToken, coverFade: this.arrivalCoverFade,
      flowToken: this.arrivalFlowToken, lastOrder: this.books.length - 1,
      onArrived: (token: number): void => this.onArrived(token),
      onReturned: (token: number): void => this.onReturned(token),
      onLoadError: (): void => this.resolvePodiumCover(bookIndex, true),
      onChoose: (): void => {
        if (Date.now() - this.lastSwipe < 300) return;
        this.onChoose(book, this.coverId(book));
      } })
  }

  private handleTouch(event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (point === undefined) return;
      this.onFanDragChange(false);
      this.dragging = false;
      this.vertical = false;
      this.startX = point.windowX;
      this.startY = point.windowY;
      this.moveSamples = [new BoardSwipeSample(point.windowX, Date.now())];
      return;
    }
    if (event.type === TouchType.Move && point !== undefined) {
      const dx: number = point.windowX - this.startX;
      const dy: number = point.windowY - this.startY;
      const absX: number = Math.abs(dx);
      const absY: number = Math.abs(dy);
      if (this.vertical) return;
      if (!this.dragging) {
        // 还没锁定方向：明显纵向就交给列表，横向占优才锁成五卡拖动。
        if (absY > 10 && absY > absX * 1.2) {
          this.vertical = true;
          return;
        }
        if (absX <= 8 || absX < absY) return;
        this.dragging = true;
        this.onFanDragChange(true);
        this.snapActive = false;
        // 从当前视觉位置接管；+dx/step 让起手那几像素不丢、也不会跳一下。
        this.dragStartPosition = this.fanPosition + dx / Math.max(1, this.step());
        this.snapToken++;
      }
      const now: number = Date.now();
      this.moveSamples.push(new BoardSwipeSample(point.windowX, now));
      while (this.moveSamples.length > 2 && now - this.moveSamples[0].time > 80) {
        this.moveSamples.shift();
      }
      this.fanMovingSign = dx < 0 ? 1 : -1;
      this.fanPosition = this.dragStartPosition - dx / Math.max(1, this.step());
      this.setInfoFocus(this.visualCenterIndex());
      return;
    }
    if (event.type !== TouchType.Up && event.type !== TouchType.Cancel) return;
    if (this.dragging) {
      this.settleFan(this.releaseVelocity());
      this.onFanDragChange(false);
      this.lastSwipe = Date.now();
    }
    this.dragging = false;
    this.vertical = false;
  }

  private releaseVelocity(): number {
    if (this.moveSamples.length < 2) return 0;
    const first: BoardSwipeSample = this.moveSamples[0];
    const last: BoardSwipeSample = this.moveSamples[this.moveSamples.length - 1];
    const dt: number = last.time - first.time;
    return dt > 0 ? (last.x - first.x) / dt * 1000 : 0;
  }

  /** 松手后按速度投影：慢放回最近一张，快甩不设张数上限，在 TOP5 里连续转。 */
  private settleFan(velocity: number): void {
    const from: number = this.fanPosition;
    const projected: number = from - velocity / Math.max(1, this.step()) * 0.2;
    this.startFanSnap(Math.round(projected));
  }

  /** 回到 TOP1：取离当前位置最近的、焦点为 0 的整数位，走同一套五卡交接动画。 */
  private returnToTopFan(): void {
    const count: number = this.books.length;
    if (count === 0) return;
    const center: number = Math.round(this.fanPosition);
    let delta: number = this.modIndex(-center);
    if (delta > count / 2) delta -= count;
    this.startFanSnap(center + delta);
  }

  /** 统一的落位入口：settleFan 和回到 TOP1 共用，保证动画完全一致。 */
  private startFanSnap(target: number): void {
    const from: number = this.fanPosition;
    const distance: number = Math.abs(target - from);
    const token: number = ++this.snapToken;
    this.snapFrom = from;
    this.snapTarget = target;
    if (distance < 0.02) {
      this.fanPosition = target;
      this.snapActive = false;
      this.fanMovingSign = 0;
      this.setInfoFocus(target, true);
      return;
    }
    this.snapDuration = Math.min(760,
      AppMotion.Base + Math.max(0, Math.ceil(distance) - 1) * 90);
    this.snapStartAt = -1;
    this.snapActive = true;
    this.fanMovingSign = target > from ? 1 : -1;
    this.postSnapFrame(token);
  }

  /** 逐帧推进 fanPosition，五卡的环绕变换每帧重算，跨多张也不会走直线叠在一起。 */
  private postSnapFrame(token: number): void {
    this.getUIContext().postFrameCallback(new RankingBoardSnapFrame((timeInNano: number): void => {
      if (!this.alive || token !== this.snapToken || !this.snapActive) return;
      const now: number = timeInNano / 1000000;
      if (this.snapStartAt < 0) {
        this.snapStartAt = now;
        this.postSnapFrame(token);
        return;
      }
      const elapsed: number = now - this.snapStartAt;
      if (elapsed >= this.snapDuration) {
        this.fanPosition = this.snapTarget;
        this.snapActive = false;
        this.fanMovingSign = 0;
        this.setInfoFocus(this.snapTarget, true);
        return;
      }
      const progress: number = this.decelerateProgress(elapsed / this.snapDuration);
      this.fanPosition = this.snapFrom + (this.snapTarget - this.snapFrom) * progress;
      // 甩动过程中也按画面中心实时换标题，而不是等停稳。
      this.setInfoFocus(this.visualCenterIndex());
      this.postSnapFrame(token);
    }));
  }

  /** AppCurve.Decelerate = cubicBezier(0,0,0,1)，等价于 y = 3x^(2/3) - 2x。 */
  private decelerateProgress(t: number): number {
    const x: number = Math.max(0, Math.min(1, t));
    const c: number = Math.pow(x, 1 / 3);
    return 3 * c * c - 2 * x;
  }

  build() {
    if (this.books.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.books, (book: RankingBook, index: number) => {
          this.podiumCard(book, index)
        }, (book: RankingBook): string => book.id)
      }.width('100%').height(this.fanHeight())
      .opacity(this.fanOpacity)
      .id(`rankingBoardPodiumHost-${this.boardId}`)
      .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
        const next: number = Number(newSize.width);
        if (Number.isFinite(next) && next > 0 && Math.abs(next - this.podiumWidth) > 0.5) {
          this.podiumWidth = next;
        }
      })
      .onTouch((event: TouchEvent): void => this.handleTouch(event))
      // 五卡横滑自己吃掉，避免同时触发外层“右滑切书架”的手势。
      .onTouchTestDone((_event: BaseGestureEvent, recognizers: GestureRecognizer[]): void => {
        for (const recognizer of recognizers) {
          if (recognizer instanceof PanRecognizer &&
              recognizer.getDirection() === PanDirection.Horizontal) {
            recognizer.preventBegin();
          }
        }
      })
    }
  }
}

@ComponentV2
struct RankingSection {
  @Require @Param board: RankingBoard;
  @Param hiddenId: string = '';
  /** 查看榜单转场：标题/页面淡出、目标货架保留、前 5 张卡聚拢。 */
  @Param chromeOpacity: number = 1;
  @Param shelfOpacity: number = 1;
  @Param gatherBoardId: string = '';
  @Param gatherProgress: number = 0;
  /** 聚拢后整组缩小，底边仍停在底栏上方。 */
  @Param gatherShrink: number = 0;
  /** MainPage 实测底栏占用高度，透传给货架算聚拢目标线。 */
  @Param bottomInset: number = 0;
  /** 页面实测的卡片集目标底边（window vp），优先于底栏高度推算。 */
  @Param gatherBottomTarget: number = 0;
  /** 打开转场瞬间货架宿主的窗口顶边。 */
  @Param shelfTop: number = 0;
  /** 递增后货架输出五张牌堆的最终视觉快照。 */
  @Param gatherSnapshotToken: number = 0;
  @Event onGatherSnapshot: (cells: RankingGatherCell[]) => void =
    (_cells: RankingGatherCell[]): void => {};
  @Event onOpenCard: (book: RankingBook, origin: CardOrigin) => void = () => {};

  private openAudioCard(book: RankingBook): void {
    const key: string = `rankingAudioCover-${this.board.id}-${book.id}`;
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), key);
      if (!rect.isValid()) return;
      this.onOpenCard(book, new CardOrigin(WindowUtils.pxToVp(rect.leftPx + rect.widthPx / 2),
        WindowUtils.pxToVp(rect.topPx + rect.heightPx / 2), WindowUtils.pxToVp(rect.widthPx), key,
        WindowUtils.pxToVp(rect.heightPx)));
    } catch (_error) { /* 未完成布局时等待下一次点击，不生成虚假的屏幕中心卡位。 */ }
  }
  @Event onMore: (board: RankingBoard) => void = () => {};
  /** 货架当前居中卡：打开查看榜单时用它做收拢锚点。 */
  @Event onCenterChange: (boardId: string, book: RankingBook, index: number) => void =
    (_boardId: string, _book: RankingBook, _index: number): void => {};
  @Local shelfBooks: RankingBook[] = [];
  /** 货架中间那张：标题区随滑动更新。 */
  @Local focusBook: RankingBook | undefined = undefined;
  @Local focusIndex: number = 0;
  /** 标题淡出淡入：旧标题单独一层，快速连变时立即让位，避免多条标题叠字。 */
  @Local prevBook: RankingBook | undefined = undefined;
  @Local prevIndex: number = 0;
  @Local focusOpacity: number = 1;
  @Local prevOpacity: number = 0;
  /** 递增后让货架用同一套惯性动画回到 TOP1。 */
  @Local scrollTopToken: number = 0;
  /** 榜单区块自身的宽度：分栏/折叠屏下不能用整窗宽度判断平板形态。 */
  @Local sectionWidth: number = WindowUtils.getWindowWidthVp();
  private headerToken: number = 0;
  private lastFocusAt: number = 0;
  private sectionAlive: boolean = true;
  private audioData: HomeRecommendationDataSource<RankingBook> = new HomeRecommendationDataSource<RankingBook>();

  aboutToAppear(): void {
    this.sectionAlive = true;
    this.syncBooks();
  }

  aboutToDisappear(): void {
    this.sectionAlive = false;
    this.headerToken++;
  }
  @Monitor('board')
  updateBoard(): void { this.syncBooks(); }

  private syncBooks(): void {
    // 用整块榜单数据；货架只渲染窗口内的卡片，数量放开不会增加节点。
    const books = this.board.books;
    this.shelfBooks = books;
    this.audioData.setItems(books);
    this.focusBook = books[0];
    this.focusIndex = 0;
    this.headerToken++;
    this.prevBook = undefined;
    this.prevIndex = 0;
    this.focusOpacity = 1;
    this.prevOpacity = 0;
    this.lastFocusAt = 0;
    if (books.length > 0) this.onCenterChange(this.board.id, books[0], 0);
  }

  /** 慢速切换走完整淡出淡入；180ms 内连续切换则旧标题立即让位，避免叠字。 */
  private updateFocus(book: RankingBook, index: number): void {
    if (this.focusBook !== undefined && this.focusBook.id === book.id) {
      this.focusIndex = index;
      return;
    }
    this.onCenterChange(this.board.id, book, index);
    const now: number = Date.now();
    const fast: boolean = now - this.lastFocusAt < 180;
    this.lastFocusAt = now;
    const previous: RankingBook | undefined = this.focusBook;
    const previousIndex: number = this.focusIndex;
    this.focusIndex = index;
    const token: number = ++this.headerToken;
    if (fast) {
      this.prevBook = undefined;
      this.prevOpacity = 0;
      this.focusBook = book;
      this.focusOpacity = 1;
      return;
    }
    this.prevBook = previous;
    this.prevIndex = previousIndex;
    this.prevOpacity = 1;
    this.focusBook = book;
    this.focusOpacity = 0;
    // 先让这一帧把"旧标题 1 / 新标题 0"真正渲染出来，下一帧再启动淡入淡出；
    // 否则新建节点会直接以终点值出生，看起来没有动画。
    setTimeout((): void => {
      if (!this.sectionAlive || token !== this.headerToken) return;
      this.getUIContext().animateTo({ duration: AppMotion.Fast, curve: AppCurve.Accelerate }, (): void => {
        if (token === this.headerToken) this.prevOpacity = 0;
      });
      this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Decelerate,
        onFinish: (): void => {
          if (token !== this.headerToken) return;
          this.prevBook = undefined;
          this.prevOpacity = 0;
        } }, (): void => {
        if (token === this.headerToken) this.focusOpacity = 1;
      });
    }, 20);
  }

  private headerRank(book: RankingBook | undefined, fallback: number): string {
    if (book === undefined) return '';
    const order: number = book.rank > 0 ? book.rank : fallback;
    return order.toString().padStart(2, '0');
  }

  private headerTitle(book: RankingBook | undefined): string {
    return book !== undefined ? book.title : '';
  }

  private headerAuthor(book: RankingBook | undefined): string {
    return book !== undefined ? (book.author || book.narrator || '') : '';
  }

  private headerRating(book: RankingBook | undefined): string {
    return book !== undefined && book.rating > 0 ? book.rating.toFixed(1) : '';
  }

  private isTabletSection(): boolean {
    return this.sectionWidth >= AdaptiveLayout.MEDIUM_WIDTH;
  }

  private tabletTitleMax(): number {
    return Math.max(160, this.sectionWidth * 0.42);
  }

  private tabletAuthorMax(): number {
    return Math.max(80, this.sectionWidth * 0.20);
  }

  /** 平板：把左侧两行焦点标签改成货架上方居中一行，和查看榜单同一形态。 */
  @Builder
  private tabletFocusHeader() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.prevBook !== undefined) {
        Row({ space: 6 }) {
          Text(this.headerRank(this.prevBook, this.prevIndex + 1)).fontSize(26)
            .fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).height(34)
          Text(this.headerTitle(this.prevBook)).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.tabletTitleMax() })
          if (this.headerAuthor(this.prevBook).length > 0) {
            Text('·').fontSize(11).fontColor(AppTheme.TextTertiary)
            Text(this.headerAuthor(this.prevBook)).fontSize(11).fontColor(AppTheme.TextSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: this.tabletAuthorMax() })
          }
          if (this.headerRating(this.prevBook).length > 0) {
            Text(this.headerRating(this.prevBook)).fontSize(11).fontColor(AppColor.Brand)
          }
        }.width('100%').height(36).padding({ left: 60, right: 60 })
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .opacity(this.prevOpacity)
      }
      if (this.focusBook !== undefined) {
        Row({ space: 6 }) {
          Text(this.headerRank(this.focusBook, this.focusIndex + 1)).fontSize(26)
            .fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).height(34)
          Text(this.headerTitle(this.focusBook)).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.tabletTitleMax() })
          if (this.headerAuthor(this.focusBook).length > 0) {
            Text('·').fontSize(11).fontColor(AppTheme.TextTertiary)
            Text(this.headerAuthor(this.focusBook)).fontSize(11).fontColor(AppTheme.TextSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: this.tabletAuthorMax() })
          }
          if (this.headerRating(this.focusBook).length > 0) {
            Text(this.headerRating(this.focusBook)).fontSize(11).fontColor(AppColor.Brand)
          }
        }.width('100%').height(36).padding({ left: 60, right: 60 })
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .opacity(this.focusOpacity)
      }
      Row() {
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_to_line')).fontSize(16)
            .fontColor([AppTheme.TextSecondary])
        }
        .width(30).height(30)
        .backgroundColor($r('app.color.glass_stroke'))
        .onClick((): void => { this.scrollTopToken++; })
        .accessibilityText($r('app.string.ranking_back_top'))
      }.width('100%').height(36).padding({ left: 24, right: 18 })
    }.width('100%').height(36).opacity(this.chromeOpacity)
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 5 }) {
          Text() {
            Span(this.board.title).fontSize(23).fontWeight(FontWeight.Bold)
            Span($r('app.string.ranking_label_separator')).fontSize(16)
            Span(this.board.platformName).fontSize(16).fontWeight(FontWeight.Medium)
          }.fontColor(AppTheme.TextPrimary).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('rankingSectionTitle-' + this.board.id)
          if (this.board.fetchedAt > 0) {
            Text(rankingUpdateTime(this.board.fetchedAt)).fontSize(11).fontColor(AppTheme.TextSecondary)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button($r('app.string.ranking_more'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(12).fontColor(AppTheme.TextSecondary).height(44)
          .onClick(() => this.onMore(this.board))
      }.width('100%').padding({ left: 24, right: 18 }).opacity(this.chromeOpacity)
      if (this.board.books.length === 0) {
        Text(this.board.unavailable ? $r('app.string.ranking_unavailable') : $r('app.string.ranking_loading'))
          .fontSize(13).fontColor(AppTheme.TextTertiary).width('100%').height(90)
      } else if (this.board.books[0]?.contentType !== 'audio') {
        Column({ space: 4 }) {
          if (this.isTabletSection()) {
            this.tabletFocusHeader()
          } else {
            Row({ space: 4 }) {
            Stack() {
              if (this.prevBook !== undefined) {
                Row({ space: 10 }) {
                  Text(this.headerRank(this.prevBook, this.prevIndex + 1)).fontSize(28)
                    .fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).height(38)
                  Column({ space: 2 }) {
                    Text(this.headerTitle(this.prevBook)).fontSize(15).fontWeight(FontWeight.Bold)
                      .fontColor(AppTheme.TextPrimary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.headerAuthor(this.prevBook)).fontSize(10)
                      .fontColor(AppTheme.TextSecondary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%').height(38).padding({ left: 24, right: 8 })
                  .alignItems(VerticalAlign.Center).opacity(this.prevOpacity)
              }
              if (this.focusBook !== undefined) {
                Row({ space: 10 }) {
                  Text(this.headerRank(this.focusBook, this.focusIndex + 1)).fontSize(28)
                    .fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).height(38)
                  Column({ space: 2 }) {
                    Text(this.headerTitle(this.focusBook)).fontSize(15).fontWeight(FontWeight.Bold)
                      .fontColor(AppTheme.TextPrimary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.headerAuthor(this.focusBook)).fontSize(10)
                      .fontColor(AppTheme.TextSecondary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%').height(38).padding({ left: 24, right: 8 })
                  .alignItems(VerticalAlign.Center).opacity(this.focusOpacity)
              }
            }.width('100%').height(38).layoutWeight(1)
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_up_to_line')).fontSize(16)
                .fontColor([AppTheme.TextSecondary])
            }
            .width(30).height(30)
            .backgroundColor($r('app.color.glass_stroke'))
            .margin({ right: 24 })
            .onClick((): void => { this.scrollTopToken++; })
            .accessibilityText($r('app.string.ranking_back_top'))
          }.width('100%').height(38).opacity(this.chromeOpacity)
          }
          RankingShelf({ books: this.shelfBooks, hiddenId: this.hiddenId, shelfKey: this.board.id,
            gatherBoardId: this.gatherBoardId, gatherProgress: this.gatherProgress,
            gatherShrink: this.gatherShrink, bottomInset: this.bottomInset,
            gatherBottomTarget: this.gatherBottomTarget, hostTop: this.shelfTop,
            gatherSnapshotToken: this.gatherSnapshotToken,
            onGatherSnapshot: this.onGatherSnapshot,
            scrollTopToken: this.scrollTopToken,
            onChoose: this.onOpenCard,
            onFocusChange: (book: RankingBook, index: number): void => {
              this.updateFocus(book, index);
            } })
            .id('rankingShelfHost-' + this.board.id)
            .opacity(this.shelfOpacity)
        }.width('100%')
      } else {
        List({ space: 16 }) {
          LazyForEach(this.audioData, (book: RankingBook) => {
            ListItem() {
              Column({ space: 9 }) {
                Stack({ alignContent: Alignment.BottomStart }) {
                  CoverImage({ url: book.coverUrl, imgWidth: 152, imgHeight: 152, useFixedHeight: true,
                    radius: RankingCardStyle.RADIUS, imageFit: ImageFit.Cover,
                    compositeEdges: true })
                  Text(book.rank.toString().padStart(2, '0')).fontSize(30).fontWeight(FontWeight.Bold)
                    .fontColor(Color.White).textShadow({ radius: 10, color: '#66000000', offsetY: 2 })
                    .margin({ left: 10, bottom: 7 })
                  Row() {
                    Blank()
                    BookRatingBadge({ rating: book.rating, coverWidth: 152 })
                  }.width(152).hitTestBehavior(HitTestMode.None)
                }.width(152).height(152).attributeModifier(new RankingCardClip())
                .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
                  offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
                .id(`rankingAudioCover-${this.board.id}-${book.id}`)
                .opacity(this.hiddenId === `rankingAudioCover-${this.board.id}-${book.id}` ? 0 : 1)
                Text(book.title).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TextPrimary).maxLines(2).height(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(book.narrator || book.author).fontSize(11).fontColor(AppTheme.TextSecondary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width(152).alignItems(HorizontalAlign.Start)
              .onClick((): void => this.openAudioCard(book))
            }
          }, (book: RankingBook): string => book.id)
        }.listDirection(Axis.Horizontal).height(228).width('100%').scrollBar(BarState.Off)
        .id('rankingShelfHost-' + this.board.id)
        .onScrollIndex((start: number): void => {
          const book: RankingBook | undefined = this.board.books[start];
          if (book !== undefined) this.updateFocus(book, start);
        })
        .contentStartOffset(24).contentEndOffset(24).cachedCount(1)
        .opacity(this.shelfOpacity)
      }
      if (this.board.stale) {
        Text($r('app.string.ranking_cached')).fontSize(11).fontColor(AppTheme.TextTertiary)
          .width('100%').padding({ left: 24, right: 24 }).opacity(this.chromeOpacity)
      }
      Divider().color(AppColor.Divider).margin({ left: 24, right: 24, top: 2 })
        .opacity(this.chromeOpacity)
    }.width('100%').padding({ top: 8, bottom: 0 }).alignItems(HorizontalAlign.Start)
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const width: number = Number(size.width);
      if (Number.isFinite(width) && width > 0) this.sectionWidth = width;
    })
  }
}

class RankingPosterItem {
  book: RankingBook;
  constructor(book: RankingBook) {
    this.book = book;
  }
}

@Builder
function rankingEmptyHeader() { Row().height(56) }

class RankingMatchRestoreFrame extends FrameCallback {
  private restore: () => void;
  constructor(restore: () => void) { super(); this.restore = restore; }
  onIdle(_timeLeftInNano: number): void { this.restore(); }
}

@ComponentV2
export struct RankingHomePage {
  @Param visible: boolean = true;
  @Param customBackground: boolean = false;
  /** 底部占用高度（系统避让区 + 底栏），由 MainPage 逐层透传，供详情卡片避让。 */
  @Param bottomTabInset: number = 0;
  /** 详情态确认后由页面打开阅读器；resourceIndex 用于目录点章，返回时回调 onReturn。 */
  @Event onOpenReader: (book: Book, onReturn: () => void, resourceIndex?: number) => void = () => {};
  /** 阅读/收听记录。 */
  @Event onOpenHistory: (book: Book) => void = () => {};
  /** 璁板綍閲屸€滆烦鍥炩€濇寚瀹氫綅缃€?*/
  @Event onHistoryJump: (session: ReadingSession, location: SessionLocation) => void = () => {};
  @BuilderParam headerBuilder: () => void = rankingEmptyHeader;
  @Event onBookTap: (id: string, resume: () => void) => void = () => {};
  @Event onSearchTap: () => void = () => {};
  @Event onManageSources: (resume: () => void) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onContentScroll: (offset: number, state: ScrollState) => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Local boards: RankingBoard[] = [];
  @Local platformId: string = '';
  @Local activeBoard: RankingBoard | undefined = undefined;
  @Local boardTransitioning: boolean = false;
  /** 最普通的页面淡入淡出：0 透明，1 完全显示。 */
  @Local boardPageFade: number = 1;
  /** 查看榜单的共享元素转场：1 首页卡收拢、2 榜单卡散开、3 关闭回位。 */
  @Local boardFlowActive: boolean = false;
  @Local boardFlowPhase: number = 0;
  @Local boardFlowT: number = 0;
  @Local boardFlowReveal: number = 1;
  /** 榜单页非五卡内容（标题/网格）的透明度。 */
  @Local boardFlowChrome: number = 1;
  /** 榜单标题/更新时间：和抽卡同步淡入。 */
  @Local boardFlowTitle: number = 1;
  /** 焦点标题：中心卡落位完成时单独淡入，不跟角标共用。 */
  @Local boardFlowFocus: number = 1;
  /** 聚拢和整组缩小同时进行。 */
  @Local boardFlowShrink: number = 0;
  /** 递增后首页货架输出五张牌堆的最终视觉快照。 */
  @Local boardFlowGatherSnapshotToken: number = 0;
  /** 扇形焦点标题（页面独立渲染，层级在五卡和发牌卡下方）。 */
  @Local boardFanFocusBook: RankingBook | undefined = undefined;
  @Local boardFanFocusIndex: number = 0;
  @Local boardFanFocusPrevBook: RankingBook | undefined = undefined;
  @Local boardFanFocusPrevIndex: number = -1;
  @Local boardFanFocusOpacity: number = 1;
  @Local boardFanFocusPrevOpacity: number = 0;
  /** 榜单五卡真实节点：arrival 从卡片集散开，exit 飞回首页槽位。 */
  @Local boardFlowPodiumMode: string = '';
  @Local boardFlowPodiumProgress: number = 1;
  @Local boardFlowPodiumDx: number[] = [];
  @Local boardFlowPodiumDy: number[] = [];
  @Local boardFlowRelayWidths: number[] = [];
  /** 牌堆交接的堆叠顺序、起始层级和起始角度，保证首页/榜单是同一个牌堆。 */
  @Local boardFlowStartZ: number[] = [];
  @Local boardFlowStartOrder: number[] = [];
  @Local boardFlowStartAngles: number[] = [];
  /** 反向取消时让榜单牌堆的首页封面层重新浮出来。 */
  @Local boardFlowCoverBackToken: number = 0;
  /** 当前中心卡名次、牌堆转场层、网格发牌/翻面。 */
  @Local boardFlowCenterRank: number = 1;
  @Local boardFlowStackVisible: boolean = false;
  @Local boardFlowStackBlockTop: boolean = true;
  @Local boardFlowStackT: number = 0;
  /** >5 滚动过程中中心卡逐渐缩小；1 为牌堆原尺寸，ratio 为最终格子尺寸。 */
  @Local boardFlowCenterShrink: number = 1;
  @Local boardFlowStackX: number = 0;
  @Local boardFlowStackY: number = 0;
  @Local boardFlowStackW: number = 0;
  @Local boardFlowStackH: number = 0;
  /** 牌堆中心的 window 坐标：榜单五卡从它起飞，由五卡组件自己换算到局部坐标。 */
  @Local boardFlowStartWindowX: number = 0;
  @Local boardFlowStartWindowY: number = 0;
  @Local boardFlowStartWindowW: number = 0;
  /** 首页牌堆五张真实卡的相对错位/宽度，交接给榜单五卡时保持牌堆形状。 */
  @Local boardFlowStartOffsetsX: number[] = [];
  @Local boardFlowStartOffsetsY: number[] = [];
  @Local boardFlowStartWidths: number[] = [];
  /** 首页五张真实卡实测中心（window）：牌堆在 t=0 直接对齐到这里，不再靠 dx/dy 推。 */
  @Local boardFlowStartCentersX: number[] = [];
  @Local boardFlowStartCentersY: number[] = [];
  /** 01–05 的新转场牌堆：独立五卡，只用首页/扇形的实测 rect。 */
  @Local boardDeckVisible: boolean = false;
  @Local boardDeckPullToken: number = 0;
  @Local boardDeckGatherToken: number = 0;
  @Local boardDeckCancelToken: number = 0;
  @Local boardDeckCover: number = 0;
  /** 过渡牌堆淡出透明度：落位时先让真实扇形在下面就绪，再撤掉过渡层。 */
  @Local boardDeckOpacity: number = 1;
  @Local boardDeckCards: BoardDeckCardData[] = [];
  @Local boardPodiumPrepareToken: number = 0;
  private boardPodiumPulling: boolean = false;
  /** 新转场期间真实扇形先隐藏，落位同一帧再显示。 */
  @Local boardFanVisible: boolean = true;
  @Local boardHomeRelayReady: boolean = false;
  private boardDeckRootX: number = 0;
  private boardDeckRootY: number = 0;
  /** 交接时先显示的首页封面，随后淡化到榜单封面，保证封面身份连续。 */
  @Local boardFlowStartCovers: string[] = [];
  @Local boardFlowCenterTargetX: number = 0;
  @Local boardFlowCenterTargetY: number = 0;
  @Local boardFlowCenterTargetW: number = 0;
  @Local boardFlowCenterTargetH: number = 0;
  @Local boardFlowGhostVisible: boolean = false;
  @Local boardFlowGridMode: string = '';
  @Local boardFlowGridVisible: boolean = false;
  /** 网格整行淡入：不用布尔 opacity，避免整块直接出现。 */
  @Local boardFlowGridReveal: number = 1;
  /** “更多好书”横栏的淡入/上移进度。 */
  @Local boardFlowGridBar: number = 0;
  @Local boardFlowGridDealToken: number = 0;
  @Local boardFlowGridFlipToken: number = 0;
  /** 中心卡落位过程中，后一页白背先淡入；翻面等落位完成。 */
  @Local boardFlowGridWhiteToken: number = 0;
  @Local boardFlowGridFirstRank: number = 0;
  @Local boardFlowGridLastRank: number = 0;
  /** 榜单列表当前滚动偏移：发牌目标要跟着滚动走，不能停在起飞时的位置。 */
  @Local boardFlowListOffset: number = 0;
  /** 中心卡后面的白卡范围：只让最终这一页的卡先白后翻。 */
  @Local boardFlowFlipLastRank: number = 0;
  @Local boardFlowGridFromX: number = 0;
  @Local boardFlowGridFromY: number = 0;
  @Local boardFlowGridFromW: number = 0;
  @Local boardFlowCenterReady: boolean = false;
  @Local boardFlowFocusToken: number = 0;
  /** 牌堆顶卡封面：首页卡片可能只在组件内部补图，转场层自己再解析一次。 */
  @Local boardFlowCenterCover: string = '';
  private boardFlowBoard: RankingBoard | undefined = undefined;
  private boardFlowToken: number = 0;
  private boardFlowPullStartAt: number = -1;
  /** 取消抽卡时的反向帧驱动状态。 */
  private boardFlowCancelFrom: number = 0;
  private boardFlowCancelStartAt: number = -1;
  private boardFlowCancelDuration: number = 0;
  /** 本次转场实测的卡片集目标底边（window vp）。 */
  private boardFlowTargetBottom: number = 0;
  /** 首页货架最终输出的五张牌堆快照。 */
  private boardFlowDeckCells: RankingGatherCell[] = [];
  /** 焦点标题的旧/新交叉淡入 token。 */
  private boardFanFocusToken: number = 0;
  private boardFanFocusLastAt: number = 0;
  private boardFlowSourceShelf: BoardFlowRect = new BoardFlowRect();
  private boardFlowSourceRects: BoardFlowRect[] = [];
  private boardFlowCenterBook: RankingBook | undefined = undefined;
  private boardFlowCenterIndex: number = 0;
  /** >5 逐行滚动：榜单网格第一行的内容起点（滚动前量一次）。 */
  private boardFlowGridContentStartY: number = 0;
  /** >5 自动滚动期间：滚动到哪一批就发哪一批。 */
  private boardFlowAutoDealActive: boolean = false;
  private boardFlowAutoDealLastAt: number = 0;
  private boardFlowStackRect: BoardFlowRect = new BoardFlowRect();
  private boardFlowCenterTargetRect: BoardFlowRect = new BoardFlowRect();
  private boardFlowGridFromRect: BoardFlowRect = new BoardFlowRect();
  /** 每个榜单货架当前居中的书：打开查看榜单时作为锚点。 */
  private homeFocusBooks: Map<string, RankingBook> = new Map<string, RankingBook>();
  private homeFocusIndexes: Map<string, number> = new Map<string, number>();
  @Local boardFabVisible: boolean = false;
  @Local boardTopToken: number = 0;
  @Local fanDragging: boolean = false;
  @Local posterCount: number = 0;
  @Local posterVisible: boolean = false;
  @Local posterCover: string = '';
  @Local contentHeight: number = 800;
  @Local headerOffset: number = 0;
  @Local overview: boolean = false;
  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local refreshPullOffset: number = 0;
  /** 完整榜单下拉不再逐帧推动背后的首页布局。 */
  @Local boardRefreshPullOffset: number = 0;
  @Local menuViewportWidth: number = 360;
  private boardColumnCount: number = 0;
  @Local openingBook: boolean = false;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  @Local leftSafe: number = WindowUtils.getLeftSafeVp();
  @Local rightSafe: number = WindowUtils.getRightSafeVp();
  @Local platforms: RankingPlatform[] = RankingService.platforms();
  @Local showBoardOrder: boolean = false;
  @Local boardOrderBounds: BoardFlowRect = new BoardFlowRect();
  @Local cardVisible: boolean = false;
  @Local cardBook: RankingBook = new RankingBook();
  @Local cardBookId: string = '';
  private readonly rankingSettingsListener = (): void => { this.reloadCategories(); };

  private async reloadCategories(): Promise<void> {
    try {
      const settings = await RankingPreferences.load();
      const boardOrder = await RankingPreferences.loadBoardOrder();
      if (!this.alive) return;
      const enabled = settings.filter((item: RankingCategorySetting): boolean => item.enabled);
      this.platforms = [RankingService.platforms()[0]].concat(enabled.map((item: RankingCategorySetting): RankingPlatform =>
        new RankingPlatform(item.id, item.name)));
      this.platformData.setItems(this.platforms);
      if (!this.platforms.some((item: RankingPlatform): boolean => item.id === this.platformId)) this.platformId = '';
      const previous = this.boards;
      const all = RankingService.boards();
      const next: RankingBoard[] = [];
      for (const platform of enabled) {
        for (const board of all.filter((item: RankingBoard): boolean => item.platformId === platform.id)) {
          next.push(previous.find((item: RankingBoard): boolean => item.id === board.id) ?? board);
        }
      }
      this.boards = RankingPreferences.orderBoards(next, boardOrder);
      this.syncBoards();
      this.load(false);
    } catch (_error) {
      // 偏好读取失败时保留默认或当前配置，不覆写保存值。
      if (this.alive) this.load(false);
    }
  }
  private boardData: HomeRecommendationDataSource<RankingBoard> = new HomeRecommendationDataSource<RankingBoard>();
  /** 完整榜单网格按列分组后的行数据，保持 LazyForEach 懒加载。 */
  private gridRowsData: HomeRecommendationDataSource<RankingBook[]> =
    new HomeRecommendationDataSource<RankingBook[]>();
  private platformData: HomeRecommendationDataSource<RankingPlatform> = new HomeRecommendationDataSource<RankingPlatform>();
  @Local posterItems: RankingPosterItem[] = [];

  @Computed
  get posterDeckItems(): BookPosterItem[] {
    return this.posterItems.map((item: RankingPosterItem): BookPosterItem => new BookPosterItem(
      item.book.id, item.book.title, item.book.author || item.book.narrator, item.book.intro,
      item.book.coverUrl, item.book.contentType !== 'audio' ? 0.75 : 1, item.book.rating));
  }

  private categoryScroller: Scroller = new Scroller();
  private posterIdentity: string = '';
  private posterPlatformId: string = '';
  private scroller: Scroller = new Scroller();
  private boardScroller: Scroller = new Scroller();
  private headerScroller: Scroller = new Scroller();
  private readonly navigationBottomBuilder: CustomBuilder = (): void => this.navigationBottom();
  private readonly searchHeaderBuilder: CustomBuilder = (): void => this.searchHeader();
  private generation: number = 0;
  private alive: boolean = false;
  // 内外层导航及独立榜单使用同一主题字色，避免滚动时互相覆盖。
  @Local statusBarContentColor: string = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  private readonly statusBarColorListener = (): void => {
    this.statusBarContentColor = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  };
  private readonly safeAreaListener = (top: number, _bottom: number): void => {
    this.topSafe = top;
    this.leftSafe = WindowUtils.getLeftSafeVp();
    this.rightSafe = WindowUtils.getRightSafeVp();
  };

  aboutToAppear(): void {
    this.alive = true;
    this.statusBarColorListener();
    WindowUtils.addReaderColorListener(this.statusBarColorListener);
    this.platformData.setItems(this.platforms);
    this.onScrollerReady(this.headerScroller);
    this.onBackHandlerChange((): boolean => {
      // 转场中返回：走按阶段反向取消，不能把事件直接吞掉。
      if (this.boardFlowActive) {
        this.cancelBoardFlow();
        return true;
      }
      if (this.showBoardOrder) { this.showBoardOrder = false; return true; }
      if (this.activeBoard !== undefined) { this.closeBoard(); return true; }
      if (this.overview) { this.selectPlatform(''); return true; }
      return false;
    });
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    RankingPreferences.subscribe(this.rankingSettingsListener);
    this.reloadCategories();
  }

  aboutToDisappear(): void {
    RankingPreferences.unsubscribe(this.rankingSettingsListener);
    WindowUtils.removeReaderColorListener(this.statusBarColorListener);
    this.alive = false;
    this.generation++;
    this.boardFlowToken++;
    this.closeCard();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange(undefined);
  }

  @Monitor('visible')
  updateHomeVisibility(): void {
    if (this.visible) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
      this.syncBoards();
    }
  }

  private randomPosterPlatform(previousId: string): string {
    const available = this.platforms.filter((platform: RankingPlatform): boolean =>
      platform.id.length > 0 && this.boards.some((board: RankingBoard): boolean =>
        board.platformId === platform.id && board.books.length > 0));
    // 按平台等概率抽取；存在其他可用平台时，避免连续两次抽中同一个。
    const alternatives = available.filter((platform: RankingPlatform): boolean => platform.id !== previousId);
    const candidates = alternatives.length > 0 ? alternatives : available;
    return candidates.length > 0 ? candidates[Math.floor(Math.random() * candidates.length)].id : '';
  }

  private syncBoards(): void {
    const visible = this.boards.filter((board: RankingBoard): boolean => !this.platformId || board.platformId === this.platformId);
    this.boardData.setItems(visible);
    if (!this.boards.some((board: RankingBoard): boolean =>
      board.platformId === this.posterPlatformId && board.books.length > 0)) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
    }
    const posterPlatformId = this.posterPlatformId;
    const posterBoards = this.boards.filter((board: RankingBoard): boolean =>
      posterPlatformId.length > 0 && board.platformId === posterPlatformId);
    const posters: RankingPosterItem[] = [];
    const seen = new Set<string>();
    // 从当前平台各榜轮流取书，最多六张；同一本书跨榜不重复。
    for (let index = 0; index < 6 && posters.length < 6; index++) {
      for (const board of posterBoards) {
        const book = board.books[index];
        if (book === undefined || seen.has(book.id) || posters.length >= 6) continue;
        seen.add(book.id);
        posters.push(new RankingPosterItem(book));
        const context = this.getUIContext().getHostContext();
        if (context !== undefined) {
          RankingComicMetadata.hydrate(context, book).then((): void => {
            // 封面是异步补的：换一个新数组让 posterDeckItems 重算，轮播才会从占位图换成真封面。
            if (this.posterItems.some((item: RankingPosterItem): boolean => item.book.id === book.id)) {
              this.posterItems = this.posterItems.slice();
            }
            if (this.posterItems[0]?.book.id === book.id && !this.posterCover) this.posterCover = book.coverUrl;
          });
        }
      }
    }
    const posterIdentity = posters.map((item: RankingPosterItem): string => item.book.id).join('|');
    if (this.posterIdentity !== posterIdentity) {
      this.posterIdentity = posterIdentity;
      this.posterItems = posters;
      this.posterCount = posters.length;
      this.posterCover = posters[0]?.book.coverUrl ?? '';
    }
    if (this.activeBoard !== undefined) {
      const id = this.activeBoard.id;
      const updated = this.boards.find((board: RankingBoard): boolean => board.id === id);
      if (updated !== this.activeBoard) {
        this.activeBoard = updated;
        this.setBoardContent(updated);
      }
    }
  }

  private async load(force: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) { this.loading = false; this.refreshing = false; return; }
    const generation = ++this.generation;
    this.loading = true;
    try {
      // 当前平台优先加载；精品推荐沿用用户保存的单榜顺序。
      const snapshot = this.boards.filter((board: RankingBoard): boolean =>
        !this.platformId || board.platformId === this.platformId).concat(
        this.boards.filter((board: RankingBoard): boolean =>
          this.platformId.length > 0 && board.platformId !== this.platformId));
      await RankingService.loadProgressively(context, snapshot, force,
        (loaded: RankingBoard): void => {
          this.boards = this.boards.map((entry: RankingBoard): RankingBoard => entry.id === loaded.id ? loaded : entry);
          this.syncBoards();
        }, (): boolean => generation === this.generation);
    } finally {
      if (generation === this.generation) { this.loading = false; this.refreshing = false; }
    }
  }

  private handlePlatformSwipe(event: GestureEvent): void {
    if (GeneralSettings.current.swipeSwitchTabs) return;
    if (!this.visible || this.activeBoard !== undefined || this.boardTransitioning || this.refreshing) return;
    if (Math.abs(event.offsetX) < 48 || Math.abs(event.offsetX) <= Math.abs(event.offsetY) * 1.2) return;
    const current: number = this.overview ? -1 :
      this.platforms.findIndex((platform: RankingPlatform): boolean => platform.id === this.platformId);
    const next: number = current + (event.offsetX < 0 ? 1 : -1);
    if (next < -1 || next >= this.platforms.length) return;
    if (next === -1) {
      this.overview = true;
      return;
    }
    this.selectPlatform(this.platforms[next].id);
    try { this.categoryScroller.scrollToIndex(next, true, ScrollAlign.AUTO); } catch (_error) { /* 分类栏尚未挂载。 */ }
  }

  private selectPlatform(id: string): void {
    if (id.length === 0) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
    } else {
      this.posterPlatformId = id;
    }
    this.platformId = id;
    this.overview = false;
    this.syncBoards();
    // 不操作纵向滚动控制器；平台切换保持当前海报与分类栏位置。
  }

  private openBoard(board: RankingBoard): void {
    if (this.boardTransitioning || this.activeBoard !== undefined) return;
    this.boardRefreshPullOffset = 0;
    this.boardScroller = new Scroller();
    this.onScrollerReady(this.boardScroller);
    this.setBoardContent(board);
    this.prepareSimpleBoard(board);
    this.boardPageFade = 0;
    this.boardTransitioning = true;
    this.activeBoard = board;
    this.getUIContext().animateTo({
      duration: AppMotion.Base, curve: AppCurve.Standard,
      onFinish: (): void => {
        if (!this.alive) return;
        this.boardPageFade = 1;
        this.boardTransitioning = false;
      }
    }, (): void => {
      this.boardPageFade = 1;
    });
  }

  /** 最简单开榜：不聚拢、不量卡片，只把榜单页正常状态准备好后整体淡入。 */
  private prepareSimpleBoard(board: RankingBoard): void {
    const firstBook: RankingBook | undefined = board.books.length > 0 ? board.books[0] : undefined;
    this.boardFlowActive = false;
    this.boardFlowPhase = 0;
    this.boardFlowT = 0;
    this.boardFlowReveal = 1;
    this.boardFlowChrome = 1;
    this.boardFlowTitle = 1;
    this.boardFlowFocus = 1;
    this.boardFlowBoard = board;
    this.boardFlowCenterBook = firstBook;
    this.boardFlowCenterCover = firstBook !== undefined ? firstBook.coverUrl : '';
    this.boardFlowCenterIndex = 0;
    this.boardFlowCenterRank = firstBook !== undefined ? firstBook.rank : 1;
    this.boardFanFocusBook = firstBook;
    this.boardFanFocusIndex = 0;
    this.boardFanFocusPrevBook = undefined;
    this.boardFanFocusPrevIndex = -1;
    this.boardFanFocusOpacity = 1;
    this.boardFanFocusPrevOpacity = 0;
    this.boardFanFocusToken++;
    this.boardFanFocusLastAt = 0;
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.boardFlowStackT = 0;
    this.boardFlowStackBlockTop = true;
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    this.boardFanVisible = true;
    this.boardDeckVisible = false;
    this.boardDeckCover = 1;
    this.boardDeckOpacity = 1;
    this.boardDeckCards = [];
    this.boardHomeRelayReady = false;
    this.boardFlowGridMode = '';
    this.boardFlowGridVisible = true;
    this.boardFlowGridReveal = 1;
    this.boardFlowGridBar = 1;
    this.boardFlowGridFirstRank = 0;
    this.boardFlowGridLastRank = 0;
    this.boardFlowFlipLastRank = 0;
    this.boardFlowCenterReady = true;
    this.boardFlowAutoDealActive = false;
    this.boardFabVisible = true;
    this.boardFlowActive = false;
  }

  private closeBoard(): void {
    if (this.boardTransitioning || this.activeBoard === undefined) return;
    this.boardRefreshPullOffset = 0;
    this.boardFabVisible = false;
    this.onScrollerReady(this.headerScroller);
    this.boardTransitioning = true;
    this.getUIContext().animateTo({
      duration: AppMotion.Base, curve: AppCurve.Standard,
      onFinish: (): void => {
        if (!this.alive) return;
        this.activeBoard = undefined;
        this.boardPageFade = 1;
        this.boardTransitioning = false;
        this.boardFlowActive = false;
        this.boardFlowPhase = 0;
        this.boardFlowBoard = undefined;
      }
    }, (): void => {
      this.boardPageFade = 0;
    });
  }

  private measureFlowRect(id: string): BoardFlowRect | undefined {
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), id);
      if (!rect.isValid()) return undefined;
      return new BoardFlowRect(WindowUtils.pxToVp(rect.leftPx), WindowUtils.pxToVp(rect.topPx),
        WindowUtils.pxToVp(rect.widthPx), WindowUtils.pxToVp(rect.heightPx));
    } catch (_error) {
      return undefined;
    }
  }

  private flowSourceCardRect(shelf: BoardFlowRect, index: number, cardW: number, cardH: number): BoardFlowRect {
    const step: number = Math.max(64, Math.min(cardW * 0.78, shelf.w / 4.2));
    const offsets: number[] = [0, step, step * 2, -step * 2, -step];
    const centerX: number = shelf.x + shelf.w / 2;
    const baseline: number = shelf.y + shelf.h - 20;
    return new BoardFlowRect(centerX + offsets[index] - cardW / 2,
      baseline - cardH, cardW, cardH);
  }

  private flowTargetFallback(index: number): BoardFlowRect {
    const width: number = Math.min(200, WindowUtils.getWindowWidthVp() * 0.24);
    const height: number = width / 0.75;
    const offsets: number[] = [0, width * 0.55, width * 1.1, -width * 1.1, -width * 0.55];
    return new BoardFlowRect(WindowUtils.getWindowWidthVp() / 2 + offsets[index] - width / 2,
      this.topSafe + 176 - (index === 0 ? 12 : 0), width, height);
  }

  private boardFlowCardWidth(shelf: BoardFlowRect): number {
    const grown: number = 120 + Math.max(0, shelf.w - 360) * 0.08;
    return Math.round(Math.max(120, Math.min(168, grown)));
  }

  private buildBoardFlowSources(board: RankingBoard): BoardFlowRect[] {
    const shelf: BoardFlowRect = this.boardFlowSourceShelf;
    const cardW: number = this.boardFlowCardWidth(shelf);
    const cardH: number = cardW / 0.746;
    const count: number = Math.min(5, board.books.length);
    const rects: BoardFlowRect[] = [];
    for (let index = 0; index < count; index++) {
      rects.push(this.flowSourceCardRect(shelf, index, cardW, cardH));
    }
    return rects;
  }

  /** 首页第 index 名卡片节点：普通状态下 id 用槽位号，关闭时能直接量到它的真实位置。 */
  private shelfCardFlowId(board: RankingBoard, index: number): string {
    const book: RankingBook | undefined = board.books[index];
    return book === undefined ? '' : `rankingCard-${board.id}-${index}-${book.id}`;
  }

  private measureBoardFlowSources(board: RankingBoard): BoardFlowRect[] {
    const fallback: BoardFlowRect[] = this.buildBoardFlowSources(board);
    const count: number = Math.min(5, board.books.length);
    const rects: BoardFlowRect[] = [];
    for (let index = 0; index < count; index++) {
      const measured: BoardFlowRect | undefined =
        this.measureFlowRect(this.shelfCardFlowId(board, index));
      rects.push(measured !== undefined ? measured : fallback[index]);
    }
    return rects;
  }

  private boardPodiumCardId(board: RankingBoard, index: number): string {
    const book: RankingBook | undefined = board.books[index];
    return book === undefined ? '' : `rankingBoardPodium-${board.id}-${book.rank}-${book.id}`;
  }

  private collectBoardTargets(board: RankingBoard): BoardFlowRect[] {
    const targets: BoardFlowRect[] = [];
    const count: number = this.podiumBookCount(board);
    for (let index = 0; index < count; index++) {
      const measured: BoardFlowRect | undefined =
        this.measureFlowRect(this.boardPodiumCardId(board, index));
      targets.push(measured !== undefined ? measured : this.flowTargetFallback(index));
    }
    return targets;
  }

  private boardFlowTopLimit(): number {
    return this.topSafe + RANKING_SEARCH_HEIGHT;
  }

  private boardFlowBottomLimit(): number {
    const bar: number = this.bottomTabInset > 0 ? this.bottomTabInset :
      WindowUtils.getFloatingTabBottomVp();
    return Math.max(this.boardFlowTopLimit() + 120,
      WindowUtils.getWindowHeightVp() - bar - 8);
  }

  /**
   * 卡片集目标底边：优先量真实迷你播放条顶边（HDS 浮动栏 windowOffset 不可靠，
   * 必须用 PlayerDragTransition 的绘制位置），没有迷你条再退回标签栏顶边。
   */
  private measureBoardFlowTargetBottom(): number {
    const windowH: number = WindowUtils.getWindowHeightVp();
    try {
      const bar = PlayerDragTransition.measure(this.getUIContext(), 'main-mini-bar');
      if (bar.isValid() && bar.heightPx > 0) {
        const top: number = WindowUtils.pxToVp(bar.topPx);
        if (Number.isFinite(top) && top > 0 && top < windowH) {
          return Math.max(0, top - FLOW_BAR_GAP);
        }
      }
    } catch (_error) { /* 迷你条未显示时走标签栏兜底 */ }
    if (this.bottomTabInset > 0) {
      // 浮动标签栏的 bottomTabInset 已包含内容呼吸区；旧版底栏则没有。
      return PlatformCompat.floatingTabs
        ? Math.max(0, windowH - this.bottomTabInset)
        : Math.max(0, windowH - this.bottomTabInset - FLOW_BAR_GAP);
    }
    return PlatformCompat.floatingTabs
      ? Math.max(0, windowH - WindowUtils.getFloatingTabBottomVp())
      : Math.max(0, windowH - WindowUtils.getFloatingTabBottomVp() - FLOW_BAR_GAP);
  }

  private gridCoverId(board: RankingBoard, book: RankingBook): string {
    return `rankingBoardCard-${board.id}-${book.rank}-${book.id}`;
  }

  private centerGridCoverId(board: RankingBoard): string {
    const book: RankingBook | undefined = this.boardFlowCenterBook;
    return book === undefined ? '' : this.gridCoverId(board, book);
  }

  private fallbackCenterRect(board: RankingBoard, centerIndex: number): BoardFlowRect {
    const shelf: BoardFlowRect = this.boardFlowSourceShelf;
    const cardW: number = this.boardFlowCardWidth(shelf);
    const cardH: number = cardW / 0.746;
    const scale: number = shelf.w >= 600 ? 1.16 : 1.12;
    const lift: number = shelf.w >= 600 ? 24 : 20;
    const visualW: number = cardW * scale;
    const visualH: number = cardH * scale;
    const centerX: number = shelf.x + shelf.w / 2;
    const centerY: number = shelf.y + 4 + lift + visualH / 2;
    return new BoardFlowRect(centerX - visualW / 2, centerY - visualH / 2, visualW, visualH);
  }

  private startBoardGatherDealFlow(board: RankingBoard): void {
    if (this.boardTransitioning || this.boardFlowActive || this.activeBoard !== undefined) return;
    this.boardRefreshPullOffset = 0;
    if (board.books.length === 0) {
      this.openBoard(board);
      return;
    }
    this.boardPageFade = 1;
    this.boardScroller = new Scroller();
    this.onScrollerReady(this.boardScroller);
    this.setBoardContent(board);
    this.boardFabVisible = false;
    this.boardFlowListOffset = 0;
    const token: number = ++this.boardFlowToken;
    const shelf: BoardFlowRect = this.measureFlowRect(`rankingShelfHost-${board.id}`) ??
      new BoardFlowRect(0, WindowUtils.getWindowHeightVp() * 0.52,
        WindowUtils.getWindowWidthVp(), 200);
    this.boardFlowBoard = board;
    this.boardFlowSourceShelf = shelf;
    this.boardFlowSourceRects = this.measureBoardFlowSources(board);
    const focused: RankingBook | undefined = this.homeFocusBooks.get(board.id);
    // 不足五本时 TOP 区最多三张，完整榜单从可见的 TOP1 开始发牌。
    const centerBook: RankingBook | undefined = focused !== undefined &&
      (board.books.length >= 5 || focused.rank <= this.podiumBookCount(board)) ? focused : board.books[0];
    const centerIndex: number = centerBook !== undefined ?
      Math.max(0, board.books.findIndex((book: RankingBook): boolean => book.id === centerBook.id)) : 0;
    this.boardFlowCenterBook = centerBook;
    this.boardFlowCenterCover = centerBook !== undefined ? centerBook.coverUrl : '';
    if (centerBook !== undefined && this.boardFlowCenterCover.length === 0) {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        RankingCoverResolver.resolve(context, centerBook, false).then((cover: string): void => {
          if (!this.alive || cover.length === 0) return;
          if (this.boardFlowCenterBook !== undefined &&
            this.boardFlowCenterBook.id === centerBook.id) {
            this.boardFlowCenterCover = cover;
          }
        }).catch((): void => {});
      }
    }
    this.boardFlowCenterIndex = centerIndex;
    this.boardFlowCenterRank = centerBook !== undefined ? centerBook.rank : 1;
    this.boardFlowTargetBottom = this.measureBoardFlowTargetBottom();
    const stack: BoardFlowRect = this.bottomDeckRect(board);
    this.boardFlowStackRect = stack;
    const root: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    const rootX: number = root !== undefined ? root.x : 0;
    const rootY: number = root !== undefined ? root.y : 0;
    this.boardFlowStackX = stack.x - rootX;
    this.boardFlowStackY = stack.y - rootY;
    this.boardFlowStackW = stack.w;
    this.boardFlowStackH = stack.h;
    this.boardFlowStartWindowX = stack.x + stack.w / 2;
    this.boardFlowStartWindowY = stack.y + stack.h / 2;
    this.boardFlowStartWindowW = stack.w;
    this.boardFlowStartOffsetsX = [];
    this.boardFlowStartOffsetsY = [];
    this.boardFlowStartWidths = [];
    this.boardFlowStartCentersX = [];
    this.boardFlowStartCentersY = [];
    this.boardDeckVisible = false;
    this.boardDeckCover = 0;
    this.boardDeckOpacity = 1;
    this.boardDeckCards = [];
    this.boardPodiumPrepareToken = 0;
    this.boardPodiumPulling = false;
    this.boardFanVisible = false;
    this.boardHomeRelayReady = false;
    this.boardFlowStartCovers = [];
    this.boardFlowStartZ = [];
    this.boardFlowStartOrder = [];
    this.boardFlowStartAngles = [];
    this.boardFlowDeckCells = [];
    this.boardFlowGatherSnapshotToken = 0;
    this.boardFanFocusBook = board.books.length > 0 ? board.books[0] : undefined;
    this.boardFanFocusIndex = 0;
    this.boardFanFocusPrevBook = undefined;
    this.boardFanFocusPrevIndex = -1;
    this.boardFanFocusOpacity = 1;
    this.boardFanFocusPrevOpacity = 0;
    this.boardFanFocusToken++;
    this.boardFanFocusLastAt = 0;
    this.boardFlowPhase = 0;
    this.boardFlowT = 0;
    this.boardFlowReveal = 0;
    this.boardFlowChrome = 0;
    this.boardFlowTitle = 0;
    this.boardFlowFocus = 0;
    this.boardFlowShrink = 0;
    this.boardFlowActive = true;
    this.boardTransitioning = true;
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    this.boardFlowPodiumDx = [];
    this.boardFlowPodiumDy = [];
    this.boardFlowRelayWidths = [];
    this.boardFlowStackVisible = false;
    this.boardFlowStackBlockTop = true;
    this.boardFlowStackT = 0;
    this.boardFlowCenterShrink = 1;
    this.boardFlowGhostVisible = false;
    this.boardFlowGridMode = 'hidden';
    this.boardFlowGridVisible = false;
    this.boardFlowGridReveal = 0;
    this.boardFlowGridBar = 0;
    this.boardFlowGridFirstRank = 0;
    this.boardFlowGridLastRank = 0;
    this.boardFlowFlipLastRank = 0;
    this.boardFlowGridFlipToken = 0;
    this.boardFlowGridWhiteToken = 0;
    this.boardFlowAutoDealActive = false;
    this.boardFlowAutoDealLastAt = 0;
    this.boardFlowCenterReady = false;
    this.activeBoard = board;
    // 榜单先在背后布局，首页卡片同步缩小并汇聚到底栏上方。
    this.waitBoardOpenTargets(board, token, 0);
  }

  /** 五卡从牌堆中心起飞：中心卡最后走，牌堆宽度作为所有卡的起点宽度。 */
  private applyBoardFlowPull(board: RankingBoard): void {
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const stack: BoardFlowRect = this.boardFlowStackRect;
    const centerX: number = stack.x + stack.w / 2;
    const centerY: number = stack.y + stack.h / 2;
    const dx: number[] = [];
    const dy: number[] = [];
    const widths: number[] = [];
    const count: number = Math.min(5, targets.length);
    for (let index: number = 0; index < count; index++) {
      const target: BoardFlowRect = targets[index];
      dx.push(centerX - (target.x + target.w / 2));
      dy.push(centerY - (target.y + target.h / 2));
      widths.push(stack.w);
    }
    this.boardFlowPodiumDx = dx;
    this.boardFlowPodiumDy = dy;
    this.boardFlowRelayWidths = widths;
  }

  private waitBoardOpenTargets(board: RankingBoard, token: number, attempt: number): void {
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      const ready: boolean = board.books.slice(0, this.podiumBookCount(board))
        .every((_book: RankingBook, index: number): boolean =>
          this.measureFlowRect(this.boardPodiumCardId(board, index)) !== undefined);
      if (!ready && attempt < 8) {
        this.waitBoardOpenTargets(board, token, attempt + 1);
        return;
      }
      this.startBoardHomeGather(token);
    }, attempt === 0 ? 32 : 24);
  }

  private startBoardHomeGather(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined || token !== this.boardFlowToken) return;
    if (board.books[0]?.contentType === 'audio') {
      this.startAudioHomeGather(board, token);
      return;
    }
    this.boardFlowPhase = 1;
    this.boardFlowT = 0;
    this.boardFlowShrink = 0;
    this.getUIContext().animateTo({
      duration: FLOW_GATHER_MS, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        // 让货架输出最终五张牌堆的视觉状态，榜单牌堆按同一份快照接管。
        this.boardFlowGatherSnapshotToken++;
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.beginBoardDeckFlow(token);
        }, FLOW_GATHER_HOLD_MS);
      }
    }, (): void => {
      // 聚拢、移到底栏上方、整组收缩同时完成，不再分两段。
      this.boardFlowT = 1;
      this.boardFlowShrink = 1;
    });
  }

  /** 有声横向列表在页面级接管封面，避免列表裁剪把向下聚拢的牌截断。 */
  private startAudioHomeGather(board: RankingBoard, token: number): void {
    const count: number = this.podiumBookCount(board);
    const stack: BoardFlowRect = this.boardFlowStackRect;
    const root: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    this.boardDeckRootX = root !== undefined ? root.x : 0;
    this.boardDeckRootY = root !== undefined ? root.y : 0;
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const cards: BoardDeckCardData[] = [];
    const first: number = Math.max(0, Math.min(board.books.length - count, this.boardFlowCenterIndex));
    for (let index: number = 0; index < count; index++) {
      const sourceBook: RankingBook = board.books[first + index];
      const source: BoardFlowRect = this.measureFlowRect(`rankingAudioCover-${board.id}-${sourceBook.id}`) ??
        new BoardFlowRect(this.boardFlowSourceShelf.x + 24 + index * 168,
          this.boardFlowSourceShelf.y, 152, 152);
      const target: BoardFlowRect = targets[index];
      const data: BoardDeckCardData = new BoardDeckCardData();
      data.key = `${board.id}:${board.books[index].id}`;
      data.sourceCx = source.x + source.w / 2;
      data.sourceCy = source.y + source.h / 2;
      data.sourceW = source.w;
      data.sourceH = source.h;
      data.startCx = stack.x + stack.w / 2 + (index - (count - 1) / 2) * 6;
      data.startCy = stack.y + stack.h / 2 - index * 2;
      data.startW = stack.w;
      data.startH = stack.h;
      data.startAngle = index % 2 === 0 ? index : -index;
      data.startZ = count - index;
      data.endCx = target.x + target.w / 2;
      data.endCy = target.y + target.h / 2;
      data.endW = target.w;
      data.endH = target.h;
      data.startCover = sourceBook.coverUrl;
      data.endCover = board.books[index].coverUrl;
      data.order = index;
      cards.push(data);
    }
    this.boardDeckCards = cards;
    this.boardDeckCover = 0;
    this.boardDeckPullToken = 0;
    this.boardDeckCancelToken = 0;
    this.boardDeckGatherToken = 0;
    this.boardDeckVisible = true;
    this.boardFlowPhase = 1;
    this.getUIContext().animateTo({ duration: FLOW_GATHER_MS, curve: AppCurve.Decelerate },
      (): void => { this.boardFlowT = 1; this.boardFlowShrink = 1; });
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.boardDeckGatherToken++;
    }, 32);
  }

  /** 聚拢完成后量首页五张真实卡的错位/宽度，按视觉顺序映射到榜单 TOP1–5。 */
  private measureDeckStarts(board: RankingBoard): void {
    const total: number = board.books.length;
    if (total === 0) {
      this.boardFlowStartWidths = [];
      this.boardFlowStartCentersX = [];
      this.boardFlowStartCentersY = [];
      this.boardFlowStartCovers = [];
      this.boardFlowStartZ = [];
      this.boardFlowStartOrder = [];
      this.boardFlowStartAngles = [];
      return;
    }
    const snapshot: RankingGatherCell[] = this.boardFlowDeckCells;
    const source: BoardFlowRect = this.boardFlowSourceShelf;
    if (total < 5 && snapshot.length >= 5) {
      const slots: number[] = [2, 3, 1];
      const count: number = this.podiumBookCount(board);
      const shortCells: RankingGatherCell[] = slots.slice(0, count)
        .map((slot: number): RankingGatherCell => snapshot[slot]);
      this.boardFlowStartWidths = shortCells.map((cell: RankingGatherCell): number => cell.width);
      this.boardFlowStartCentersX = shortCells.map((cell: RankingGatherCell): number => source.x + cell.cx);
      this.boardFlowStartCentersY = shortCells.map((cell: RankingGatherCell): number => source.y + cell.cy);
      this.boardFlowStartCovers = shortCells.map((cell: RankingGatherCell): string => cell.cover);
      this.boardFlowStartAngles = shortCells.map((cell: RankingGatherCell): number => cell.angle);
      this.boardFlowStartOrder = shortCells.map((_cell: RankingGatherCell, index: number): number => index);
      this.boardFlowStartZ = shortCells.map((_cell: RankingGatherCell, index: number): number => count - index);
      return;
    }
    const useMeta: boolean = snapshot.length >= 5;
    // 快照同时保存未投影的视觉中心、缩放尺寸和角度，不能把 3D 投影后的左上角
    // 与未投影宽高拼成新 rect，再旋转一次，否则交接时牌堆会跳动。
    const measured: DeckStartCell[] = [];
    for (let offset: number = -2; offset <= 2; offset++) {
      const index: number = ((this.boardFlowCenterIndex + offset) % total + total) % total;
      const book: RankingBook | undefined = board.books[index];
      const rect: BoardFlowRect | undefined =
        this.measureFlowRect(this.shelfCardFlowId(board, index));
      if (rect === undefined || book === undefined) continue;
      const meta: RankingGatherCell | undefined =
        useMeta ? snapshot[offset + 2] : undefined;
      measured.push(new DeckStartCell(meta !== undefined ? source.x + meta.cx : rect.x + rect.w / 2,
        meta !== undefined ? source.y + meta.cy : rect.y + rect.h / 2,
        meta !== undefined ? meta.width : rect.w,
        meta !== undefined ? meta.cover : book.coverUrl,
        meta !== undefined ? meta.angle : 0,
        meta !== undefined ? meta.z : 0));
    }
    let cells: DeckStartCell[] = [];
    if (measured.length >= 5) {
      cells = measured;
    } else if (useMeta && source.w > 0) {
      for (let index: number = 0; index < snapshot.length; index++) {
        const cell: RankingGatherCell = snapshot[index];
        cells.push(new DeckStartCell(source.x + cell.cx, source.y + cell.cy, cell.width,
          cell.cover, cell.angle, cell.z));
      }
    }
    if (cells.length < 5) {
      this.boardFlowStartWidths = [];
      this.boardFlowStartCentersX = [];
      this.boardFlowStartCentersY = [];
      this.boardFlowStartCovers = [];
      this.boardFlowStartZ = [];
      this.boardFlowStartOrder = [];
      this.boardFlowStartAngles = [];
      return;
    }
    cells.sort((a: DeckStartCell, b: DeckStartCell): number => a.cx - b.cx);
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const podiumOrder: number[] = [3, 4, 0, 1, 2];
    // 抽卡顺序按首页牌堆从上到下；同层右侧压左侧。
    let orderBySorted: number[] = [4, 2, 0, 1, 3];
    if (useMeta) {
      const sortedIndices: number[] = [0, 1, 2, 3, 4];
      sortedIndices.sort((a: number, b: number): number =>
        (cells[b].z - cells[a].z) || (cells[b].cx - cells[a].cx));
      orderBySorted = [0, 0, 0, 0, 0];
      for (let order: number = 0; order < 5; order++) {
        orderBySorted[sortedIndices[order]] = order;
      }
    }
    const angleBySorted: number[] = [4, 2, 0, -2, -4];
    const dx: number[] = [0, 0, 0, 0, 0];
    const dy: number[] = [0, 0, 0, 0, 0];
    const widths: number[] = [0, 0, 0, 0, 0];
    const covers: string[] = ['', '', '', '', ''];
    const startZ: number[] = [0, 0, 0, 0, 0];
    const startOrder: number[] = [0, 0, 0, 0, 0];
    const startAngles: number[] = [0, 0, 0, 0, 0];
    const startCentersX: number[] = [0, 0, 0, 0, 0];
    const startCentersY: number[] = [0, 0, 0, 0, 0];
    for (let index: number = 0; index < 5; index++) {
      const cell: DeckStartCell = cells[index];
      const podiumIndex: number = podiumOrder[index];
      const target: BoardFlowRect | undefined = targets[podiumIndex];
      if (target !== undefined) {
        dx[podiumIndex] = cell.cx - (target.x + target.w / 2);
        dy[podiumIndex] = cell.cy - (target.y + target.h / 2);
      }
      const order: number = orderBySorted[index];
      widths[podiumIndex] = cell.width;
      startCentersX[podiumIndex] = cell.cx;
      startCentersY[podiumIndex] = cell.cy;
      covers[podiumIndex] = cell.cover;
      // 起始层级直接由抽卡顺序决定，保证“最先抽的卡”同时就是牌堆最上面那张。
      startZ[podiumIndex] = 5 - order * 0.5;
      startOrder[podiumIndex] = order;
      startAngles[podiumIndex] = useMeta ? cell.angle : angleBySorted[index];
    }
    this.boardFlowPodiumDx = dx;
    this.boardFlowPodiumDy = dy;
    this.boardFlowStartWidths = widths;
    this.boardFlowStartCentersX = startCentersX;
    this.boardFlowStartCentersY = startCentersY;
    this.boardFlowStartCovers = covers;
    this.boardFlowStartZ = startZ;
    this.boardFlowStartOrder = startOrder;
    this.boardFlowStartAngles = startAngles;
    this.boardFlowStartOffsetsX = [];
    this.boardFlowStartOffsetsY = [];
  }

  /** 聚拢牌堆的底边停在实测底栏上方，避开状态栏和标题。 */
  private bottomDeckRect(board: RankingBoard): BoardFlowRect {
    const root: BoardFlowRect = this.measureFlowRect('rankingCardAnchor') ??
      new BoardFlowRect(0, 0, WindowUtils.getWindowWidthVp(), WindowUtils.getWindowHeightVp());
    const top: number = Math.max(root.y, this.boardFlowTopLimit()) + FLOW_BAR_GAP;
    const bottom: number = Math.max(top + 1,
      Math.min(root.y + root.h, this.boardFlowBottomLimit(), this.measureBoardFlowTargetBottom()) - FLOW_BAR_GAP);
    const aspect: number = board.books[0]?.contentType === 'audio' ? 1 : 0.75;
    const width: number = Math.max(1, Math.min(PODIUM_CENTER_W, root.w * 0.4,
      (bottom - top) * 0.6 * aspect));
    const height: number = width / aspect;
    return new BoardFlowRect(root.x + (root.w - width) / 2, bottom - height, width, height);
  }

  /** 接管聚拢后的真实卡位，再用独立原生动画逐张向上抽到 TOP 五卡。 */
  private beginBoardDeckFlow(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined || !this.alive || token !== this.boardFlowToken) return;
    const count: number = this.podiumBookCount(board);
    if (count === 0) { this.finishBoardCancel(); return; }
    if (board.books[0]?.contentType !== 'audio') {
      this.measureDeckStarts(board);
      this.measureDeckCenter(board);
    }
    // 完整榜单从顶部开始展示；首页仍保留原来浏览的书，不把底部牌堆带进网格。
    this.boardFlowCenterRank = 1;
    const stack: BoardFlowRect = this.boardFlowStackRect;
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const host: BoardFlowRect = this.measureFlowRect(`rankingBoardPodiumHost-${board.id}`) ??
      new BoardFlowRect(this.leftSafe, this.topSafe + RANKING_SEARCH_HEIGHT + 80);
    const root: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    this.boardDeckRootX = root !== undefined ? root.x : 0;
    this.boardDeckRootY = root !== undefined ? root.y : 0;
    const cards: BoardDeckCardData[] = [];
    for (let index: number = 0; index < count; index++) {
      const book: RankingBook = board.books[index];
      const target: BoardFlowRect = targets[index];
      const data: BoardDeckCardData = new BoardDeckCardData();
      data.key = `${board.id}:${book.id}`;
      data.hostX = host.x;
      data.hostY = host.y;
      const measured: boolean = this.boardFlowStartWidths.length >= count;
      const gathered: BoardDeckCardData | undefined = this.boardDeckCards[index];
      const audio: boolean = board.books[0]?.contentType === 'audio' && gathered !== undefined;
      data.startCx = measured ? this.boardFlowStartCentersX[index] :
        (audio && gathered !== undefined ? gathered.startCx : stack.x + stack.w / 2);
      data.startCy = measured ? this.boardFlowStartCentersY[index] :
        (audio && gathered !== undefined ? gathered.startCy : stack.y + stack.h / 2);
      data.startW = measured ? this.boardFlowStartWidths[index] : stack.w;
      data.startH = measured ? data.startW / RankingCardStyle.COVER_ASPECT : stack.h;
      data.startAngle = measured ? this.boardFlowStartAngles[index] : index % 2 === 0 ? index : -index;
      data.startZ = measured ? this.boardFlowStartZ[index] : count - index;
      data.endCx = target.x + target.w / 2;
      data.endCy = target.y + target.h / 2;
      data.endW = target.w;
      data.endH = target.h;
      data.startCover = measured ? this.boardFlowStartCovers[index] :
        (audio && gathered !== undefined ? gathered.startCover : book.coverUrl);
      data.endCover = book.coverUrl;
      data.order = measured ? this.boardFlowStartOrder[index] : index;
      cards.push(data);
    }
    this.boardDeckCards = cards;
    this.boardFlowPhase = 2;
    this.boardFlowT = 0;
    this.boardFlowReveal = 0;
    this.boardFlowChrome = 0;
    this.boardFlowTitle = 0;
    this.boardFlowFocus = 0;
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.boardFlowStackT = 0;
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    this.boardFlowPullStartAt = -1;
    this.boardDeckPullToken = 0;
    this.boardDeckCancelToken = 0;
    this.boardDeckCover = 0;
    this.boardDeckOpacity = 1;
    this.boardFanVisible = false;
    this.boardPodiumPulling = true;
    this.boardPodiumPrepareToken = token;
    this.boardFlowActive = true;
    this.boardTransitioning = true;
    this.getUIContext().postFrameCallback(new RankingBoardSnapFrame((): void => {
      this.getUIContext().postFrameCallback(new RankingBoardSnapFrame((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        // 真实五卡已经在底部牌堆位置准备好；之后一直由这些节点抽到顶部。
        this.boardFanVisible = true;
        this.boardHomeRelayReady = true;
        this.boardDeckVisible = false;
        this.getUIContext().animateTo({ duration: FLOW_DECK_FADE_MS, curve: AppCurve.Standard },
          (): void => { this.boardDeckCover = 1; });
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.getUIContext().animateTo({ duration: FLOW_TITLE_MS, curve: AppCurve.Standard }, (): void => {
            this.boardFlowReveal = 1;
            this.boardFlowTitle = 1;
          });
          this.boardDeckPullToken++;
        }, FLOW_DECK_FADE_MS);
      }));
    }));
    if (this.boardFlowCenterRank === 1) {
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.startBoardFocusFade(token);
      }, 32 + FLOW_PULL_CARD_MS + FLOW_PULL_SETTLE_MS);
    }
  }

  private finishBoardDeckPull(token: number): void {
    if (!this.alive || token !== this.boardFlowToken || !this.boardPodiumPulling) return;
    // 不做封面树/透明度交接，只接着从同一组 TOP 卡向网格发牌。
    this.boardPodiumPulling = false;
    this.onBoardPullFinished(token);
  }

  private beginBoardPullFlow(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board !== undefined) {
      this.measureDeckStarts(board);
      this.measureDeckCenter(board);
    }
    this.boardFlowPhase = 2;
    this.boardFlowT = 0;
    this.boardFlowReveal = 1;
    this.boardFlowChrome = 0;
    this.boardFlowTitle = 0;
    this.boardFlowFocus = 0;
    // 中心 01–05 时牌堆就是榜单这五张，由五卡自己接管，页面级转场层不要留空牌边。
    const centerInFan: boolean = this.boardFlowCenterRank <= 5;
    this.boardFlowStackVisible = !centerInFan;
    this.boardFlowStackT = 0;
    this.boardFlowGhostVisible = !centerInFan;
    this.boardFlowStackBlockTop = !centerInFan;
    this.boardFlowPodiumMode = 'arrival';
    this.boardFlowPodiumProgress = 0;
    this.boardFlowPullStartAt = -1;
    // 牌堆静止完成封面身份转换，之后立刻逐张抽卡；
    // 榜单标题/更新时间与抽卡同一刻开始淡入。
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.getUIContext().animateTo({
        duration: FLOW_TITLE_MS, curve: AppCurve.Standard
      }, (): void => {
        this.boardFlowTitle = 1;
      });
      this.postBoardPullFrame(token);
    }, FLOW_DECK_PREPARE_MS + FLOW_DECK_HOLD_MS);
    // 01 的扇形中心就是第一张抽出的卡：它落位回弹结束即淡入焦点标题。
    // >05 时选中的中心卡不在扇形里，焦点标题先不出现，避免被牌堆卡盖住。
    if (this.boardFlowCenterRank === 1) {
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.startBoardFocusFade(token);
      }, FLOW_DECK_PREPARE_MS + FLOW_DECK_HOLD_MS + FLOW_PULL_CARD_MS +
        FLOW_PULL_SETTLE_MS);
    }
  }

  /** 焦点标题只做自己的淡入，不再等五卡全部落位。 */
  private startBoardFocusFade(token: number): void {
    if (!this.alive || token !== this.boardFlowToken) return;
    this.getUIContext().animateTo({
      duration: FLOW_TEXT_MS, curve: AppCurve.Standard
    }, (): void => {
      this.boardFlowFocus = 1;
    });
  }

  /** 首页牌堆缩小后，中心卡的真实位置给页面级牌堆层做接力。 */
  private measureDeckCenter(board: RankingBoard): void {
    let rect: BoardFlowRect | undefined = undefined;
    const snapshot: RankingGatherCell[] = this.boardFlowDeckCells;
    const source: BoardFlowRect = this.boardFlowSourceShelf;
    if (snapshot.length >= 5 && source.w > 0) {
      const cell: RankingGatherCell = snapshot[2];
      rect = new BoardFlowRect(source.x + cell.cx - cell.width / 2,
        source.y + cell.cy - cell.height / 2, cell.width, cell.height);
    } else {
      rect = this.measureFlowRect(this.shelfCardFlowId(board, this.boardFlowCenterIndex));
    }
    if (rect === undefined) return;
    this.boardFlowStackRect = rect;
    const root: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    this.boardFlowStackX = rect.x - (root !== undefined ? root.x : 0);
    this.boardFlowStackY = rect.y - (root !== undefined ? root.y : 0);
    this.boardFlowStackW = rect.w;
    this.boardFlowStackH = rect.h;
    this.boardFlowStartWindowX = rect.x + rect.w / 2;
    this.boardFlowStartWindowY = rect.y + rect.h / 2;
    this.boardFlowStartWindowW = rect.w;
  }

  /** 帧驱动抽卡：master progress 每帧推进，每张卡的错峰才真正生效。 */
  private postBoardPullFrame(token: number): void {
    this.getUIContext().postFrameCallback(new RankingBoardSnapFrame((timeInNano: number): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      const now: number = timeInNano / 1000000;
      if (this.boardFlowPullStartAt < 0) {
        this.boardFlowPullStartAt = now;
        this.boardFlowPodiumProgress = 0;
        this.postBoardPullFrame(token);
        return;
      }
      const elapsed: number = now - this.boardFlowPullStartAt;
      const progress: number = Math.max(0, Math.min(1, elapsed / FLOW_PULL_SPAN_MS));
      this.boardFlowPodiumProgress = progress;
      if (progress >= 1) {
        this.onBoardPullFinished(token);
        return;
      }
      this.postBoardPullFrame(token);
    }));
  }

  private onBoardPullFinished(token: number): void {
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    if (this.boardFlowCenterRank > 5) {
      // 牌堆保留，等中心卡落到榜单真实位置；角标淡入和发牌并行，不再等角标结束。
      this.revealBoardChrome(token, (): void => {});
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.startBoardGridPhase(token);
      }, FLOW_FAN_PAUSE_MS);
      return;
    }
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    if (this.boardFlowCenterRank >= 2 && this.boardFlowCenterRank <= 5) {
      this.boardFlowFocusToken++;
      const count: number = Math.max(1, this.boardFlowBoard !== undefined ?
        this.podiumBookCount(this.boardFlowBoard) : 5);
      let delta: number = (this.boardFlowCenterRank - 1) % count;
      if (delta > count / 2) delta -= count;
      const snapMs: number = Math.min(700,
        AppMotion.Base + Math.max(0, Math.abs(delta) - 1) * 80);
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        // 最终中心卡转正完成，焦点/角标开始淡入，同时很快继续发牌。
        this.startBoardFocusFade(token);
        this.revealBoardChrome(token, (): void => {});
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.startBoardGridPhase(token);
        }, 40);
      }, snapMs);
      return;
    }
    this.revealBoardChrome(token, (): void => {});
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.startBoardGridPhase(token);
    }, FLOW_FAN_PAUSE_MS);
  }

  /** 抽卡结束后才显五张卡左上角的排名角标（焦点标题已经独立淡入）。 */
  private revealBoardChrome(token: number, after: () => void): void {
    this.getUIContext().animateTo({
      duration: FLOW_TEXT_MS, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        after();
      }
    }, (): void => {
      this.boardFlowChrome = 1;
    });
  }

  private measureGridVisibleRanks(board: RankingBoard): number[] {
    const top: number = this.boardFlowTopLimit();
    const bottom: number = this.boardFlowBottomLimit();
    const columns: number = Math.max(1, this.boardColumns());
    const podium: number = this.podiumBookCount(board);
    let first: number = podium + 1;
    let last: number = board.books.length;
    if (this.boardFlowCenterRank > 5) {
      first = Math.max(first, this.boardFlowCenterRank - columns * 3);
      last = Math.min(last, this.boardFlowCenterRank + columns * 3);
    } else {
      last = Math.min(last, first + columns * 7);
    }
    const ranks: number[] = [];
    for (let rank: number = first; rank <= last; rank++) {
      const book: RankingBook | undefined = board.books[rank - 1];
      if (book === undefined) continue;
      const rect: BoardFlowRect | undefined = this.measureFlowRect(this.gridCoverId(board, book));
      if (rect === undefined) continue;
      if (rect.y < bottom && rect.y + rect.h > top) ranks.push(rank);
    }
    return ranks;
  }

  private gridFlowDuration(firstRank: number, lastRank: number): number {
    return FLOW_GRID_CARD_MS + Math.max(0, lastRank - firstRank) * FLOW_GRID_STAGGER_MS;
  }

  private showBoardFlowGrid(token: number): void {
    setTimeout((): void => {
      if (!this.alive || !this.boardFlowActive || token !== this.boardFlowToken) return;
      this.boardFlowGridVisible = true;
      // 行本身立即显示，避免发牌飞行的前半段被行的淡入透明盖掉。
      this.boardFlowGridReveal = 1;
      this.getUIContext().animateTo({
        duration: 180, curve: AppCurve.Decelerate
      }, (): void => {
        this.boardFlowGridBar = 1;
      });
    }, 0);
  }

  private setPodiumDealOrigin(): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined) return;
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const center: BoardFlowRect | undefined = targets[0];
    if (center === undefined) return;
    let bottom: number = center.y + center.h;
    for (const rect of targets) bottom = Math.max(bottom, rect.y + rect.h);
    const width: number = Math.min(center.w * 0.72, this.boardCardWidth());
    const aspect: number = board.books[0]?.contentType === 'audio' ? 1 : 0.75;
    this.boardFlowGridFromX = center.x + center.w / 2;
    this.boardFlowGridFromY = bottom - width / aspect / 2;
    this.boardFlowGridFromW = width;
  }

  private startBoardGridPhase(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined) return;
    if (this.boardFlowCenterRank <= 5) {
      this.boardFlowStackVisible = false;
      this.boardFlowGhostVisible = false;
      const podium: number = this.podiumBookCount(board);
      // 首屏发牌范围按几何位置算，不依赖封面节点是否已经挂载/量到；
      // 否则节点晚挂载时会整段跳发牌，或者只量到一半导致先闪出几张。
      const columns: number = Math.max(1, this.boardColumns());
      const firstRank: number = podium + 1;
      const startY: number = this.boardGridStartY(board);
      const rowH: number = this.boardGridRowHeight();
      const bottom: number = this.boardFlowBottomLimit();
      const rows: number = startY < bottom ?
        Math.max(1, Math.ceil((bottom - startY) / Math.max(1, rowH))) : 1;
      const lastRank: number = Math.min(board.books.length,
        firstRank + columns * rows - 1);
      if (board.books.length <= podium || lastRank < firstRank) {
        // 没有“更多好书”可发时才直接显示网格。
        this.showBoardFlowGrid(token);
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.fadeBoardFlowText(token);
        }, 200);
        return;
      }
      this.boardFlowGridMode = 'dealAll';
      this.boardFlowGridFirstRank = firstRank;
      this.boardFlowGridLastRank = lastRank;
      this.setPodiumDealOrigin();
      this.boardFlowCenterReady = true;
      this.showBoardFlowGrid(token);
      // 等网格行挂载/布局一帧后再发牌，卡片的起点/终点才量得到。
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.boardFlowGridDealToken++;
      }, 16);
      const wait: number = this.gridFlowDuration(this.boardFlowGridFirstRank,
        this.boardFlowGridLastRank) + 120;
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.fadeBoardFlowText(token);
      }, wait);
      return;
    }
    const centerRect: BoardFlowRect | undefined =
      this.measureFlowRect(this.centerGridCoverId(board));
    const top: number = this.boardFlowTopLimit();
    const bottom: number = this.boardFlowBottomLimit();
    const visible: boolean = centerRect !== undefined &&
      centerRect.y >= top && centerRect.y + centerRect.h <= bottom;
    if (visible) {
      this.runBoardPivotPhase(token);
      return;
    }
    // >5：页面连续下滑，发牌和目标格位同时跟滚动进行。
    this.beginBoardScrollDeal(board, token);
    this.scrollBoardToCenter(board, token);
  }

  /** >5 逐行滚动 + 逐行发牌：每行先滚到可视中心，再从左到右发这一行。 */
  private startBoardRowDealFlow(board: RankingBoard, token: number): void {
    const columns: number = Math.max(1, this.boardColumns());
    const podium: number = this.podiumBookCount(board);
    const center: number = this.boardFlowCenterRank;
    const firstRank: number = podium + 1;
    const centerRow: number = Math.max(0, Math.floor((center - firstRank) / columns));
    this.boardFlowGridMode = 'pivot';
    this.boardFlowStackVisible = true;
    this.boardFlowStackBlockTop = true;
    this.boardFlowGhostVisible = true;
    this.boardFlowCenterReady = false;
    this.boardFlowStackT = 0;
    this.boardFlowCenterShrink = 1;
    this.boardFlowFlipLastRank = Math.min(board.books.length,
      center + columns * 3);
    this.boardFlowGridFirstRank = 0;
    this.boardFlowGridLastRank = 0;
    this.boardFlowGridContentStartY = this.boardGridStartY(board);
    this.setPodiumDealOrigin();
    const ratio: number = Math.min(1,
      this.boardCardWidth() / Math.max(1, this.boardFlowStackRect.w));
    const rows: number = centerRow + 1;
    this.getUIContext().animateTo({
      duration: Math.max(420, rows * 520), curve: AppCurve.Standard
    }, (): void => {
      this.boardFlowCenterShrink = ratio;
    });
    this.showBoardFlowGrid(token);
    this.runBoardRowDeal(board, token, 0, centerRow, firstRank, columns);
  }

  private runBoardRowDeal(board: RankingBoard, token: number, row: number,
    centerRow: number, firstRank: number, columns: number): void {
    if (!this.alive || token !== this.boardFlowToken) return;
    if (row > centerRow) {
      this.startBoardCenterLanding(token);
      return;
    }
    const total: number = board.books.length;
    const rowFirst: number = firstRank + row * columns;
    if (rowFirst > total) {
      this.startBoardCenterLanding(token);
      return;
    }
    const rowLast: number = Math.min(total, rowFirst + columns - 1);
    const center: number = this.boardFlowCenterRank;
    const dealLast: number = row === centerRow ? Math.min(rowLast, center - 1) : rowLast;
    const startY: number = this.boardFlowGridContentStartY > 0 ?
      this.boardFlowGridContentStartY : this.boardGridStartY(board);
    const rowH: number = this.boardGridRowHeight();
    const cardH: number = this.boardCardWidth() / Math.max(0.5, this.boardCoverAspect());
    const desired: number = (this.boardFlowTopLimit() + this.boardFlowBottomLimit()) / 2;
    const scrollY: number = Math.max(0, startY + row * rowH + cardH / 2 - desired);
    try {
      this.boardScroller.scrollTo({
        xOffset: 0, yOffset: scrollY,
        animation: { duration: 300, curve: AppCurve.Decelerate }
      });
    } catch (_error) { /* 列表尚未挂载 */ }
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      let wait: number = 60;
      if (dealLast >= rowFirst) {
        this.boardFlowGridFirstRank = rowFirst;
        this.boardFlowGridLastRank = dealLast;
        this.setPodiumDealOrigin();
        this.boardFlowGridDealToken++;
        wait = this.gridFlowDuration(rowFirst, dealLast) + 120;
      }
      if (row === centerRow) {
        // 最后一行的发牌和中心卡落位同时开始，中心卡不再等前面落完。
        this.startBoardCenterLanding(token);
        return;
      }
      setTimeout((): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.runBoardRowDeal(board, token, row + 1, centerRow, firstRank, columns);
      }, Math.max(120, wait));
    }, 330);
  }

  /** >5 开始滚动前：中心卡牌堆留在原位，网格进入 pivot，滚动过程中持续从它背后发牌。 */
  private beginBoardScrollDeal(board: RankingBoard, token: number): void {
    this.boardFlowGridMode = 'pivot';
    this.boardFlowStackVisible = true;
    this.boardFlowStackBlockTop = true;
    this.boardFlowGhostVisible = true;
    this.boardFlowCenterReady = false;
    this.boardFlowStackT = 0;
    this.boardFlowCenterShrink = 1;
    // 第一排（第6名起）先发；滚动过程中后面的可见批次继续补。
    const columns: number = Math.max(1, this.boardColumns());
    const firstRank: number = this.podiumBookCount(board) + 1;
    const firstLast: number = Math.min(this.boardFlowCenterRank - 1,
      firstRank + columns - 1);
    this.setPodiumDealOrigin();
    this.boardFlowGridFirstRank = firstLast >= firstRank ? firstRank : 0;
    this.boardFlowGridLastRank = firstLast >= firstRank ? firstLast : 0;
    if (firstLast >= firstRank) this.boardFlowGridDealToken++;
    // 最终这一页（包括被底栏盖住的下一排）先保持白背，中心落位过程中淡入。
    this.boardFlowFlipLastRank = Math.min(board.books.length,
      this.boardFlowCenterRank + columns * 3);
    this.boardFlowAutoDealActive = true;
    this.boardFlowAutoDealLastAt = 0;
    this.showBoardFlowGrid(token);
    this.dealVisibleBeforeCenterDuringScroll();
    this.scheduleBoardScrollDealTick(token);
  }

  /** 程序化 scrollTo 的 onDidScroll 在部分设备上回调很少，用定时轮询兜底保证连续发牌。 */
  private scheduleBoardScrollDealTick(token: number): void {
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken || !this.boardFlowAutoDealActive) return;
      this.dealVisibleBeforeCenterDuringScroll();
      this.scheduleBoardScrollDealTick(token);
    }, 80);
  }

  /** 滚动到哪一批可见卡，就从中心卡背后发哪一批；已发过的卡不重启。 */
  private dealVisibleBeforeCenterDuringScroll(force: boolean = false): number {
    if (!this.boardFlowActive || this.boardFlowCenterRank <= 5) return 0;
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined) return 0;
    const now: number = Date.now();
    if (!force && now - this.boardFlowAutoDealLastAt < 60) return 0;
    this.boardFlowAutoDealLastAt = now;
    const ranks: number[] = this.measureGridVisibleRanks(board);
    let first: number = 0;
    let last: number = 0;
    for (let index: number = 0; index < ranks.length; index++) {
      const rank: number = ranks[index];
      if (rank >= this.boardFlowCenterRank) continue;
      if (first === 0 || rank < first) first = rank;
      if (rank > last) last = rank;
    }
    if (first === 0 || last === 0) return 0;
    this.boardFlowGridMode = 'pivot';
    this.boardFlowGridFirstRank = first;
    this.boardFlowGridLastRank = last;
    // 滚动中保持同一个窗口中央原点，起始尺寸跟随中央牌堆。
    this.setPodiumDealOrigin();
    this.boardFlowCenterReady = false;
    this.boardFlowStackVisible = true;
    this.boardFlowStackBlockTop = true;
    this.boardFlowGhostVisible = true;
    this.boardFlowGridDealToken++;
    return this.gridFlowDuration(first, last) + 80;
  }

  /** 滚动结束：补发最后一批，确定白卡范围，等这批发完再让中心卡落位。 */
  private finishBoardScrollDeal(board: RankingBoard, token: number): void {
    this.boardFlowAutoDealActive = false;
    this.dealVisibleBeforeCenterDuringScroll(true);
    const ranks: number[] = this.measureGridVisibleRanks(board);
    let flipLast: number = this.boardFlowCenterRank;
    for (let index: number = 0; index < ranks.length; index++) {
      if (ranks[index] > this.boardFlowCenterRank && ranks[index] > flipLast) {
        flipLast = ranks[index];
      }
    }
    if (flipLast <= this.boardFlowCenterRank) {
      flipLast = Math.min(board.books.length,
        this.boardFlowCenterRank + Math.max(1, this.boardColumns()) * 2);
    }
    this.boardFlowFlipLastRank = flipLast;
    // 中心卡不等待最后一批发牌全部落位：它和最后一批同时开始缩小/落位。
    this.startBoardCenterLanding(token);
  }

  /** 榜单列表滚动回调：>5 转场时驱动连续发牌。 */
  private onBoardFlowScroll(): void {
    if (!this.boardFlowAutoDealActive || !this.boardFlowActive || !this.boardFlowDealActiveToken()) {
      return;
    }
    this.dealVisibleBeforeCenterDuringScroll();
  }

  private onBoardListScroll(offset: number, state: ScrollState): void {
    this.onContentScroll(offset, state);
    // onDidScroll 给的是本帧增量，发牌修正和回顶按钮需要滚动总偏移。
    const total: number = Math.max(0, this.boardScroller.currentOffset()?.yOffset ?? 0);
    if (this.boardFlowActive && this.boardFlowGridMode.length > 0 &&
      this.boardFlowGridMode !== 'hidden') {
      this.boardFlowListOffset = total;
      this.onBoardFlowScroll();
    }
    const show: boolean = !this.boardFlowActive && total > 180;
    if (show !== this.boardFabVisible) this.boardFabVisible = show;
  }

  private boardFlowDealActiveToken(): boolean {
    return this.boardFlowPhase === 2 && this.boardFlowCenterRank > 5;
  }

  private boardGridRowHeight(): number {
    const cardW: number = this.boardCardWidth();
    const aspect: number = this.boardCoverAspect();
    const fs: number = this.boardCardFontScale();
    const space: number = fs > 1.1 ? 6 : 5;
    return cardW / Math.max(0.5, aspect) + space + 34 * fs + space + 14 * fs;
  }

  private boardGridStartY(board: RankingBoard): number {
    const header: BoardFlowRect | undefined =
      this.measureFlowRect(`rankingBoardGridStart-${board.id}`);
    if (header !== undefined) return header.y + header.h + BOARD_ROW_GAP;
    return WindowUtils.getWindowHeightVp() * 0.72;
  }

  private scrollBoardToCenter(board: RankingBoard, token: number): void {
    const columns: number = Math.max(1, this.boardColumns());
    const podium: number = this.podiumBookCount(board);
    const row: number = Math.max(0,
      Math.floor((this.boardFlowCenterRank - podium - 1) / columns));
    const rowHeight: number = this.boardGridRowHeight();
    const startY: number = this.boardGridStartY(board);
    const cardH: number = this.boardCardWidth() / Math.max(0.5, this.boardCoverAspect());
    const targetY: number = startY + row * rowHeight + cardH / 2;
    const desiredY: number = (this.boardFlowTopLimit() + this.boardFlowBottomLimit()) / 2;
    const scrollY: number = Math.max(0, targetY - desiredY);
    const animatedRows: number = Math.min(row + 1, FLOW_SCROLL_MAX_ROWS);
    const duration: number = 380 + animatedRows * 80;
    // 中心卡在背景滚动过程中逐渐缩到榜格格位大小，最后再进入位置落位。
    const shrinkRatio: number = Math.min(1,
      this.boardCardWidth() / Math.max(1, this.boardFlowStackRect.w));
    this.boardFlowCenterShrink = 1;
    this.getUIContext().animateTo({
      duration: duration + 360, curve: AppCurve.Standard
    }, (): void => {
      this.boardFlowCenterShrink = shrinkRatio;
    });
    try {
      this.boardScroller.scrollTo({
        xOffset: 0, yOffset: scrollY,
        animation: { duration: duration, curve: AppCurve.Decelerate }
      });
    } catch (_error) { /* 列表尚未挂载 */ }
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      const rect: BoardFlowRect | undefined =
        this.measureFlowRect(this.centerGridCoverId(board));
      if (rect === undefined) {
        this.finishBoardScrollDeal(board, token);
        return;
      }
      const top: number = this.boardFlowTopLimit();
      const bottom: number = this.boardFlowBottomLimit();
      const desired: number = (top + bottom) / 2;
      const current: number = this.boardScroller.currentOffset().yOffset;
      const delta: number = (rect.y + rect.h / 2) - desired;
      if (Math.abs(delta) > 4) {
        // 首次滚动只保证到达附近；这里一定要把选中卡补到可视区中心，不能停在左上。
        try {
          this.boardScroller.scrollTo({
            xOffset: 0, yOffset: Math.max(0, current + delta),
            animation: { duration: 220, curve: AppCurve.Decelerate }
          });
        } catch (_error) { /* 列表尚未挂载 */ }
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.finishBoardScrollDeal(board, token);
        }, 320);
        return;
      }
      this.finishBoardScrollDeal(board, token);
    }, duration + 160);
  }

  private runBoardPivotPhase(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined) return;
    const ranks: number[] = this.measureGridVisibleRanks(board);
    let first: number = ranks.length > 0 ? ranks[0] : this.boardFlowCenterRank;
    let last: number = ranks.length > 0 ? ranks[ranks.length - 1] : this.boardFlowCenterRank;
    first = Math.min(first, this.boardFlowCenterRank);
    last = Math.max(last, this.boardFlowCenterRank);
    this.boardFlowGridMode = 'pivot';
    this.boardFlowGridFirstRank = first;
    this.boardFlowGridLastRank = last;
    this.boardFlowFlipLastRank = Math.min(board.books.length, Math.max(last,
      this.boardFlowCenterRank + Math.max(1, this.boardColumns()) * 3));
    this.boardFlowAutoDealActive = false;
    this.setPodiumDealOrigin();
    this.boardFlowCenterReady = false;
    this.boardFlowStackVisible = true;
    this.boardFlowStackBlockTop = true;
    this.boardFlowGhostVisible = true;
    this.showBoardFlowGrid(token);
    const beforeCount: number = Math.max(0, this.boardFlowCenterRank - first);
    if (beforeCount === 0) {
      this.startBoardCenterLanding(token);
      return;
    }
    this.boardFlowGridDealToken++;
    const wait: number = this.gridFlowDuration(first,
      this.boardFlowCenterRank - 1) + 160;
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.startBoardCenterLanding(token);
    }, wait);
  }

  private startBoardCenterLanding(token: number): void {
    const board: RankingBoard | undefined = this.boardFlowBoard;
    if (board === undefined) return;
    const target: BoardFlowRect | undefined =
      this.measureFlowRect(this.centerGridCoverId(board));
    const fallback: BoardFlowRect = new BoardFlowRect(
      WindowUtils.getWindowWidthVp() / 2 - this.boardFlowStackRect.w / 2,
      WindowUtils.getWindowHeightVp() / 2 - this.boardFlowStackRect.h / 2,
      this.boardFlowStackRect.w, this.boardFlowStackRect.h);
    const rect: BoardFlowRect = target !== undefined ? target : fallback;
    const root: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    const rootX: number = root !== undefined ? root.x : 0;
    const rootY: number = root !== undefined ? root.y : 0;
    this.boardFlowCenterTargetX = rect.x - rootX;
    this.boardFlowCenterTargetY = rect.y - rootY;
    this.boardFlowCenterTargetW = rect.w;
    this.boardFlowCenterTargetH = rect.h;
    this.boardFlowStackT = 0;
    // 中心卡一开始落位，就让后面的白背淡入；翻面要等落位结束。
    this.boardFlowGridWhiteToken++;
    this.getUIContext().animateTo({
      duration: FLOW_CENTER_MS, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.boardFlowCenterReady = true;
        this.boardFlowStackVisible = false;
        this.boardFlowGhostVisible = false;
        const afterCount: number = Math.max(0,
          this.boardFlowFlipLastRank - this.boardFlowCenterRank);
        if (afterCount === 0) {
          this.fadeBoardFlowText(token);
          return;
        }
        this.boardFlowGridFlipToken++;
        const wait: number = (afterCount - 1) * FLOW_FLIP_STAGGER_MS +
          FLOW_FLIP_MS + 180;
        setTimeout((): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.fadeBoardFlowText(token);
        }, wait);
      }
    }, (): void => {
      this.boardFlowStackT = 1;
    });
  }

  private fadeBoardFlowText(token: number): void {
    this.getUIContext().animateTo({
      duration: FLOW_TEXT_MS, curve: AppCurve.Decelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.boardFlowActive = false;
        this.boardFlowPhase = 0;
        this.boardFlowT = 0;
        this.boardFlowReveal = 1;
        this.boardFlowChrome = 1;
        this.boardFlowTitle = 1;
        this.boardFlowFocus = 1;
        this.boardFlowShrink = 0;
        this.boardFlowPodiumMode = '';
        this.boardFlowPodiumProgress = 1;
        this.boardFlowPodiumDx = [];
        this.boardFlowPodiumDy = [];
        this.boardFlowRelayWidths = [];
        this.boardFlowStartZ = [];
        this.boardFlowStartOrder = [];
        this.boardFlowStartAngles = [];
        this.boardFlowStackVisible = false;
        this.boardFlowGhostVisible = false;
        this.boardFlowGridMode = '';
        this.boardFlowGridVisible = true;
        this.boardFlowGridReveal = 1;
        this.boardFlowGridBar = 1;
        this.boardFlowFlipLastRank = 0;
        this.boardFlowAutoDealActive = false;
        this.boardFlowCenterReady = true;
        this.boardTransitioning = false;
      }
    }, (): void => {
      this.boardFlowChrome = 1;
    });
  }

  /** 返回时回收正在发出的卡，再淡出榜单；不再进入首页货架聚拢分支。 */
  private cancelBoardFlow(): void {
    if (!this.boardFlowActive || this.boardFlowPhase === 3) return;
    const token: number = ++this.boardFlowToken;
    this.boardFlowAutoDealActive = false;
    if (this.boardPodiumPulling) {
      this.boardDeckCancelToken = token;
      return;
    }
    if (this.boardDeckVisible) {
      this.boardDeckCancelToken = token;
      return;
    }
    this.cancelCenterDealPage(token);
  }

  private cancelCenterDealPage(token: number): void {
    if (!this.alive || token !== this.boardFlowToken) return;
    this.boardFlowPhase = 3;
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.getUIContext().animateTo({ duration: AppMotion.Fast, curve: AppCurve.Accelerate,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.finishBoardCancel();
        this.boardPageFade = 1;
      } }, (): void => { this.boardPageFade = 0; });
  }

  /** 抽卡中的取消：master progress 从当前退到 0，卡片沿原路回到牌堆。 */
  private cancelBoardPull(token: number): void {
    const from: number = Math.max(0, Math.min(1, this.boardFlowPodiumProgress));
    this.boardFlowCancelFrom = from;
    this.boardFlowCancelStartAt = -1;
    this.boardFlowCancelDuration = Math.min(900, Math.max(220, from * FLOW_PULL_SPAN_MS));
    this.getUIContext().animateTo({
      duration: 180, curve: AppCurve.Standard
    }, (): void => {
      this.boardFlowTitle = 0;
      this.boardFlowFocus = 0;
      this.boardFlowChrome = 0;
    });
    this.postBoardPullCancelFrame(token);
  }

  private postBoardPullCancelFrame(token: number): void {
    this.getUIContext().postFrameCallback(new RankingBoardSnapFrame((timeInNano: number): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      const now: number = timeInNano / 1000000;
      if (this.boardFlowCancelStartAt < 0) {
        this.boardFlowCancelStartAt = now;
        this.boardFlowPodiumProgress = this.boardFlowCancelFrom;
        this.postBoardPullCancelFrame(token);
        return;
      }
      const p: number = Math.max(0, Math.min(1,
        (now - this.boardFlowCancelStartAt) / Math.max(1, this.boardFlowCancelDuration)));
      this.boardFlowPodiumProgress = this.boardFlowCancelFrom * (1 - p);
      if (p >= 1) {
        this.boardFlowPodiumProgress = 0;
        this.reverseDeckCoversThenHome(token);
        return;
      }
      this.postBoardPullCancelFrame(token);
    }));
  }

  /** 把牌堆的榜单封面淡回首页封面，再把首页真实牌堆从同一位置交回来。 */
  private reverseDeckCoversThenHome(token: number): void {
    this.boardFlowCoverBackToken++;
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.revealHomeDeck(token);
    }, FLOW_DECK_FADE_MS + 30);
  }

  /** 榜单页隐藏，首页牌堆以聚拢+缩小后的状态原地接管，再反向展开。 */
  private revealHomeDeck(token: number): void {
    this.boardFlowPhase = 1;
    this.boardFlowT = 1;
    this.boardFlowShrink = 1;
    this.boardFlowChrome = 0;
    this.boardFlowTitle = 1;
    this.boardFlowFocus = 0;
    this.boardFlowReveal = 0;
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    this.boardFlowPodiumDx = [];
    this.boardFlowPodiumDy = [];
    this.boardFlowRelayWidths = [];
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.boardFlowStackT = 0;
    this.boardFlowGridVisible = true;
    this.boardFlowGridReveal = 0;
    this.boardFlowGridBar = 0;
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.reverseHomeGather(token, 1, 1);
    }, 16);
  }

  private reverseHomeGather(token: number, fromT: number, fromShrink: number): void {
    const from: number = Math.max(0, Math.min(1, Math.max(fromT, fromShrink)));
    this.getUIContext().animateTo({
      duration: Math.max(180, 320 * from), curve: AppCurve.Standard,
      onFinish: (): void => {
        if (!this.alive || token !== this.boardFlowToken) return;
        this.finishBoardCancel();
      }
    }, (): void => {
      this.boardFlowT = 0;
      this.boardFlowShrink = 0;
    });
  }

  private finishBoardCancel(): void {
    this.boardRefreshPullOffset = 0;
    this.onScrollerReady(this.headerScroller);
    this.boardDeckVisible = false;
    this.boardPodiumPulling = false;
    this.boardFanVisible = true;
    this.boardFabVisible = false;
    this.activeBoard = undefined;
    this.boardFlowActive = false;
    this.boardFlowPhase = 0;
    this.boardFlowT = 0;
    this.boardFlowReveal = 1;
    this.boardFlowChrome = 1;
    this.boardFlowTitle = 1;
    this.boardFlowFocus = 1;
    this.boardFlowShrink = 0;
    this.boardFlowPodiumMode = '';
    this.boardFlowPodiumProgress = 1;
    this.boardFlowPodiumDx = [];
    this.boardFlowPodiumDy = [];
    this.boardFlowRelayWidths = [];
    this.boardFlowStartZ = [];
    this.boardFlowStartOrder = [];
    this.boardFlowStartAngles = [];
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.boardFlowStackT = 0;
    this.boardFlowGridMode = '';
    this.boardFlowGridVisible = true;
    this.boardFlowGridReveal = 1;
    this.boardFlowGridBar = 1;
    this.boardFlowCenterReady = true;
    this.boardFlowSourceRects = [];
    this.boardFlowBoard = undefined;
    this.boardFlowPullStartAt = -1;
    this.boardTransitioning = false;
  }

  private startBoardCloseFlow(): void {
    const board: RankingBoard | undefined = this.boardFlowBoard ?? this.activeBoard;
    if (board === undefined) {
      this.activeBoard = undefined;
      return;
    }
    // 中心 >5 时选中的中心卡是页面级牌堆层，不是五卡扇形成员；
    // 关闭/侧滑返回时必须一起撤掉，否则它会留在首页上不消失。
    this.boardFlowStackVisible = false;
    this.boardFlowGhostVisible = false;
    this.boardFlowStackT = 0;
    this.boardDeckVisible = false;
    this.boardFanVisible = true;
    this.boardFlowAutoDealActive = false;
    this.boardFlowFlipLastRank = 0;
    this.boardFlowCenterReady = true;
    const sources: BoardFlowRect[] = this.measureBoardFlowSources(board);
    this.boardFlowSourceRects = sources;
    const targets: BoardFlowRect[] = this.collectBoardTargets(board);
    const dx: number[] = [];
    const dy: number[] = [];
    const widths: number[] = [];
    const count: number = Math.min(targets.length, sources.length);
    for (let index = 0; index < count; index++) {
      const source: BoardFlowRect = sources[index];
      const target: BoardFlowRect = targets[index];
      dx.push(source.x + source.w / 2 - (target.x + target.w / 2));
      dy.push(source.y + source.h / 2 - (target.y + target.h / 2));
      widths.push(source.w);
    }
    const token: number = ++this.boardFlowToken;
    this.boardFlowPhase = 3;
    this.boardFlowT = 0;
    this.boardFlowReveal = 1;
    this.boardFlowChrome = 1;
    this.boardFlowTitle = 1;
    this.boardFlowFocus = 1;
    this.boardFlowShrink = 0;
    this.boardFlowPodiumMode = 'exit';
    this.boardFlowPodiumProgress = 0;
    this.boardFlowPodiumDx = dx;
    this.boardFlowPodiumDy = dy;
    this.boardFlowRelayWidths = widths;
    this.boardFlowActive = true;
    this.boardTransitioning = true;
    // 先让“回到正常姿态 + 起点位移”真正渲染一帧，再启动回位动画，避免起止值被合并。
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFlowToken) return;
      this.getUIContext().animateTo({
        duration: AppMotion.Slow, curve: AppCurve.Decelerate,
        onFinish: (): void => {
          if (!this.alive || token !== this.boardFlowToken) return;
          this.activeBoard = undefined;
          this.boardFlowActive = false;
          this.boardFlowPhase = 0;
          this.boardFlowT = 0;
          this.boardFlowReveal = 1;
          this.boardFlowChrome = 1;
          this.boardFlowTitle = 1;
          this.boardFlowFocus = 1;
          this.boardFlowShrink = 0;
          this.boardFlowPodiumMode = '';
          this.boardFlowPodiumProgress = 1;
          this.boardFlowPodiumDx = [];
          this.boardFlowPodiumDy = [];
          this.boardFlowRelayWidths = [];
          this.boardFlowStartZ = [];
          this.boardFlowStartOrder = [];
          this.boardFlowStartAngles = [];
          this.boardFlowStackVisible = false;
          this.boardFlowGhostVisible = false;
          this.boardFlowStackT = 0;
          this.boardFlowFlipLastRank = 0;
          this.boardFlowAutoDealActive = false;
          this.boardFlowCenterReady = true;
          this.boardFlowSourceRects = [];
          this.boardFlowBoard = undefined;
          this.boardTransitioning = false;
        }
      }, (): void => {
        this.boardFlowT = 1;
        this.boardFlowReveal = 0;
        this.boardFlowChrome = 0;
        this.boardFlowPodiumProgress = 1;
      });
    }, 16);
  }

  private boardAvailableWidth(): number {
    return Math.max(0, this.menuViewportWidth - this.leftSafe - this.rightSafe - BOARD_EDGE * 2);
  }

  /** 页脚底部避让：优先用 MainPage 透传的实测底栏，否则用 WindowUtils 的双排兜底。 */
  private contentBottomPadding(): number {
    const bar: number = this.bottomTabInset > 0 ? this.bottomTabInset :
      WindowUtils.getFloatingTabBottomVp();
    return Math.max(120, bar + 24);
  }

  /** 网格列数按当前容器宽度计算，适配分栏和窗口调整。 */
  private boardColumns(): number {
    const width: number = this.boardAvailableWidth();
    let columns: number = 4;
    if (width >= AdaptiveLayout.MEDIUM_WIDTH) columns = 5;
    if (width >= AdaptiveLayout.LARGE_WIDTH) columns = 6;
    if (width >= 1200) columns = 7;
    return columns;
  }

  private boardCardWidth(): number {
    const columns: number = this.boardColumns();
    const available: number = this.boardAvailableWidth();
    // 去掉 96vp 硬下限：手机 4 列约 70vp，必须允许小于 96 才能塞进内容区。
    return Math.max(48, (available - BOARD_GRID_GAP * (columns - 1)) / columns);
  }

  /** 卡片变宽时文字同步放大，手机窄卡保持 1.0。 */
  private boardCardFontScale(): number {
    return Math.min(1.25, Math.max(1, this.boardCardWidth() / 120));
  }

  /** 宽度跨列数档位时重新分组，避免旋转/分栏后行分组还停留在旧列数。 */
  private syncBoardColumns(): void {
    const next: number = this.boardColumns();
    if (next === this.boardColumnCount) return;
    this.boardColumnCount = next;
    if (this.activeBoard !== undefined) this.setBoardContent(this.activeBoard);
  }

  private boardCoverAspect(): number {
    const first: RankingBook | undefined = this.activeBoard?.books[0];
    return first !== undefined && first.contentType === 'audio' ? 1 : 0.75;
  }

  /** TOP 区展示 5 本；不足 5 本回退到 3 本，避免扇形槽位不对称。 */
  private podiumBookCount(board: RankingBoard | undefined): number {
    const total: number = board !== undefined ? board.books.length : 0;
    return total >= 5 ? 5 : Math.min(3, total);
  }

  private boardTopBooks(): RankingBook[] {
    return this.activeBoard !== undefined ?
      this.activeBoard.books.slice(0, this.podiumBookCount(this.activeBoard)) : [];
  }

  /** TOP 区之外的书籍按列分组，交给 LazyForEach 按行懒加载。 */
  private setBoardContent(board: RankingBoard | undefined): void {
    if (board === undefined) {
      this.gridRowsData.setItems([]);
      return;
    }
    const rest: RankingBook[] = board.books.slice(this.podiumBookCount(board));
    const columns: number = this.boardColumns();
    this.boardColumnCount = columns;
    const rows: RankingBook[][] = [];
    for (let index = 0; index < rest.length; index += columns) {
      rows.push(rest.slice(index, index + columns));
    }
    this.gridRowsData.setItems(rows);
  }

  /** 完整榜单点卡：量封面位置，沿用首页货架的白色铺满展开。 */
  private openBoardBook(book: RankingBook, nodeId: string): void {
    const platform: Resource = this.activeBoard !== undefined ? this.activeBoard.platformName :
      $r('app.string.ranking_home');
    let origin: CardOrigin;
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), nodeId);
      if (!rect.isValid()) throw new Error('rect unavailable');
      origin = new CardOrigin(WindowUtils.pxToVp(rect.leftPx + rect.widthPx / 2),
        WindowUtils.pxToVp(rect.topPx + rect.heightPx / 2), WindowUtils.pxToVp(rect.widthPx), nodeId,
        WindowUtils.pxToVp(rect.heightPx));
    } catch (_error) {
      origin = new CardOrigin(WindowUtils.getWindowWidthVp() / 2,
        WindowUtils.getWindowHeightVp() / 2, 120);
    }
    this.openCard(book, platform, origin);
  }

  private sectionChromeOpacity(boardId: string): number {
    if (!this.boardFlowActive) return 1;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    if (this.boardFlowPhase === 2) {
      // 榜单/过渡牌堆接管后，首页目标分区的标题和焦点也一起隐藏。
      return 0;
    }
    if (this.boardFlowPhase !== 1) return 1;
    return 1 - Math.max(0, Math.min(1, this.boardFlowT));
  }

  private sectionShelfOpacity(boardId: string): number {
    if (!this.boardFlowActive) return 1;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    // 有声货架已交给页面牌堆；切入第二阶段等待 TOP 节点就绪时也不能重新露出。
    if (target && (this.boardFlowPhase === 1 || this.boardFlowPhase === 2) && this.boardDeckVisible &&
      this.boardFlowBoard?.books[0]?.contentType === 'audio') return 0;
    if (this.boardFlowPhase === 2) {
      // 榜单页接管后首页货架必须彻底隐藏；否则聚拢状态结束、卡片弹回普通货架，
      // 会叠在榜单牌堆后面/上面，出现同一张封面重复和牌堆轮廓变化。
      return target && !this.boardHomeRelayReady ? 1 : 0;
    }
    if (this.boardFlowPhase !== 1) return 1;
    return target ? 1 : 1 - Math.max(0, Math.min(1, this.boardFlowT));
  }

  private sectionGatherProgress(boardId: string): number {
    if (!this.boardFlowActive || (this.boardFlowPhase !== 1 && this.boardFlowPhase !== 2)) return 0;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    if (target && this.boardFlowPhase === 2) return 1;
    return target ? Math.max(0, Math.min(1, this.boardFlowT)) : 0;
  }

  private sectionGatherBoardId(boardId: string): string {
    if (!this.boardFlowActive || (this.boardFlowPhase !== 1 && this.boardFlowPhase !== 2)) return '';
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    return target ? boardId : '';
  }

  private sectionGatherShrink(boardId: string): number {
    if (!this.boardFlowActive || (this.boardFlowPhase !== 1 && this.boardFlowPhase !== 2)) return 0;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    if (target && this.boardFlowPhase === 2) return 1;
    return target ? Math.max(0, Math.min(1, this.boardFlowShrink)) : 0;
  }

  private sectionShelfTop(boardId: string): number {
    if (!this.boardFlowActive || (this.boardFlowPhase !== 1 && this.boardFlowPhase !== 2)) return 0;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    return target ? this.boardFlowSourceShelf.y : 0;
  }

  private sectionGatherTargetBottom(boardId: string): number {
    if (!this.boardFlowActive || (this.boardFlowPhase !== 1 && this.boardFlowPhase !== 2)) return 0;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    return target ? this.boardFlowTargetBottom : 0;
  }

  private sectionGatherSnapshotToken(boardId: string): number {
    if (!this.boardFlowActive || this.boardFlowPhase !== 1) return 0;
    const target: boolean = this.boardFlowBoard !== undefined && this.boardFlowBoard.id === boardId;
    return target ? this.boardFlowGatherSnapshotToken : 0;
  }

  /** 书架点击先展示书籍卡片，开始阅读再进入原有书源匹配流程。 */
  private openCard(book: RankingBook, platform: Resource, origin: CardOrigin): void {
    // 必须在挂载卡片之前量好基准，否则首帧位移会以 0 为基准，表现为从角落飞入。
    let baseCx: number = WindowUtils.getWindowWidthVp() / 2;
    let baseCy: number = WindowUtils.getWindowHeightVp() / 2;
    let hostTop: number = 0;
    try {
      const host = this.getUIContext().getComponentUtils().getRectangleById('main-page-root');
      baseCx = px2vp(host.windowOffset.x + host.size.width / 2);
      baseCy = px2vp(host.windowOffset.y + host.size.height / 2);
      hostTop = px2vp(host.windowOffset.y);
    } catch (_error) { /* 量不到时用窗口中心 */ }
    this.cardBook = book;
    // 隐藏哪张卡片要和动画起点用同一个唯一键，否则同名书会一起被隐藏。
    this.cardBookId = origin.key.length > 0 ? origin.key : book.id;
    this.cardVisible = true;
    const actions: RankingCardActions = new RankingCardActions();
    actions.prepareMatch = (match: RankingMatch): Promise<void> => this.prepareMatch(match);
    actions.openReader = (target: Book, onReturn: () => void, resourceIndex?: number): void => {
      this.openReaderFromCard(target, onReturn, resourceIndex);
    };
    actions.openHistory = (target: Book): void => { this.openHistoryFromCard(target); };
    actions.historyJump = (session: ReadingSession, location: SessionLocation): void => {
      this.onHistoryJump(session, location);
    };
    actions.manageSources = (): void => this.manageSourcesFromCard();
    actions.exit = (): void => this.closeCard();
    actions.restoreSource = (): void => { this.cardBookId = ''; };
    // 卡片实际渲染在 MainPage 根 Stack：底栏之上、Navigation 目的地之下，阅读器能盖住它。
    rankingCardStore.hostTop = hostTop;
    this.updateCardTopBoundary();
    rankingCardStore.open(book, platform, origin, baseCx, baseCy, actions);
  }

  /** 沿用旧版选择版本的顶部边界，不读取 HDS 标题 Builder 的代理坐标。 */
  @Monitor('topSafe', 'headerOffset', 'contentHeight', 'activeBoard')
  private updateCardTopBoundary(): void {
    if (!this.cardVisible) return;
    const titleHeight: number = this.activeBoard !== undefined ? RANKING_SEARCH_HEIGHT :
      this.searchViewportHeight > 0.5 ? this.searchViewportHeight : 48;
    rankingCardStore.topBoundary = Math.max(0,
      this.topSafe + titleHeight + AppSpace.Xs - rankingCardStore.hostTop);
  }

  /** 顶部海报封面点击：从右侧那张封面实际所在的位置展开详情卡片。 */
  private openCardFromPoster(book: RankingBook, nodeId: string): void {
    let origin: CardOrigin;
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), nodeId);
      if (!rect.isValid()) throw new Error('poster rect unavailable');
      origin = new CardOrigin(WindowUtils.pxToVp(rect.leftPx + rect.widthPx / 2),
        WindowUtils.pxToVp(rect.topPx + rect.heightPx / 2), WindowUtils.pxToVp(rect.widthPx), nodeId,
        WindowUtils.pxToVp(rect.heightPx));
    } catch (_error) {
      origin = new CardOrigin(WindowUtils.getWindowWidthVp() / 2,
        WindowUtils.getWindowHeightVp() / 2, 120);
    }
    this.openCard(book, $r('app.string.ranking_home'), origin);
  }

  /** 卡片缩回书架后回调，卸掉卡片并把书架上的卡片露回来。 */
  private closeCard(): void {
    this.cardVisible = false;
    this.cardBookId = '';
    rankingCardStore.close();
  }

  /** 选中书源后先校验、缓存、记住选择；真正的打开留给详情态的主按钮。 */
  private async prepareMatch(match: RankingMatch): Promise<void> {
    if (!this.alive || !this.cardVisible || this.openingBook) throw new Error('Card unavailable');
    this.openingBook = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('Context unavailable');
      const sources = await SourceDataService.getEnabledSources();
      if (!sources.some((source: BookSource): boolean => source.bookSourceUrl === match.book.sourceUrl)) {
        throw new Error('Selected source is no longer enabled');
      }
      await DataService.upsertCachedBook(match.book);
      await BookMatchService.remember(context, this.cardBook, match);
      if (!this.alive) return;
      SearchCache.put(match.book);
    } catch (_error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_open_failed') });
      } catch (_ignored) { /* 页面离开时不显示提示。 */ }
      throw new Error('Unable to prepare selected source');
    } finally {
      this.openingBook = false;
    }
  }

  /** 详情态的「阅读记录」：卡片留在下面，记录页盖上去，返回时状态原样保留。 */
  private openHistoryFromCard(book: Book): void {
    this.onOpenHistory(book);
  }

  /** 详情态的「开始阅读」：交给外层推入阅读器；卡片原位保留，返回后原样露出。 */
  private openReaderFromCard(book: Book, onReturn: () => void, resourceIndex?: number): void {
    this.onOpenReader(book, onReturn, resourceIndex);
  }

  /** 面板里的“导入/管理书源”入口。 */
  private manageSourcesFromCard(): void {
    this.onManageSources((): void => {
      if (this.alive && this.cardVisible) rankingCardStore.refreshToken++;
    });
  }


  @Builder
  private heroContent() {
    if (this.posterCount > 0) {
      BookPosterCarousel({ items: this.posterDeckItems,
        autoPlay: this.visible && this.posterVisible && this.activeBoard === undefined &&
          !this.boardTransitioning && !this.cardVisible,
        // 右侧整叠封面本身也要能点开详情。
        openCover: true,
        // 卡片接走后隐藏同一张封面，和书架卡片一致。
        hiddenId: this.cardBookId,
        onChoose: (item: BookPosterItem, nodeId: string): void => {
          const poster = this.posterItems.find((entry: RankingPosterItem): boolean => entry.book.id === item.id);
          if (poster !== undefined) this.openCardFromPoster(poster.book, nodeId);
        },
        onCoverChange: (cover: string): void => { this.posterCover = cover; },
        onVerticalScroll: (offset: number): void => this.scrollFromPoster(offset),
        onVerticalFling: (velocity: number): void => this.flingFromPoster(velocity) })
      .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number): void => { this.posterVisible = visible && ratio >= 0.5; })
    } else if (this.loading) {
      Row({ space: 16 }) {
        Column({ space: 14 }) {
          Row().height(22).width('80%').backgroundColor(AppColor.Divider).borderRadius(6)
          Row().height(16).width('55%').backgroundColor(AppColor.Divider).borderRadius(5)
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() {
          Row().width(RANKING_COVER_WIDTH).height(RANKING_COVER_WIDTH / 0.75)
            .borderRadius(AppRadius.Sm).backgroundColor(AppColor.Divider)
        }.width(RANKING_COVER_WIDTH).height(RANKING_DECK_HEIGHT)
      }.height(RANKING_POSTER_HEIGHT).width('100%')
        .padding({ left: 24, right: 42, top: 8, bottom: 16 })
    }
  }

  @Builder
  private platformTabs() {
    Row({ space: AppSpace.Xs }) {
      ImmersiveTabComponent({ label: $r('app.string.home_categories'), fitContent: true,
        selected: this.overview, onTap: (): void => { this.overview = true; } })
      List({ space: AppSpace.Xs, scroller: this.categoryScroller }) {
        LazyForEach(this.platformData, (platform: RankingPlatform) => {
          ListItem() {
            ImmersiveTabComponent({ label: platform.name, fitContent: true,
              selected: !this.overview && this.platformId === platform.id,
              onTap: (): void => this.selectPlatform(platform.id) })
          }
        }, (platform: RankingPlatform): string => platform.id || 'recommendations')
      }.layoutWeight(1).height(34).listDirection(Axis.Horizontal).scrollBar(BarState.Off)
      // 与书源首页一致，保留两侧渐隐，材质随背景实时绘制。
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(24) })
      .renderGroup(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).cachedCount(1)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(21).fontColor([AppTheme.IconPrimary])
      }.width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.ranking_order')).id('ranking-order-button')
        .onClick((): void => { this.showBoardOrder = true; })
      if (this.isSearchCollapsed) {
        Stack() {
          Stack({ alignContent: Alignment.Center }) {
            ThemeIconComponent({ role: ThemeIconRole.Search, symbol: $r('sys.symbol.magnifyingglass'),
              iconSize: 21, tint: AppTheme.IconPrimary })
          }.width(42).height(42).borderRadius(AppRadius.Pill)
            .backgroundColor(Color.Transparent)
            .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
            .onClick(() => this.onSearchTap())
        }.width(42).height(42)
      }
    }.height(48).width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: 3, bottom: 3 })
  }

  @Builder
  private categoryOverview() {
    Column({ space: 12 }) {
      ForEach(this.platforms.filter((platform: RankingPlatform): boolean => platform.id.length > 0),
        (platform: RankingPlatform) => {
          Column({ space: 12 }) {
            Text(platform.name).fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
              ForEach(this.boards.filter((board: RankingBoard): boolean => board.platformId === platform.id),
                (board: RankingBoard) => {
                  Button(board.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppTheme.TextPrimary)
                    .height(44).backgroundColor(AppColor.Divider).onClick(() => this.openBoard(board))
                }, (board: RankingBoard): string => board.id)
            }.width('100%')
          }.alignItems(HorizontalAlign.Start).padding(18).width('100%').borderRadius(16)
          .backgroundColor(AppColor.GlassSheetControlTint)
        }, (platform: RankingPlatform): string => platform.id)
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private refreshIndicator(offset: number) {
    Row() {
      if (this.refreshing) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      } else {
        Progress({ value: Math.min(100, offset / 96 * 100), total: 100, type: ProgressType.Ring })
          .width(24).height(24).color(AppColor.Brand).backgroundColor(Color.Transparent)
          .style({ strokeWidth: 2, enableSmoothEffect: false })
      }
    }.width('100%').height(offset).justifyContent(FlexAlign.Center)
      .opacity(Math.min(1, offset / 24)).clip(true)
  }

  private currentRefreshPullOffset(): number {
    return this.activeBoard === undefined ? this.refreshPullOffset : this.boardRefreshPullOffset;
  }

  /** 隐藏只停止绘制，保留首页滚动位置和原卡节点；返回动画启动前恢复。 */
  private homeLayerVisibility(): Visibility {
    return this.activeBoard !== undefined && !this.boardTransitioning && !this.boardFlowActive ?
      Visibility.Hidden : Visibility.Visible;
  }

  @Builder
  private emptyRefreshIndicator() {
    Column().width(0).height(0)
  }


  /** 横屏/矮窗口：收起顶部大海报，把高度让给分类和榜单内容。 */
  private posterHeight(): number {
    // 横屏也保留顶部推荐位，不能因为矮窗口把整块内容裁掉。
    return RANKING_POSTER_HEIGHT;
  }

  /** 首页 chrome（搜索/海报/分类）在收拢阶段淡出；榜单页盖住后不再参与。 */
  private homeChromeOpacity(): number {
    if (!this.boardFlowActive) return 1;
    // 一进入聚拢就把首页 hero/海报/搜索整体藏掉；它们不能和过渡牌堆同时出现。
    if (this.boardFlowPhase === 1 || this.boardFlowPhase === 2) return 0;
    return 1;
  }

  @Computed
  get headerRange(): number { return RANKING_SEARCH_HEIGHT + this.posterHeight(); }

  @Computed
  get posterBackgroundHeight(): number { return this.topSafe + this.headerRange + 48; }

  @Computed
  get searchViewportHeight(): number {
    return Math.max(0, RANKING_SEARCH_HEIGHT - this.headerOffset);
  }

  @Computed
  get isSearchCollapsed(): boolean { return this.headerOffset >= this.headerRange - 0.5; }

  @Computed
  get searchTitleContent(): TitleBarContentOptions {
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' }, stackBuilder: this.searchHeaderBuilder
    };
    if (PlatformCompat.supports(26)) {
      const builder: BuilderOptions = { builder: this.searchHeaderBuilder, updated: false };
      content.stackBuilderContent = builder;
    }
    return content;
  }

  @Computed
  get navigationTitleContent(): TitleBarContentOptions {
    const bottom: BottomBuilderParams = {
      builder: this.navigationBottomBuilder,
      height: this.posterHeight() + 48
    };
    if (PlatformCompat.supports(26)) {
      const builderContent: BuilderOptions = { builder: this.navigationBottomBuilder, updated: false };
      bottom.builderContent = builderContent;
    }
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' }, bottomBuilder: bottom
    };
    return content;
  }

  private scrollFromPoster(offset: number): void {
    if (this.activeBoard !== undefined || this.boardTransitioning) return;
    // 标题层不属于 Scroll 子树，显式将纵向拖动交给既有的两级滚动容器。
    if (offset > 0) {
      const headerDelta = Math.min(offset, Math.max(0, this.headerRange - this.headerScroller.currentOffset().yOffset));
      this.headerScroller.scrollBy(0, headerDelta);
      if (offset > headerDelta) this.scroller.scrollBy(0, offset - headerDelta);
    } else {
      const listDelta = Math.max(offset, -Math.max(0, this.scroller.currentOffset().yOffset));
      this.scroller.scrollBy(0, listDelta);
      if (offset < listDelta) this.headerScroller.scrollBy(0, offset - listDelta);
    }
  }

  private flingFromPoster(velocity: number): void {
    if (this.activeBoard !== undefined || this.boardTransitioning) return;
    try {
      const headerOffset = this.headerScroller.currentOffset().yOffset;
      if ((velocity < 0 && headerOffset < this.headerRange - 0.5) ||
        (velocity > 0 && this.scroller.currentOffset().yOffset < 0.5)) {
        this.headerScroller.fling(velocity);
      } else {
        this.scroller.fling(velocity);
      }
    } catch (_error) { /* 页面离开时滚动控制器可能已解绑。 */ }
  }

  private syncHeaderScroll(): void {
    const previousOffset = this.headerOffset;
    this.headerOffset = Math.max(0, Math.min(this.headerRange, this.headerScroller.currentOffset().yOffset));
    // 首页双击回顶时联动正文；独立榜单不改变这两个滚动控制器。
    if (this.activeBoard === undefined && previousOffset >= 0.5 &&
      this.headerOffset < 0.5 && this.scroller.currentOffset().yOffset > 0.5) {
      this.scroller.scrollEdge(Edge.Top);
    }
  }

  @LocalBuilder
  private searchHeader() {
    Row() { this.headerBuilder() }
      .width('100%').height(RANKING_SEARCH_HEIGHT)
      .translate({ y: -Math.min(RANKING_SEARCH_HEIGHT, this.headerOffset) })
      .opacity(Math.min(1, this.searchViewportHeight / 24) * this.homeChromeOpacity())
      .visibility(this.searchViewportHeight <= 0.5 ? Visibility.Hidden : Visibility.Visible)
  }

  @LocalBuilder
  private navigationBottom() {
    Column() {
      Column() { this.heroContent() }.width('100%').height(RANKING_POSTER_HEIGHT)
        .flexShrink(0).clip(true)
        .opacity(Math.max(0, Math.min(1, (this.headerRange - this.headerOffset) / 64)))
        .enabled(!this.isSearchCollapsed)
      this.platformTabs()
    }.width('100%').height(this.posterHeight() + 48).opacity(this.homeChromeOpacity())
  }

  @Builder
  private rankingNavigation() {
    // 与书源首页相同：整段导航随外层 Scroll 移动，内部标题和占位始终保持完整高度。
    HdsNavigation() {
      Column() {
        Column().width('100%').height(this.topSafe + this.headerRange + 48)
        this.rankingContent()
      }.width('100%').clip(false).backgroundColor(Color.Transparent)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: this.navigationTitleContent,
      style: {
        scrollEffectOpts: { scrollEffectType: HdsCompat.scrollEffect },
        originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
        thermoCtrl: true, systemMaterialEffect: HdsCompat.material
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true).mode(NavigationMode.Stack)
    .bindToScrollable([this.scroller])
    .systemBarStyle({ statusBarContentColor: this.statusBarContentColor },
      { statusBarContentColor: this.statusBarContentColor })
    .width('100%').height(this.contentHeight + this.headerRange).flexShrink(0)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private rankingContent() {
    // 首页始终保留在树中，榜单使用独立列表，返回无需重建或回填滚动位置。
    List({ scroller: this.scroller }) {
      ListItemGroup() {
        if (this.overview) {
          ListItem() { this.categoryOverview() }
        } else if (!this.loading && this.boards.length === 0) {
          ListItem() {
            Text($r('app.string.ranking_categories_empty')).fontSize(14)
              .fontColor(AppTheme.TextSecondary).textAlign(TextAlign.Center)
              .width('100%').padding(32)
          }
        } else {
          LazyForEach(this.boardData, (board: RankingBoard) => {
            ListItem() {
              RankingSection({ board: board, hiddenId: this.cardBookId,
                chromeOpacity: this.sectionChromeOpacity(board.id),
                shelfOpacity: this.sectionShelfOpacity(board.id),
                gatherBoardId: this.sectionGatherBoardId(board.id),
                gatherProgress: this.sectionGatherProgress(board.id),
                gatherShrink: this.sectionGatherShrink(board.id),
                bottomInset: this.bottomTabInset,
                gatherBottomTarget: this.sectionGatherTargetBottom(board.id),
                gatherSnapshotToken: this.sectionGatherSnapshotToken(board.id),
                onGatherSnapshot: (cells: RankingGatherCell[]): void => {
                  if (this.boardFlowBoard !== undefined && this.boardFlowBoard.id === board.id) {
                    this.boardFlowDeckCells = cells;
                  }
                },
                shelfTop: this.sectionShelfTop(board.id),
                onOpenCard: (book: RankingBook, origin: CardOrigin): void =>
                  this.openCard(book, board.platformName, origin),
                onCenterChange: (boardId: string, book: RankingBook, index: number): void => {
                  this.homeFocusBooks.set(boardId, book);
                  this.homeFocusIndexes.set(boardId, index);
                },
                onMore: (item: RankingBoard): void => this.startBoardGatherDealFlow(item) })
            }
            // 卡片集可能向上/向下移到底栏上方，跨到相邻榜单区域时也要盖在它们上面。
            .zIndex(this.sectionGatherProgress(board.id) > 0 ? 80 : 0)
          }, (board: RankingBoard): string => `${board.id}:${board.fetchedAt}:${board.stale}:${board.unavailable}`)
        }
      }
      ListItem() {
        Text($r('app.string.ranking_footer')).fontSize(11).fontColor(AppTheme.TextTertiary)
          .textAlign(TextAlign.Center).width('100%')
          .padding({ top: 30, bottom: this.contentBottomPadding(), left: 24, right: 24 })
      }
    }.width('100%').height(Math.max(1, this.contentHeight - this.topSafe - 48))
    .scrollBar(BarState.Off).cachedCount(1)
    .onDidScroll((offset: number, state: ScrollState): void => this.onContentScroll(offset, state))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    // 外层抵消整页下拉以固定海报和分类；仅正文下移，为分类下方的刷新指示器留出空间。
    .translate({ y: this.refreshPullOffset })
    // 与书源首页一致：让滚出视口的书籍继续绘制在分类胶囊背后，供沉浸材质采样。
    .clip(false).backgroundColor(Color.Transparent)
  }

  @Monitor('showBoardOrder', 'topSafe', 'leftSafe', 'rightSafe', 'headerOffset', 'contentHeight',
    'menuViewportWidth', 'bottomTabInset')
  private updateBoardOrderBounds(): void {
    if (!this.showBoardOrder) return;
    const host: BoardFlowRect | undefined = this.measureFlowRect('rankingCardAnchor');
    const hostTop: number = host?.y ?? 0;
    const titleHeight: number = this.searchViewportHeight > 0.5 ? this.searchViewportHeight : 48;
    const top: number = Math.max(0, this.topSafe + titleHeight + AppSpace.Xs - hostTop);
    const bottom: number = Math.min(this.contentHeight,
      this.measureBoardFlowTargetBottom() - hostTop - 12);
    const available: number = Math.max(1, this.menuViewportWidth - this.leftSafe - this.rightSafe);
    const width: number = Math.min(440, available * 0.88);
    this.boardOrderBounds = new BoardFlowRect(this.leftSafe + (available - width) / 2, top,
      width, Math.max(1, bottom - top));
  }

  @Builder
  private boardOrderSheet() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor('#33000000')
        .onClick((): void => { this.showBoardOrder = false; })
      Column() {
        RankingBoardOrderComponent({ onClose: (): void => { this.showBoardOrder = false; } })
      }.width(this.boardOrderBounds.w).height(this.boardOrderBounds.h)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(24).clip(true)
        .id('ranking-board-order-panel')
        .position({ x: this.boardOrderBounds.x, y: this.boardOrderBounds.y })
    }.width('100%').height('100%')
  }

  @Builder
  private boardHeader(board: RankingBoard) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text() {
          Span(board.title).fontSize(28).fontWeight(FontWeight.Bold)
          Span($r('app.string.ranking_label_separator')).fontSize(18)
          Span(board.platformName).fontSize(18).fontWeight(FontWeight.Medium)
        }.fontColor(AppTheme.TextPrimary).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          .id('rankingBoardTitle-' + board.id)
        Text($r('app.string.ranking_top_badge', board.books.length)).fontSize(11)
          .fontColor(AppTheme.TextSecondary)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.glass_stroke')).borderRadius(10)
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Text(board.fetchedAt > 0
          ? rankingUpdateTime(board.fetchedAt)
          : $r('app.string.ranking_unavailable')).fontSize(11).fontColor(AppTheme.TextSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (board.books.length > 0) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_up_to_line')).fontSize(16)
              .fontColor([AppTheme.TextSecondary])
          }.width(30).height(30).padding(0)
          .backgroundColor($r('app.color.glass_stroke'))
          .onClick((): void => { this.boardTopToken++; })
          .accessibilityText($r('app.string.ranking_back_top'))
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      if (board.stale) {
        Text($r('app.string.ranking_cached')).fontSize(11).fontColor(AppTheme.TextTertiary)
      }
    }.width('100%').padding({ left: BOARD_EDGE, right: BOARD_EDGE, top: 8 })
      .alignItems(HorizontalAlign.Start)
  }

  /** 行 key 必须包含列数和这一行的全部书；只取第一本会在转屏重分行时复用旧行，导致多/少一张。 */
  private boardGridRowKey(row: RankingBook[]): string {
    const ids: string[] = [];
    for (let index: number = 0; index < row.length; index++) {
      ids.push(`${row[index].rank}:${row[index].id}`);
    }
    return `${this.boardColumnCount}:${row.length}:${ids.join('|')}`;
  }

  /** 发牌中的行抬到白卡行之上；中心卡前面那几行里的飞行封面再单卡抬到最上面。 */
  private boardGridRowZ(row: RankingBook[]): number {
    if (!this.boardFlowActive || this.boardFlowPhase !== 2) return 0;
    if (this.boardFlowCenterRank > 5) {
      for (let index: number = 0; index < row.length; index++) {
        if (row[index].rank < this.boardFlowCenterRank) return 7;
      }
    }
    return 6;
  }

  private boardCardFlowZ(book: RankingBook): number {
    if (this.boardFlowActive && this.boardFlowGridMode === 'pivot' &&
      book.rank < this.boardFlowCenterRank) {
      return 20;
    }
    return 1;
  }

  @Builder
  private boardCardRow(row: RankingBook[]) {
    Row({ space: BOARD_GRID_GAP }) {
      ForEach(row, (book: RankingBook) => {
        RankingBoardCard({ book: book, boardId: this.activeBoard?.id ?? '',
          hiddenId: this.cardBookId,
          coverAspect: this.boardCoverAspect(), fontScale: this.boardCardFontScale(),
          flowDealToken: this.boardFlowGridDealToken,
          flowFlipToken: this.boardFlowGridFlipToken,
          flowWhiteToken: this.boardFlowGridWhiteToken,
          flowScrollOffset: this.boardFlowListOffset,
          flowMode: this.boardFlowGridMode,
          flowCenterRank: this.boardFlowCenterRank,
          flowFirstRank: this.boardFlowGridFirstRank,
          flowLastRank: this.boardFlowGridLastRank,
          flowFlipLastRank: this.boardFlowFlipLastRank,
          flowFromX: this.boardFlowGridFromX,
          flowFromY: this.boardFlowGridFromY,
          flowFromW: this.boardFlowGridFromW,
          flowCenterReady: this.boardFlowCenterReady,
          onChoose: (item: RankingBook, nodeId: string): void => this.openBoardBook(item, nodeId) })
          .width(this.boardCardWidth())
          .zIndex(this.boardCardFlowZ(book))
      }, (book: RankingBook): string => `${book.id}:${book.rank}`)
    }.width('100%').height(this.boardGridRowHeight())
      .padding({ left: BOARD_EDGE, right: BOARD_EDGE })
  }

  private boardRestCount(): number {
    return this.activeBoard !== undefined ?
      Math.max(0, this.activeBoard.books.length - this.podiumBookCount(this.activeBoard)) : 0;
  }

  /** TOP 区和网格之间：一块主题自适应面板，单纯做章节分隔。 */
  @Builder
  private boardShelfHeader() {
    Row({ space: 8 }) {
      Text($r('app.string.ranking_board_more')).fontSize(16).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary)
      Text($r('app.string.ranking_board_rest_count', this.boardRestCount()))
        .fontSize(11).fontColor(AppTheme.TextTertiary)
      Blank()
    }.width('100%').height(46).padding({ left: 14, right: 14 })
    .backgroundColor(AppTheme.Surface)
    .borderRadius(AppRadius.Lg)
    .shadow({ radius: 12, color: RankingCardStyle.SHADOW_COLOR, offsetY: 4 })
    .margin({ top: 10, bottom: 4 })
  }

  private boardFlowLayerBaseW(): number {
    const shrink: number = Math.max(0.2, Math.min(1, this.boardFlowCenterShrink));
    return this.boardFlowStackW * shrink;
  }

  private boardFlowLayerBaseH(): number {
    const shrink: number = Math.max(0.2, Math.min(1, this.boardFlowCenterShrink));
    return this.boardFlowStackH * shrink;
  }

  private boardFlowLayerX(): number {
    const baseW: number = this.boardFlowLayerBaseW();
    const baseX: number = this.boardFlowStackX + (this.boardFlowStackW - baseW) / 2;
    return baseX + (this.boardFlowCenterTargetX - baseX) * this.boardFlowStackT;
  }

  private boardFlowLayerY(): number {
    const baseH: number = this.boardFlowLayerBaseH();
    const baseY: number = this.boardFlowStackY + (this.boardFlowStackH - baseH) / 2;
    return baseY + (this.boardFlowCenterTargetY - baseY) * this.boardFlowStackT;
  }

  private boardFlowLayerW(): number {
    const baseW: number = this.boardFlowLayerBaseW();
    const target: number = this.boardFlowCenterTargetW > 0 ?
      this.boardFlowCenterTargetW : this.boardFlowStackW;
    return baseW + (target - baseW) * this.boardFlowStackT;
  }

  private boardFlowLayerH(): number {
    const baseH: number = this.boardFlowLayerBaseH();
    const target: number = this.boardFlowCenterTargetH > 0 ?
      this.boardFlowCenterTargetH : this.boardFlowStackH;
    return baseH + (target - baseH) * this.boardFlowStackT;
  }

  private boardFocusInfoScale(): number {
    const width: number = Math.max(280,
      this.menuViewportWidth - this.leftSafe - this.rightSafe);
    const aspect: number = this.boardCoverAspect() >= 1 ? 1 : RankingCardStyle.COVER_ASPECT;
    const baseHeight: number = PODIUM_CENTER_W / aspect;
    const widthScale: number = width / 360;
    const heightScale: number = (WindowUtils.getWindowHeightVp() * 0.50) / baseHeight;
    const scale: number = Math.max(0.85, Math.min(2.1, widthScale, heightScale));
    return Math.min(1.25, Math.max(1, scale * 0.7));
  }

  private boardFocusInfoHeight(): number { return 36 * this.boardFocusInfoScale(); }

  private boardFocusInfoWidth(): number {
    return Math.max(280, this.menuViewportWidth - this.leftSafe - this.rightSafe);
  }

  private boardFanFocusRank(book: RankingBook | undefined): string {
    return book !== undefined ? book.rank.toString().padStart(2, '0') : '';
  }

  private boardFanFocusAuthor(book: RankingBook | undefined): string {
    return book !== undefined ? (book.author || book.narrator || '') : '';
  }

  private boardFanFocusRating(book: RankingBook | undefined): string {
    return book !== undefined && book.rating > 0 ? book.rating.toFixed(1) : '';
  }

  /** 扇形转动时焦点标题做旧/新交叉淡化，不再直接换字。 */
  private onBoardFanFocusInfo(book: RankingBook, index: number): void {
    if (this.boardFanFocusBook !== undefined && this.boardFanFocusBook.id === book.id) {
      this.boardFanFocusIndex = index;
      return;
    }
    const now: number = Date.now();
    const fast: boolean = now - this.boardFanFocusLastAt < 180;
    this.boardFanFocusLastAt = now;
    const token: number = ++this.boardFanFocusToken;
    if (fast) {
      this.boardFanFocusPrevBook = undefined;
      this.boardFanFocusPrevIndex = -1;
      this.boardFanFocusPrevOpacity = 0;
      this.boardFanFocusBook = book;
      this.boardFanFocusIndex = index;
      this.boardFanFocusOpacity = 1;
      return;
    }
    this.boardFanFocusPrevBook = this.boardFanFocusBook;
    this.boardFanFocusPrevIndex = this.boardFanFocusIndex;
    this.boardFanFocusPrevOpacity = 1;
    this.boardFanFocusOpacity = 0;
    this.boardFanFocusBook = book;
    this.boardFanFocusIndex = index;
    setTimeout((): void => {
      if (!this.alive || token !== this.boardFanFocusToken) return;
      this.getUIContext().animateTo({
        duration: AppMotion.Fast, curve: AppCurve.Accelerate
      }, (): void => {
        if (token === this.boardFanFocusToken) this.boardFanFocusPrevOpacity = 0;
      });
      this.getUIContext().animateTo({
        duration: AppMotion.Base, curve: AppCurve.Decelerate,
        onFinish: (): void => {
          if (token !== this.boardFanFocusToken) return;
          this.boardFanFocusPrevBook = undefined;
          this.boardFanFocusPrevIndex = -1;
          this.boardFanFocusPrevOpacity = 0;
        }
      }, (): void => {
        if (token === this.boardFanFocusToken) this.boardFanFocusOpacity = 1;
      });
    }, 20);
  }

  @Builder
  private boardFocusCurrentRow() {
    Row({ space: 6 }) {
      Text(this.boardFanFocusRank(this.boardFanFocusBook))
        .fontSize(26 * this.boardFocusInfoScale()).fontWeight(FontWeight.Bold)
        .fontColor(AppColor.Brand).height(34 * this.boardFocusInfoScale())
      Text(this.boardFanFocusBook !== undefined ? this.boardFanFocusBook.title : '')
        .fontSize(16 * this.boardFocusInfoScale()).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: Math.max(80, this.boardFocusInfoWidth() * 0.42) })
      if (this.boardFanFocusAuthor(this.boardFanFocusBook).length > 0) {
        Text('·').fontSize(11 * this.boardFocusInfoScale()).fontColor(AppTheme.TextTertiary)
        Text(this.boardFanFocusAuthor(this.boardFanFocusBook))
          .fontSize(11 * this.boardFocusInfoScale()).fontColor(AppTheme.TextSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: Math.max(48, this.boardFocusInfoWidth() * 0.24) })
      }
      if (this.boardFanFocusRating(this.boardFanFocusBook).length > 0) {
        Text(this.boardFanFocusRating(this.boardFanFocusBook))
          .fontSize(11 * this.boardFocusInfoScale()).fontColor(AppColor.Brand)
      }
    }.width('100%').height(this.boardFocusInfoHeight())
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .opacity(this.boardFanFocusOpacity * this.boardFlowFocus)
  }

  @Builder
  private boardFocusPrevRow() {
    Row({ space: 6 }) {
      Text(this.boardFanFocusRank(this.boardFanFocusPrevBook))
        .fontSize(26 * this.boardFocusInfoScale()).fontWeight(FontWeight.Bold)
        .fontColor(AppColor.Brand).height(34 * this.boardFocusInfoScale())
      Text(this.boardFanFocusPrevBook !== undefined ? this.boardFanFocusPrevBook.title : '')
        .fontSize(16 * this.boardFocusInfoScale()).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: Math.max(80, this.boardFocusInfoWidth() * 0.42) })
      if (this.boardFanFocusAuthor(this.boardFanFocusPrevBook).length > 0) {
        Text('·').fontSize(11 * this.boardFocusInfoScale()).fontColor(AppTheme.TextTertiary)
        Text(this.boardFanFocusAuthor(this.boardFanFocusPrevBook))
          .fontSize(11 * this.boardFocusInfoScale()).fontColor(AppTheme.TextSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: Math.max(48, this.boardFocusInfoWidth() * 0.24) })
      }
      if (this.boardFanFocusRating(this.boardFanFocusPrevBook).length > 0) {
        Text(this.boardFanFocusRating(this.boardFanFocusPrevBook))
          .fontSize(11 * this.boardFocusInfoScale()).fontColor(AppColor.Brand)
      }
    }.width('100%').height(this.boardFocusInfoHeight())
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .opacity(this.boardFanFocusPrevOpacity * this.boardFlowFocus)
  }

  /** 焦点标题独立成 ListItem：层级在五卡下方、发牌卡上方。 */
  @Builder
  private boardFocusCaption() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.boardFanFocusPrevBook !== undefined) {
        this.boardFocusPrevRow()
      }
      if (this.boardFanFocusBook !== undefined) {
        this.boardFocusCurrentRow()
      }
    }.width('100%').height(this.boardFocusInfoHeight())
    .onClick((): void => {
      const book: RankingBook | undefined = this.boardFanFocusBook;
      const board: RankingBoard | undefined = this.activeBoard;
      if (book === undefined || board === undefined) return;
      this.openBoardBook(book, this.boardPodiumCardId(board, Math.max(0, book.rank - 1)));
    })
  }

  /** 页面只派发起停令牌；逐张抽牌由子组件提交原生变换动画。 */
  @Builder
  private boardDeckLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.boardDeckCards, (card: BoardDeckCardData) => {
        RankingDeckCard({ card: card, rootX: this.boardDeckRootX, rootY: this.boardDeckRootY,
          coverFade: this.boardDeckCover, pullToken: this.boardDeckPullToken,
          gatherToken: this.boardDeckGatherToken, gatherFirst: this.boardFlowPhase === 1,
          cancelToken: this.boardDeckCancelToken, flowToken: this.boardFlowToken,
          lastOrder: this.boardDeckCards.length - 1,
          onGathered: (token: number): void => {
            setTimeout((): void => {
              if (!this.alive || token !== this.boardFlowToken) return;
              this.beginBoardDeckFlow(token);
            }, FLOW_GATHER_HOLD_MS);
          },
          onArrived: (token: number): void => {
            setTimeout((): void => {
              if (!this.alive || token !== this.boardFlowToken || !this.boardDeckVisible) return;
              this.finishBoardDeckPull(token);
            }, FLOW_PULL_SETTLE_MS);
          },
          onReturned: (token: number): void => {
            if (!this.alive || token !== this.boardFlowToken) return;
            this.boardDeckVisible = false;
            this.cancelCenterDealPage(token);
          } })
      }, (card: BoardDeckCardData): string => card.key)
    }.width('100%').height('100%').opacity(this.boardDeckOpacity)
    .zIndex(70).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  @Builder
  private boardFlowStackLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.boardFlowStackBlockTop && this.boardFlowCenterBook !== undefined) {
        Stack({ alignContent: Alignment.TopStart }) {
          CoverImage({ url: this.boardFlowCenterCover.length > 0 ?
            this.boardFlowCenterCover : this.boardFlowCenterBook.coverUrl,
            title: this.boardFlowCenterBook.title,
            author: this.boardFlowCenterBook.author || this.boardFlowCenterBook.narrator,
            imgWidth: this.boardFlowLayerW(), imgHeight: this.boardFlowLayerH(),
            useFixedHeight: true, imageFit: ImageFit.Cover, radius: 0,
            themedDecoration: true })
        }.width(this.boardFlowLayerW()).height(this.boardFlowLayerH())
        .borderRadius(RankingCardStyle.RADIUS)
        .clip(true)
        .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
          offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
        .position({ x: this.boardFlowLayerX(), y: this.boardFlowLayerY() })
        .zIndex(20)
      }
    }.width('100%').height('100%')
    .zIndex(60).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  @Builder
  private boardPage(board: RankingBoard) {
    HdsNavigation() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Refresh({ refreshing: $$this.refreshing, builder: this.emptyRefreshIndicator() }) {
          List({ scroller: this.boardScroller, space: BOARD_ROW_GAP }) {
            ListItem() { this.boardHeader(board) }.opacity(this.boardFlowTitle)
              .id(`rankingBoardHeader-${board.id}`).zIndex(1)
            if (board.books.length > 0) {
              ListItem() {
                RankingBoardPodium({ books: this.boardTopBooks(), boardId: board.id,
                  hiddenId: this.cardBookId,
                  coverAspect: this.boardCoverAspect(), topToken: this.boardTopToken,
                  flowMode: this.boardFlowPodiumMode,
                  flowProgress: this.boardFlowPodiumProgress,
                  flowDx: this.boardFlowPodiumDx, flowDy: this.boardFlowPodiumDy,
                  flowRelayWidths: this.boardFlowRelayWidths,
                  flowSpanMs: FLOW_PULL_SPAN_MS,
                  flowCardMs: FLOW_PULL_CARD_MS,
                  flowStaggerMs: FLOW_PULL_STAGGER_MS,
                  flowStartWindowX: this.boardFlowStartWindowX,
                  flowStartWindowY: this.boardFlowStartWindowY,
                  flowStartWindowW: this.boardFlowStartWindowW,
                  flowStartOffsetsX: this.boardFlowStartOffsetsX,
                  flowStartOffsetsY: this.boardFlowStartOffsetsY,
                  flowStartWidths: this.boardFlowStartWidths,
                  flowStartCentersX: this.boardFlowStartCentersX,
                  flowStartCentersY: this.boardFlowStartCentersY,
                  fanOpacity: this.boardFanVisible ? 1 : 0,
                  arrivalCards: this.boardDeckCards,
                  arrivalPrepareToken: this.boardPodiumPrepareToken,
                  arrivalPullToken: this.boardDeckPullToken,
                  arrivalCancelToken: this.boardDeckCancelToken,
                  arrivalCoverFade: this.boardDeckCover,
                  arrivalFlowToken: this.boardFlowToken,
                  onArrived: (token: number): void => this.finishBoardDeckPull(token),
                  onReturned: (token: number): void => {
                    if (!this.alive || token !== this.boardFlowToken) return;
                    this.boardPodiumPulling = false;
                    this.cancelCenterDealPage(token);
                  },
                  flowStartCovers: this.boardFlowStartCovers,
                  flowStartZ: this.boardFlowStartZ,
                  flowStartOrder: this.boardFlowStartOrder,
                  flowStartAngles: this.boardFlowStartAngles,
                  infoOpacity: this.boardFlowChrome,
                  coverBackToken: this.boardFlowCoverBackToken,
                  focusRankToken: this.boardFlowFocusToken,
                  focusRank: this.boardFlowCenterRank,
                  onFocusInfo: (book: RankingBook, index: number): void =>
                    this.onBoardFanFocusInfo(book, index),
                  onFanDragChange: (dragging: boolean): void => { this.fanDragging = dragging; },
                  onChoose: (book: RankingBook, nodeId: string): void =>
                    this.openBoardBook(book, nodeId) })
              }.id(`rankingBoardPodiumItem-${board.id}`).zIndex(10)
            }
            if (board.books.length > 0) {
              ListItem() { this.boardFocusCaption() }
                .id(`rankingBoardFocus-${board.id}`)
                .zIndex(5)
            }
            if (board.books.length > this.podiumBookCount(board)) {
              ListItem() { this.boardShelfHeader() }
                .padding({ left: BOARD_EDGE, right: BOARD_EDGE })
                .opacity(this.boardFlowGridBar)
                .translate({ y: (1 - this.boardFlowGridBar) * 8 })
                .id(`rankingBoardGridStart-${board.id}`)
                .zIndex(2)
            }
            LazyForEach(this.gridRowsData, (row: RankingBook[]) => {
              ListItem() { this.boardCardRow(row) }
                .opacity(this.boardFlowGridReveal)
                .zIndex(this.boardGridRowZ(row))
            }, (row: RankingBook[]): string => this.boardGridRowKey(row))
            ListItem() {
              Text($r('app.string.ranking_footer')).fontSize(11).fontColor(AppTheme.TextTertiary)
                .textAlign(TextAlign.Center).width('100%')
                .padding({ top: 30, bottom: this.contentBottomPadding(),
                  left: BOARD_EDGE, right: BOARD_EDGE })
            }.opacity(this.boardFlowChrome).zIndex(1)
          }.width('100%').height('100%').contentStartOffset(this.topSafe + RANKING_SEARCH_HEIGHT)
          .scrollBar(BarState.Off).cachedCount(2)
          .enableScrollInteraction(!this.fanDragging)
          .onDidScroll((offset: number, state: ScrollState): void => {
            this.onBoardListScroll(offset, state);
          })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }.width('100%').height('100%').onRefreshing(() => this.load(true))
        .onOffsetChange((offset: number): void => { this.boardRefreshPullOffset = Math.max(0, offset); })
        .refreshOffset(96).pullDownRatio(0.5)
        if (this.boardFabVisible) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_up_to_line')).fontSize(18)
              .fontColor([AppTheme.TextSecondary])
          }
          .width(36).height(36)
          .backgroundColor($r('app.color.glass_stroke'))
          .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
          .margin({ right: BOARD_EDGE, bottom: WindowUtils.getBottomSafeVp() + 24 })
          .onClick((): void => {
            try {
              this.boardScroller.scrollToIndex(0, true, ScrollAlign.START);
            } catch (_error) { /* 列表尚未挂载 */ }
          })
          .accessibilityText($r('app.string.ranking_back_top'))
        }
      }.width('100%').height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: { title: { mainTitle: '' }, backIcon: {
        icon: $r('sys.symbol.chevron_left'), action: (): void => this.closeBoard()
      } },
      style: { scrollEffectOpts: { scrollEffectType: HdsCompat.scrollEffect },
        originalStyle: {
          contentStyle: { backIconStyle: { iconColor: AppTheme.IconPrimary } }
        },
        scrollEffectStyle: {
          contentStyle: { backIconStyle: { iconColor: AppTheme.IconPrimary } }
        },
        thermoCtrl: true, systemMaterialEffect: HdsCompat.material }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(this.boardFlowActive && this.boardFlowChrome < 0.99)
    .mode(NavigationMode.Stack)
    .bindToScrollable([this.boardScroller])
    .systemBarStyle({ statusBarContentColor: this.statusBarContentColor },
      { statusBarContentColor: this.statusBarContentColor })
    .width('100%').height('100%').backgroundColor(Color.Transparent)
    .padding({ left: this.leftSafe, right: this.rightSafe })
    .opacity(this.boardFlowActive && !this.boardFanVisible ? 0 : 1)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (AppTheme.ShowCoverBackdrop && !this.customBackground) {
        Stack({ alignContent: Alignment.Top }) {
          RankingPosterBackground({ cover: this.posterCover, imageHeight: this.posterBackgroundHeight })
          Column().width('100%').height(this.posterBackgroundHeight)
            .linearGradient({ angle: 180, colors: [[Color.Transparent, 0.25], [HomeTheme.BgNeutral, 1]] })
        }.width('100%').height(this.posterBackgroundHeight)
          .translate({ y: -this.headerOffset }).clip(true).hitTestBehavior(HitTestMode.None)
          .opacity(this.homeChromeOpacity())
          .visibility(this.homeLayerVisibility())
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END])
          .accessibilityLevel('no')
      }
      HdsNavigation() {
        Refresh({ refreshing: $$this.refreshing, builder: this.emptyRefreshIndicator() }) {
          Scroll(this.headerScroller) {
            Column() { this.rankingNavigation() }
              .width('100%').height(this.contentHeight + this.headerRange).clip(false)
              .translate({ y: -this.refreshPullOffset })
          }.width('100%').height('100%').scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).clip(false)
            .onDidScroll((_x: number, y: number, state: ScrollState): void => {
              this.syncHeaderScroll(); this.onContentScroll(y, state);
            })
        }.onRefreshing(() => this.load(true)).width('100%').height('100%')
        .onOffsetChange((offset: number): void => { this.refreshPullOffset = Math.max(0, offset); })
        .refreshOffset(96).pullDownRatio(0.5)
        .pullToRefresh(this.headerOffset < 0.5)
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: this.searchTitleContent,
        style: {
          // 外层仅承载搜索，不创建会覆盖内层分类前景的模糊/材质层。
          scrollEffectOpts: { enableScrollEffect: false },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent,
              maskExtraHeight: 0 },
            contentStyle: { backIconStyle: { iconColor: AppTheme.IconPrimary } }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent,
              maskExtraHeight: 0 },
            contentStyle: { backIconStyle: { iconColor: AppTheme.IconPrimary } }
          },
          thermoCtrl: true
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true).mode(NavigationMode.Stack)
      .bindToScrollable([this.headerScroller]).backgroundColor(Color.Transparent)
      .dynamicHideTitleBar({
        hideTitleArea: true,
        hideBottomBuilder: true,
        hideStatusBar: false,
        mode: HideMode.SCROLL_UP_TO,
        hideRatio: 1.0
      })
      .padding({ left: this.leftSafe, right: this.rightSafe })
      .enabled(this.activeBoard === undefined)
      .visibility(this.homeLayerVisibility())
      .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 }).tag('page-type-swipe')
        .onActionEnd((event: GestureEvent): void => this.handlePlatformSwipe(event)))
      .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult =>
        info.tag === 'page-type-swipe' && GeneralSettings.current.swipeSwitchTabs ?
          GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE)
      .accessibilityLevel(this.activeBoard === undefined ? 'auto' : 'no-hide-descendants')
      .systemBarStyle({ statusBarContentColor: this.statusBarContentColor },
        { statusBarContentColor: this.statusBarContentColor })
      if (this.activeBoard !== undefined) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 背景独立淡入，抽牌封面不再跟整页透明度一起变亮。
          Column().width('100%').height('100%').backgroundColor(HomeTheme.BgNeutral)
            .opacity(this.boardFlowActive ? this.boardFlowReveal : 1)
          this.boardPage(this.activeBoard)
        }.width('100%').height('100%').opacity(this.boardPageFade)
      }
      if (this.boardFlowStackVisible && this.boardFlowCenterBook !== undefined) {
        this.boardFlowStackLayer()
      }
      if (this.boardDeckVisible) {
        this.boardDeckLayer()
      }
      if (this.currentRefreshPullOffset() > 0) {
        Column() { this.refreshIndicator(this.currentRefreshPullOffset()) }.width('100%')
          .position({ x: 0, y: this.topSafe + (this.activeBoard === undefined
            ? Math.max(0, this.headerRange - this.headerOffset) + 48 : RANKING_SEARCH_HEIGHT) })
          .hitTestBehavior(HitTestMode.None)
      }
      // 卡片不在这里渲染：它在 MainPage 根 Stack，底栏之上、Navigation 目的地之下。
      if (this.showBoardOrder) {
        this.boardOrderSheet()
      }
    }.width('100%').height('100%')
    .backgroundColor(this.boardFlowActive ? HomeTheme.BgNeutral :
      (!AppTheme.ShowCoverBackdrop || this.customBackground ? Color.Transparent : HomeTheme.BgNeutral))
    .enabled(!this.boardTransitioning)
    .id('rankingCardAnchor')
    .clip(true)
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const height: number = Number(size.height);
      if (Number.isFinite(height) && height > 0) this.contentHeight = height;
      this.menuViewportWidth = Math.max(1, Number(size.width));
      this.syncBoardColumns();
    })
  }
}
