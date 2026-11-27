/** 番茄官网 dc027189e0ba4cd 字体的 Unicode 对照，仅用于公开榜单元数据。
 * 字表参考：https://github.com/404-novel-project/fanqie_font_tables/blob/b76d07b95268a9cbbf24866d9f9a4874bb9a9453/dc027189e0ba4cd.woff2.json
 * 未知私用区字符保留，由榜单解析器拒绝展示；不执行网页脚本或加载远程字体。 */
export class FanqieRankingText {
  private static readonly FIRST_CODE: number = 0xE3E8;
  static readonly GLYPHS: string =
    'D在主特家军然表场4要只v和\u00006别还g现儿岁\u0000\u0000此象月3出战工相o男直失世F都平文什VO将真T那当\u0000会立些u是十张学气大爱两' +
    '命全后东性通被1它乐接而感车山公了常以何可话先pi叫轻M士W着变尔快l个说少色里安花远7难师放t报认面道S\u0000克地度I好机U民' +
    '写把万同水新没书电吃像斯5为y白几日教看但第加候作上拉住有法r事应位利你声身国问马女他Y比父XAHNSX边美对所金活回意到Z' +
    '从j知又内因点Q三定8Rb正或夫向德听更\u0000得告并本q过记L让打f人就者去原满体做经K走如孩CG给使物\u0000最笑部\u0000员等受k行一条' +
    '果动光门头见往自解成处天能于名其发总母的死手入路进心来h时力多开已许d至由很界n小与Z想代么分生口再妈望次西风种带J\u0000实情才' +
    '这\u0000E我神格长觉间年眼无不亲关结0友信下却重己老2音字m呢明之前高PB目太e9起稜她也W用方子英每理便四数期中C外样a海们任';

  static decode(value: string): string {
    let result = '';
    for (let index = 0; index < value.length; index++) {
      const offset = value.charCodeAt(index) - FanqieRankingText.FIRST_CODE;
      const decoded = FanqieRankingText.GLYPHS.charAt(offset);
      result += offset >= 0 && decoded.length > 0 && decoded !== '\u0000' ? decoded : value.charAt(index);
    }
    return result;
  }
}
