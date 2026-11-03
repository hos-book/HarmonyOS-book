import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import lazy { floatView } from '@kit.ArkUI';
import { PlatformCompat } from '../../utils/PlatformCompat';

@ObservedV2
export class ReaderFloatingState {
  @Trace visible: boolean = false;
  @Trace native: boolean = false;
  @Trace starting: boolean = false;
  @Trace title: string = '';
  @Trace paragraph: string = '';
  @Trace speech: boolean = false;
}

/** 由用户打开；后台朗读仅更新文本，不重复建窗、不自动申请权限。 */
export class ReaderFloatingService {
  static readonly state: ReaderFloatingState = new ReaderFloatingState();
  private static controller: floatView.FloatViewController | null = null;
  private static readonly changed = (info: floatView.FloatViewStateChangeInfo): void => {
    if (info.state === floatView.FloatViewState.STARTED) {
      ReaderFloatingService.state.visible = true;
      ReaderFloatingService.state.native = true;
      ReaderFloatingService.state.starting = false;
    } else if (info.state === floatView.FloatViewState.STOPPED) {
      ReaderFloatingService.state.visible = false;
      ReaderFloatingService.state.native = false;
      ReaderFloatingService.state.starting = false;
      ReaderFloatingService.detach();
    }
  };

  static update(title: string, content: string, offset: number, speech: boolean): void {
    const state = ReaderFloatingService.state;
    if (!state.visible && !state.starting) return;
    if (state.speech && !speech) return;
    const position = Math.max(0, Math.min(content.length, offset));
    const start = content.lastIndexOf('\n', Math.max(0, position - 1)) + 1;
    const end = content.indexOf('\n', position);
    state.title = title;
    state.paragraph = content.substring(start, end < 0 ? content.length : end).trim().slice(0, 4000);
  }

  static async open(context: common.UIAbilityContext, title: string, content: string,
    offset: number, speech: boolean): Promise<boolean> {
    if (ReaderFloatingService.state.starting) return true;
    ReaderFloatingService.state.speech = speech;
    ReaderFloatingService.state.starting = true;
    ReaderFloatingService.update(title, content, offset, speech);
    if (ReaderFloatingService.state.visible) { ReaderFloatingService.state.starting = false; return true; }
    try {
      if (!PlatformCompat.supports(26) || !canIUse('SystemCapability.Window.SessionManager') || !floatView.isFloatViewEnabled()) {
        ReaderFloatingService.state.visible = true;
        ReaderFloatingService.state.native = false;
        ReaderFloatingService.state.starting = false;
        return true;
      }
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.FLOAT_VIEW']);
      if (result.authResults.length !== 1 || result.authResults[0] !== 0) {
        ReaderFloatingService.state.starting = false;
        ReaderFloatingService.state.native = false;
        ReaderFloatingService.state.visible = true;
        return true;
      }
      const controller = await floatView.create({ context: context, templateType: floatView.FloatViewTemplateType.HORIZONTAL_BAR });
      ReaderFloatingService.controller = controller;
      controller.onStateChange(ReaderFloatingService.changed);
      await controller.setUIContext('pages/ReaderFloatingPage');
      await controller.start();
      return true;
    } catch (_error) {
      ReaderFloatingService.detach();
      ReaderFloatingService.state.starting = false;
      ReaderFloatingService.state.native = false;
      ReaderFloatingService.state.visible = true;
      return true;
    }
  }

  private static detach(): void {
    const controller = ReaderFloatingService.controller;
    ReaderFloatingService.controller = null;
    try { controller?.offStateChange(ReaderFloatingService.changed); } catch (_error) { /* 已销毁窗口。 */ }
  }

  static async close(): Promise<void> {
    const controller = ReaderFloatingService.controller;
    try { await controller?.stop(); } catch (_error) { /* 系统已关闭窗口。 */ }
    ReaderFloatingService.detach();
    ReaderFloatingService.state.visible = false;
    ReaderFloatingService.state.native = false;
    ReaderFloatingService.state.starting = false;
  }
}
