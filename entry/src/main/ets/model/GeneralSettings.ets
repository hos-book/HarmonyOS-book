/** 本机通用偏好；由 PreferenceService 初始化并持久保存。 */
@ObservedV2
export class GeneralSettings {
  static readonly current: GeneralSettings = new GeneralSettings();
  @Trace historyEnabled: boolean = true;
  @Trace showShelfSource: boolean = true;
  @Trace adaptiveHandedness: boolean = true;
}
