import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { SupportOrbitComponent } from '../components/SupportOrbitComponent';
import { AppColor, AppCurve, AppTheme } from '../theme/Theme';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { WindowUtils } from '../utils/WindowUtils';

class SupportCredit {
  name: string = '';
  sponsor: boolean = false;
  featured: boolean = false;
  message: ResourceStr = '';

  constructor(name: string, sponsor: boolean, featured: boolean, message: ResourceStr) {
    this.name = name;
    this.sponsor = sponsor;
    this.featured = featured;
    this.message = message;
  }
}

/** 每张卡片独立持有按压和一次性入场状态，避免刷新整份名单。 */
@ComponentV2
struct SupportCreditCard {
  @Require @Param credit: SupportCredit;
  @Param order: number = 0;
  @Event onSelect: (credit: SupportCredit) => void = (_credit: SupportCredit): void => {};
  @Local entrance: number = 0;
  @Local pressScale: number = 1;
  private appeared: boolean = false;

  private reveal(visible: boolean): void {
    if (!visible || this.appeared) return;
    this.appeared = true;
    this.getUIContext().animateTo({ duration: 480,
      delay: (this.order % 6) * 45, curve: AppCurve.Decelerate }, (): void => {
      this.entrance = 1;
    });
  }

  private press(down: boolean): void {
    this.getUIContext().animateTo({ duration: 220,
      curve: AppCurve.Spring }, (): void => {
      this.pressScale = down ? 0.94 : 1;
    });
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: this.credit.featured ? 12 : 8 }) {
        Stack() {
          if (this.credit.featured) {
            Row().borderRadius(999).width(40).height(40).backgroundColor('#1AE8C782')
              .border({ width: 1, color: '#45E8C782' })
          }
          SymbolGlyph(this.credit.sponsor ? $r('sys.symbol.heart_fill') : $r('sys.symbol.star_fill'))
            .fontSize(this.credit.featured ? 19 : 12)
            .fontColor([this.credit.featured ? '#F3D59A' :
              this.credit.sponsor ? $r('app.color.sponsor_gold') : AppColor.Brand])
        }
        Column({ space: 4 }) {
          Text(this.credit.name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.credit.featured ? '#F7DEAB' :
              this.credit.sponsor ? $r('app.color.sponsor_gold') : AppTheme.TextPrimary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.credit.featured) {
            Text(this.credit.sponsor ? $r('app.string.support_featured_sponsor') :
              $r('app.string.support_featured_technical'))
              .fontSize(11).fontColor('#BFB5A3')
          }
        }.alignItems(HorizontalAlign.Start).flexShrink(1)
        if (this.credit.featured) {
          Blank()
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(17).fontColor(['#E8C782'])
        }
      }
      .padding(this.credit.featured ? 18 : { left: 13, right: 13, top: 12, bottom: 12 })
      .constraintSize({ minHeight: this.credit.featured ? 80 : 48 })
      .width(this.credit.featured ? '100%' : undefined)
    }
    .id('support_credit_' + this.credit.name)
    .width(this.credit.featured ? '100%' : undefined)
    .constraintSize({ maxWidth: '100%' })
    .backgroundColor(this.credit.featured ? '#191E23' :
      this.credit.sponsor ? $r('app.color.sponsor_gold_surface') : AppColor.BrandSoft)
    .linearGradient({ angle: 120, colors: this.credit.featured ?
      [['#263136', 0], ['#181C22', 0.55], ['#373022', 1]] : [['#00FFFFFF', 0], ['#08FFFFFF', 1]] })
    .border({ width: 0.8, color: this.credit.featured ? '#66B99A60' :
      this.credit.sponsor ? '#28BD944D' : AppColor.GlassStroke })
    .borderRadius(this.credit.featured ? 22 : 16)
    .clip(true)
    .renderGroup(true)
    .opacity(this.entrance)
    .translate({ y: (1 - this.entrance) * 18 })
    .scale({ x: this.pressScale, y: this.pressScale })
    .accessibilityText($r('app.string.support_open_thanks', this.credit.name))
    .onVisibleAreaChange([0, 1], (visible: boolean): void => { this.reveal(visible); })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) this.press(true);
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.type === TouchType.Move) {
        this.press(false);
      }
    })
    .onClick((): void => { this.press(false); this.onSelect(this.credit); })
  }
}

