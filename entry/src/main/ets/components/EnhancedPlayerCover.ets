import { emitter } from '@kit.BasicServicesKit';
import { MembershipState } from '../model/MembershipState';
import { CoverSuperResolutionService } from '../service/CoverSuperResolutionService';
import { EVT_COVER_SUPER_RESOLUTION_CHANGED } from '../service/PreferenceService';

/** 原图始终由父组件保留；处理成功后才叠加增强图。 */
@ComponentV2
export struct EnhancedPlayerCover {
  @Param url: string = '';
  @Local enhanced: string = '';
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
      Image(this.enhanced)
        .width('100%').height('100%').objectFit(ImageFit.Cover)
        .onError((): void => { this.enhanced = ''; })
        .hitTestBehavior(HitTestMode.None)
    }
  }
}
