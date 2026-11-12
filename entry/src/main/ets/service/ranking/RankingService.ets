import { common } from '@kit.AbilityKit';
import { RankingBoard, RankingPlatform } from '../../model/Ranking';
import { HttpClient } from '../http/HttpClient';
import { JsonObj } from '../builtin/JsonValue';
import { RankingParser } from './RankingParser';
import { RankingStorage } from './RankingStorage';

class RankingCacheRecord {
  fetchedAt: number;
  body: string;
  constructor(fetchedAt: number, body: string) {
    this.fetchedAt = fetchedAt;
    this.body = body;
  }
}

export class RankingService {
  static readonly HOME_URL: string = 'home://rankings';
  /** 榜单详情页最多展示 99 项，超出部分不解析进内存也不落盘。 */
  static readonly MAX_BOOKS: number = 99;
  private static readonly TTL: number = 6 * 60 * 60 * 1000;
  private static pending: Map<string, Promise<RankingBoard>> = new Map<string, Promise<RankingBoard>>();

  static platforms(): RankingPlatform[] {
    return [new RankingPlatform('', $r('app.string.home_recommendations')),
      new RankingPlatform('qqcomic', $r('app.string.ranking_qqcomic')),
      new RankingPlatform('bilicomic', $r('app.string.ranking_bilicomic')),
      new RankingPlatform('qidian', $r('app.string.ranking_qidian')),
      new RankingPlatform('lrts', $r('app.string.ranking_lrts')),
      new RankingPlatform('ximalaya', $r('app.string.ranking_ximalaya')),
      new RankingPlatform('qimao', $r('app.string.ranking_qimao')),
      new RankingPlatform('jjwxc', $r('app.string.ranking_jjwxc')),
      new RankingPlatform('fanqie', $r('app.string.ranking_fanqie')),
      new RankingPlatform('faloo', $r('app.string.ranking_faloo'))];
  }

