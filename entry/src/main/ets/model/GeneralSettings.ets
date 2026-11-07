/** 本机通用偏好；由 PreferenceService 初始化并持久保存。 */
@ObservedV2
export class GeneralSettings {
  static readonly current: GeneralSettings = new GeneralSettings();
  @Trace historyEnabled: boolean = true;
  @Trace searchRecommendations: boolean = true;
  @Trace showShelfSource: boolean = true;
  @Trace adaptiveHandedness: boolean = true;
  @Trace swipeSwitchTabs: boolean = true;
  /** 0 为永久显示，其余为暂停后自动隐藏的分钟数。 */
  @Trace miniPlayerHideMinutes: number = 0;
  @Trace jianjianCompanionEnabled: boolean = false;
  @Trace jianjianNightCareEnabled: boolean = true;
}
