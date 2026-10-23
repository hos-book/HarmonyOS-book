/** 主题图标按用途解析；页面无需绑定具体素材文件。 */
export enum ThemeIconRole {
  None,
  Search,
  Filter,
  Grid,
  List,
  ChevronRight,
  Home,
  Shelf,
  Record,
  Profile,
  Category
}

export class ThemeIcons {
  static paper(role: ThemeIconRole): Resource {
    switch (role) {
      case ThemeIconRole.Search: return $r('app.media.theme_paper_search');
      case ThemeIconRole.Filter: return $r('app.media.theme_paper_filter');
      case ThemeIconRole.Grid: return $r('app.media.theme_paper_grid');
      case ThemeIconRole.List: return $r('app.media.theme_paper_list');
      case ThemeIconRole.ChevronRight: return $r('app.media.theme_paper_chevron_right');
      case ThemeIconRole.Home: return $r('app.media.theme_paper_home');
      case ThemeIconRole.Shelf: return $r('app.media.theme_paper_shelf');
      case ThemeIconRole.Record: return $r('app.media.theme_paper_record');
      case ThemeIconRole.Profile: return $r('app.media.theme_paper_profile');
      default: return $r('app.media.theme_paper_category');
    }
  }
}
