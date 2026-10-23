import { AppTheme } from './Theme';

/** 仅解析封面呈现；真实图片地址、封面缓存和书籍身份始终由原链路管理。 */
export class CoverTheme {
  static isPaper(themeBundleId: string = ''): boolean {
    return themeBundleId.length > 0 ? themeBundleId === 'paper-study' : AppTheme.isPaper;
  }

  static placeholder(themeBundleId: string = ''): Resource {
    return CoverTheme.isPaper(themeBundleId) ? $r('app.media.theme_paper_cover') :
      $r('app.media.book_cover_placeholder');
  }

  static localPlaceholder(themeBundleId: string = ''): Resource {
    return CoverTheme.isPaper(themeBundleId) ? $r('app.media.theme_paper_local_cover') :
      $r('app.media.local_book_cover_placeholder');
  }

  static titleColor(local: boolean = false, themeBundleId: string = ''): ResourceColor {
    if (CoverTheme.isPaper(themeBundleId)) {
      return local ? $r('app.color.theme_paper_local_cover_text') : $r('app.color.theme_paper_cover_text');
    }
    return local ? '#493E35' : '#FFF4E6';
  }

  static authorColor(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.isPaper(themeBundleId) ? $r('app.color.theme_paper_local_cover_author') : '#64584B';
  }

  static titleBackground(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.isPaper(themeBundleId) ? $r('app.color.theme_paper_cover_label') : '#AA493E35';
  }

  static edgeColor(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.isPaper(themeBundleId) ? $r('app.color.theme_paper_text_secondary') : AppTheme.TextSecondary;
  }
}