@ComponentV2
export struct TechnicalSupportPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local technicalCredits: SupportCredit[] = [];
  @Local sponsorCredits: SupportCredit[] = [];
  @Local selectedCredit: SupportCredit = new SupportCredit('', false, false, '');
  @Local foreground: boolean = true;
  @Local pageVisible: boolean = false;
  @Local dialogOpen: boolean = false;
  @Local heroEntrance: number = 0;
  @Local pageWidth: number = 0;
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 64;
  private context: common.Context | undefined = undefined;
  private attached: boolean = false;
  private dialogId: number = -1;
  private dialogGeneration: number = 0;
  private heroAppeared: boolean = false;
  // 按姓名关联专属文案，名单调整顺序时仍对应同一封信。
  private readonly creditMessages: Map<string, Resource> = new Map<string, Resource>([
    ['QG', $r('app.string.support_thanks_qg')],
    ['浅度', $r('app.string.support_thanks_qiandu')],
    ['相思界', $r('app.string.support_thanks_xiangsijie')],
    ['XIAOBAO', $r('app.string.support_thanks_xiaobao')],
    ['三三', $r('app.string.support_thanks_sansan')],
    ['WT', $r('app.string.support_thanks_wt')],
    ['子阳', $r('app.string.support_thanks_ziyang')],
    ['default', $r('app.string.support_thanks_default')],
    ['干脆面不用泡', $r('app.string.support_thanks_gancuimian')],
    ['苏小锋', $r('app.string.support_thanks_suxiaofeng')],
    ['张', $r('app.string.support_thanks_zhang')],
    ['李富贵', $r('app.string.support_thanks_lifugui')],
    ['最初未来', $r('app.string.support_thanks_zuichuweilai')],
    ['潮生万象', $r('app.string.support_thanks_chaoshengwanxiang')],
    ['向钱看向厚看', $r('app.string.support_thanks_xiangqiankan')],
    ['HAOYUN', $r('app.string.support_thanks_haoyun')],
    ['*.', $r('app.string.support_thanks_star_dot')],
    ['一飞冲天', $r('app.string.support_thanks_yifeichongtian')],
    ['L.', $r('app.string.support_thanks_l_dot')],
    ['再见', $r('app.string.support_thanks_zaijian')],
    ['柏子', $r('app.string.support_thanks_baizi')],
    ['爱你806', $r('app.string.support_thanks_aini806')],
    ['*城', $r('app.string.support_thanks_star_city')],
    ['我有点紧张', $r('app.string.support_thanks_woyoudianjinzhang')]
  ]);
  private applicationState: ApplicationStateChangeCallback = {
    onApplicationForeground: (): void => { this.foreground = true; },
    onApplicationBackground: (): void => { this.foreground = false; }
  };

  aboutToAppear(): void {
    this.attached = true;
    this.context = this.getUIContext().getHostContext();
    const resources = this.context?.resourceManager;
    if (resources) {
      this.technicalCredits = [new SupportCredit(
        resources.getStringSync($r('app.string.technical_support_light_page').id), false, true,
        $r('app.string.support_thanks_light_page'))];
      const technicalNames: string[] = resources.getStringSync($r('app.string.technical_support_names').id)
        .split('\n').map((name: string): string => name.trim()).filter((name: string): boolean => name.length > 0);
      technicalNames.forEach((name: string): void => {
        this.technicalCredits.push(new SupportCredit(name, false, false,
          this.creditMessages.get(name) ?? $r('app.string.support_thanks_everyone')));
      });
      this.sponsorCredits = [new SupportCredit(
        resources.getStringSync($r('app.string.sponsor_thanks_hendo').id), true, true,
        $r('app.string.support_thanks_hendo'))];
      const sponsorNames: string[] = resources.getStringSync($r('app.string.sponsor_thanks_names').id)
        .split('\n').map((name: string): string => name.trim()).filter((name: string): boolean => name.length > 0);
      sponsorNames.forEach((name: string): void => {
        this.sponsorCredits.push(new SupportCredit(name, true, false,
          this.creditMessages.get(name) ?? $r('app.string.support_thanks_everyone')));
      });
    }
    try { this.context?.getApplicationContext().on('applicationStateChange', this.applicationState); } catch (_error) {}
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.closeThanks();
    try { this.context?.getApplicationContext().off('applicationStateChange', this.applicationState); } catch (_error) {}
  }

  private revealHero(): void {
    if (this.heroAppeared) return;
    this.heroAppeared = true;
    this.getUIContext().animateTo({ duration: 760,
      curve: AppCurve.Decelerate }, (): void => { this.heroEntrance = 1; });
  }

  private async openThanks(credit: SupportCredit): Promise<void> {
    if (!this.attached || this.dialogOpen) return;
    this.selectedCredit = credit;
    this.dialogOpen = true;
    const generation: number = ++this.dialogGeneration;
    const prompt = this.getUIContext().getPromptAction();
    const options: promptAction.CustomDialogOptions = {
      builder: (): void => { this.thanksDialog(); },
      alignment: DialogAlignment.Center,
      width: '90%',
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      cornerRadius: 30,
      autoCancel: true,
      maskColor: '#99070F15',
      dialogTransition: TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.86, y: 0.86 }))
        .combine(TransitionEffect.translate({ y: 24 }))
        .animation({ duration: 420, curve: AppCurve.SpringSoft }),
      maskTransition: TransitionEffect.OPACITY.animation({ duration: 220 }),
      onDidDisappear: (): void => {
        if (generation !== this.dialogGeneration) return;
        this.dialogId = -1;
        this.dialogOpen = false;
      }
    };
    try {
      const id: number = await prompt.openCustomDialog(options);
      if (this.attached && this.dialogOpen && generation === this.dialogGeneration) this.dialogId = id;
      else prompt.closeCustomDialog(id);
    } catch (_error) {
      if (generation !== this.dialogGeneration) return;
      this.dialogOpen = false;
      if (this.attached) {
        this.getUIContext().showAlertDialog({ title: credit.name, message: credit.message,
          confirm: { value: $r('app.string.support_thanks_close'), action: (): void => {} } });
      }
    }
  }

  private closeThanks(): void {
    this.dialogOpen = false;
    if (this.dialogId < 0) return;
    const id: number = this.dialogId;
    this.dialogId = -1;
    try { this.getUIContext().getPromptAction().closeCustomDialog(id); } catch (_error) {}
  }

  @Builder
  thanksDialog() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          SupportOrbitComponent({ running: this.foreground && this.dialogOpen,
            golden: this.selectedCredit.sponsor || this.selectedCredit.featured, compact: true })
        }.width('100%').padding({ top: 12 })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor(['#DFE9E7'])
        }.width(44).height(44).backgroundColor('#12FFFFFF').margin(12)
          .accessibilityText($r('app.string.common_close'))
          .onClick((): void => { this.closeThanks(); })
      }.width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text($r('app.string.support_thanks_kicker')).fontSize(10).letterSpacing(3).fontColor('#A7C7BD')
          Text(this.selectedCredit.name).fontSize(28).fontWeight(FontWeight.Bold)
            .fontColor('#F5DEAC').textAlign(TextAlign.Center).width('100%')
          Text($r('app.string.support_thanks_heading')).fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor('#EFF6F2').textAlign(TextAlign.Center)
          Text(this.selectedCredit.message).fontSize(15).lineHeight(26).fontColor('#CBD8D3')
            .textAlign(TextAlign.Center).width('100%')
          Row({ space: 12 }) {
            Divider().width(30).color('#506A6D')
            SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(11).fontColor(['#D6B67B'])
            Divider().width(30).color('#506A6D')
          }.margin({ top: 6, bottom: 4 })
          Text($r('app.string.support_thanks_signature')).fontSize(12).fontColor('#9CB2AC')
        }.width('100%').padding({ left: 26, right: 26, bottom: 20 })
      }.width('100%').constraintSize({ maxHeight: '42%' }).scrollBar(BarState.Off)
      Button($r('app.string.support_thanks_close'), { type: ButtonType.Capsule })
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#203029')
        .backgroundColor('#E8D6AB').height(48).width('82%').margin({ top: 4, bottom: 26 })
        .defaultFocus(true).onClick((): void => { this.closeThanks(); })
    }
    .width('100%').constraintSize({ maxWidth: 420 })
    .linearGradient({ angle: 150, colors: [['#203938', 0], ['#142126', 0.45], ['#252522', 1]] })
    .border({ width: 1, color: '#668B9D87' }).borderRadius(30).clip(true)
    .shadow({ radius: 36, color: '#55000000', offsetY: 16 })
  }

  @Builder
  hero() {
    Column({ space: 10 }) {
      Text($r('app.string.support_hero_kicker')).fontSize(10).letterSpacing(4).fontColor('#B0D7CC')
      SupportOrbitComponent({ running: this.foreground && this.pageVisible && !this.dialogOpen })
      Text($r('app.string.support_intro_title')).fontSize(30).fontWeight(FontWeight.Bold)
        .fontColor('#F2F7EF').textAlign(TextAlign.Center).lineHeight(40)
      Text($r('app.string.support_intro_body')).fontSize(13).lineHeight(22)
        .fontColor('#AFC6BF').textAlign(TextAlign.Center).constraintSize({ maxWidth: 310 })
      Row({ space: 7 }) {
        Row().borderRadius(999).width(4).height(4).backgroundColor('#E3C587')
        Text($r('app.string.support_touch_hint')).fontSize(11).fontColor('#DAC89F')
      }.margin({ top: 10 })
    }
    .width('100%').padding({ left: 24, right: 24, top: 28, bottom: 28 })
    .linearGradient({ angle: 155, colors: [['#203C3B', 0], ['#111E27', 0.5], ['#292B27', 1]] })
    .border({ width: 1, color: '#42627C71' }).borderRadius(30).clip(true)
    .opacity(this.heroEntrance).translate({ y: 20 * (1 - this.heroEntrance) })
    .onVisibleAreaChange([0, 1], (visible: boolean): void => { if (visible) this.revealHero(); })
  }

  @Builder
  section(sponsor: boolean) {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        SymbolGlyph(sponsor ? $r('sys.symbol.heart_fill') : $r('sys.symbol.star_fill'))
          .fontSize(19).fontColor([sponsor ? $r('app.color.sponsor_gold') : AppColor.Brand])
        Text(sponsor ? $r('app.string.sponsor_thanks_title') : $r('app.string.technical_support_title'))
          .fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Text($r('app.string.support_order_note')).fontSize(10).fontColor(AppTheme.TextTertiary)
      }.width('100%')
      Text(sponsor ? $r('app.string.support_sponsor_subtitle') : $r('app.string.support_technical_subtitle'))
        .fontSize(12).lineHeight(19).fontColor(AppTheme.TextSecondary).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(sponsor ? this.sponsorCredits : this.technicalCredits, (credit: SupportCredit, index: number) => {
          SupportCreditCard({ credit: credit, order: index,
            onSelect: (selected: SupportCredit): void => { this.openThanks(selected); } })
            .width(credit.featured ? '100%' : undefined)
            .margin({ right: credit.featured ? 0 : 8, bottom: 10 })
        }, (credit: SupportCredit): string => credit.name)
      }.width('100%')
    }
    .width('100%').padding(20).alignItems(HorizontalAlign.Start)
    .backgroundColor(AppTheme.Surface)
    .border({ width: 0.8, color: AppColor.GlassStroke }).borderRadius(26)
  }

  @Builder
  header() {
    FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(48).height(48).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.about_technical_support')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)

      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + 8, left: 8, right: 20, bottom: 8 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 20 }) {
          this.hero()
          GridRow({ columns: this.pageWidth >= AdaptiveLayout.LARGE_WIDTH ? 2 : 1,
            gutter: { x: 20, y: 20 } }) {
            GridCol() { this.section(false) }
            GridCol() { this.section(true) }
          }.width('100%')
          Button({ type: ButtonType.Normal }) {
            Column({ space: 10 }) {
              Text($r('app.string.support_everyone_title')).fontSize(17).fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TextPrimary)
              Text($r('app.string.support_everyone_hint')).fontSize(12).lineHeight(20)
                .fontColor(AppTheme.TextSecondary).textAlign(TextAlign.Center)
              Row({ space: 6 }) {
                Text($r('app.string.support_everyone_action')).fontSize(12).fontColor(AppColor.Brand)
                SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(12).fontColor([AppColor.Brand])
              }
            }.width('100%').padding({ top: 20, bottom: 24, left: 12, right: 12 })
          }.width('100%').backgroundColor(Color.Transparent).borderRadius(24)
            .onClick((): void => {
              this.openThanks(new SupportCredit(
                this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.support_everyone_name').id) ?? '',
                false, false, $r('app.string.support_thanks_everyone')));
            })
        }
        .width('100%').constraintSize({ maxWidth: 1000 })
        .padding({ top: this.headerHeight + 12, left: 20, right: 20,
          bottom: WindowUtils.getBottomSafeVp() + 24 })
      }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      this.header()
    }
    .width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
      const measured: number = Number(newSize.width);
      if (measured > 0) this.pageWidth = measured;
    })
    .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number): void => {
      this.pageVisible = visible && ratio > 0;
    })
  }
}
