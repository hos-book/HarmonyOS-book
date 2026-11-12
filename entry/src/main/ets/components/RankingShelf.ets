import { FrameCallback } from '@kit.ArkUI';
import { RankingBook } from '../model/Ranking';
import { CoverImage } from './CoverImage';
import { RankingCoverResolver } from '../service/ranking/RankingCoverResolver';
import { RankingCardStyle, RankingCardClip } from './RankingCardStyle';
import { AppCurve, AppMotion } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { PlayerDragTransition } from '../utils/PlayerDragTransition';

/** 卡片基准宽度 120；宽屏按实测宽度缓升到 168，避免平板上缩成一排小卡。 */
const CARD_BASE_W: number = 120;
const CARD_MAX_W: number = 168;
/** 宽屏断点：与项目 AdaptiveLayout.MEDIUM_WIDTH 一致。 */
const SHELF_WIDE_WIDTH: number = 600;
/** 整排卡片的左边距，与榜单标题左对齐。 */
const SHELF_LEFT_PAD: number = 24;
/** 窗口内额外渲染的卡片数，保证拖动时边缘不露空。 */
const WINDOW_EXTRA: number = 4;
/** 松手速度投影到目标位置的系数；不限制投影距离，完全由速度决定。 */
const FLING_PROJECTION: number = 0.22;
/** 松手速度取样窗口。 */
const VELOCITY_WINDOW_MS: number = 80;
/** 惯性逐卡动画：每张卡最短/最长停留，保证再快的甩动也能一张张过。 */
const STEP_MIN_MS: number = 60;
const STEP_MAX_MS: number = 300;
/** 惯性途中补水封面的最小间隔，避免每帧都扫整个窗口。 */
const HYDRATE_INTERVAL_MS: number = 80;
/** 查看榜单：卡片集底边停在底部导航栏上方，留出与卡片页一致的 12vp 间距。 */
const GATHER_BAR_GAP: number = 12;
/** 聚拢时同步缩小 30%，后续抽牌直接复用这份几何。 */
const GATHER_SHRINK_SCALE: number = 0.30;

/** 查看榜单转场：首页牌堆一张卡的最终视觉状态（货架局部坐标）。 */
export class RankingGatherCell {
  cx: number;
  cy: number;
  width: number;
  height: number;
  angle: number;
  z: number;
  cover: string;

  constructor(cx: number, cy: number, width: number, height: number, angle: number,
    z: number, cover: string) {
    this.cx = cx;
    this.cy = cy;
    this.width = width;
    this.height = height;
    this.angle = angle;
    this.z = z;
    this.cover = cover;
  }
}

class MoveSample {
  x: number;
  time: number;

  constructor(x: number, time: number) {
    this.x = x;
    this.time = time;
  }
}

/** 每帧回调：逐帧推进惯性位置，状态值始终等于屏幕位置，手指随时可以接管。 */
class RankingFlingFrame extends FrameCallback {
  private action: (timeInNano: number) => void;

  constructor(action: (timeInNano: number) => void) {
    super();
    this.action = action;
  }

  onFrame(timeInNano: number): void { this.action(timeInNano); }
}

/** 被点卡片在窗口中的位置与宽度（vp），供卡片做原位放大的起手参数。 */
export class CardOrigin {
  centerX: number = 0;
  centerY: number = 0;
  width: number = 0;
  height: number = 0;
  /** 被点卡片的唯一键（榜单 + 书），用于精确隐藏这一张。 */
  key: string = '';

  constructor(centerX: number, centerY: number, width: number, key: string = '', height: number = 0) {
    this.centerX = centerX;
    this.centerY = centerY;
    this.width = width;
    this.height = height;
    this.key = key;
  }
}

/**
 * 榜单横排卡片：虚拟无限循环，offset 不设边界，索引用取模。
 * 渲染按虚拟索引 v 而不是固定槽位，屏幕内卡片的内容不会在跨整数时被替换。
 * 松手用官方 interpolatingSpring 带速度抛到目标，再吸附到居中那张。
 */
@ComponentV2
export struct RankingShelf {
  @Require @Param books: RankingBook[] = [];
  /** 已被卡片接走的书 id，让位给原位放大，本机保留占位不绘制。 */
  @Param hiddenId: string = '';
  /** 打开查看榜单时，属于这个榜单的货架真实卡向中心聚拢。 */
  @Param gatherBoardId: string = '';
  @Param gatherProgress: number = 0;
  /** 聚拢完成后整组缩小的进度（0–1），底边保持在同一位置。 */
  @Param gatherShrink: number = 0;
  /** MainPage 实测的底栏占用高度；为 0 时退回 WindowUtils 的双排底栏算法。 */
  @Param bottomInset: number = 0;
  /** 页面实测的卡片集目标底边（window vp）；>0 时优先用它，不再自己算。 */
  @Param gatherBottomTarget: number = 0;
  /** 货架宿主的窗口顶边（打开转场瞬间实测），用来把卡片集底边对齐到底栏上方。 */
  @Param hostTop: number = 0;
  /** 递增后把当前五张牌堆的最终视觉状态交给页面，保证两侧牌堆完全一致。 */
  @Param gatherSnapshotToken: number = 0;
  @Event onGatherSnapshot: (cells: RankingGatherCell[]) => void = (_cells: RankingGatherCell[]): void => {};
  /** 所属榜单 id：同名的书可能出现在多个榜单里，卡片 id 必须带上它才唯一。 */
  @Param shelfKey: string = '';
  /** 父层点“回到 TOP1”时递增，货架用同一套惯性动画回到第一本。 */
  @Param scrollTopToken: number = 0;
  @Event onChoose: (book: RankingBook, origin: CardOrigin) => void = () => {};
  /** 中间那张变化时通知外层更新排名/书名标题。 */
  @Event onFocusChange: (book: RankingBook, index: number) => void = () => {};
  /** 连续虚拟偏移，可为负数/小数，不做 clamp。 */
  @Local bookOffset: number = 0;
  @Local shelfWidth: number = 360;
  /** 封面异步补全或换源后递增，驱动窗口内卡片重绘。 */
  @Local coverRevision: number = 0;

