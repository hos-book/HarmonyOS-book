import { emitter } from '@kit.BasicServicesKit';
import { MembershipState } from '../model/MembershipState';
import { CoverSuperResolutionService } from '../service/CoverSuperResolutionService';
import { EVT_COVER_SUPER_RESOLUTION_CHANGED } from '../service/PreferenceService';

/** 原图始终由父组件保留；处理成功后才叠加增强图。 */
@ComponentV2
export struct EnhancedPlayerCover {
  @Param url: string = '';
  @Local enhanced: string = '';
  @Local displayed: string = '';
  @Local membership: MembershipState = MembershipState.current;
  private generation: number = 0;
  private alive: boolean = false;
  private preferenceChanged = (): void => { this.refresh(); };

  aboutToAppear(): void {
    this.alive = true;
    emitter.on(EVT_COVER_SUPER_RESOLUTION_CHANGED, this.preferenceChanged);
    this.refresh();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    emitter.off(EVT_COVER_SUPER_RESOLUTION_CHANGED, this.preferenceChanged);
  }

  @Monitor('url')
  onUrlChanged(): void { this.refresh(); }

  private refresh(): void {
    const ticket = ++this.generation;
    this.enhanced = '';
    this.displayed = '';
    if (!this.alive) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    const active = (): boolean => this.alive && ticket === this.generation;
    CoverSuperResolutionService.enhance(context, this.url, active).then((uri: string): void => {
      if (active()) this.enhanced = uri;
    }).catch((): void => { /* 原图保留 */ });
  }

  build() {
    if (this.enhanced && this.membership.hasAccess) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        ForEach([this.enhanced], (uri: string) => {
          Image(uri)
            .width('100%').height('100%').objectFit(ImageFit.Cover)
            .draggable(false)
            .onComplete((event) => {
              if (this.alive && this.enhanced === uri && event?.loadingStatus === 1) this.displayed = uri;
            })
            .onError((): void => {
              if (this.enhanced === uri) {
                this.enhanced = '';
                this.displayed = '';
              }
            })
        }, (uri: string): string => uri)
        if (this.displayed === this.enhanced) {
          Text($r('app.string.player_cover_super_resolution_badge'))
            .fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .maxLines(1)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#99000000').borderRadius(6)
            .margin(8)
        }
      }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
    }
  }
}
