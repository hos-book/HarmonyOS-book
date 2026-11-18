/** 本机通用偏好；由 PreferenceService 初始化并持久保存。 */
@ObservedV2
export class GeneralSettings {
  static readonly current: GeneralSettings = new GeneralSettings();
  @Trace historyEnabled: boolean = true;
  @Trace audioCacheWifiOnly: boolean = false;
  @Trace shelfCollectionOrder: string = '[]';
  @Trace shelfCollectionExpanded: boolean = true;
  @Trace searchRecommendations: boolean = true;
  @Trace showShelfSource: boolean = true;
  @Trace showAllShelfGroup: boolean = true;
  @Trace showUngroupedShelfGroup: boolean = true;
  @Trace hiddenShelfGroups: string = '[]';

  isShelfGroupVisible(group: string): boolean {
    const hidden: string[] = JSON.parse(this.hiddenShelfGroups);
    return !hidden.includes(group);
  }
  @Trace adaptiveHandedness: boolean = true;
  @Trace swipeSwitchTabs: boolean = true;
  /** -1 关闭，0 永久显示，正数为暂停后自动隐藏的分钟数。 */
  @Trace miniPlayerHideMinutes: number = 0;
  @Trace selectionMenuOrder: string = '';
  @Trace selectionMenuHidden: string = '';
  @Trace jianjianCompanionEnabled: boolean = false;
  @Trace jianjianNightCareEnabled: boolean = true;
}