  private startX: number = 0;
  private startY: number = 0;
  private startOffset: number = 0;
  private dragging: boolean = false;
  private vertical: boolean = false;
  private lastSwipe: number = 0;
  private alive: boolean = true;
  private widthReady: boolean = false;
  private offsetReady: boolean = false;
  private lastFocusIndex: number = -1;
  private moveSamples: MoveSample[] = [];
  private coverPending: Set<string> = new Set<string>();
  private coverFailed: Set<string> = new Set<string>();
  private hydrating: Set<string> = new Set<string>();
  /** 惯性动画代次：手指接管或新一次松手都会作废旧动画链。 */
  private gestureToken: number = 0;
  private hydrateBase: number = -999999;
  private hydrateAt: number = 0;
  /** 惯性期间冻结渲染窗口：起点窗口与目标窗口的并集，动画途中不再挂载新节点。 */
  @Local freezeActive: boolean = false;
  @Local freezeBase: number = 0;
  @Local freezeCount: number = 0;
  /** 惯性动画的逐帧进度。 */
  private flingActive: boolean = false;
  private flingStartAt: number = -1;
  private flingFrom: number = 0;
  private flingTargets: number[] = [];
  private flingDurations: number[] = [];
  private flingTotal: number = 0;
  /** 打开查看榜单时的收拢锚点：当前居中那张卡，聚拢全程不动。 */
  private gatherAnchorVirtual: number = -999999;
  private gatherAnchorX: number = 0;
  private gatherAnchorY: number = 0;
  /** 货架宿主在窗口里的顶边：用来把卡片集底边对齐到底栏上方。 */
  private gatherHostTop: number = 0;
  private gatherHostMeasured: boolean = false;

  aboutToAppear(): void {
    this.hydrateVisible();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.flingActive = false;
    this.gestureToken++;
  }

  @Monitor('books')
  onBooksChange(): void {
    this.offsetReady = false;
    this.lastFocusIndex = -1;
    this.coverFailed.clear();
    this.hydrateBase = -999999;
    this.gestureToken++;
    this.flingActive = false;
    this.endFreeze();
    if (this.widthReady) this.initOffset();
  }

  @Monitor('scrollTopToken')
  onScrollTopToken(): void { this.returnToTop(); }

  @Monitor('gatherProgress')
  onGatherProgressChanged(): void {
    if (this.gatherProgress <= 0) {
      this.gatherAnchorVirtual = -999999;
      this.gatherHostMeasured = false;
    }
  }

  @Monitor('gatherBoardId')
  onGatherBoardChanged(): void {
    this.gatherAnchorVirtual = -999999;
    this.gatherHostMeasured = false;
  }

  @Monitor('gatherSnapshotToken')
  onGatherSnapshotToken(): void {
    this.emitGatherSnapshot();
  }

  /** 输出五张牌堆卡此刻的视觉中心/宽度/角度/层级/封面，页面直接用它做榜单牌堆起点。 */
  private emitGatherSnapshot(): void {
    if (this.gatherBoardId.length === 0 || this.gatherBoardId !== this.shelfKey) return;
    if (this.gatherProgress <= 0) return;
    this.ensureGatherAnchor();
    if (this.gatherAnchorVirtual === -999999) return;
    const cells: RankingGatherCell[] = [];
    for (let distance: number = -2; distance <= 2; distance++) {
      const virtualIndex: number = this.gatherAnchorVirtual + distance;
      const book: RankingBook = this.bookAt(virtualIndex);
      const scale: number = this.scaleOf(this.focusAt(virtualIndex)) *
        this.gatherShrinkFactor(virtualIndex);
      const cx: number = this.xOfVirtual(virtualIndex) + this.cardW() / 2 +
        this.gatherDx(virtualIndex);
      // scale 与 rotate 共用中心锚点；记录真实中心，不再按底边锚点补一次缩放差。
      const cy: number = this.yOf(this.focusAt(virtualIndex)) + this.cardH() / 2 +
        this.gatherDy(virtualIndex);
      cells.push(new RankingGatherCell(cx, cy, this.cardW() * scale, this.cardH() * scale,
        this.gatherAngle(virtualIndex), 5 - Math.abs(distance), book.coverUrl));
    }
    this.onGatherSnapshot(cells);
  }

