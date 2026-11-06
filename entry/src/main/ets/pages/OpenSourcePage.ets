import { AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

class NoticeSection {
  id: string;
  title: ResourceStr;
  paragraphs: ResourceStr[];

  constructor(id: string, title: ResourceStr, paragraphs: ResourceStr[]) {
    this.id = id;
    this.title = title;
    this.paragraphs = paragraphs;
  }
}

/** 开源声明:与仓库 THIRD_PARTY_NOTICES.md 保持一致,只声明实际引入的开源组件和许可边界。 */
const NOTICE_SECTIONS: NoticeSection[] = [
  new NoticeSection('components', $r('app.string.open_source_section_components'), [
    $r('app.string.open_source_quickjs'), $r('app.string.open_source_binding'),
    $r('app.string.open_source_napi'), $r('app.string.open_source_crypto'), $r('app.string.open_source_acefile'),
    $r('app.string.open_source_petrel')
  ]),
  new NoticeSection('boundary', $r('app.string.open_source_section_boundary'), [
    $r('app.string.open_source_boundary_body')
  ]),
  new NoticeSection('execution', $r('app.string.open_source_section_execution'), [
    $r('app.string.open_source_execution_body')
  ]),
  new NoticeSection('license', $r('app.string.open_source_section_license'), [
    $r('app.string.open_source_license_body')
  ])
];

@ComponentV2
export struct OpenSourcePage {
  @Param navStack: NavPathStack = new NavPathStack();

  build() {
    Column() {
      this.buildHeader()

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          ForEach(NOTICE_SECTIONS, (sec: NoticeSection) => {
            Column({ space: AppSpace.Sm }) {
              Text(sec.title)
                .fontSize(AppFont.BodyL)
                .fontColor($r('sys.color.font_primary'))
                .fontWeight(FontWeight.Bold)
                .width('100%')

              ForEach(sec.paragraphs, (p: ResourceStr) => {
                Text(p)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary'))
                  .lineHeight(22)
                  .width('100%')
              }, (p: ResourceStr, index: number) => `${sec.id}-${index}`)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
          }, (sec: NoticeSection) => sec.id)
        }
        .width('100%')
        .padding({ bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Text($r('app.string.about_open_source'))
        .fontSize(AppFont.Title)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .margin({ left: AppSpace.Sm })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
    })
  }
}
