import { AppTheme } from '../theme/Theme';
import { ThemeIconRole, ThemeIcons } from '../theme/ThemeIcons';

/** 保留系统符号回退，让已有按钮的点击区域与无障碍语义保持原位。 */
@ComponentV2
export struct ThemeIconComponent {
  @Param role: ThemeIconRole = ThemeIconRole.None;
  @Param symbol: Resource = $r('sys.symbol.magnifyingglass');
  @Param iconSize: number = 24;
  @Param tint: ResourceColor = AppTheme.TextPrimary;

  build() {
    Stack() {
      if (AppTheme.isPaper && this.role !== ThemeIconRole.None) {
        Image(ThemeIcons.paper(this.role))
          .width(this.iconSize).height(this.iconSize).objectFit(ImageFit.Contain)
          .fillColor(this.tint)
      } else {
        SymbolGlyph(this.symbol).fontSize(this.iconSize).fontColor([this.tint])
      }
    }.width(this.iconSize).height(this.iconSize)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