  static boards(): RankingBoard[] {
    return [
      new RankingBoard('fq-hot', 'fanqie', $r('app.string.ranking_fanqie'), $r('app.string.ranking_novel_hot'),
        'https://fanqienovel.com/api/author/misc/top_book_list/v1/'),
      new RankingBoard('fl-month', 'faloo', $r('app.string.ranking_faloo'), $r('app.string.ranking_month'),
        'https://b.faloo.com/y_0_0_0_0_3_15_1.html'),
      new RankingBoard('fl-flowers', 'faloo', $r('app.string.ranking_faloo'), $r('app.string.ranking_month_flowers'),
        'https://b.faloo.com/y_0_0_0_0_3_5_1.html'),
      new RankingBoard('qqcomic-top', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_top100'),
        'https://ac.qq.com/Rank/comicRank/type/top'),
      new RankingBoard('qqcomic-mt', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_month'),
        'https://ac.qq.com/Rank/comicRank/type/mt'),
      new RankingBoard('qqcomic-rise', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_rising'),
        'https://ac.qq.com/Rank/comicRank/type/rise'),
      new RankingBoard('qqcomic-new', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_new'),
        'https://ac.qq.com/Rank/comicRank/type/new'),
      new RankingBoard('qqcomic-pay', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_sales'),
        'https://ac.qq.com/Rank/comicRank/type/pay'),
      new RankingBoard('qqcomic-male', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_male'),
        'https://ac.qq.com/Rank/comicRank/type/male'),
      new RankingBoard('qqcomic-female', 'qqcomic', $r('app.string.ranking_qqcomic'), $r('app.string.ranking_comic_female'),
        'https://ac.qq.com/Rank/comicRank/type/female'),
      new RankingBoard('bilicomic-1', 'bilicomic', $r('app.string.ranking_bilicomic'), $r('app.string.ranking_comic_chinese'),
        'https://manga.bilibili.com/ranking/1'),
      new RankingBoard('bilicomic-0', 'bilicomic', $r('app.string.ranking_bilicomic'), $r('app.string.ranking_comic_japanese'),
        'https://manga.bilibili.com/ranking/0'),
      new RankingBoard('bilicomic-2', 'bilicomic', $r('app.string.ranking_bilicomic'), $r('app.string.ranking_comic_korean'),
        'https://manga.bilibili.com/ranking/2'),
      new RankingBoard('bilicomic-7', 'bilicomic', $r('app.string.ranking_bilicomic'), $r('app.string.ranking_comic_new'),
        'https://manga.bilibili.com/ranking/7'),
      new RankingBoard('bilicomic-13', 'bilicomic', $r('app.string.ranking_bilicomic'), $r('app.string.ranking_comic_finished'),
        'https://manga.bilibili.com/ranking/13'),
      new RankingBoard('lr-hot', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_hot'),
        RankingService.lanrenEndpoint(75)),
      new RankingBoard('qd-month', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_month'),
        'https://m.qidian.com/rank/yuepiao/'),
      new RankingBoard('xm-free', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_free'),
        'https://www.ximalaya.com/revision/rank/getRankList?rankType=freeAlbum&pageSize=50'),
      new RankingBoard('qd-finished', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_finished'),
        'https://m.qidian.com/bestsell/'),
      new RankingBoard('qd-reading', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_reading'),
        'https://m.qidian.com/rank/readindex/'),
      new RankingBoard('qd-recommend', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_recommend'),
        'https://m.qidian.com/rank/rec/'),
      new RankingBoard('qd-new', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_new'),
        'https://m.qidian.com/rank/newbook/'),
      new RankingBoard('qd-sales', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_sales'),
        'https://m.qidian.com/rank/hotsales/'),
      new RankingBoard('lr-comment', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_comment'),
        RankingService.lanrenEndpoint(76)),
      new RankingBoard('xm-paid', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_paid'),
        'https://www.ximalaya.com/revision/rank/getRankList?rankType=paidAlbum&pageSize=50'),
      new RankingBoard('qm-boy', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_hot'),
        'https://www.qimao.com/paihang/boy/hot/'),
      new RankingBoard('qm-girl', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_hot'),
        'https://www.qimao.com/paihang/girl/hot/'),
      new RankingBoard('jj-total', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_total_points'),
        'https://www.jjwxc.net/topten.php?orderstr=7'),
      new RankingBoard('jj-month', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_monthly'),
        'https://www.jjwxc.net/topten.php?orderstr=5'),
      new RankingBoard('lr-search', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_search_week'),
        RankingService.lanrenEndpoint(77)),
      new RankingBoard('lr-free', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_free_week'),
        RankingService.lanrenEndpoint(14481)),
      new RankingBoard('lr-sales', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_sales_week'),
        RankingService.lanrenEndpoint(265)),
      new RankingBoard('lr-finished', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_finished_week'),
        RankingService.lanrenEndpoint(739)),
      new RankingBoard('xm-hot', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_hot'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=12&clusterId=52&pageNum=1&pageSize=30'),
      new RankingBoard('xm-new', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_new'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=14&clusterId=70&pageNum=1&pageSize=30'),
      new RankingBoard('xm-reputation', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_reputation'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=15&clusterId=394&pageNum=1&pageSize=30'),
      new RankingBoard('xm-vip', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_novel_vip'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=25&clusterId=362&pageNum=1&pageSize=30'),
      new RankingBoard('qm-boy-new', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_new'),
        'https://www.qimao.com/paihang/boy/new/date/'),
      new RankingBoard('qm-girl-new', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_new'),
        'https://www.qimao.com/paihang/girl/new/date/'),
      new RankingBoard('qm-boy-finished', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_finished'),
        'https://www.qimao.com/paihang/boy/over/date/'),
      new RankingBoard('qm-girl-finished', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_finished'),
        'https://www.qimao.com/paihang/girl/over/date/'),
      new RankingBoard('jj-season', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_season'),
        'https://www.jjwxc.net/topten.php?orderstr=4'),
      new RankingBoard('jj-half-year', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_half_year'),
        'https://www.jjwxc.net/topten.php?orderstr=6'),
      new RankingBoard('jj-vip', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_vip_recommend'),
        'https://www.jjwxc.net/topten.php?orderstr=2'),
      new RankingBoard('jj-words', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_words'),
        'https://www.jjwxc.net/topten.php?orderstr=8'),
      new RankingBoard('fq-fantasy-reading', 'fanqie', $r('app.string.ranking_fanqie'),
        $r('app.string.ranking_fantasy_reading'), RankingService.fanqieCategory(1, 2, 257)),
      new RankingBoard('fq-urban-reading', 'fanqie', $r('app.string.ranking_fanqie'),
        $r('app.string.ranking_urban_reading'), RankingService.fanqieCategory(1, 2, 1014)),
      new RankingBoard('fq-historical-reading', 'fanqie', $r('app.string.ranking_fanqie'),
        $r('app.string.ranking_historical_reading'), RankingService.fanqieCategory(0, 2, 1139)),
      new RankingBoard('fq-fantasy-new', 'fanqie', $r('app.string.ranking_fanqie'),
        $r('app.string.ranking_fantasy_new'), RankingService.fanqieCategory(1, 1, 257)),
      new RankingBoard('fq-historical-new', 'fanqie', $r('app.string.ranking_fanqie'),
        $r('app.string.ranking_historical_new'), RankingService.fanqieCategory(0, 1, 1139)),
      new RankingBoard('fl-week-flowers', 'faloo', $r('app.string.ranking_faloo'),
        $r('app.string.ranking_week_flowers'), 'https://b.faloo.com/y_0_0_0_0_3_4_1.html'),
      new RankingBoard('fl-week-clicks', 'faloo', $r('app.string.ranking_faloo'),
        $r('app.string.ranking_week_clicks'), 'https://b.faloo.com/y_0_0_0_0_3_1_1.html'),
      new RankingBoard('fl-month-clicks', 'faloo', $r('app.string.ranking_faloo'),
        $r('app.string.ranking_month_clicks'), 'https://b.faloo.com/y_0_0_0_0_3_2_1.html'),
      new RankingBoard('fl-month-favorites', 'faloo', $r('app.string.ranking_faloo'),
        $r('app.string.ranking_month_favorites'), 'https://b.faloo.com/y_0_0_0_0_3_8_1.html')
    ];
  }

