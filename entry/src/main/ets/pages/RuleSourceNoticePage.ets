import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct RuleSourceNoticePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;

  @Builder
  private section(title: Resource, body: Resource) {
    Column({ space: AppSpace.Sm }) {
      Text(title).fontSize(AppFont.BodyL).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).width('100%')
      Text(body).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        .lineHeight(25).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: AppSpace.Lg }) {
          Column({ space: AppSpace.Lg }) {
            Text($r('app.string.rule_source_notice_summary')).fontSize(AppFont.Body)
              .fontWeight(FontWeight.Medium).fontColor(AppColor.Brand).lineHeight(25).width('100%')
            this.section($r('app.string.rule_source_notice_scope_title'), $r('app.string.rule_source_notice_scope'))
            this.section($r('app.string.rule_source_notice_rights_title'), $r('app.string.rule_source_notice_rights'))
            this.section($r('app.string.rule_source_notice_privacy_title'), $r('app.string.rule_source_notice_privacy'))
            this.section($r('app.string.rule_source_notice_security_title'), $r('app.string.rule_source_notice_security'))
            this.section($r('app.string.rule_source_notice_cost_title'), $r('app.string.rule_source_notice_cost'))
            this.section($r('app.string.rule_source_notice_responsibility_title'),
              $r('app.string.rule_source_notice_responsibility'))
            this.section($r('app.string.rule_source_notice_exit_title'), $r('app.string.rule_source_notice_exit'))
          }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Lg)
            .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
        }.width('100%').constraintSize({ maxWidth: 760 })
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: this.headerHeight + AppSpace.Sm,
            bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      }.width('100%').height('100%').scrollBar(BarState.Off)
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.rule_source_notice_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
