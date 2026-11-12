import { RankingBook } from '../model/Ranking';
import { CardOrigin } from '../components/RankingShelf';
import { RankingMatch } from '../service/ranking/BookMatchService';
import { Book } from '../model/Book';
import { ReadingSession, SessionLocation } from '../service/ReadingSessionService';

/** 卡片事件回调：RankingHomePage 打开卡片时写入，MainPage 渲染卡片时调用。 */
export class RankingCardActions {
  prepareMatch: (match: RankingMatch) => Promise<void> = async (): Promise<void> => {};
  openReader: (book: Book, onReturn: () => void, resourceIndex?: number) => void = () => {};
  openHistory: (book: Book) => void = () => {};
  historyJump: (session: ReadingSession, location: SessionLocation) => void = () => {};
  manageSources: () => void = () => {};
  exit: () => void = () => {};
  restoreSource: () => void = () => {};
}

/**
 * 卡片状态从 RankingHomePage 提升到 MainPage：
 * 卡片渲染在 MainPage 根 Stack（HdsTabs 之后），在底栏之上，但在 Navigation 目的地之下。
 * 阅读器推入时盖住卡片、卡片保持挂载；返回后详情态原样露出。
 */
@ObservedV2
export class RankingCardStore {
  /** 只有显隐需要驱动 MainPage 重绘；其余字段在 visible 置 true 前写好。 */
  @Trace visible: boolean = false;
  @Trace refreshToken: number = 0;
  /** 相对宿主的顶部边界，随搜索栏/吸顶分类和安全区更新。 */
  @Trace topBoundary: number = 0;
  hostTop: number = 0;
  book: RankingBook = new RankingBook();
  platform: Resource = $r('app.string.ranking_home');
  origin: CardOrigin = new CardOrigin(0, 0, 88);
  baseCx: number = 0;
  baseCy: number = 0;
  actions: RankingCardActions = new RankingCardActions();

  open(book: RankingBook, platform: Resource, origin: CardOrigin, baseCx: number, baseCy: number,
    actions: RankingCardActions): void {
    this.book = book;
    this.platform = platform;
    this.origin = origin;
    this.baseCx = baseCx;
    this.baseCy = baseCy;
    this.actions = actions;
    this.visible = true;
  }

  close(): void {
    this.visible = false;
    this.topBoundary = 0;
    this.actions = new RankingCardActions();
  }
}

export const rankingCardStore: RankingCardStore = new RankingCardStore();