  /** 以第一张卡居中作为初始位置；之后靠取模实现首尾相接。 */
  private initOffset(): void {
    if (this.books.length === 0) return;
    this.flingActive = false;
    this.endFreeze();
    this.bookOffset = -this.focusShift();
    this.offsetReady = true;
    this.lastFocusIndex = -1;
    this.hydrateBase = -999999;
    this.emitFocus(0);
    this.hydrateVisible();
  }

  /** 卡片宽度随货架实测宽度缓升；手机 120，平板约 158–168。 */
  private cardW(): number {
    const width: number = this.shelfWidth > 0 ? this.shelfWidth : 360;
    const grown: number = CARD_BASE_W + Math.max(0, width - 360) * 0.08;
    return Math.round(Math.max(CARD_BASE_W, Math.min(CARD_MAX_W, grown)));
  }

  private cardH(): number {
    return this.cardW() / RankingCardStyle.COVER_ASPECT;
  }

  /** 宽屏中心卡再抬高、放大一点，但不超过底边留白。 */
  private centerScale(): number {
    return this.shelfWidth >= SHELF_WIDE_WIDTH ? 1.16 : 1.12;
  }

  private centerLift(): number {
    return this.shelfWidth >= SHELF_WIDE_WIDTH ? 24 : 20;
  }

  /** 基线保证放大后的中心卡顶部仍有约 4vp 余量；底部留 20vp。 */
  private shelfBaseline(): number {
    return 4 + this.cardH() * this.centerScale() + this.centerLift();
  }

  private shelfHeight(): number {
    return this.shelfBaseline() + 20;
  }

  /** 卡片比书脊宽，间距略大一些，仍保留明显交叠；宽屏不再卡在 108。 */
  private step(): number {
    return Math.max(64, Math.min(this.cardW() * 0.78, this.shelfWidth / 4.2));
  }

  /** 一屏能完整站下的卡片数量。 */
  private visibleCount(): number {
    const span: number = this.shelfWidth - SHELF_LEFT_PAD * 2;
    return Math.max(1, Math.floor(span / this.step()));
  }

  /** 实际渲染的卡片数：窗口内多留几张，书少时不超过总数。 */
  private slotCount(): number {
    return Math.min(this.books.length, this.visibleCount() + WINDOW_EXTRA);
  }

  /** offset 增加多少时，某张卡正好位于书架中心。 */
  private focusShift(): number {
    return (this.shelfWidth / 2 - SHELF_LEFT_PAD - this.cardW() / 2) / this.step();
  }

  private modIndex(virtualIndex: number): number {
    const count: number = this.books.length;
    if (count === 0) return 0;
    return ((virtualIndex % count) + count) % count;
  }

  /** 当前居中的虚拟索引（四舍五入到最近一张）。 */
  private focusVirtual(): number {
    return Math.round(this.bookOffset + this.focusShift());
  }

  private emitFocus(virtualIndex?: number): void {
    if (this.books.length === 0) return;
    const target: number = virtualIndex !== undefined ? virtualIndex : this.focusVirtual();
    const index: number = this.modIndex(target);
    if (index === this.lastFocusIndex) return;
    this.lastFocusIndex = index;
    this.onFocusChange(this.books[index], index);
  }

  /** offset 每帧变化（拖动或惯性动画）都实时更新焦点标题，并按窗口推进补水封面。 */
  @Monitor('bookOffset')
  private onOffsetChanged(): void {
    if (!this.offsetReady) return;
    this.emitFocus();
    this.hydrateAlong();
  }

  private baseVirtual(): number { return Math.floor(this.bookOffset) - 2; }

  /** 渲染窗口起点：惯性期间用冻结起点，避免动画途中因跨整数重新挂卡。 */
  private windowBase(): number {
    return this.freezeActive ? this.freezeBase : this.baseVirtual();
  }

  private windowCount(): number {
    return this.freezeActive ? this.freezeCount : this.slotCount();
  }

  /** 按虚拟索引渲染：可见卡的 key 不随跨整数变化，避免内容被瞬间替换。 */
  private virtualSlots(): number[] {
    // 读一下封面版本，注册依赖：封面换源后整窗重绘。
    const revision: number = this.coverRevision;
    const base: number = this.windowBase();
    const count: number = this.windowCount();
    const values: number[] = [];
    for (let slot = 0; slot < count; slot++) values.push(base + slot);
    if (revision < 0) values.length = 0;
    return values;
  }

  private bookAt(virtualIndex: number): RankingBook {
    const book: RankingBook | undefined = this.books[this.modIndex(virtualIndex)];
    return book !== undefined ? book : new RankingBook();
  }

  private focusAt(virtualIndex: number): number {
    return this.focusOfVirtual(this.xOfVirtual(virtualIndex) + this.cardW() / 2);
  }

  private orderOf(virtualIndex: number): number {
    return virtualIndex - this.windowBase();
  }

  /** 补一本书的封面；同一本书只允许一个解析请求在飞。 */
  private hydrateBook(book: RankingBook): void {
    if (book.coverUrl.length > 0 || this.hydrating.has(book.id)) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.hydrating.add(book.id);
    const before: string = book.coverUrl;
    RankingCoverResolver.resolve(context, book, false).then((cover: string): void => {
      this.hydrating.delete(book.id);
      if (this.alive && cover.length > 0 && book.coverUrl !== before) this.coverRevision++;
    }).catch((): void => {
      this.hydrating.delete(book.id);
    });
  }

