import { LocalTextImage } from './LocalTextImage';

export class EpubOriginalSpot {
  snippet: string = '';
  fraction: number = 0;
  page: number = 0;
  count: number = 1;
  end: boolean = false;
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
    const plain = LocalTextImage.speechContent(text);
    const compact = EpubOriginalPosition.compact(plain);
    const expected = Math.round(Math.max(0, Math.min(1, spot.fraction)) * compact.length);
    let found = -1;
    const snippet = EpubOriginalPosition.compact(spot.snippet);
    if (snippet) {
      let index = compact.indexOf(snippet);
      while (index >= 0) {
        if (found < 0 || Math.abs(index - expected) < Math.abs(found - expected)) found = index;
        index = compact.indexOf(snippet, index + 1);
      }
    }
    const target = found >= 0 ? found : expected;
    let count = 0;
    for (let index = 0; index < plain.length; index++) {
      if (!EpubOriginalPosition.compact(plain[index])) continue;
      if (count++ >= target) return index;
    }
    return text.length;
  }
}