  /** 新版官网榜单接口：rangeType=1 为周榜；保留旧 board ID 和用户排序。 */
  private static lanrenEndpoint(rankId: number): string {
    return `https://www.lanrentingshu.com/api/ranking/resList?rankId=${rankId}&rangeType=1&pageSize=100`;
  }

  /** 官网分类榜：gender 1/0 为男/女频，rankMold 2/1 为阅读/新书榜。 */
  private static fanqieCategory(gender: number, rankMold: number, categoryId: number): string {
    return 'https://fanqienovel.com/api/rank/category/list?app_id=2503&rank_list_type=3' +
      `&offset=0&limit=30&category_id=${categoryId}&rank_version=&gender=${gender}&rankMold=${rankMold}`;
  }

  static async cached(context: common.Context, board: RankingBoard): Promise<RankingBoard> {
    try {
      const text = await RankingStorage.read(context, board.id);
      if (!text) return board;
      const record = new JsonObj(JSON.parse(text));
      const time = record.getInt('fetchedAt');
      if (time <= 0 || time > Date.now() + 60000 || Date.now() - time > 30 * 86400000) return board;
      const books = RankingParser.parse(board.platformId, board.id, record.getString('body'));
      if (books.length > 0) {
        board.books = books.slice(0, RankingService.MAX_BOOKS);
        board.fetchedAt = time;
        board.stale = Date.now() - time >= RankingService.TTL;
      }
    } catch (_error) { /* 损坏缓存回退网络。 */ }
    return board;
  }

  /** 首屏先读先显；缓存解析与联网均不等待其余全部榜单完成。 */
  static async loadProgressively(context: common.Context, boards: RankingBoard[], force: boolean,
    onUpdate: (board: RankingBoard) => void, isCurrent: () => boolean): Promise<void> {
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (isCurrent() && cursor < boards.length) {
        let board = boards[cursor++];
        if (board.books.length === 0) {
          board = await RankingService.cached(context, board);
          if (!isCurrent()) return;
          if (board.books.length > 0) onUpdate(board);
        }
        if (!isCurrent()) return;
        const loaded = await RankingService.load(context, board, force);
        if (!isCurrent()) return;
        if (loaded !== board || board.books.length === 0) onUpdate(loaded);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
  }

  static async load(context: common.Context, board: RankingBoard, force: boolean): Promise<RankingBoard> {
    if (!force && board.books.length > 0 && !board.stale) return board;
    const running = RankingService.pending.get(board.id);
    if (running !== undefined) return running;
    const task = RankingService.fetch(context, board).finally((): void => {
      RankingService.pending.delete(board.id);
    });
    RankingService.pending.set(board.id, task);
    return task;
  }

  /** 漫画榜使用官网桌面页面；手机 UA 会重定向到不同结构的移动站。 */
  static headers(platform: string): Record<string, string> {
    if (platform === 'lrts') {
      return { 'Referer': 'https://www.lanrentingshu.com/discover/ranking', 'Accept': 'application/json' };
    }
    if (platform !== 'qqcomic' && platform !== 'bilicomic') return {};
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      'Referer': platform === 'qqcomic' ? 'https://ac.qq.com/Rank' : 'https://manga.bilibili.com/',
      'Accept': 'text/html,application/xhtml+xml'
    };
  }

  private static async fetch(context: common.Context, board: RankingBoard): Promise<RankingBoard> {
    const next = new RankingBoard(board.id, board.platformId, board.platformName, board.title, board.endpoint);
    next.books = board.books;
    next.fetchedAt = board.fetchedAt;
    try {
      const response = await HttpClient.request(board.endpoint, { timeout: 12000,
        headers: RankingService.headers(board.platformId),
        charset: board.platformId === 'faloo' ? 'gb18030' : 'utf-8' });
      if (response.statusCode !== 200) throw new Error(`Ranking HTTP ${response.statusCode}`);
      const books = RankingParser.parse(board.platformId, board.id, response.body);
      if (books.length === 0) throw new Error('Ranking page changed or empty');
      next.books = books.slice(0, RankingService.MAX_BOOKS);
      next.fetchedAt = Date.now();
      await RankingStorage.write(context, board.id, JSON.stringify(new RankingCacheRecord(next.fetchedAt, response.body)));
    } catch (_error) {
      next.unavailable = next.books.length === 0;
      next.stale = next.books.length > 0;
    }
    return next;
  }
}