  /** 只补窗口内的封面，滑到哪补到哪；空封面走平台无关兜底。 */
  private hydrateVisible(): void {
    if (this.books.length === 0) return;
    const base: number = this.baseVirtual();
    const count: number = this.slotCount();
    for (let slot = 0; slot < count; slot++) this.hydrateBook(this.books[this.modIndex(base + slot)]);
  }

  /** 惯性途中按窗口推进补水，节流到 80ms 一次；停稳后仍会再补一遍兜底。 */
  private hydrateAlong(): void {
    const base: number = this.baseVirtual();
    if (base === this.hydrateBase) return;
    const now: number = Date.now();
    if (this.hydrateBase !== -999999 && now - this.hydrateAt < HYDRATE_INTERVAL_MS) return;
    this.hydrateBase = base;
    this.hydrateAt = now;
    this.hydrateVisible();
  }

  /** 动画开始前先把目标窗口的封面排上队，避免停稳后中间还是 App logo。 */
  private prefetchTarget(targetOffset: number): void {
    if (this.books.length === 0) return;
    const base: number = Math.floor(targetOffset) - 2;
    const count: number = this.slotCount();
    for (let slot = 0; slot < count; slot++) this.hydrateBook(this.books[this.modIndex(base + slot)]);
  }

  /**
   * 冻结渲染窗口为"起点窗口 ∪ 目标窗口"。动画期间 offset 只在关键帧事件里跳到目标值，
   * 若此时窗口跟着跨整数，新挂载的卡会直接落在目标位置、脱离当前这段插值，表现为卡片提前入镜或叠在一起。
   * 一次性把整段路径上的卡都挂好，就能让每张卡都从头参与动画。
   */
  private beginFreeze(start: number, target: number): void {
    if (this.books.length === 0) return;
    const count: number = this.slotCount();
    const startBase: number = Math.floor(start) - 2;
    const targetBase: number = Math.floor(target) - 2;
    const low: number = Math.min(startBase, targetBase);
    const high: number = Math.max(startBase + count, targetBase + count);
    this.freezeBase = low;
    // 书很少时窗口可能比书总数还长，仍按虚拟索引渲染，避免长甩到后半段窗口是空的。
    this.freezeCount = Math.max(1, high - low);
    this.freezeActive = true;
  }

  private endFreeze(): void {
    if (this.freezeActive) this.freezeActive = false;
  }

  /** 图片加载失败：强制换源一次；仍失败就让 CardImage 继续显示 App logo。 */
  private refreshCover(book: RankingBook): void {
    if (this.coverPending.has(book.id) || this.coverFailed.has(book.id)) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.coverPending.add(book.id);
    RankingCoverResolver.resolve(context, book, true).then((cover: string): void => {
      this.coverPending.delete(book.id);
      if (!this.alive) return;
      if (cover.length === 0) {
        this.coverFailed.add(book.id);
        return;
      }
      if (book.coverUrl !== cover) {
        book.coverUrl = cover;
        this.coverRevision++;
      } else {
        this.coverFailed.add(book.id);
      }
    }).catch((): void => {
      this.coverPending.delete(book.id);
      this.coverFailed.add(book.id);
    });
  }

  /** 卡片中心相对容器中心的偏移，-1 为最左，1 为最右。 */
  private focusOfVirtual(centerX: number): number {
    const center: number = this.shelfWidth / 2;
    return Math.max(-1, Math.min(1, (centerX - center) / center));
  }

  /** 中央卡片最大，越靠两侧越小；中心档位随宽屏再抬高一点。 */
  private scaleOf(focus: number): number {
    const center: number = this.centerScale();
    const falloff: number = center >= 1.16 ? 0.26 : 0.25;
    return Math.max(0.84, center - Math.abs(focus) * falloff);
  }

  /** 经过屏幕中央的卡片抬起，幅度随设备断点变化。 */
  private liftOf(focus: number): number {
    return -this.centerLift() * Math.max(0, 1 - Math.abs(focus) * 1.4);
  }

  /** 两侧卡片略压暗，把视觉重心留给中央。 */
  private opacityOf(focus: number): number { return Math.max(0.72, 1 - Math.abs(focus) * 0.2); }

  private xOfVirtual(virtualIndex: number): number {
    return SHELF_LEFT_PAD + (virtualIndex - this.bookOffset) * this.step();
  }

  private yOf(focus: number): number {
    return this.shelfBaseline() - this.cardH() + this.liftOf(focus);
  }

  /** 卡片唯一 id：榜单 + 槽位 + 书 id。冻结窗口可能重复渲染同一本书，冻结期间必须带虚拟索引。 */
  private cardId(book: RankingBook, virtualIndex: number): string {
    const slot: number = this.freezeActive ? virtualIndex : this.modIndex(virtualIndex);
    return `rankingCard-${this.shelfKey}-${slot}-${book.id}`;
  }

