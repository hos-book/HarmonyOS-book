import { emitter } from '@kit.BasicServicesKit';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleControl, LocalRulePanel, LocalRulePanelAction } from '../../model/LocalRulePanel';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { SourceDataService } from '../SourceDataService';
import { EVT_HOME_SOURCE_CHANGED } from '../PreferenceService';
import { LightSourceBridge } from './light/LightSourceBridge';

export class LocalRulePanelService {
  static async load(source: LocalRuleSource, login: boolean,
    _variables: Record<string, string> = {}): Promise<LocalRulePanel> {
    if (!source.canExecute()) throw new Error('此书源格式已停用，请导入轻页支持的定义');
    return LightSourceBridge.panel(source, login);
  }
  static async act(source: LocalRuleSource, control: LocalRuleControl,
    controls: LocalRuleControl[], _login: boolean): Promise<LocalRulePanelAction> {
    const result = await LightSourceBridge.panelAction(source, control, controls);
    if (result.refresh) {
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
      emitter.emit(EVT_HOME_SOURCE_CHANGED);
    }
    return result;
  }
  static async options(source: LocalRuleSource, control: LocalRuleControl): Promise<string[]> {
    return LightSourceBridge.panelOptions(source, control.id);
  }
  static async checkLogin(source: LocalRuleSource, content: string,
    _variables: Record<string, string> = {}, baseUrl: string = source.bookSourceUrl): Promise<void> {
    if (!await LightSourceBridge.checkLogin(source, content, baseUrl)) {
      await LocalRuleSourceRepository.expireLogin(source.bookSourceUrl);
      throw new Error('书源登录未通过声明的检查');
    }
    await LocalRuleSourceRepository.setLoginStatus(source.bookSourceUrl, 'valid');
    SourceDataService.invalidateLocalSources(source.bookSourceUrl);
    emitter.emit(EVT_HOME_SOURCE_CHANGED);
  }
}
