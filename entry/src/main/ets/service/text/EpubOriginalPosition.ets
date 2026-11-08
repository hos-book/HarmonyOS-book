import { LocalTextImage } from './LocalTextImage';

export class EpubOriginalSpot {
  snippet: string = '';
  fraction: number = 0;
  page: number = 0;
  count: number = 1;
  end: boolean = false;
}

/** 每个活动片段只建立一次映射，滚动回调不再逐字运行正则来换算坐标。 */
export class EpubOriginalPositionIndex {
  private text: string = '';
  private offsets: number[] = [];
  private length: number = 0;

  constructor(source: string) {
    const plain = LocalTextImage.speechContent(source);
    this.length = source.length;
    const characters: string[] = [];
    for (let index = 0; index < plain.length; index++) {
      const value = EpubOriginalPosition.compact(plain[index]);
      if (value) { characters.push(value); this.offsets.push(index); }
    }
    this.text = characters.join('');
  }

  offset(spot: EpubOriginalSpot): number {
    const expected = Math.round(Math.max(0, Math.min(1, spot.fraction)) * this.text.length);
    const snippet = EpubOriginalPosition.compact(spot.snippet);
    let found = -1;
    if (snippet) {
      let index = this.text.indexOf(snippet);
      while (index >= 0) {
        if (found < 0 || Math.abs(index - expected) < Math.abs(found - expected)) found = index;
        index = this.text.indexOf(snippet, index + 1);
      }
    }
    return this.offsets[found >= 0 ? found : expected] ?? this.length;
  }
}

/** 以正文片段定位，图片标记和排版空白不参与匹配。重复句按章内比例消歧。 */
export class EpubOriginalPosition {
  /** 与轻页网页脚本相同：去空白、零宽空格/BOM，统一上下标数字。 */
  static compact(text: string): string {
    return text.replace(/[\s\u200b\ufeff]/g, '').replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉]/g,
      (digit: string): string => String('⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉'.indexOf(digit) % 10));
  }

  static spot(text: string, offset: number): EpubOriginalSpot {
    const plain = LocalTextImage.speechContent(text);
    const before = EpubOriginalPosition.compact(plain.substring(0, Math.max(0, offset))).length;
    const compact = EpubOriginalPosition.compact(plain);
    const spot = new EpubOriginalSpot();
    spot.snippet = compact.substring(before, before + 32);
    spot.fraction = compact.length > 0 ? before / compact.length : 0;
    return spot;
  }

  static offset(text: string, spot: EpubOriginalSpot): number {
    return new EpubOriginalPositionIndex(text).offset(spot);
  }
}
