import { RankingBook } from '../../model/Ranking';
import { BookMetadataPolicy } from '../../utils/BookMetadataPolicy';
import { JsonObj } from '../builtin/JsonValue';
import { FanqieRankingText } from './FanqieRankingText';

/** 只解析已经下载的公开榜单文本，不执行页面脚本。 */
export class RankingParser {
  private static rating(item: JsonObj): number {
    return BookMetadataPolicy.rating(item.getString('rating')) ||
      BookMetadataPolicy.rating(item.getString('score')) ||
      BookMetadataPolicy.rating(item.getString('bookScore')) ||
      BookMetadataPolicy.rating(item.getString('albumScore'));
  }

  private static htmlRating(html: string): number {
    const value = /\bitemprop=["']ratingValue["'][^>]*\bcontent=["']([^"']+)["']/i.exec(html)?.[1]
      ?? /\bitemprop=["']ratingValue["'][^>]*>([^<]+)/i.exec(html)?.[1]
      ?? RankingParser.capture(html, /<(?:span|em|div)\b[^>]*class=["'][^"']*\b(?:score|rating|book-score)\b[^"']*["'][^>]*>([\s\S]*?)<\//i);
    return BookMetadataPolicy.rating(value);
  }

  static text(html: string): string {
    return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
      .replace(/&nbsp;|\u00a0/g, ' ').replace(/&#(\d+);/g,
        (_match: string, code: string): string => String.fromCharCode(Number(code)))
      .replace(/\s+/g, ' ').trim();
  }

  private static capture(html: string, pattern: RegExp): string {
    return RankingParser.text(pattern.exec(html)?.[1] ?? '');
  }

  static imageUrl(value: string): string {
    const clean = value.replace(/&amp;/g, '&').trim();
    if (clean.startsWith('//')) return `https:${clean}`;
    return clean.startsWith('https://') ? clean : '';
  }

  private static qqcomic(body: string): RankingBook[] {
    // 只读当前榜期的 rank-ul，不能混入上期排名、侧边推荐或全部漫画目录。
    const panels = body.split(/<div\b[^>]*class=["'][^"']*\brank-tabcon\b[^"']*["'][^>]*>/i);
    const lists = panels.length >= 2
      ? panels[1].match(/<ul\b[^>]*class=["']rank-ul["'][^>]*>[\s\S]*?<\/ul>/gi) ?? []
      : body.match(/<ol\b[^>]*class=["'][^"']*\bmod-rank-month-list\b[^"']*["'][^>]*>[\s\S]*?<\/ol>/gi) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const list of lists) {
      const rows = list.match(/<li\b[^>]*>[\s\S]*?<\/li>/gi) ?? [];
      for (const html of rows) {
        if (books.length >= 99) return books;
        const link = /<a\b[^>]*href=["']\/Comic\/ComicInfo\/id\/(\d+)["'][^>]*>([\s\S]*?)<\/a>/i.exec(html);
        if (link === null || seen.has(link[1])) continue;
        const title = RankingParser.text(link[2]);
        const rank = Number(RankingParser.capture(html, /<(?:em|sub)\b[^>]*>(\d+)<\/(?:em|sub)>/i));
        if (!title || !Number.isInteger(rank) || rank <= 0) continue;
        const book = new RankingBook();
        book.id = `qqcomic:${link[1]}`;
        book.platformId = 'qqcomic';
        book.contentType = 'comic';
        book.title = title;
        book.rank = rank;
        book.originalUrl = `https://ac.qq.com/Comic/comicInfo/id/${link[1]}`;
        // 腾讯完整榜单仅提供书名和名次，不编造作者或封面地址。
        seen.add(link[1]);
        books.push(book);
      }
    }
    return books;
  }

  private static bilicomic(boardId: string, body: string): RankingBook[] {
    const data = /<script\b[^>]*id=["']vike_pageContext["'][^>]*>([\s\S]*?)<\/script>/i.exec(body)?.[1] ?? '';
    if (!data) return [];
    try {
      const root = new JsonObj(JSON.parse(data));
      if (root.getString('pageId') !== '/pages/ranking' ||
        root.getObj('routeParams').getString('page_id') !== boardId.substring('bilicomic-'.length)) return [];
      const page = root.getObj('data');
      const list = page.getArr('rankListInfo');
      const books: RankingBook[] = [];
      const seen = new Set<string>();
      for (let index = 0; index < Math.min(list.length(), 99); index++) {
        const item = list.getObj(index);
        const id = item.getString('comic_id');
        const title = RankingParser.text(item.getString('title'));
        if (!/^\d+$/.test(id) || !title || seen.has(id)) continue;
        const book = new RankingBook();
        book.id = `bilicomic:${id}`;
        book.platformId = 'bilicomic';
        book.contentType = 'comic';
        book.title = title;
        book.rank = index + 1;
        const authors = item.getArr('author');
        const names: string[] = [];
        for (let authorIndex = 0; authorIndex < Math.min(authors.length(), 10); authorIndex++) {
          const author = RankingParser.text(authors.getString(authorIndex));
          if (author) names.push(author);
        }
        book.author = names.join(' / ');
        book.intro = RankingParser.text(item.getString('comic_introduction'));
        book.coverUrl = RankingParser.imageUrl(item.getString('vertical_cover')
          .replace(/^http:\/\/(i[0-9]+\.hdslb\.com)\//, 'https://$1/'));
        book.originalUrl = `https://manga.bilibili.com/detail/mc${id}`;
        seen.add(id);
        books.push(book);
      }
      return books;
    } catch (_error) { return []; }
  }

  static parse(platform: string, boardId: string, body: string): RankingBook[] {
    if (!body || body.length > 2 * 1024 * 1024) return [];
    if (platform === 'qqcomic') return RankingParser.qqcomic(body);
    if (platform === 'bilicomic') return RankingParser.bilicomic(boardId, body);
    if (platform === 'ximalaya') return RankingParser.ximalaya(boardId, body);
    if (platform === 'qimao') return RankingParser.qimao(body);
    if (platform === 'jjwxc') return RankingParser.jjwxc(body);
    if (platform === 'fanqie') return RankingParser.fanqie(boardId, body);
    if (platform === 'faloo') return RankingParser.faloo(body);
    if (platform === 'qidian') {
      const records = RankingParser.qidianPage(boardId, body);
      // 完结入口只使用带明确完本状态的结构化记录，不能回退到页面中的推荐书。
      if (records.length > 0 || boardId === 'qd-finished') return records;
    }
    const blocks = platform === 'qidian'
      ? body.match(/<a\b[^>]*href="(?:https?:)?\/\/m\.qidian\.com\/book\/\d+\/"[^>]*>[\s\S]*?<\/a>/g) ?? []
      : body.match(/<li\s+class="book-item"[^>]*>[\s\S]*?<\/li>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const html of blocks.slice(0, 100)) {
      const platformBookId = /\/book\/(\d+)/.exec(html)?.[1] ?? '';
      if (!platformBookId || seen.has(platformBookId)) continue;
      const book = new RankingBook();
      book.id = `${platform}:${platformBookId}`;
      book.platformId = platform;
      book.rank = books.length + 1;
      book.rating = RankingParser.htmlRating(html);
      if (platform === 'qidian') {
        book.contentType = 'text';
        book.title = RankingParser.capture(html, /<h2\b[^>]*>([\s\S]*?)<\/h2>/);
        const subtitle = RankingParser.capture(html, /<p\b[^>]*class="[^"]*_subTitle_[^"]*"[^>]*>([\s\S]*?)<\/p>/);
        book.author = subtitle.split('·')[0].trim();
        book.coverUrl = RankingParser.imageUrl(/data-src="([^"]+)"/.exec(html)?.[1] ?? '')
          .replace(/(bookcover\.yuewen\.com\/qdbimg\/\d+\/\d+)\/180$/, '$1/600');
        book.originalUrl = `https://m.qidian.com/book/${platformBookId}/`;
        book.intro = RankingParser.capture(html, /<p\b[^>]*class="[^"]*_bookDesc_[^"]*"[^>]*>([\s\S]*?)<\/p>/);
      } else {
        book.contentType = 'audio';
        book.title = RankingParser.capture(html, /<a\b[^>]*class="book-item-name"[^>]*>([\s\S]*?)<\/a>/);
        book.author = RankingParser.capture(html, /<a\b[^>]*class="author"[^>]*>([\s\S]*?)<\/a>/);
        book.narrator = RankingParser.capture(html, /主播：[\s\S]*?<a\b[^>]*>([\s\S]*?)<\/a>/);
        book.coverUrl = RankingParser.imageUrl(/<img\b[^>]*\bsrc="([^"]+)"/.exec(html)?.[1] ?? '')
          .replace(/(bookpic\.lrts\.me\/[^/?]+-1-\d+)\.(png|jpg|jpeg)$/, '$1_600x600.$2');
        book.originalUrl = `https://www.lrts.me/book/${platformBookId}`;
        book.intro = RankingParser.capture(html, /<p\b[^>]*class="book-item-desc[^\"]*"[^>]*>([\s\S]*?)<\/p>/);
      }
      if (!book.title) continue;
      seen.add(platformBookId);
      books.push(book);
    }
    return books;
  }

  static qqComicMetadata(id: string, body: string): RankingBook | null {
    if (!/^qqcomic:\d+$/.test(id) || body.length > 2 * 1024 * 1024) return null;
    const scripts = body.match(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) ?? [];
    for (const script of scripts) {
      try {
        const text = />([\s\S]*?)<\/script>/i.exec(script)?.[1] ?? '';
        const item = new JsonObj(JSON.parse(text));
        if (item.getString('@type') !== 'ComicSeries' ||
          item.getString('url').toLowerCase() !== `https://ac.qq.com/comic/comicinfo/id/${id.substring(8)}`) continue;
        const cover = RankingParser.imageUrl(item.getString('image'));
        if (!cover) continue;
        const book = new RankingBook();
        book.id = id;
        book.coverUrl = cover;
        book.author = RankingParser.text(item.getObj('author').getString('name'));
        book.intro = RankingParser.text(item.getString('description'));
        book.rating = BookMetadataPolicy.rating(item.getObj('aggregateRating').getString('ratingValue'));
        return book;
      } catch (_error) { /* 单个无关结构化块损坏不影响作品信息。 */ }
    }
    return null;
  }

  private static fanqie(boardId: string, body: string): RankingBook[] {
    const root = new JsonObj(JSON.parse(body));
    const category = boardId !== 'fq-hot';
    if (category && root.getString('code') !== '0') return [];
    const list = category ? root.getObj('data').getArr('book_list') : root.getArr('book_list');
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (let index = 0; index < Math.min(list.length(), 99); index++) {
      const item = list.getObj(index);
      const id = item.getString(category ? 'bookId' : 'book_id');
      const title = RankingParser.fanqieText(item.getString(category ? 'bookName' : 'book_name'), category);
      if (!/^\d+$/.test(id) || !title || /[\uE000-\uF8FF]/.test(title) || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `fanqie:${id}`;
      book.platformId = 'fanqie';
      book.title = title;
      book.author = RankingParser.fanqieText(item.getString('author'), category);
      book.coverUrl = RankingParser.imageUrl(item.getString(category ? 'thumbUri' : 'thumb_url'));
      book.originalUrl = `https://fanqienovel.com/page/${id}`;
      book.intro = RankingParser.fanqieText(item.getString(category ? 'abstract' : 'category'), category);
      book.rating = RankingParser.rating(item);
      const rank = category ? item.getInt('currentPos') : 0;
      book.rank = rank > 0 ? rank : index + 1;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static fanqieText(value: string, decode: boolean): string {
    const text = RankingParser.text(decode ? FanqieRankingText.decode(value) : value);
    return /[\uE000-\uF8FF]/.test(text) ? '' : text;
  }

  private static faloo(body: string): RankingBook[] {
    const rows = body.split('<div class="TwoBox02_02">').slice(1, 100);
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      const heading = /<h1\b[^>]*>([\s\S]*?)<\/h1>/.exec(row)?.[1] ?? '';
      const id = /href="(?:https?:)?\/\/b\.faloo\.com\/(\d+)\.html"/.exec(heading)?.[1] ?? '';
      const title = RankingParser.text(heading);
      if (!id || !title || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `faloo:${id}`;
      book.platformId = 'faloo';
      book.title = title;
      book.author = RankingParser.capture(row, /<a\b[^>]*href="[^\"]*\/l_0_1\.html\?t=2[^\"]*"[^>]*>([\s\S]*?)<\/a>/);
      const image = /<img\b[^>]*\bsrc="([^"]+)"/.exec(row)?.[1] ?? '';
      book.coverUrl = RankingParser.imageUrl(image.replace(/^http:\/\/img\.faloo\.com\//, 'https://img.faloo.com/'));
      book.originalUrl = `https://b.faloo.com/${id}.html`;
      book.intro = RankingParser.capture(row, /<div class="TwoBox02_06">([\s\S]*?)<\/div>/);
      book.rating = RankingParser.htmlRating(row);
      book.rank = books.length + 1;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static qidianPage(boardId: string, body: string): RankingBook[] {
    const data = /<script\b[^>]*\bid=["']vite-plugin-ssr_pageContext["'][^>]*>([\s\S]*?)<\/script>/.exec(body)?.[1] ?? '';
    if (!data) return [];
    try {
      const root = new JsonObj(JSON.parse(data));
      const records = root.getObj('pageContext').getObj('pageProps').getObj('pageData').getArr('records');
      const books: RankingBook[] = [];
      const seen = new Set<string>();
      for (let index = 0; index < Math.min(records.length(), 100); index++) {
        const item = records.getObj(index);
        const id = item.getString('bid');
        if (!/^\d+$/.test(id) || seen.has(id)) continue;
        if (boardId === 'qd-finished' && item.getString('state') !== '完本' &&
          item.getString('state') !== '已经完本') continue;
        const book = new RankingBook();
        book.id = `qidian:${id}`;
        book.platformId = 'qidian';
        book.title = RankingParser.text(item.getString('bName'));
        if (!book.title) continue;
        book.author = RankingParser.text(item.getString('bAuth'));
        book.intro = RankingParser.text(item.getString('desc'));
        book.rating = RankingParser.rating(item);
        book.coverUrl = `https://bookcover.yuewen.com/qdbimg/349573/${id}/600`;
        book.originalUrl = `https://m.qidian.com/book/${id}/`;
        book.contentType = 'text';
        const rank = item.getInt('rankNum');
        book.rank = rank > 0 ? rank : index + 1;
        seen.add(id);
        books.push(book);
      }
      return books;
    } catch (_error) {
      return [];
    }
  }

  private static ximalaya(boardId: string, body: string): RankingBook[] {
    const root = new JsonObj(JSON.parse(body));
    if (root.getInt('ret') !== 200) return [];
    let list = root.getObj('data').getObj(boardId === 'xm-paid' ? 'paidAlbumRank' : 'freeAlbumRank')
      .getArr('rankListInfo');
    if (boardId !== 'xm-free' && boardId !== 'xm-paid') {
      const rankId = boardId === 'xm-hot' ? 48 : boardId === 'xm-new' ? 71 :
        boardId === 'xm-reputation' ? 117 : boardId === 'xm-vip' ? 282 : 0;
      if (rankId === 0) return [];
      const ranks = root.getObj('data').getArr('rankList');
      let matched = false;
      for (let index = 0; index < ranks.length(); index++) {
        const rank = ranks.getObj(index);
        if (rank.getInt('rankId') !== rankId) continue;
        list = rank.getArr('albums');
        matched = true;
        break;
      }
      if (!matched) return [];
    }
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (let index = 0; index < Math.min(list.length(), 100); index++) {
      const item = list.getObj(index);
      const id = item.getString('id');
      if (!/^\d+$/.test(id) || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `ximalaya:${id}`;
      book.platformId = 'ximalaya';
      book.title = RankingParser.text(item.getString('albumTitle'));
      book.narrator = RankingParser.text(item.getString('anchorName'));
      const cover = item.getString('cover');
      book.coverUrl = /^(storages\/|group\d+\/)[A-Za-z0-9_./-]+$/.test(cover)
        ? `https://imagev2.xmcdn.com/${cover}` : RankingParser.imageUrl(cover);
      book.originalUrl = `https://www.ximalaya.com/album/${id}`;
      book.contentType = 'audio';
      book.intro = RankingParser.text(item.getString('description'));
      book.rating = RankingParser.rating(item);
      book.rank = index + 1;
      if (!book.title) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static qimao(body: string): RankingBook[] {
    const rows = body.match(/<li\b[^>]*class="rank-list-item"[^>]*>[\s\S]*?<\/li>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const row of rows.slice(0, 100)) {
      const id = /\/shuku\/(\d+)\//.exec(row)?.[1] ?? '';
      if (!id || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `qimao:${id}`;
      book.platformId = 'qimao';
      book.title = RankingParser.capture(row, /<a\b[^>]*class="s-book-title"[^>]*>([\s\S]*?)<\/a>/);
      book.author = RankingParser.capture(row, /<a\b[^>]*href="[^\"]*\/zuozhe\/[^\"]*"[^>]*>([\s\S]*?)<\/a>/);
      book.coverUrl = RankingParser.imageUrl(/<img\b[^>]*\bsrc="([^\"]+)"/.exec(row)?.[1] ?? '');
      book.intro = RankingParser.capture(row, /<span\b[^>]*class="s-book-intro"[^>]*>([\s\S]*?)<\/span>/);
      book.originalUrl = `https://www.qimao.com/shuku/${id}/`;
      book.rating = RankingParser.htmlRating(row);
      book.rank = books.length + 1;
      if (!book.title) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }

  private static jjwxc(body: string): RankingBook[] {
    const rows = body.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/g) ?? [];
    const books: RankingBook[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      if (books.length >= 100) break;
      const tags = row.match(/<a\b(?:[^"'<>]|"[^"]*"|'[^']*')*>/g) ?? [];
      const link = tags.find((tag: string): boolean => /href="onebook\.php\?novelid=\d+"/.test(tag));
      if (!link) continue;
      const id = /novelid=(\d+)/.exec(link)?.[1] ?? '';
      if (!id || seen.has(id)) continue;
      const book = new RankingBook();
      book.id = `jjwxc:${id}`;
      book.platformId = 'jjwxc';
      book.title = RankingParser.capture(link, /\btitle="([^"]+)"/);
      if (!book.title) {
        book.title = RankingParser.capture(row,
          /<a\b[^>]*href="onebook\.php\?novelid=\d+"[^>]*>([\s\S]*?)<\/a>/);
      }
      const authorLink = tags.find((tag: string): boolean => tag.includes('oneauthor.php?authorid='));
      book.author = RankingParser.capture(authorLink ?? '', /\btitle="([^"]+)"/);
      if (!book.author) {
        book.author = RankingParser.capture(row,
          /<a\b[^>]*href="oneauthor\.php\?authorid=\d+"[^>]*>([\s\S]*?)<\/a>/);
      }
      book.intro = RankingParser.capture(link, /\brel="([^"]*)"/);
      book.coverUrl = `https://i9-static.jjwxc.net/novelimage.php?novelid=${id}`;
      book.originalUrl = `https://www.jjwxc.net/onebook.php?novelid=${id}`;
      book.rank = books.length + 1;
      if (!book.title || !book.author) continue;
      seen.add(id);
      books.push(book);
    }
    return books;
  }
}