  private cardIdAt(virtualIndex: number): string { return this.cardId(this.bookAt(virtualIndex), virtualIndex); }

  /** 读取被点卡片在窗口中的真实位置，作为卡片原位放大的起点。 */
  private originOf(book: RankingBook, virtualIndex: number): CardOrigin {
    const key: string = this.cardId(book, virtualIndex);
    try {
      const rect = PlayerDragTransition.measure(this.getUIContext(), key);
      if (!rect.isValid()) throw new Error('rect unavailable');
      return new CardOrigin(WindowUtils.pxToVp(rect.leftPx + rect.widthPx / 2),
        WindowUtils.pxToVp(rect.topPx + rect.heightPx / 2), WindowUtils.pxToVp(rect.widthPx), key,
        WindowUtils.pxToVp(rect.heightPx));
    } catch (_error) {
      // 拿不到布局信息时退化为从书架中线放大，不影响交互。
      return new CardOrigin(this.shelfWidth / 2, 0, this.cardW(), key);
    }
  }

  /**
   * 松手：按最后 80ms 的速度算出总投影距离，再拆成"一张卡一段"的关键帧动画。
   * 每段时长按匀减速物理模型分配（越到后面越慢），所以再快的甩动也是逐张经过中心；
   * 动画期间冻结渲染窗口，并用帧回调跟踪屏幕真实偏移，供手指中途接管。
   */
  private settle(velocityX: number = 0): void {
    const shift: number = this.focusShift();
    const step: number = this.step();
    const cardsPerSecond: number = -velocityX / step;
    const projected: number = this.bookOffset + cardsPerSecond * FLING_PROJECTION;
    const target: number = Math.round(projected + shift) - shift;
    const start: number = this.bookOffset;
    const distance: number = target - start;
    const count: number = Math.round(Math.abs(distance));
    const token: number = ++this.gestureToken;
    this.flingActive = false;
    if (count === 0) {
      this.beginFreeze(start, target);
      this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Decelerate,
        onFinish: (): void => {
          if (!this.alive || token !== this.gestureToken) return;
          this.endFreeze();
          this.hydrateVisible();
        } }, (): void => {
        if (this.alive && token === this.gestureToken) this.bookOffset = target;
      });
      return;
    }
    // 逐帧状态就是当前可见位置，只保留当前窗口，避免长甩一次挂载整条路径。
    this.endFreeze();
    this.prefetchTarget(target);
    const speed: number = Math.abs(cardsPerSecond);
    const targets: number[] = [];
    const durations: number[] = [];
    let total: number = 0;
    for (let index = 0; index < count; index++) {
      targets.push(start + distance * (index + 1) / count);
      const duration: number = this.stepDuration(speed, count, index);
      durations.push(duration);
      total += duration;
    }
    this.flingFrom = start;
    this.flingTargets = targets;
    this.flingDurations = durations;
    this.flingTotal = total;
    this.flingStartAt = -1;
    this.flingActive = true;
    this.postFlingFrame(token);
  }

  /** 回到当前榜单 TOP1：选最近的 0 号虚拟位，用与甩动相同的逐帧动画走过去。 */
  private returnToTop(): void {
    if (!this.offsetReady || this.books.length === 0) return;
    const total: number = this.books.length;
    const shift: number = this.focusShift();
    const current: number = Math.round(this.bookOffset + shift);
    const remainder: number = ((current % total) + total) % total;
    let delta: number = -remainder;
    // 首尾相接，取更短的方向；例如 98/100 往右 2 张到 1，比往左 98 张自然。
    if (delta < -total / 2) delta += total;
    if (delta === 0) return;
    const target: number = (current + delta) - shift;
    const start: number = this.bookOffset;
    const distance: number = target - start;
    const steps: number = Math.max(1, Math.round(Math.abs(distance)));
    const token: number = ++this.gestureToken;
    this.flingActive = false;
    this.endFreeze();
    this.prefetchTarget(target);
    const targets: number[] = [];
    const durations: number[] = [];
    let durationSum: number = 0;
    for (let index = 0; index < steps; index++) {
      targets.push(start + distance * (index + 1) / steps);
      // 回顶节奏：中段快速逐张掠过，只留最后两张减速收尾。
      const duration: number = this.returnStepDuration(steps, index);
      durations.push(duration);
      durationSum += duration;
    }
    this.flingFrom = start;
    this.flingTargets = targets;
    this.flingDurations = durations;
    this.flingTotal = durationSum;
    this.flingStartAt = -1;
    this.flingActive = true;
    this.postFlingFrame(token);
  }

  /** 回顶专用节奏：全程匀速偏快，最后两张单独减速，避免每张都拖到 300ms。 */
  private returnStepDuration(count: number, index: number): number {
    const left: number = count - index;
    if (left <= 1) return 220;
    if (left === 2) return 120;
    return count >= 16 ? 48 : 54;
  }

  /** 匀减速模型：第 index 张卡的耗时 = 1 / 该段平均速度，并夹在可感知的上下限内。 */
  private stepDuration(speed: number, count: number, index: number): number {
    const v0: number = Math.max(0.35, speed);
    const from: number = v0 * (1 - index / count);
    const to: number = v0 * (1 - (index + 1) / count);
    const average: number = Math.max(0.08, (from + to) / 2);
    return Math.max(STEP_MIN_MS, Math.min(STEP_MAX_MS, 1000 / average));
  }

  /**
   * 逐帧推进惯性：每帧直接写 bookOffset，状态值就是屏幕位置。
   * 这样新挂载的卡永远拿到当前真实位置，接管时也不需要把状态从"关键帧终点"拉回来。
   */
  private postFlingFrame(token: number): void {
    this.getUIContext().postFrameCallback(new RankingFlingFrame((timeInNano: number): void => {
      if (!this.alive || token !== this.gestureToken || !this.flingActive) return;
      const now: number = timeInNano / 1000000;
      if (this.flingStartAt < 0) {
        // 第一帧只记起点，从下一帧开始推进，避免首帧就产生位移。
        this.flingStartAt = now;
        this.postFlingFrame(token);
        return;
      }
      const elapsed: number = now - this.flingStartAt;
      if (elapsed >= this.flingTotal) {
        const last: number = this.flingTargets.length - 1;
        if (last >= 0) this.bookOffset = this.flingTargets[last];
        this.flingActive = false;
        this.endFreeze();
        this.hydrateVisible();
        return;
      }
      this.bookOffset = this.offsetAt(elapsed);
      this.postFlingFrame(token);
    }));
  }

  private offsetAt(elapsed: number): number {
    let remaining: number = elapsed;
    let from: number = this.flingFrom;
    for (let index = 0; index < this.flingDurations.length; index++) {
      const duration: number = this.flingDurations[index];
      if (remaining < duration) {
        const progress: number = duration > 0 ? remaining / duration : 1;
        return from + (this.flingTargets[index] - from) * progress;
      }
      remaining -= duration;
      from = this.flingTargets[index];
    }
    return this.flingTargets.length > 0 ? this.flingTargets[this.flingTargets.length - 1] : from;
  }

  /** 手指接管惯性：逐帧推进时状态已经是屏幕位置，停掉后续帧即可无缝接住。 */
  private takeOverFling(): number {
    const visual: number = this.bookOffset;
    this.flingActive = false;
    this.gestureToken++;
    this.endFreeze();
    return visual;
  }

  private handleTouch(event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (point === undefined) return;
      this.dragging = false;
      this.vertical = false;
      this.startX = point.windowX;
      this.startY = point.windowY;
      this.startOffset = this.bookOffset;
      this.moveSamples = [new MoveSample(point.windowX, Date.now())];
      return;
    }
    if (event.type === TouchType.Move && point !== undefined) {
      const dx: number = point.windowX - this.startX;
      const dy: number = point.windowY - this.startY;
      if (!this.vertical && Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) this.vertical = true;
      if (this.vertical) return;
      if (Math.abs(dx) > 6) {
        const now: number = Date.now();
        this.moveSamples.push(new MoveSample(point.windowX, now));
        while (this.moveSamples.length > 2 && now - this.moveSamples[0].time > VELOCITY_WINDOW_MS) {
          this.moveSamples.shift();
        }
        // 第一次真正拖动时接管正在跑的惯性：先对齐到屏幕真实位置，再交给手指。
        if (!this.dragging) {
          this.dragging = true;
          const visual: number = this.takeOverFling();
          // 以接管瞬间为新的起点，避免惯性已经跑掉的位移被算进手指位移。
          this.startX = point.windowX;
          this.startOffset = visual;
          this.moveSamples = [new MoveSample(point.windowX, now)];
        }
        this.bookOffset = this.startOffset - (point.windowX - this.startX) / this.step();
      }
      return;
    }
    if (event.type !== TouchType.Up && event.type !== TouchType.Cancel) return;
    if (this.dragging) {
      this.settle(this.releaseVelocity());
      this.lastSwipe = Date.now();
    }
    this.dragging = false;
  }

  /** 松手速度：只看最后 80ms 的位移/时间。 */
  private releaseVelocity(): number {
    if (this.moveSamples.length < 2) return 0;
    const first: MoveSample = this.moveSamples[0];
    const last: MoveSample = this.moveSamples[this.moveSamples.length - 1];
    const dt: number = last.time - first.time;
    return dt > 0 ? (last.x - first.x) / dt * 1000 : 0;
  }

  /** 打开查看榜单时，只有锚点中心卡和左右各两张参与收拢。 */
  private ensureGatherAnchor(): void {
    if (this.gatherProgress <= 0) {
      this.gatherAnchorVirtual = -999999;
      return;
    }
    if (this.gatherAnchorVirtual !== -999999) return;
    const anchor: number = this.focusVirtual();
    const focus: number = this.focusAt(anchor);
    this.gatherAnchorVirtual = anchor;
    this.gatherAnchorX = this.xOfVirtual(anchor) + this.cardW() / 2;
    // 卡片以底边为缩放锚点，收拢对齐的是缩放后的视觉中心。
    this.gatherAnchorY = this.yOf(focus) + this.cardH() - this.cardH() * this.scaleOf(focus) / 2;
    this.measureGatherHost();
  }

  /** 货架宿主的窗口顶边：卡片集底边要落在底栏上方的固定线。 */
  private measureGatherHost(): void {
    if (this.gatherHostMeasured) return;
    // 页面已经量过宿主顶边（可能是负数，货架上半部分滚出窗口），直接用它的值。
    if (this.hostTop !== 0) {
      this.gatherHostTop = this.hostTop;
      this.gatherHostMeasured = true;
      return;
    }
    try {
      const host = this.getUIContext().getComponentUtils()
        .getRectangleById(`rankingShelfHost-${this.shelfKey}`);
      const top: number = px2vp(host.windowOffset.y);
      if (Number.isFinite(top)) {
        this.gatherHostTop = top;
        this.gatherHostMeasured = true;
      }
    } catch (_error) { /* 量不到时用 0 兜底，仍按窗口高度算目标 */ }
  }

  /** 卡片集五张卡里最低的那条视觉底边（局部坐标，未加移动量）。 */
  private gatherLowestBottom(): number {
    let lowest: number = -999999;
    for (let distance: number = -2; distance <= 2; distance++) {
      const focus: number = this.focusAt(this.gatherAnchorVirtual + distance);
      const bottom: number = this.gatherAnchorY + this.gatherOffsetY(distance) +
        this.cardH() * this.scaleOf(focus) / 2;
      lowest = Math.max(lowest, bottom);
    }
    return lowest;
  }

  private gatherTargetBottom(): number {
    if (this.gatherBottomTarget > 0) return this.gatherBottomTarget;
    const bar: number = this.bottomInset > 0 ? this.bottomInset :
      WindowUtils.getFloatingTabBottomVp();
    return WindowUtils.getWindowHeightVp() - bar - GATHER_BAR_GAP;
  }

  private gatherDistance(virtualIndex: number): number {
    this.ensureGatherAnchor();
    return this.gatherAnchorVirtual === -999999 ? 99 : virtualIndex - this.gatherAnchorVirtual;
  }

  private gatherAmount(virtualIndex: number): number {
    if (this.gatherBoardId.length === 0 || this.gatherBoardId !== this.shelfKey) return 0;
    if (this.gatherProgress <= 0) return 0;
    if (Math.abs(this.gatherDistance(virtualIndex)) > 2) return 0;
    return Math.max(0, Math.min(1, this.gatherProgress));
  }

  /** 错位量按卡片实际尺寸取比例，手机/平板/横屏都保持同样的视觉交错。 */
  private gatherOffsetX(distance: number): number {
    const width: number = this.cardW();
    if (distance === -2) return -width * 0.38;
    if (distance === -1) return -width * 0.15;
    if (distance === 1) return width * 0.22;
    if (distance === 2) return width * 0.33;
    return 0;
  }

  private gatherOffsetY(distance: number): number {
    const height: number = this.cardH();
    if (distance === -2) return height * 0.17;
    if (distance === -1) return height * 0.05;
    if (distance === 1) return height * 0.11;
    if (distance === 2) return height * 0.04;
    return 0;
  }

  private gatherDx(virtualIndex: number): number {
    const amount: number = this.gatherAmount(virtualIndex);
    if (amount === 0) return 0;
    const distance: number = this.gatherDistance(virtualIndex);
    if (distance === 0) return 0;
    // 整组缩小时侧卡也向中心收，保持卡片集的整体形状，而不是只把单卡变小。
    const shrink: number = this.gatherShrinkFactor(virtualIndex);
    const targetX: number = this.gatherAnchorX + this.gatherOffsetX(distance) * shrink;
    const cardCenterX: number = this.xOfVirtual(virtualIndex) + this.cardW() / 2;
    return (targetX - cardCenterX) * amount;
  }

  private gatherDy(virtualIndex: number): number {
    const amount: number = this.gatherAmount(virtualIndex);
    if (amount === 0) return 0;
    const distance: number = this.gatherDistance(virtualIndex);
    const focus: number = this.focusAt(virtualIndex);
    const shrink: number = this.gatherShrinkFactor(virtualIndex);
    const lowest: number = this.gatherLowestBottom();
    // 聚拢和“移动到底栏上方”同时发生：中心卡也一起走，不再固定在原位。
    const lift: number = this.gatherTargetBottom() - this.gatherHostTop - lowest;
    // 整组绕卡片集底边中点缩放：底边留在底栏上方，侧卡的错位和尺寸一起收。
    const pivot: number = lowest + lift;
    const targetCenter: number = this.gatherAnchorY + this.gatherOffsetY(distance) + lift;
    const shrunkCenter: number = pivot + (targetCenter - pivot) * shrink;
    const scale: number = this.scaleOf(focus) * shrink;
    const visualCenterY: number = this.yOf(focus) + this.cardH() - this.cardH() * scale / 2;
    return (shrunkCenter - visualCenterY) * amount;
  }

  /** 聚拢完成后整组再缩一点；缩放锚点是卡片集底边中点。 */
  private gatherShrinkAmount(virtualIndex: number): number {
    if (this.gatherAmount(virtualIndex) <= 0) return 0;
    return Math.max(0, Math.min(1, this.gatherShrink));
  }

  private gatherShrinkFactor(virtualIndex: number): number {
    return 1 - GATHER_SHRINK_SCALE * this.gatherShrinkAmount(virtualIndex);
  }

  /** 侧卡滑入时带一点 3D 角度，落位回正；中心卡始终 0°。 */
  private gatherAngle(virtualIndex: number): number {
    const amount: number = this.gatherAmount(virtualIndex);
    if (amount === 0) return 0;
    const distance: number = this.gatherDistance(virtualIndex);
    if (distance === 0) return 0;
    const direction: number = distance < 0 ? 1 : -1;
    const abs: number = Math.abs(distance);
    const peak: number = abs === 1 ? 8 : 14;
    const residual: number = abs === 1 ? 2 : 4;
    return direction * (residual * amount + peak * Math.sin(Math.PI * amount));
  }

  private gatherOpacity(virtualIndex: number, base: number): number {
    if (this.gatherProgress <= 0) return base;
    const amount: number = Math.max(0, Math.min(1, this.gatherProgress));
    if (Math.abs(this.gatherDistance(virtualIndex)) <= 2) {
      // 聚拢过程中两侧卡逐渐提到全亮，和榜单卡接力时不会突然变色。
      return base + (1 - base) * amount;
    }
    return base * (1 - amount);
  }

  @Builder
  private bookItem(virtualIndex: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      CoverImage({ url: this.bookAt(virtualIndex).coverUrl, title: this.bookAt(virtualIndex).title,
        author: this.bookAt(virtualIndex).author, imgWidth: this.cardW(),
        aspectRatioValue: RankingCardStyle.COVER_ASPECT, useOriginalRatio: false, radius: 0,
        imageFit: ImageFit.Cover, themedDecoration: true, compositeEdges: true,
        onLoadError: (): void => { this.refreshCover(this.bookAt(virtualIndex)); } })
        .width(this.cardW()).height(this.cardH())
    }
    .width(this.cardW()).height(this.cardH())
    .attributeModifier(new RankingCardClip())
    // 大半径柔和投影，交叠处形成清晰的层次。
    .shadow({ radius: RankingCardStyle.SHADOW_RADIUS, color: RankingCardStyle.SHADOW_COLOR,
      offsetY: RankingCardStyle.SHADOW_OFFSET_Y })
    .position({ x: 0, y: 0 })
    .translate({ x: this.xOfVirtual(virtualIndex) + this.gatherDx(virtualIndex),
      y: this.yOf(this.focusAt(virtualIndex)) + this.gatherDy(virtualIndex) })
    .zIndex(this.gatherAmount(virtualIndex) > 0 ?
      2000 + (5 - Math.abs(this.gatherDistance(virtualIndex))) :
      1000 + this.orderOf(virtualIndex))
    .id(this.cardIdAt(virtualIndex))
    .opacity(this.cardIdAt(virtualIndex) === this.hiddenId ? 0 :
      this.gatherOpacity(virtualIndex, this.opacityOf(this.focusAt(virtualIndex))))
    .scale({ x: this.scaleOf(this.focusAt(virtualIndex)) * this.gatherShrinkFactor(virtualIndex),
      y: this.scaleOf(this.focusAt(virtualIndex)) * this.gatherShrinkFactor(virtualIndex),
      centerX: '50%', centerY: '50%' })
    .rotate({ x: 0, y: 1, z: 0, angle: this.gatherAngle(virtualIndex),
      centerX: '50%', centerY: '50%', perspective: 900 })
    .onClick((): void => {
      // 刚拖动完不触发打开，避免横滑结束误点。
      if (Date.now() - this.lastSwipe < 300) return;
      const book: RankingBook = this.bookAt(virtualIndex);
      this.onChoose(book, this.originOf(book, virtualIndex));
    })
    .accessibilityGroup(true).accessibilityText(this.bookAt(virtualIndex).title)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.virtualSlots(), (virtualIndex: number) => {
        this.bookItem(virtualIndex)
      }, (virtualIndex: number): string => 'v-' + virtualIndex)
    }
    .width('100%').height(this.shelfHeight())
    // 聚拢时整组会移到货架上方，不能按货架高度裁切；静止时仍保持裁切。
    .clip(this.gatherProgress <= 0)
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const width: number = Number(size.width);
      if (!Number.isFinite(width) || width <= 0) return;
      const changed: boolean = Math.abs(width - this.shelfWidth) > 0.5;
      const oldFocus: number = Math.round(this.bookOffset + this.focusShift());
      this.shelfWidth = width;
      if (!this.widthReady) {
        this.widthReady = true;
        this.initOffset();
      } else if (changed || !this.offsetReady) {
        if (!this.offsetReady) {
          this.initOffset();
        } else {
          // 卡片宽度/步距变了，把同一本书重新对回中心，避免旋转后焦点漂走。
          this.bookOffset = oldFocus - this.focusShift();
          this.emitFocus(oldFocus);
        }
      }
    })
    .onTouch((event: TouchEvent): void => this.handleTouch(event))
    // 横滑交给书架，阻止外层切页手势同时响应。
    .onTouchTestDone((_event: BaseGestureEvent, recognizers: GestureRecognizer[]): void => {
      for (const recognizer of recognizers) {
        if (recognizer instanceof PanRecognizer && recognizer.getDirection() === PanDirection.Horizontal) {
          recognizer.preventBegin();
        }
      }
    })
  }
}
