import { SourceTestTaskService } from '../service/rulesource/SourceTestTaskService';
import { BusinessError } from '@kit.BasicServicesKit';
import { MembershipState } from '../model/MembershipState';
import { fileIo, picker } from '@kit.CoreFileKit';
import { RuleSourceImportQueue } from '../service/rulesource/RuleSourceImportQueue';
import lazy { scanBarcode, scanCore } from '@kit.ScanKit';
import { LocalRuleSource, LocalRuleSourceStatus, LocalRuleSourceType } from '../model/LocalRuleSource';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { BookSourceService } from '../service/BookSourceService';
import {
  LocalRuleSourceRemoteImporter, RuleSourceRemoteImportError, RuleSourceRemoteImportFailure
} from '../service/rulesource/LocalRuleSourceRemoteImporter';
import { LocalRuleSourceImportParser } from '../service/rulesource/LocalRuleSourceImportParser';
import { LocalRuleSourceImportService } from '../service/rulesource/LocalRuleSourceImportService';
import { LocalRuleSourceFileImporter, RuleSourceFileImportResult } from '../service/rulesource/LocalRuleSourceFileImporter';
import {
  LocalRuleSourceBulkTester,
  LocalRuleSourceBulkTestProgress,
  LocalRuleSourceBulkTestReport
} from '../service/rulesource/LocalRuleSourceBulkTester';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleSourceCodec } from '../service/rulesource/LocalRuleSourceCodec';
import { LocalRuleTlsTrustStore } from '../service/rulesource/LocalRuleTlsTrustStore';
import { LightSourceCookies as LocalRuleHttpClient } from '../service/rulesource/light/LightSourceCookies';
import {
  RuleSourceAccountService,
  RuleSourceAccountState
} from '../service/rulesource/RuleSourceAccountService';
import { RuleSourceChildService } from '../service/rulesource/RuleSourceChildService';
import { SourceDataService } from '../service/SourceDataService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { CharsetCodec } from '../utils/CharsetCodec';
import { WindowUtils } from '../utils/WindowUtils';
import { promptAction } from '@kit.ArkUI';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { TalebookConnectComponent } from '../components/TalebookConnectComponent';
import { TalebookSourceIdentity } from '../service/rulesource/talebook/TalebookSourceIdentity';

interface RuleSourceEditParams {
  sourceUrl: string;
}

interface RuleSourceDebugParams {
  sourceUrl: string;
}

const RULE_SOURCE_SUCCESS: string = '#168A5B';
const RULE_SOURCE_DANGER: string = '#D03050';
const RULE_SOURCE_DANGER_SOFT: string = '#14D03050';
const RULE_SOURCE_WARNING: string = '#9A6700';
const RULE_SOURCE_IMPORT_MAX_LENGTH: number = 10 * 1024 * 1024;
const RULE_SOURCE_TEST_KEYWORD: string = '我的';
const RULE_SOURCE_MIN_BOTTOM_INSET: number = 28;

@ObservedV2
class RuleSourceListItem {
  readonly sourceUrl: string;
  @Trace source: LocalRuleSource;
  @Trace index: number;

  constructor(source: LocalRuleSource, index: number) {
    this.sourceUrl = source.bookSourceUrl;
    this.source = source;
    this.index = index;
  }
}

class RuleSourceDataSource implements IDataSource {
  private sources: RuleSourceListItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.sources.length;
  }

  getData(index: number): RuleSourceListItem {
    return this.sources[index];
  }

  setSources(sources: LocalRuleSource[]): void {
    // LazyForEach 会复用同一 URL 的节点；必须更新它正在观察的条目，不能只替换数组。
    const previous: Map<string, RuleSourceListItem> = new Map();
    for (const item of this.sources) previous.set(item.sourceUrl, item);
    this.sources = sources.map((source: LocalRuleSource, index: number): RuleSourceListItem => {
      const item = previous.get(source.bookSourceUrl);
      if (item === undefined) return new RuleSourceListItem(source, index);
      item.source = source;
      item.index = index;
      return item;
    });
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

@ComponentV2
export struct RuleSourcePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local externalImports: RuleSourceImportQueue = RuleSourceImportQueue.getInstance();
  private pageAttached: boolean = false;
  @Local importJson: string = '';
  @Local searchKeyword: string = '';
  @Local sourceCount: number = 0;
  @Local filteredSourceCount: number = 0;
  @Local isLoading: boolean = true;
  @Local isImporting: boolean = false;
  @Local importFileCurrent: number = 0;
  @Local importFileTotal: number = 0;
  @Local fileImportResult: RuleSourceFileImportResult = new RuleSourceFileImportResult();
  @Local hasFileImportResult: boolean = false;
  @Local isBulkTesting: boolean = false;
  @Local isEditMode: boolean = false;
  @Local showImportPanel: boolean = false;
  @Local expandedSourceUrls: Set<string> = new Set();
  @Local showTalebook: boolean = false;
  @Local talebookSourceUrl: string = '';
  @Local selectedSourceCount: number = 0;
  @Local selectionRevision: number = 0;
  @Local bulkTestTotal: number = 0;
  @Local bulkTestCompleted: number = 0;
  @Local bulkTestPassed: number = 0;
  @Local bulkTestFailed: number = 0;
  @Local bulkTestRetained: number = 0;
  @Local loadFailed: boolean = false;
  @Local sourceKeyUnavailable: boolean = false;
  @Local busySourceUrl: string = '';
  @Local managementView: string = '';
  @Local sourceGroups: string[] = [];
  @Local selectedGroup: string = '';
  @Local statusFilter: number = 0;
  @Local contentFilter: number = 0;
  @Local sortMode: number = 0;
  @Local groupDraft: string = '';
  @Local editingGroup: string = '';
  @Local testMode: string = 'search';
  @Local testScope: number = 0;
  @Local testKeyword: string = RULE_SOURCE_TEST_KEYWORD;
  @Local testFailures: LocalRuleSource[] = [];
  @Local testCancelled: boolean = false;
  @Local trustedHosts: string[] = [];
  @Local trustHostDraft: string = '';
  @Local dragSourceName: string = '';
  @Local orderCount: number = 0;
  @Local safeTop: number = WindowUtils.getStatusBarHeightVp();
  @Local safeBottom: number = WindowUtils.getBottomSafeVp();
  private orderDataSource: RuleSourceDataSource = new RuleSourceDataSource();
  private failureDataSource: RuleSourceDataSource = new RuleSourceDataSource();
  private orderedSources: LocalRuleSource[] = [];
  private activeTester: LocalRuleSourceBulkTester | undefined = undefined;
  private selectedSources: Set<string> = new Set();
  private changingSourceUrls: Set<string> = new Set();
  private dataSource: RuleSourceDataSource = new RuleSourceDataSource();
  private allSources: LocalRuleSource[] = [];
  @Local loginStatuses: Map<string, string> = new Map();
  private loginRevision: number = -1;

  private async refreshLoginStatuses(): Promise<void> {
    const revision = LocalRuleSourceRepository.getLoginRevision();
    const statuses = await LocalRuleSourceRepository.listLoginStatuses();
    for (const source of this.allSources) {
      if (RuleSourceAccountService.supports(source.bookSourceUrl)) {
        const state = await RuleSourceAccountService.getState(source.bookSourceUrl);
        if (state.loggedIn) statuses.set(source.bookSourceUrl, 'valid');
        else if (state.expired) statuses.set(source.bookSourceUrl, 'expired');
      }
    }
    this.loginStatuses = statuses;
    this.loginRevision = revision;
  }

  private sourceLoginLabel(source: LocalRuleSource): Resource {
    const status = this.loginStatuses.get(source.bookSourceUrl) ?? '';
    if (status === 'valid' || status === 'saved') return $r('app.string.source_login_valid');
    if (status === 'expired') return $r('app.string.source_login_expired');
    return $r('app.string.source_login_none');
  }
  private filteredSources: LocalRuleSource[] = [];
  private lastInvalidationCounter: number = 0;
  private refreshCheckTimer: number = -1;
  private loadRevision: number = 0;
  private safeAreaListener: (top: number, bottom: number) => void = (top: number, bottom: number): void => {
    this.safeTop = top;
    this.safeBottom = bottom;
  };

  aboutToAppear(): void {
    this.pageAttached = true;
    SourceTestTaskService.subscribe(this.testTaskHandler);
    this.syncTestTask();
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.lastInvalidationCounter = SourceDataService.getInvalidationCounter();
    this.loadSources();
    this.startRefreshCheck();
  }

  aboutToDisappear(): void {
    this.pageAttached = false;
    this.loadRevision++;
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.stopRefreshCheck();
    SourceTestTaskService.unsubscribe(this.testTaskHandler);
  }

  private startRefreshCheck(): void {
    this.refreshCheckTimer = setInterval(() => {
      // 手动导入/测试期间收到的文件保留排队，空闲且回到本页后继续。
      this.consumeExternalImports();
      if (this.loginRevision !== LocalRuleSourceRepository.getLoginRevision()) {
        this.refreshLoginStatuses().catch((): void => {});
      }
      const currentCounter = SourceDataService.getInvalidationCounter();
      if (currentCounter !== this.lastInvalidationCounter) {
        this.lastInvalidationCounter = currentCounter;
        this.refresh();
      }
    }, 1000);
  }

  private stopRefreshCheck(): void {
    if (this.refreshCheckTimer >= 0) {
      clearInterval(this.refreshCheckTimer);
      this.refreshCheckTimer = -1;
    }
  }

  refresh(): void {
    this.loadSources(false);
  }

  private async loadSources(showLoading: boolean = true): Promise<void> {
    const revision = ++this.loadRevision;
    const invalidationCounter = SourceDataService.getInvalidationCounter();
    if (showLoading) {
      this.isLoading = true;
    }
    try {
      const context = this.getUIContext().getHostContext();
      if (context) await LocalRuleSourceRepository.init(context);
      const sources = await LocalRuleSourceRepository.list();
      const groups = await LocalRuleSourceRepository.listGroups();
      if (revision !== this.loadRevision) return;
      this.allSources = sources;
      this.sourceGroups = groups;
      this.sourceCount = sources.length;
      this.applyFilters();
      if (this.managementView === 'order') this.refreshOrderSources();
      this.loadFailed = false;
      this.sourceKeyUnavailable = false;
      this.lastInvalidationCounter = invalidationCounter;
      this.refreshLoginStatuses().catch((): void => {});
    } catch (error) {
      if (revision !== this.loadRevision) return;
      const failure: BusinessError = error;
      this.sourceKeyUnavailable = failure.code === 14800020;
      console.error(`[RuleSourcePage] load failed: code=${failure.code}; message=${failure.message}`);
      this.sourceCount = 0;
      this.filteredSourceCount = 0;
      this.allSources = [];
      this.filteredSources = [];
      this.dataSource.setSources([]);
      this.loadFailed = true;
    } finally {
      if (revision === this.loadRevision) {
        this.isLoading = false;
        this.consumeExternalImports();
      }
    }
  }

  @Monitor('externalImports.revision')
  private onExternalImportRequested(): void {
    this.consumeExternalImports();
  }

  private async consumeExternalImports(): Promise<void> {
    const paths = this.navStack.getAllPathName();
    if (!this.pageAttached || this.isLoading || this.loadFailed || this.isImporting || this.isBulkTesting ||
      this.busySourceUrl.length > 0 || paths[paths.length - 1] !== 'ruleSources' ||
      !this.externalImports.hasPending()) return;
    if (!this.externalImports.tryBegin()) return;
    this.closeManagement();
    this.isEditMode = false;
    this.resetSelection();
    this.isImporting = true;
    this.showImportPanel = true;
    let allSucceeded = true;
    try {
      while (this.pageAttached && this.externalImports.hasPending()) {
        const uri = this.externalImports.take();
        if (uri === undefined) break;
        try {
          const content = await this.readLocalJson(uri);
          const imported = content !== undefined && await this.persistImportContent(content);
          if (!imported) allSucceeded = false;
        } catch (error) {
          allSucceeded = false;
          this.showImportError(error);
        }
      }
      if (allSucceeded) this.showImportPanel = false;
    } finally {
      this.isImporting = false;
      this.externalImports.finish();
    }
  }

  private applyFilters(): void {
    let filtered: LocalRuleSource[] = this.allSources.slice();

    // 搜索过滤
    if (this.searchKeyword.trim().length > 0) {
      const keyword = this.searchKeyword.trim().toLowerCase();
      filtered = filtered.filter((source: LocalRuleSource) => {
        return source.bookSourceName.toLowerCase().includes(keyword) ||
          source.bookSourceUrl.toLowerCase().includes(keyword) ||
          source.bookSourceGroup.toLowerCase().includes(keyword);
      });
    }

    if (this.selectedGroup.length > 0) {
      filtered = filtered.filter((source: LocalRuleSource) => this.selectedGroup === '__ungrouped__'
        ? this.sourceGroupLabels(source).length === 0 : this.sourceGroupLabels(source).includes(this.selectedGroup));
    }
    filtered = filtered.filter((source: LocalRuleSource): boolean => this.matchesStatus(source) &&
      (this.contentFilter === 0 || (this.contentFilter === 1 && source.isAudio()) ||
      (this.contentFilter === 2 && source.isText() && !source.isComic()) ||
      (this.contentFilter === 3 && source.isComic())));
    filtered.sort((left: LocalRuleSource, right: LocalRuleSource): number => {
      if (left.isPinned !== right.isPinned) return left.isPinned ? -1 : 1;
      if (this.sortMode === 1) return left.bookSourceName.localeCompare(right.bookSourceName);
      if (this.sortMode === 2) return right.lastUpdateTime - left.lastUpdateTime;
      if (this.sortMode === 3) return left.lastUpdateTime - right.lastUpdateTime;
      return left.customOrder - right.customOrder;
    });

    this.filteredSources = filtered;
    this.filteredSourceCount = filtered.length;
    this.dataSource.setSources(filtered);
  }

  private matchesStatus(source: LocalRuleSource): boolean {
    if (this.statusFilter === 1) return source.enabled;
    if (this.statusFilter === 2) return !source.enabled;
    if (this.statusFilter === 3) return source.enabledExplore;
    if (this.statusFilter === 4) return !source.enabledExplore;
    if (this.statusFilter === 5) return source.isLocked;
    if (this.statusFilter === 6) return source.validationStatus === LocalRuleSourceStatus.READY;
    if (this.statusFilter === 7) return source.validationStatus === LocalRuleSourceStatus.FAILED;
    if (this.statusFilter === 8) return source.validationStatus === LocalRuleSourceStatus.UNCHECKED;
    return true;
  }

  private statusFilterLabel(): ResourceStr {
    if (this.statusFilter === 1) return $r('app.string.source_manage_enabled');
    if (this.statusFilter === 2) return $r('app.string.source_manage_disabled');
    if (this.statusFilter === 3) return $r('app.string.source_manage_explore_enabled');
    if (this.statusFilter === 4) return $r('app.string.source_manage_explore_disabled');
    if (this.statusFilter === 5) return $r('app.string.source_manage_locked');
    if (this.statusFilter === 6) return $r('app.string.rule_source_status_ready');
    if (this.statusFilter === 7) return $r('app.string.rule_source_status_failed');
    if (this.statusFilter === 8) return $r('app.string.rule_source_status_unchecked');
    return $r('app.string.source_manage_all_status');
  }

  private testScopeLabel(): ResourceStr {
    if (this.testScope === 1) return $r('app.string.source_manage_test_visible');
    if (this.testScope === 2) return $r('app.string.source_manage_test_selected');
    return $r('app.string.source_manage_test_all');
  }

  private groupOptions(includeAll: boolean): SelectOption[] {
    const options: SelectOption[] = [];
    if (includeAll) options.push({ value: $r('app.string.source_manage_all_groups') });
    options.push({ value: $r('app.string.source_manage_ungrouped') });
    for (const name of this.sourceGroups) options.push({ value: name });
    return options;
  }

  private selectedGroupIndex(): number {
    if (this.selectedGroup.length === 0) return 0;
    if (this.selectedGroup === '__ungrouped__') return 1;
    return this.sourceGroups.indexOf(this.selectedGroup) + 2;
  }

  private currentGroupLabel(): ResourceStr {
    if (this.selectedGroup.length === 0) return $r('app.string.source_manage_all_groups');
    return this.selectedGroup === '__ungrouped__' ? $r('app.string.source_manage_ungrouped') : this.selectedGroup;
  }

  private managementTitle(): ResourceStr {
    if (this.managementView === 'homeSource') return $r('app.string.home_source_setting');
    if (this.managementView === 'groups') return $r('app.string.source_manage_groups');
    if (this.managementView === 'groupAssign') return $r('app.string.source_manage_group_assign');
    if (this.managementView === 'order') return $r('app.string.source_manage_order');
    if (this.managementView === 'test') return $r('app.string.source_manage_test_settings');
    if (this.managementView === 'tls') return $r('app.string.source_manage_tls');
    return $r('app.string.rule_source_title');
  }

  private closeManagement(): void {
    this.managementView = '';
    this.editingGroup = '';
    this.groupDraft = '';
  }

  /** 页内多级视图逐级返回：管理视图 → 编辑模式 → 导入面板，全部收起后才退出路由。 */
  private requestBack(): boolean {
    if (this.managementView.length > 0) {
      this.closeManagement();
      return true;
    }
    if (this.isEditMode) {
      this.toggleEditMode();
      return true;
    }
    if (this.showImportPanel) {
      this.showImportPanel = false;
      return true;
    }
    return false;
  }

  private async openManagement(view: string): Promise<void> {
    if (this.isImporting || this.busySourceUrl.length > 0) return;
    if (view === 'order') {
      this.refreshOrderSources();
    }
    if (view === 'tls') {
      try { this.trustedHosts = await LocalRuleTlsTrustStore.listTrustedHosts(); }
      catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); return; }
    }
    this.managementView = view;
  }

  private refreshOrderSources(): void {
    this.orderedSources = this.allSources.slice().sort((left: LocalRuleSource, right: LocalRuleSource): number => {
      if (left.isPinned !== right.isPinned) return left.isPinned ? -1 : 1;
      return left.customOrder - right.customOrder;
    });
    this.orderCount = this.orderedSources.length;
    this.orderDataSource.setSources(this.orderedSources);
  }

  private async runSelectedAction(action: string): Promise<void> {
    if (this.selectedSourceCount === 0 || this.busySourceUrl.length > 0 || this.isBulkTesting) return;
    if (action === 'group') { this.groupDraft = ''; this.managementView = 'groupAssign'; return; }
    if (action === 'export') { await this.exportSelectedSources(); return; }
    if (action === 'test') { this.testScope = 2; this.managementView = 'test'; return; }
    this.busySourceUrl = 'batch';
    try {
      const urls = this.selectedSourceUrls();
      let changed: number = 0;
      if (action === 'exploreOn' || action === 'exploreOff') {
        changed = await LocalRuleSourceRepository.setExploreEnabledBatch(urls, action === 'exploreOn');
      } else {
        changed = await LocalRuleSourceRepository.setLockedBatch(urls, action === 'lock');
      }
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.finishBatchEdit();
      this.showToast($r('app.string.source_manage_changed', changed));
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async exportSelectedSources(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.busySourceUrl = 'export';
    try {
      const urls = this.selectedSourceUrls();
      const sources = this.allSources.filter((source: LocalRuleSource) => urls.includes(source.bookSourceUrl));
      const text = LocalRuleSourceCodec.exportBatch(sources);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`book-sources-${Date.now()}.json`];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) return;
      const file = await fileIo.open(uris[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, text); }
      finally { await fileIo.close(file); }
      this.showToast($r('app.string.rule_source_export_saved'));
    } catch (_error) { this.showToast($r('app.string.rule_source_report_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async saveGroup(): Promise<void> {
    if (this.busySourceUrl.length > 0) return;
    const name = this.groupDraft.trim();
    if (name.length === 0 || (this.sourceGroups.includes(name) && name !== this.editingGroup)) {
      this.showToast($r('app.string.source_manage_group_exists')); return;
    }
    this.busySourceUrl = 'group';
    try {
      if (this.editingGroup.length > 0) {
        await LocalRuleSourceRepository.renameGroup(this.editingGroup, name);
        if (this.selectedGroup === this.editingGroup) this.selectedGroup = name;
      } else { await LocalRuleSourceRepository.createGroup(name); }
      this.groupDraft = ''; this.editingGroup = '';
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private groupSourceCount(name: string): number {
    return this.allSources.filter((source: LocalRuleSource) => this.sourceGroupLabels(source).includes(name)).length;
  }

  private confirmRemoveGroup(name: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.source_manage_group_remove'),
      message: $r('app.string.source_manage_group_remove_message', name),
      buttons: [
        { value: $r('app.string.common_cancel'), action: () => {} },
        { value: $r('app.string.rule_source_delete_action'), fontColor: RULE_SOURCE_DANGER,
          action: () => { this.removeGroup(name); } }
      ]
    });
  }

  private async removeGroup(name: string): Promise<void> {
    if (this.busySourceUrl.length > 0) return;
    this.busySourceUrl = 'group';
    try {
      await LocalRuleSourceRepository.deleteGroup(name);
      if (this.selectedGroup === name) this.selectedGroup = '';
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async clearEmptyGroups(): Promise<void> {
    if (this.busySourceUrl.length > 0) return;
    const empty = this.sourceGroups.filter((name: string) => this.groupSourceCount(name) === 0);
    if (empty.length === 0) { this.showToast($r('app.string.source_manage_group_no_empty')); return; }
    this.busySourceUrl = 'group';
    try {
      for (const name of empty) await LocalRuleSourceRepository.deleteGroup(name);
      await this.loadSources(false);
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async assignSelectedGroup(): Promise<void> {
    if (this.busySourceUrl.length > 0) return;
    this.busySourceUrl = 'group';
    try {
      const changed = await LocalRuleSourceRepository.setGroupBatch(this.selectedSourceUrls(), this.groupDraft.trim());
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.closeManagement(); this.finishBatchEdit();
      this.showToast($r('app.string.source_manage_changed', changed));
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async changeSourceFlag(source: LocalRuleSource, action: string): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isBulkTesting || this.isImporting) return;
    this.busySourceUrl = source.bookSourceUrl;
    try {
      if (action === 'pin') await LocalRuleSourceRepository.setPinned(source.bookSourceUrl, !source.isPinned);
      if (action === 'lock') await LocalRuleSourceRepository.setLockedBatch([source.bookSourceUrl], !source.isLocked);
      if (action === 'explore') {
        await LocalRuleSourceRepository.setExploreEnabledBatch([source.bookSourceUrl], !source.enabledExplore);
      }
      if (action === 'bottom') {
        await LocalRuleSourceRepository.setPinned(source.bookSourceUrl, false);
        const urls = this.allSources.filter((item: LocalRuleSource) => item.bookSourceUrl !== source.bookSourceUrl)
          .sort((left: LocalRuleSource, right: LocalRuleSource) => left.customOrder - right.customOrder)
          .map((item: LocalRuleSource) => item.bookSourceUrl);
        urls.push(source.bookSourceUrl);
        await LocalRuleSourceRepository.saveOrder(urls);
        this.sortMode = 0;
      }
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
      await this.loadSources(false);
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private async moveSourceOrder(from: number, to: number): Promise<void> {
    if (this.busySourceUrl.length > 0 || from < 0 || from >= this.orderedSources.length) return;
    const target = Math.max(0, Math.min(to, this.orderedSources.length - 1));
    if (target === from || this.orderedSources[from].isPinned !== this.orderedSources[target].isPinned) return;
    this.busySourceUrl = 'order';
    try {
      const next = this.orderedSources.slice();
      const moved = next.splice(from, 1)[0];
      next.splice(target, 0, moved);
      await LocalRuleSourceRepository.saveOrder(next.map((source: LocalRuleSource) => source.bookSourceUrl));
      this.orderedSources = next;
      this.orderDataSource.setSources(next);
      this.sortMode = 0;
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private canMoveSourceOrder(from: number, to: number): boolean {
    return this.busySourceUrl.length === 0 && from >= 0 && from < this.orderCount && to >= 0 && to < this.orderCount &&
      this.orderedSources[from].isPinned === this.orderedSources[to].isPinned;
  }

  private toggleEditMode(): void {
    this.isEditMode = !this.isEditMode;
    this.resetSelection();
    if (this.isEditMode) this.showImportPanel = false;
  }

  private sourceListScroller: Scroller = new Scroller();

  private toggleImportPanel(): void {
    this.showImportPanel = !this.showImportPanel;
    if (this.showImportPanel && this.isEditMode) {
      this.isEditMode = false;
      this.resetSelection();
    }
  }

  private resetSelection(): void {
    this.selectedSources = new Set<string>();
    this.selectedSourceCount = 0;
    this.selectionRevision++;
  }

  private isSourceSelected(sourceUrl: string, _selectionRevision: number): boolean {
    return this.selectedSources.has(sourceUrl);
  }

  private toggleSelectSource(sourceUrl: string): void {
    const nextSelected = new Set<string>(this.selectedSources);
    const wasSelected = this.isSourceSelected(sourceUrl, this.selectionRevision);
    if (wasSelected) {
      nextSelected.delete(sourceUrl);
    } else {
      nextSelected.add(sourceUrl);
    }
    this.selectedSources = nextSelected;
    this.selectionRevision++;
    if (wasSelected) {
      this.selectedSourceCount = Math.max(0, this.selectedSourceCount - 1);
    } else {
      this.selectedSourceCount = Math.min(this.filteredSourceCount, this.selectedSourceCount + 1);
    }
  }

  private selectAllSources(): void {
    if (this.areAllVisibleSourcesSelected()) {
      this.resetSelection();
      return;
    }
    const nextSelected = new Set<string>();
    for (const source of this.filteredSources) {
      nextSelected.add(source.bookSourceUrl);
    }
    this.selectedSources = nextSelected;
    this.selectedSourceCount = nextSelected.size;
    this.selectionRevision++;
  }

  private areAllVisibleSourcesSelected(): boolean {
    return this.filteredSourceCount > 0 && this.selectedSourceCount === this.filteredSourceCount;
  }

  private selectedSourceUrls(): string[] {
    const urls: string[] = [];
    for (const source of this.filteredSources) {
      if (this.isSourceSelected(source.bookSourceUrl, this.selectionRevision)) urls.push(source.bookSourceUrl);
    }
    return urls;
  }

  private finishBatchEdit(): void {
    this.resetSelection();
    this.isEditMode = false;
  }

  private async batchEnableSelected(enabled: boolean): Promise<void> {
    if (this.selectedSourceCount === 0) return;
    this.busySourceUrl = 'batch';
    try {
      const urls = this.selectedSourceUrls();
      const changed = await LocalRuleSourceRepository.setEnabledBatch(urls, enabled);
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.finishBatchEdit();
      this.showToast($r('app.string.source_manage_changed', changed));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private confirmBatchDelete(): void {
    if (this.selectedSourceCount === 0) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_batch_delete_title'),
      message: $r('app.string.rule_source_batch_delete_message', this.selectedSourceCount),
      primaryButton: {
        value: $r('app.string.rule_source_delete_action'),
        fontColor: RULE_SOURCE_DANGER,
        action: () => {
          this.batchDeleteSelected();
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async batchDeleteSelected(): Promise<void> {
    if (this.selectedSourceCount === 0) return;
    this.busySourceUrl = 'batch';
    try {
      const selectedUrls = this.selectedSourceUrls();
      const urls = this.allSources.filter((source: LocalRuleSource) => !source.isLocked &&
        selectedUrls.includes(source.bookSourceUrl)).map((source: LocalRuleSource) => source.bookSourceUrl);
      await LocalRuleSourceRepository.deleteBatch(urls);
      LocalRuleHttpClient.clearCookieCacheBatch(urls);
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.finishBatchEdit();
      this.showToast($r('app.string.rule_source_batch_delete_success'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  private async importSources(): Promise<void> {
    const input = this.importJson.trim();
    if (this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0 || input.length === 0) {
      if (input.length === 0) {
        this.showToast($r('app.string.rule_source_import_empty'));
      }
      return;
    }

    this.isImporting = true;
    try {
      const content = await this.resolveImportContent(input);
      const imported = await this.persistImportContent(content);
      if (imported) {
        this.importJson = '';
        this.showImportPanel = false;
      }
    } catch (error) {
      this.showImportError(error);
    } finally {
      this.isImporting = false;
    }
  }

  private async importLocalFile(): Promise<void> {
    if (this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0) return;
    this.isImporting = true;
    try {
      const uris = await this.pickLocalJsonUris();
      if (uris.length === 0) { this.showImportPanel = false; return; }
      this.hasFileImportResult = false;
      const result = await LocalRuleSourceFileImporter.importFiles(uris, (current: number, total: number) => {
        this.importFileCurrent = current;
        this.importFileTotal = total;
      });
      this.fileImportResult = result;
      this.hasFileImportResult = true;
      if (result.imported > 0) {
        this.sortMode = 0;
        this.searchKeyword = '';
        this.selectedGroup = '';
        this.statusFilter = 0;
      }
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.showToast($r('app.string.rule_source_import_files_result',
        result.imported, result.skippedSources, result.skippedFiles));
      if (result.imported > 0 && result.skippedFiles === 0 && result.skippedSources === 0) {
        this.showImportPanel = false;
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.isImporting = false;
      this.importFileCurrent = 0;
      this.importFileTotal = 0;
    }
  }

  private async scanQRCode(): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) return;
    if (this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0) return;
    this.isImporting = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.showToast('无法获取上下文');
        return;
      }

      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };

      const result = await scanBarcode.startScanForResult(context, options);

      if (result && result.originalValue && result.originalValue.length > 0) {
        const scannedText = result.originalValue;

        // 判断是 URL 还是 JSON 内容
        if (this.isRemoteImport(scannedText)) {
          // 是 URL，自动下载
          const content = await this.resolveImportContent(scannedText);
          const imported = await this.persistImportContent(content);
          if (imported) this.showImportPanel = false;
        } else {
          // 是 JSON 内容，直接导入
          const imported = await this.persistImportContent(scannedText);
          if (imported) this.showImportPanel = false;
        }
      } else {
        // 用户取消扫描，不提示错误
      }
    } catch (error) {
      this.showImportError(error);
    } finally {
      this.isImporting = false;
    }
  }

  private async pickLocalJsonUris(): Promise<string[]> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) return [];
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = LocalRuleSourceFileImporter.MAX_FILES;
      options.fileSuffixFilters = ['.json'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: Array<string> = await documentPicker.select(options);
      return uris;
    } catch (_error) {
      // 用户取消选择时不提示错误。
      return [];
    }
  }

  private async readLocalJson(uri: string): Promise<string | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0) {
        this.showToast($r('app.string.rule_source_import_file_empty'));
        return undefined;
      }
      if (stat.size > RULE_SOURCE_IMPORT_MAX_LENGTH) {
        this.showToast($r('app.string.rule_source_import_file_too_large'));
        return undefined;
      }
      const buffer = new ArrayBuffer(stat.size);
      const bytesRead = await fileIo.read(file.fd, buffer);
      if (bytesRead !== stat.size) {
        this.showToast($r('app.string.rule_source_import_file_failed'));
        return undefined;
      }
      const content = CharsetCodec.decodeBuffer(buffer);
      if (content.trim().length === 0) {
        this.showToast($r('app.string.rule_source_import_file_empty'));
        return undefined;
      }
      return content;
    } catch (_error) {
      this.showToast($r('app.string.rule_source_import_file_failed'));
      return undefined;
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (_error) {
          // 关闭失败不影响已经读取的导入内容。
        }
      }
    }
  }

  private async persistImportContent(content: string): Promise<boolean> {
    const report = LocalRuleSourceImportParser.parse(content);
    if (report.sources.length === 0) {
      this.showToast(report.message.length > 0 ? report.message : $r('app.string.rule_source_import_invalid'));
      return false;
    }
    let importedCount = 0;
    try {
      importedCount = await LocalRuleSourceImportService.importSources(report.sources);
    } catch (error) {
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
    if (importedCount > 0) this.sortMode = 0;
    SourceDataService.invalidateLocalSources();
    await this.loadSources(false);
    this.showToast($r('app.string.source_manage_import_result', importedCount, report.sources.length - importedCount));
    return importedCount > 0;
  }

  private isRemoteImport(input: string): boolean {
    return LocalRuleSourceRemoteImporter.isRemote(input);
  }

  private async resolveImportContent(input: string): Promise<string> {
    return LocalRuleSourceRemoteImporter.resolve(input);
  }

  private showImportError(error: Object): void {
    if (!(error instanceof RuleSourceRemoteImportError)) {
      this.showToast($r('app.string.rule_source_operation_failed'));
      return;
    }
    if (error.failure === RuleSourceRemoteImportFailure.ADDRESS) {
      this.showToast($r('app.string.source_import_address_invalid'));
    } else if (error.failure === RuleSourceRemoteImportFailure.TOO_LARGE) {
      this.showToast($r('app.string.rule_source_import_file_too_large'));
    } else if (error.failure === RuleSourceRemoteImportFailure.AUTH) {
      this.showToast($r('app.string.source_import_auth_required'));
    } else if (error.failure === RuleSourceRemoteImportFailure.NOT_FOUND) {
      this.showToast($r('app.string.source_import_not_found'));
    } else if (error.failure === RuleSourceRemoteImportFailure.HTML) {
      this.showToast($r('app.string.source_import_html_response'));
    } else if (error.failure === RuleSourceRemoteImportFailure.FORMAT) {
      this.showToast($r('app.string.rule_source_import_invalid'));
    } else {
      this.showToast($r('app.string.source_import_network_failed'));
    }
  }

  private async changeEnabled(source: LocalRuleSource, enabled: boolean): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting ||
      source.isLocked || this.changingSourceUrls.has(source.bookSourceUrl)) return;
    if (!source.canExecute()) {
      this.showToast($r('app.string.rule_source_unsupported_action'));
      return;
    }

    const previousEnabled = source.enabled;
    source.enabled = enabled;
    this.changingSourceUrls.add(source.bookSourceUrl);
    try {
      await LocalRuleSourceRepository.setEnabled(source.bookSourceUrl, enabled);
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
      await this.loadSources(false);
    } catch (_error) {
      source.enabled = previousEnabled;
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.changingSourceUrls.delete(source.bookSourceUrl);
    }
  }

  private editSource(source: LocalRuleSource): void {
    if (source.isLocked) { this.showToast($r('app.string.source_manage_locked_message')); return; }
    const params: RuleSourceEditParams = { sourceUrl: source.bookSourceUrl };
    this.navStack.pushPathByName('RuleSourceEditPage', params, () => this.refresh());
  }

  private debugSource(source: LocalRuleSource): void {
    const params: RuleSourceDebugParams = { sourceUrl: source.bookSourceUrl };
    this.navStack.pushPathByName('RuleSourceDebugPage', params);
  }

  private async testSource(cardSource: LocalRuleSource): Promise<void> {
    // 相同 URL 重导后 LazyForEach 可能保留旧卡片闭包，测试必须使用本次加载的定义。
    const source = this.allSources.find((item: LocalRuleSource) =>
      item.bookSourceUrl === cardSource.bookSourceUrl);
    if (source === undefined) return;
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting || !source.canExecute()) return;
    if (!(await this.hasMainAccount(source))) {
      this.showToast($r('app.string.rule_source_account_required_for_test'));
      this.openMainAccount(source);
      return;
    }
    this.busySourceUrl = source.bookSourceUrl;
    try {
      const health = await BookSourceService.testLocalSource(source, RULE_SOURCE_TEST_KEYWORD);
      source.validationStatus = health.status;
      source.validationMessage = health.message;
      cardSource.validationStatus = health.status;
      cardSource.validationMessage = health.message;
      await LocalRuleSourceRepository.updateValidationBatch([source]);
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
      await this.loadSources(false);
      if (health.status === LocalRuleSourceStatus.READY) {
        this.showToast($r('app.string.rule_source_test_success'));
      } else {
        this.showToast(health.message.length > 0 ? health.message : $r('app.string.rule_source_test_failed'));
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_test_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private canOpenSourceLogin(source: LocalRuleSource): boolean {
    if (source.engine === 'light' || source.engine === 'light-native') {
      return source.loginUrl.trim().length > 0 || source.loginUi.trim().length > 0;
    }
    if (TalebookSourceIdentity.isSourceUrl(source.bookSourceUrl)) return true;
    if (RuleSourceChildService.supports(source.bookSourceUrl)) return false;
    return source.loginUrl.trim().toLowerCase().startsWith('https://');
  }

  private async hasMainAccount(source: LocalRuleSource): Promise<boolean> {
    if (!RuleSourceAccountService.supports(source.bookSourceUrl)) return true;
    const state: RuleSourceAccountState = await RuleSourceAccountService.getState(source.bookSourceUrl);
    return state.loggedIn;
  }

  private openMainAccount(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!RuleSourceAccountService.supports(source.bookSourceUrl)) return;
    if (RuleSourceAccountService.usesWebLogin(source.bookSourceUrl)) {
      const loginUrl = RuleSourceAccountService.webLoginUrl(source.bookSourceUrl);
      const route = RuleSourceLoginRouteParams.forMainAccount(
        source.bookSourceUrl, source.bookSourceName, loginUrl);
      if (route.isValid()) this.navStack.pushPathByName('ruleSourceLogin', route);
      return;
    }
    this.navStack.pushPathByName('ruleSourceAccount', source.bookSourceUrl);
  }

  private openSourceLogin(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (TalebookSourceIdentity.isSourceUrl(source.bookSourceUrl)) {
      this.talebookSourceUrl = source.bookSourceUrl;
      this.showTalebook = true;
      return;
    }
    if (!this.canOpenSourceLogin(source)) return;
    const route = RuleSourceLoginRouteParams.of(
      source.bookSourceUrl, source.bookSourceName, source.loginUrl);
    this.navStack.pushPathByName('ruleSourceLogin', route);
  }

  private openLoginEntry(source: LocalRuleSource): void {
    if (source.engine === 'light' || source.engine === 'light-native' || source.loginUi.length > 0) {
      this.navStack.pushPathByName('ruleSourceLoginPanel', source.bookSourceUrl);
    } else {
      this.openSourceLogin(source);
    }
  }

  private openSourceChildren(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!RuleSourceChildService.supports(source.bookSourceUrl)) return;
    this.navStack.pushPathByName('ruleSourceChildren', source.bookSourceUrl);
  }

  private confirmDelete(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (source.isLocked) { this.showToast($r('app.string.source_manage_locked_message')); return; }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_delete_title'),
      message: $r('app.string.rule_source_delete_message'),
      primaryButton: {
        value: $r('app.string.rule_source_delete_action'),
        fontColor: RULE_SOURCE_DANGER,
        action: () => {
          this.deleteSource(source);
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async deleteSource(source: LocalRuleSource): Promise<void> {
    this.busySourceUrl = source.bookSourceUrl;
    try {
      const deleted = await LocalRuleSourceRepository.delete(source.bookSourceUrl);
      if (deleted) {
        await LocalRuleHttpClient.clearCookies(source.bookSourceUrl);
        SourceDataService.invalidateLocalSources(source.bookSourceUrl);
        await this.loadSources(false);
        this.showToast($r('app.string.rule_source_delete_success'));
      } else {
        this.showToast($r('app.string.rule_source_not_found'));
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private async confirmBulkTest(): Promise<void> {
    if (this.isBulkTesting || this.isImporting || this.busySourceUrl.length > 0 || this.sourceCount === 0) return;
    this.testScope = this.selectedSourceCount > 0 ? 2 : 0;
    this.managementView = 'test';
  }

  private async runBulkTest(retrySources?: LocalRuleSource[]): Promise<void> {
    if (this.isBulkTesting || this.isImporting || this.busySourceUrl.length > 0) return;
    if (this.testKeyword.trim().length === 0 && this.testMode === 'search') return;
    const selectedUrls = this.selectedSourceUrls();
    const sources = retrySources !== undefined ? retrySources : this.testScope === 1 ? this.filteredSources.slice() :
      this.testScope === 2 ? this.allSources.filter((source: LocalRuleSource) => selectedUrls.includes(source.bookSourceUrl)) :
        this.allSources.slice();
    if (sources.length === 0) { this.showToast($r('app.string.source_manage_test_empty')); return; }
    SourceTestTaskService.start(sources, this.testKeyword.trim() || RULE_SOURCE_TEST_KEYWORD,
      this.testMode).catch((): void => {});
  }

  private testTaskHandler: () => void = (): void => { this.syncTestTask(); };

  private syncTestTask(): void {
    if (!this.pageAttached) return;
    const state = SourceTestTaskService.state;
    const wasRunning = this.isBulkTesting;
    this.isBulkTesting = state.running;
    this.applyBulkTestProgress(state.progress);
    if (state.report !== null) {
      this.bulkTestRetained = state.report.retained;
      this.testFailures = state.report.failedSources;
      this.failureDataSource.setSources(this.testFailures);
      this.testCancelled = state.report.cancelled;
    }
    if (wasRunning && !state.running) this.loadSources(false);
  }

  private cancelBulkTest(): void { SourceTestTaskService.cancel(); }

  private async handleFailedSources(remove: boolean): Promise<void> {
    if (this.isBulkTesting || this.busySourceUrl.length > 0) return;
    this.busySourceUrl = 'failed';
    try {
      const sources = await LocalRuleSourceRepository.list();
      const failedUrls = this.testFailures.filter((source: LocalRuleSource) =>
        source.validationStatus === LocalRuleSourceStatus.FAILED).map((source: LocalRuleSource) => source.bookSourceUrl);
      const urls = sources.filter((source: LocalRuleSource) => !source.isLocked && failedUrls.includes(source.bookSourceUrl))
        .map((source: LocalRuleSource) => source.bookSourceUrl);
      const changed = remove ? await LocalRuleSourceRepository.deleteBatch(urls) :
        await LocalRuleSourceRepository.setEnabledBatch(urls, false);
      if (remove) {
        LocalRuleHttpClient.clearCookieCacheBatch(urls);
        this.testFailures = this.testFailures.filter((source: LocalRuleSource) => !urls.includes(source.bookSourceUrl));
        this.failureDataSource.setSources(this.testFailures);
      }
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.showToast($r('app.string.source_manage_changed', changed));
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private confirmDeleteFailed(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.source_manage_test_failed_delete'),
      message: $r('app.string.source_manage_test_failed_delete_message'),
      buttons: [
        { value: $r('app.string.common_cancel'), action: () => {} },
        { value: $r('app.string.rule_source_delete_action'), fontColor: RULE_SOURCE_DANGER,
          action: () => { this.handleFailedSources(true); } }
      ]
    });
  }

  private confirmDisableFailed(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.source_manage_test_failed_disable'),
      message: $r('app.string.source_manage_test_failed_disable_message'),
      buttons: [
        { value: $r('app.string.common_cancel'), action: () => {} },
        { value: $r('app.string.rule_source_batch_disable'), fontColor: RULE_SOURCE_DANGER,
          action: () => { this.handleFailedSources(false); } }
      ]
    });
  }

  private certificateFailureHost(source: LocalRuleSource): string {
    return LocalRuleTlsTrustStore.certificateErrorHost(source.validationMessage, source.bookSourceUrl);
  }

  private confirmTrustHosts(hosts: string[], retrySources?: LocalRuleSource[]): void {
    if (hosts.length === 0) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.source_manage_tls'),
      message: $r('app.string.source_manage_tls_confirm', hosts.join('\n')),
      buttons: [
        { value: $r('app.string.common_cancel'), action: () => {} },
        { value: $r('app.string.source_manage_tls_trust'), fontColor: RULE_SOURCE_DANGER,
          action: () => { this.trustHosts(hosts, retrySources); } }
      ]
    });
  }

  private confirmTrustDraft(): void {
    const value = this.trustHostDraft.trim();
    const host = LocalRuleTlsTrustStore.hostFromUrl(value.includes('://') ? value : `https://${value}`);
    if (host.length === 0 || value.includes('*') || value.includes('@')) {
      this.showToast($r('app.string.source_manage_tls_invalid')); return;
    }
    this.confirmTrustHosts([host]);
  }

  private async trustHosts(hosts: string[], retrySources?: LocalRuleSource[]): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isBulkTesting) return;
    this.busySourceUrl = 'tls';
    let trusted = false;
    try {
      await LocalRuleTlsTrustStore.trustHosts(hosts);
      this.trustedHosts = await LocalRuleTlsTrustStore.listTrustedHosts();
      this.trustHostDraft = '';
      trusted = true;
      this.showToast($r('app.string.source_manage_tls_updated'));
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
    if (trusted && retrySources !== undefined) await this.runBulkTest(retrySources);
  }

  private async revokeHost(host: string): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isBulkTesting) return;
    this.busySourceUrl = 'tls';
    try {
      await LocalRuleTlsTrustStore.revokeHost(host);
      this.trustedHosts = await LocalRuleTlsTrustStore.listTrustedHosts();
      this.showToast($r('app.string.source_manage_tls_strict'));
    } catch (_error) { this.showToast($r('app.string.rule_source_operation_failed')); }
    finally { this.busySourceUrl = ''; }
  }

  private applyBulkTestProgress(progress: LocalRuleSourceBulkTestProgress): void {
    this.bulkTestTotal = progress.total;
    this.bulkTestCompleted = progress.completed;
    this.bulkTestPassed = progress.passed;
    this.bulkTestFailed = progress.failed;
    const testedSource = progress.testedSource;
    if (testedSource === undefined) return;
    for (const source of this.allSources) {
      if (source.bookSourceUrl !== testedSource.bookSourceUrl) continue;
      source.validationStatus = testedSource.validationStatus;
      source.validationMessage = testedSource.validationMessage;
      break;
    }
  }

  private statusLabel(status: number): ResourceStr {
    if (status === LocalRuleSourceStatus.READY) return $r('app.string.rule_source_status_ready');
    if (status === LocalRuleSourceStatus.FAILED) return $r('app.string.rule_source_status_failed');
    if (status === LocalRuleSourceStatus.UNSUPPORTED) return $r('app.string.rule_source_status_unsupported');
    return $r('app.string.rule_source_status_unchecked');
  }

  private statusColor(status: number): ResourceColor {
    if (status === LocalRuleSourceStatus.READY) return RULE_SOURCE_SUCCESS;
    if (status === LocalRuleSourceStatus.FAILED) return RULE_SOURCE_DANGER;
    if (status === LocalRuleSourceStatus.UNSUPPORTED) return RULE_SOURCE_WARNING;
    return $r('sys.color.font_tertiary');
  }

  private statusMessage(source: LocalRuleSource): ResourceStr {
    if (source.validationMessage.length > 0) return source.validationMessage;
    return $r('app.string.rule_source_waiting_test');
  }

  private sourceGroupLabels(source: LocalRuleSource): string[] {
    return LocalRuleSourceRepository.groupNames(source.bookSourceGroup);
  }

  private sourceTypeLabel(source: LocalRuleSource): ResourceStr {
    if (source.isComic()) return $r('app.string.comic_type');
    if (source.bookSourceType === LocalRuleSourceType.AUDIO) {
      return $r('app.string.rule_source_type_audio');
    }
    return $r('app.string.rule_source_type_text');
  }

  build() {
    ProfileMenuDestination({
      pageBackground: $r('sys.color.background_secondary'),
      onBackRequested: (): boolean => this.requestBack()
    }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.buildBody()
        if (!this.isLoading && !this.loadFailed && !this.isEditMode &&
          this.managementView.length === 0 && !this.showImportPanel) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(25).fontColor([AppColor.Brand])
          }
          .width(52).height(52)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .border({ width: 1, color: AppColor.BrandSoft })
          .shadow({ radius: 12, color: '#20000000', offsetY: 4 })
          .margin({ right: AppSpace.Lg, bottom: Math.max(this.safeBottom, RULE_SOURCE_MIN_BOTTOM_INSET) + 16 })
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_import_title'))
          .id('rule-source-import-button')
          .bindMenu(this.buildImportMenu())
        }
      }.width('100%').height('100%')
      .bindSheet($$this.showImportPanel, this.buildImportSheet(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.LARGE, '45%', '70%'], preferType: SheetType.BOTTOM, dragBar: true, showClose: true,
        onWillDismiss: (action: DismissSheetAction): void => {
          if (!this.isImporting) action.dismiss();
        }
      })
    }
  }

  @Builder
  buildBody() {
    Column() {
      this.buildHeader()

      if (this.managementView.length > 0) {
        this.buildManagementBody()
      } else if (this.isLoading) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(AppColor.Brand)
          Text($r('app.string.rule_source_loading'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppSpace.Sm, scroller: this.sourceListScroller }) {
          ListItem() {
            Row() {
              Text($r('app.string.rule_source_installed'))
                .fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_tertiary'))
              Blank()
              Text(`${this.filteredSourceCount}/${this.sourceCount}`)
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
              Text($r('app.string.rule_source_count_unit'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
                .margin({ left: 2 })
            }
            .width('100%')
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: AppSpace.Xs })
          }

          if (!this.loadFailed && this.bulkTestTotal > 0) {
            ListItem() {
              this.buildBulkTestSection()
            }
          }

          if (this.loadFailed) {
            ListItem() {
              this.buildLoadFailed()
            }
          } else if (this.sourceCount === 0) {
            ListItem() {
              this.buildEmptyState()
            }
          } else if (this.filteredSourceCount === 0) {
            ListItem() {
              this.buildNoMatchState()
            }
          } else {
            LazyForEach(this.dataSource, (item: RuleSourceListItem) => {
              ListItem() {
                this.buildSourceItem(item)
              }
            }, (item: RuleSourceListItem) => item.sourceUrl)
          }
          ListItem() { Row().height(88) }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: AppSpace.Xs,
          bottom: AppSpace.Xs
        })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    // 底部避让取系统安全区与 28vp 的较大值，避免重复叠加导航条留白。
    .padding({ bottom: Math.max(this.safeBottom, RULE_SOURCE_MIN_BOTTOM_INSET) })
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showTalebook, this.buildTalebookConnection(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE, '45%', '70%'], preferType: SheetType.BOTTOM, dragBar: true, showClose: true,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.isImporting) action.dismiss();
      }
    })
  }

  @Builder
  buildImportMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.rule_source_import_file_action') })
        .onClick((): void => { this.showImportPanel = true; this.importLocalFile(); })
      MenuItem({ content: $r('app.string.rule_source_import_link_action') })
        .onClick((): void => this.toggleImportPanel())
      if (canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
        MenuItem({ content: $r('app.string.rule_source_import_scan_action') })
          .onClick(() => this.scanQRCode())
      }
    }
  }

  @Builder
  buildImportSheet() {
    Scroll() { this.buildImportSection() }
      .width('100%').height('100%')
      .padding({ bottom: Math.max(this.safeBottom, RULE_SOURCE_MIN_BOTTOM_INSET) })
  }

  @Builder
  buildTalebookConnection() {
    TalebookConnectComponent({
      sourceUrl: this.talebookSourceUrl,
      onBusy: (busy: boolean): void => { this.isImporting = busy; },
      onConnected: (): void => {
        this.showTalebook = false;
        this.showImportPanel = false;
        SourceDataService.invalidateLocalSources();
        this.loadSources(false);
        this.showToast($r('app.string.talebook_connected'));
      }
    })
  }

  @Builder
  buildHeader() {
    Column({ space: AppSpace.Xs }) {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(AppRadius.Pill)
        .onClick(() => {
          if (!this.requestBack()) this.navStack.pop();
        })

        Text(this.managementTitle())
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!this.isLoading && !this.loadFailed && !this.isEditMode && this.managementView.length === 0) {
          if (this.sourceCount > 0) {
            Button() {
              if (this.isBulkTesting) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(AppColor.Brand)
              } else {
                SymbolGlyph($r('sys.symbol.bolt_fill'))
                  .fontSize('20vp')
                  .fontColor([AppColor.Brand])
              }
            }
            .width(36)
            .height(36)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .borderRadius(AppRadius.Pill)
            .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_bulk_action'))
            .onClick(() => this.confirmBulkTest())
          }

          if (this.sourceCount === 0) {
            Button() { SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(20).fontColor([AppColor.Brand]) }
              .height(36).width(36).padding(0).backgroundColor(Color.Transparent)
              .accessibilityText($r('app.string.source_manage_more')).bindMenu(this.buildToolsMenu())
          }

        }

        if (!this.isLoading && !this.loadFailed && this.sourceCount > 0 && this.managementView.length === 0) {
          Text(this.isEditMode ? $r('app.string.common_done') : $r('app.string.rule_source_manage'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .padding({ left: AppSpace.Xxs, right: 0, top: AppSpace.Xs, bottom: AppSpace.Xs })
            .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
            .onClick(() => this.toggleEditMode())
        }
      }
      .width('100%')
      .padding({
        top: this.safeTop + AppSpace.Xs,
        left: AppSpace.Xs,
        right: AppSpace.Md,
        bottom: 0
      })

      if (!this.isLoading && !this.loadFailed && this.sourceCount > 0 && this.managementView.length === 0) {
        Stack({ alignContent: Alignment.Start }) {
          TextInput({
            placeholder: $r('app.string.rule_source_search_placeholder'),
            text: $$this.searchKeyword
          })
            .width('100%')
            .height(40)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.background_primary'))
            .borderRadius(AppRadius.Sm)
            .padding({ left: 38, right: AppSpace.Sm })
            .enabled(!this.isEditMode && !this.isImporting && !this.isBulkTesting &&
              this.busySourceUrl.length === 0)
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.applyFilters();
            })

          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_tertiary')])
            .margin({ left: AppSpace.Sm })
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md })

        Row({ space: 8 }) {
          ForEach([$r('app.string.search_type_all'), $r('app.string.search_type_audio'),
            $r('app.string.search_type_text'), $r('app.string.comic_type')], (label: Resource, index: number) => {
            Button(label).layoutWeight(1).fontSize(13)
              .backgroundColor(this.contentFilter === index ? AppColor.Brand : $r('sys.color.comp_background_primary'))
              .fontColor(this.contentFilter === index ? Color.White : $r('sys.color.font_primary'))
              .enabled(!this.isEditMode && !this.isImporting && !this.isBulkTesting)
              .onClick(() => { this.contentFilter = index; this.applyFilters(); })
          }, (label: Resource): string => label.id.toString())
        }.width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: 8 })
        Row({ space: AppSpace.Xs }) {
          Select(this.groupOptions(true))
            .selected(this.selectedGroupIndex()).value(this.currentGroupLabel())
            .font({ size: AppFont.Caption }).layoutWeight(1).constraintSize({ minWidth: 0 })
            .selectedOptionFontColor(AppColor.Brand).selectedOptionBgColor(AppColor.BrandSoft)
            .enabled(!this.isEditMode && !this.isImporting && !this.isBulkTesting)
            .onSelect((index: number) => {
              this.selectedGroup = index === 0 ? '' : index === 1 ? '__ungrouped__' : this.sourceGroups[index - 2];
              this.applyFilters();
            })
          Select([
            { value: $r('app.string.source_manage_all_status') },
            { value: $r('app.string.source_manage_enabled') },
            { value: $r('app.string.source_manage_disabled') },
            { value: $r('app.string.source_manage_explore_enabled') },
            { value: $r('app.string.source_manage_explore_disabled') },
            { value: $r('app.string.source_manage_locked') },
            { value: $r('app.string.rule_source_status_ready') },
            { value: $r('app.string.rule_source_status_failed') },
            { value: $r('app.string.rule_source_status_unchecked') }
          ])
            .selected(this.statusFilter).value(this.statusFilterLabel()).font({ size: AppFont.Caption })
            .layoutWeight(1).constraintSize({ minWidth: 0 })
            .selectedOptionFontColor(AppColor.Brand).selectedOptionBgColor(AppColor.BrandSoft)
            .enabled(!this.isEditMode && !this.isImporting && !this.isBulkTesting)
            .onSelect((index: number) => { this.statusFilter = index; this.applyFilters(); })
          Button() {
            SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(22).fontColor([AppColor.Brand])
          }
          .width(40).height(40).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.source_manage_more'))
          .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
          .bindMenu(this.buildToolsMenu())
        }
        .width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md })
      }

      if (this.isEditMode && this.managementView.length === 0) {
        Column({ space: AppSpace.Xs }) {
          Row() {
            Text(this.selectedSourceCount > 0 ?
              $r('app.string.rule_source_selected_count', this.selectedSourceCount) :
              $r('app.string.rule_source_select_hint'))
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)

            Text(this.areAllVisibleSourcesSelected() ? $r('app.string.rule_source_deselect_all') :
              $r('app.string.rule_source_select_all'))
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs, bottom: AppSpace.Xs })
              .borderRadius(AppRadius.Sm)
              .backgroundColor(AppColor.BrandSoft)
              .onClick(() => this.selectAllSources())
          }

          Row({ space: AppSpace.Xs }) {
            Button($r('app.string.rule_source_batch_enable'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .backgroundColor(AppColor.BrandSoft)
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.batchEnableSelected(true))

            Button($r('app.string.rule_source_batch_disable'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .backgroundColor($r('sys.color.comp_background_primary'))
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.batchEnableSelected(false))

            Button($r('app.string.rule_source_batch_delete'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor(RULE_SOURCE_DANGER)
              .backgroundColor(Color.Transparent)
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.confirmBatchDelete())

            Button() {
              SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(20).fontColor([AppColor.Brand])
            }
              .width(40).height(36).padding(0).backgroundColor(Color.Transparent)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0 && !this.isBulkTesting)
              .accessibilityText($r('app.string.source_manage_more'))
              .bindMenu(this.buildBatchMenu())
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })
      }
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  buildToolsMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.source_manage_groups') }).onClick(() => this.openManagement('groups'))
      MenuItem({ content: $r('app.string.source_manage_order') }).onClick(() => this.openManagement('order'))
      MenuItem({ content: $r('app.string.source_manage_tls') }).onClick(() => this.openManagement('tls'))
      MenuItemGroup({ header: $r('app.string.source_manage_filters') }) {
        MenuItem({ content: $r('app.string.source_manage_order_custom') })
          .onClick(() => { this.sortMode = 0; this.applyFilters(); })
        MenuItem({ content: $r('app.string.source_manage_order_name') })
          .onClick(() => { this.sortMode = 1; this.applyFilters(); })
        MenuItem({ content: $r('app.string.source_manage_order_newest') })
          .onClick(() => { this.sortMode = 2; this.applyFilters(); })
        MenuItem({ content: $r('app.string.source_manage_order_oldest') })
          .onClick(() => { this.sortMode = 3; this.applyFilters(); })
      }
    }
  }

  @Builder
  buildBatchMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.source_manage_group_assign') }).onClick(() => this.runSelectedAction('group'))
      MenuItem({ content: $r('app.string.source_manage_export_selected') }).onClick(() => this.runSelectedAction('export'))
      MenuItem({ content: $r('app.string.source_manage_test_selected') }).onClick(() => this.runSelectedAction('test'))
      MenuItem({ content: $r('app.string.source_manage_explore_enable') }).onClick(() => this.runSelectedAction('exploreOn'))
      MenuItem({ content: $r('app.string.source_manage_explore_disable') }).onClick(() => this.runSelectedAction('exploreOff'))
      MenuItem({ content: $r('app.string.source_manage_lock') }).onClick(() => this.runSelectedAction('lock'))
      MenuItem({ content: $r('app.string.source_manage_unlock') }).onClick(() => this.runSelectedAction('unlock'))
    }
  }

  @Builder
  buildSourceMenu(item: RuleSourceListItem) {
    Menu() {
      MenuItem({ content: item.source.isPinned ? $r('app.string.source_manage_unpin') : $r('app.string.source_manage_pin') })
        .onClick(() => this.changeSourceFlag(item.source, 'pin'))
      MenuItem({ content: item.source.isLocked ? $r('app.string.source_manage_unlock') : $r('app.string.source_manage_lock') })
        .onClick(() => this.changeSourceFlag(item.source, 'lock'))
      MenuItem({ content: item.source.enabledExplore ? $r('app.string.source_manage_explore_disable') :
        $r('app.string.source_manage_explore_enable') })
        .enabled(!item.source.isLocked).onClick(() => this.changeSourceFlag(item.source, 'explore'))
      MenuItem({ content: $r('app.string.source_manage_group_assign') }).enabled(!item.source.isLocked)
        .onClick(() => {
          this.isEditMode = true; this.resetSelection(); this.toggleSelectSource(item.source.bookSourceUrl);
          this.groupDraft = item.source.bookSourceGroup; this.managementView = 'groupAssign';
        })
      MenuItem({ content: $r('app.string.source_manage_move_bottom') }).onClick(() => this.changeSourceFlag(item.source, 'bottom'))
      MenuItem({ content: $r('app.string.source_manage_tls') }).onClick(() => this.openManagement('tls'))
    }
  }

  @Builder
  buildManagementBody() {
    if (this.managementView === 'groups') {
      this.buildGroupManager()
    } else if (this.managementView === 'groupAssign') {
      this.buildGroupAssignment()
    } else if (this.managementView === 'order') {
      this.buildOrderManager()
    } else if (this.managementView === 'test') {
      this.buildTestManager()
    } else if (this.managementView === 'tls') {
      this.buildTlsManager()
    }
  }

  @Builder
  buildGroupManager() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        TextInput({ text: $$this.groupDraft, placeholder: $r('app.string.source_manage_group_name') })
          .layoutWeight(1).height(44).fontSize(AppFont.Body).caretColor(AppColor.Brand)
        Button() {
          SymbolGlyph(this.editingGroup.length > 0 ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
            .fontSize(20).fontColor([AppColor.Brand])
        }
          .width(44).height(44).padding(0).backgroundColor(AppColor.BrandSoft)
          .accessibilityText(this.editingGroup.length > 0 ? $r('app.string.source_manage_save') :
            $r('app.string.source_manage_group_add'))
          .enabled(this.groupDraft.trim().length > 0 && this.busySourceUrl.length === 0).onClick(() => this.saveGroup())
        if (this.editingGroup.length > 0) {
          Button() { SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.font_secondary')]) }
            .width(44).height(44).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_cancel'))
            .onClick(() => { this.editingGroup = ''; this.groupDraft = ''; })
        }
      }.width('100%')
      List() {
        ForEach(this.sourceGroups, (name: string) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Text(name).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
                .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.groupSourceCount(name)}`).fontSize(AppFont.Caption).fontColor($r('sys.color.font_tertiary'))
              Button() { SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(18).fontColor([AppColor.Brand]) }
                .width(40).height(44).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText($r('app.string.source_manage_group_rename'))
                .enabled(this.busySourceUrl.length === 0)
                .onClick(() => { this.editingGroup = name; this.groupDraft = name; })
              Button() { SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([RULE_SOURCE_DANGER]) }
                .width(40).height(44).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText($r('app.string.source_manage_group_remove'))
                .enabled(this.busySourceUrl.length === 0).onClick(() => this.confirmRemoveGroup(name))
            }.width('100%').constraintSize({ minHeight: 52 })
          }
        }, (name: string) => name)
        if (this.sourceGroups.length === 0) {
          ListItem() { Text($r('app.string.source_manage_group_none')).fontColor($r('sys.color.font_tertiary')).padding(20) }
        }
      }.layoutWeight(1).width('100%').divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
      Button($r('app.string.source_manage_group_empty'), { type: ButtonType.Normal })
        .fontSize(AppFont.Body).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
        .width('100%').height(44).borderRadius(AppRadius.Sm)
        .enabled(this.busySourceUrl.length === 0).onClick(() => this.clearEmptyGroups())
    }.width('100%').layoutWeight(1).padding(AppSpace.Md)
  }

  @Builder
  buildGroupAssignment() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.rule_source_selected_count', this.selectedSourceCount))
        .width('100%').fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
      Select(this.groupOptions(false)).value(this.groupDraft.length > 0 ? this.groupDraft : $r('app.string.source_manage_ungrouped'))
        .width('100%').font({ size: AppFont.Body }).selectedOptionFontColor(AppColor.Brand)
        .onSelect((index: number) => { this.groupDraft = index === 0 ? '' : this.sourceGroups[index - 1]; })
      TextInput({ text: $$this.groupDraft, placeholder: $r('app.string.source_manage_group_name') })
        .width('100%').height(48).fontSize(AppFont.Body).caretColor(AppColor.Brand)
      Button($r('app.string.source_manage_apply'), { type: ButtonType.Normal })
        .height(44).width('100%').fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).borderRadius(AppRadius.Sm)
        .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0).onClick(() => this.assignSelectedGroup())
      Blank()
    }.width('100%').layoutWeight(1).padding(AppSpace.Md)
  }

  @Builder
  buildOrderPreview() {
    Text(this.dragSourceName).fontSize(AppFont.Body).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('sys.color.font_primary')).padding(AppSpace.Md).width(240)
      .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Sm)
  }

  @Builder
  buildOrderManager() {
    List() {
      LazyForEach(this.orderDataSource, (item: RuleSourceListItem) => {
        ListItem() {
          Row({ space: AppSpace.Sm }) {
            SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(20).fontColor([$r('sys.color.font_tertiary')])
              .accessibilityText($r('app.string.source_manage_drag'))
            if (item.source.isPinned) { SymbolGlyph($r('sys.symbol.pin')).fontSize(16).fontColor([AppColor.Brand]) }
            Text(item.source.bookSourceName).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
              .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Button() { SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(20).fontColor([AppColor.Brand]) }
              .width(40).height(44).padding(0).backgroundColor(Color.Transparent)
              .enabled(this.canMoveSourceOrder(item.index, item.index - 1))
              .accessibilityText($r('app.string.source_manage_move_up')).onClick(() => this.moveSourceOrder(item.index, item.index - 1))
            Button() { SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(20).fontColor([AppColor.Brand]) }
              .width(40).height(44).padding(0).backgroundColor(Color.Transparent)
              .enabled(this.canMoveSourceOrder(item.index, item.index + 1))
              .accessibilityText($r('app.string.source_manage_move_down')).onClick(() => this.moveSourceOrder(item.index, item.index + 1))
          }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
      }, (item: RuleSourceListItem) => item.sourceUrl)
    }
    .width('100%').layoutWeight(1).divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
    .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
      this.dragSourceName = itemIndex >= 0 && itemIndex < this.orderedSources.length ?
        this.orderedSources[itemIndex].bookSourceName : '';
      return this.buildOrderPreview;
    })
    .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
      if (isSuccess) this.moveSourceOrder(itemIndex, insertIndex > itemIndex ? insertIndex - 1 : insertIndex);
      this.dragSourceName = '';
    })
  }

  @Builder
  buildTestManager() {
    List({ space: AppSpace.Md }) {
      ListItem() {
        Column({ space: AppSpace.Sm }) {
          Row({ space: AppSpace.Sm }) {
            Radio({ value: 'search', group: 'sourceTestMode' }).checked(this.testMode === 'search')
              .radioStyle({ checkedBackgroundColor: AppColor.Brand }).enabled(!this.isBulkTesting)
              .onChange((checked: boolean) => { if (checked) this.testMode = 'search'; })
            Text($r('app.string.source_manage_test_search')).fontSize(AppFont.Body).layoutWeight(1)
            Radio({ value: 'exploreReading', group: 'sourceTestMode' }).checked(this.testMode === 'exploreReading')
              .radioStyle({ checkedBackgroundColor: AppColor.Brand }).enabled(!this.isBulkTesting)
              .onChange((checked: boolean) => { if (checked) this.testMode = 'exploreReading'; })
            Text($r('app.string.source_manage_test_reading')).fontSize(AppFont.Body).layoutWeight(1)
          }.width('100%')
          Select([
            { value: $r('app.string.source_manage_test_all') },
            { value: $r('app.string.source_manage_test_visible') },
            { value: $r('app.string.source_manage_test_selected') }
          ]).selected(this.testScope).value(this.testScopeLabel()).width('100%')
            .font({ size: AppFont.Body }).enabled(!this.isBulkTesting)
            .onSelect((index: number) => { this.testScope = index; })
          if (this.testMode === 'search') {
            TextInput({ text: $$this.testKeyword, placeholder: $r('app.string.source_manage_test_keyword') })
              .height(44).width('100%').fontSize(AppFont.Body).caretColor(AppColor.Brand).enabled(!this.isBulkTesting)
          }
          Button(this.isBulkTesting ? $r('app.string.source_manage_test_cancel') : $r('app.string.source_manage_test_start'),
            { type: ButtonType.Normal })
            .height(44).width('100%').fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).borderRadius(AppRadius.Sm)
            .enabled(this.busySourceUrl.length === 0)
            .onClick(() => { if (this.isBulkTesting) this.cancelBulkTest(); else this.runBulkTest(); })
        }.width('100%')
      }
      if (this.bulkTestTotal > 0) {
        ListItem() { this.buildBulkTestSection() }
      }
      if (!this.isBulkTesting && this.testFailures.length > 0) {
        ListItem() {
          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.source_manage_test_retry'), { type: ButtonType.Normal })
              .layoutWeight(1).height(44).fontSize(AppFont.Body).fontColor(AppColor.Brand)
              .backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Sm)
              .enabled(this.busySourceUrl.length === 0).onClick(() => this.runBulkTest(this.testFailures.slice()))
            Button() { SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(22).fontColor([AppColor.Brand]) }
              .width(44).height(44).backgroundColor(Color.Transparent).padding(0)
              .accessibilityText($r('app.string.source_manage_more')).enabled(this.busySourceUrl.length === 0)
              .bindMenu(this.buildFailureActions())
          }.width('100%')
        }
        LazyForEach(this.failureDataSource, (item: RuleSourceListItem) => {
          ListItem() {
            Column({ space: AppSpace.Xs }) {
              Row({ space: AppSpace.Sm }) {
                Text(item.source.bookSourceName).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button() { SymbolGlyph($r('sys.symbol.scope')).fontSize(20).fontColor([AppColor.Brand]) }
                  .width(44).height(44).padding(0).backgroundColor(Color.Transparent)
                  .accessibilityText($r('app.string.source_manage_debug')).onClick(() => this.debugSource(item.source))
              }.width('100%')
              Text(item.source.validationMessage).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
                .width('100%')
              if (this.certificateFailureHost(item.source).length > 0) {
                Button($r('app.string.source_manage_tls_retry'), { type: ButtonType.Normal })
                  .width('100%').height(40).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
                  .borderRadius(AppRadius.Sm).enabled(this.busySourceUrl.length === 0)
                  .onClick(() => this.confirmTrustHosts([this.certificateFailureHost(item.source)], [item.source]))
              }
              Divider().color($r('sys.color.comp_divider')).margin({ top: AppSpace.Sm })
            }.width('100%')
          }
        }, (item: RuleSourceListItem) => item.sourceUrl)
      }
    }.width('100%').layoutWeight(1).padding(AppSpace.Md)
  }

  @Builder
  buildFailureActions() {
    Menu() {
      MenuItem({ content: $r('app.string.source_manage_test_failed_disable') }).onClick(() => this.confirmDisableFailed())
      MenuItem({ content: $r('app.string.source_manage_test_failed_delete') }).onClick(() => this.confirmDeleteFailed())
    }
  }

  @Builder
  buildTlsManager() {
    Column({ space: AppSpace.Md }) {
      Row({ space: AppSpace.Sm }) {
        TextInput({ text: $$this.trustHostDraft, placeholder: $r('app.string.source_manage_tls_host') })
          .height(44).layoutWeight(1).fontSize(AppFont.Body).caretColor(AppColor.Brand)
        Button() { SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([AppColor.Brand]) }
          .height(44).width(44).padding(0).backgroundColor(AppColor.BrandSoft)
          .accessibilityText($r('app.string.source_manage_tls_trust'))
          .enabled(this.trustHostDraft.trim().length > 0 && this.busySourceUrl.length === 0)
          .onClick(() => this.confirmTrustDraft())
      }.width('100%')
      List() {
        ForEach(this.trustedHosts, (host: string) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Text(host).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
                .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Button() { SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([RULE_SOURCE_DANGER]) }
                .height(44).width(44).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText($r('app.string.source_manage_tls_revoke'))
                .enabled(this.busySourceUrl.length === 0).onClick(() => this.revokeHost(host))
            }.width('100%').constraintSize({ minHeight: 52 })
          }
        }, (host: string) => host)
        if (this.trustedHosts.length === 0) {
          ListItem() { Text($r('app.string.source_manage_tls_empty')).fontColor($r('sys.color.font_tertiary')).padding(20) }
        }
      }.width('100%').layoutWeight(1).divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
    }.width('100%').layoutWeight(1).padding(AppSpace.Md)
  }

  private canImportSources(): boolean {
    return !this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0 &&
      this.importJson.trim().length > 0;
  }

  private importColorChannel(hex: string, offset: number): number {
    const channel: number = parseInt(hex.substring(offset, offset + 2), 16) / 255;
    return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
  }

  private importActionForeground(): ResourceColor {
    if (!this.canImportSources()) return $r('app.color.text_secondary');
    const brand: ResourceStr = AppColor.Brand;
    // 默认深浅两套橙色都配黑字；自定义色按 sRGB 相对亮度选择对比度更高的黑/白。
    if (typeof brand !== 'string') return Color.Black;
    const luminance: number = 0.2126 * this.importColorChannel(brand, 1) +
      0.7152 * this.importColorChannel(brand, 3) + 0.0722 * this.importColorChannel(brand, 5);
    return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? Color.Black : Color.White;
  }

  @Builder
  buildImportSection() {
    Column({ space: AppSpace.Sm }) {
      Button($r('app.string.talebook_add'), { type: ButtonType.Normal })
        .width('100%').height(44).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
        .borderRadius(AppRadius.Sm)
        .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
        .onClick(() => { this.talebookSourceUrl = ''; this.showTalebook = true; })
      Column({ space: 2 }) {
        Text($r('app.string.rule_source_import_title'))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
        Text($r('app.string.rule_source_import_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
        if (MembershipState.featureEnabled) {
          Text($r('app.string.rule_source_membership_hint'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button() {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(18)
            .fontColor([AppColor.Brand])
          Text($r('app.string.rule_source_import_file_action'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColor.BrandSoft)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
      .opacity(this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0 ? 0.55 : 1)
      .onClick(() => this.importLocalFile())

      Text($r('app.string.rule_source_import_files_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      if (this.importFileTotal > 0) {
        Text($r('app.string.rule_source_import_files_progress', this.importFileCurrent, this.importFileTotal))
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
      }
      if (this.hasFileImportResult && !this.isImporting) {
        Column({ space: 4 }) {
          Text($r('app.string.rule_source_import_files_result', this.fileImportResult.imported,
            this.fileImportResult.skippedSources, this.fileImportResult.skippedFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          if (this.fileImportResult.oversizedFiles > 0) {
            Text($r('app.string.rule_source_import_files_oversized', this.fileImportResult.oversizedFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          }
          if (this.fileImportResult.budgetFiles > 0) {
            Text($r('app.string.rule_source_import_files_budget', this.fileImportResult.budgetFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          }
          if (this.fileImportResult.invalidFiles > 0) {
            Text($r('app.string.rule_source_import_files_invalid', this.fileImportResult.invalidFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          }
          if (this.fileImportResult.readFailedFiles > 0) {
            Text($r('app.string.rule_source_import_files_read_failed', this.fileImportResult.readFailedFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          }
          if (this.fileImportResult.writeFailedFiles > 0) {
            Text($r('app.string.rule_source_import_files_write_failed', this.fileImportResult.writeFailedFiles))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }

      Button() {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(18)
            .fontColor([AppColor.Brand])
          Text($r('app.string.rule_source_import_scan_action'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColor.BrandSoft)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
      .opacity(this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0 ? 0.55 : 1)
      .onClick(() => this.scanQRCode())
      .visibility(canIUse('SystemCapability.Multimedia.Scan.ScanBarcode') ? Visibility.Visible : Visibility.None)

      TextArea({
        placeholder: $r('app.string.rule_source_import_placeholder'),
        text: this.importJson
      })
        .width('100%')
        .height(132)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius(AppRadius.Sm)
        .padding(AppSpace.Sm)
        .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
        .onChange((value: string) => {
          this.importJson = value;
        })

      Stack() {
        // 禁用 Button 会淡化其整个内容子树；视觉内容独立绘制，保留真实按钮的禁用语义。
        Button()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(AppRadius.Sm)
          .enabled(this.canImportSources())
          .accessibilityText(this.isImporting ? $r('app.string.rule_source_importing') :
            $r('app.string.rule_source_import_action'))
          .onClick(() => this.importSources())

        Row({ space: AppSpace.Xs }) {
          if (this.isImporting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(18)
              .fontColor([this.importActionForeground()])
          }
          Text(this.isImporting ? $r('app.string.rule_source_importing') :
            $r('app.string.rule_source_import_action'))
            .fontSize(AppFont.Body)
            .fontColor(this.importActionForeground())
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      }
      .width('100%')
      .height(44)
      .backgroundColor(this.canImportSources() ? AppColor.Brand : $r('app.color.input_background'))
      .borderRadius(AppRadius.Sm)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
  }

  @Builder
  buildBulkTestSection() {
    Column({ space: AppSpace.Xs }) {
      Progress({
        value: this.bulkTestCompleted,
        total: this.bulkTestTotal,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(4)
        .color(AppColor.Brand)

      Row({ space: AppSpace.Xs }) {
        Text($r('app.string.rule_source_bulk_tested'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        Text(`${this.bulkTestCompleted}/${this.bulkTestTotal}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        Text($r('app.string.rule_source_bulk_passed'))
          .fontSize(AppFont.Caption)
          .fontColor(RULE_SOURCE_SUCCESS)
        Text(`${this.bulkTestPassed}`)
          .fontSize(AppFont.Caption)
          .fontColor(RULE_SOURCE_SUCCESS)
        Text($r('app.string.rule_source_bulk_failed_count'))
          .fontSize(AppFont.Caption)
          .fontColor(RULE_SOURCE_DANGER)
        Text(`${this.bulkTestFailed}`)
          .fontSize(AppFont.Caption)
          .fontColor(RULE_SOURCE_DANGER)
        Text($r('app.string.rule_source_bulk_retained'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        Text(`${this.bulkTestRetained}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.managementView !== 'test' || this.testCancelled) {
        Row() {
          if (this.testCancelled) {
            Text($r('app.string.source_manage_test_cancelled')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          } else { Blank() }
          if (this.managementView !== 'test') {
            Button(this.isBulkTesting ? $r('app.string.source_manage_test_settings') : $r('app.string.source_manage_test_failures'),
              { type: ButtonType.Normal })
              .height(36).fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick(() => { this.managementView = 'test'; })
          }
        }.width('100%')
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Xs, right: AppSpace.Xs, bottom: AppSpace.Xxs })
  }

  @Builder
  buildLoadFailed() {
    Column({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(32)
        .fontColor([RULE_SOURCE_DANGER])
      Text(this.sourceKeyUnavailable ? $r('app.string.rule_source_key_unavailable') :
        $r('app.string.rule_source_load_failed'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.common_retry'))
        .height(40)
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .backgroundColor(AppColor.BrandSoft)
        .borderRadius(AppRadius.Sm)
        .onClick(() => this.loadSources())
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.bookshelf'))
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.rule_source_empty'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.rule_source_empty_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildNoMatchState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.rule_source_no_match'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.rule_source_no_match_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }

  private toggleSourceExpanded(sourceUrl: string): void {
    const expanded = new Set(this.expandedSourceUrls);
    if (expanded.has(sourceUrl)) expanded.delete(sourceUrl);
    else expanded.add(sourceUrl);
    this.expandedSourceUrls = expanded;
  }

  @Builder
  buildSourceItem(item: RuleSourceListItem) {
    Column({ space: AppSpace.Xs }) {
      Row({ space: AppSpace.Sm }) {
        if (this.isEditMode) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isSourceSelected(item.source.bookSourceUrl, this.selectionRevision)) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([AppColor.OnBrand])
            }
          }
            .width(24)
            .height(24)
            .backgroundColor(this.isSourceSelected(item.source.bookSourceUrl, this.selectionRevision) ?
              AppColor.Brand : Color.Transparent)
            .border({
              width: 1.5,
              color: this.isSourceSelected(item.source.bookSourceUrl, this.selectionRevision) ?
                AppColor.Brand : $r('sys.color.font_tertiary')
            })
            .borderRadius(AppRadius.Pill)
            .accessibilityText($r('app.string.rule_source_select_hint'))
            .onClick(() => this.toggleSelectSource(item.source.bookSourceUrl))
        }

        Column({ space: 6 }) {
          Row({ space: AppSpace.Xs }) {
            Button() {
              SymbolGlyph(this.expandedSourceUrls.has(item.sourceUrl) ?
                $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                .fontSize(18).fontColor([$r('sys.color.font_tertiary')])
            }
            .width(32).height(40).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText(this.expandedSourceUrls.has(item.sourceUrl) ?
              $r('app.string.source_collapse') : $r('app.string.source_expand'))
            .onClick(() => this.toggleSourceExpanded(item.sourceUrl))
            if (item.source.isPinned) {
              SymbolGlyph($r('sys.symbol.pin')).fontSize(16).fontColor([AppColor.Brand])
                .accessibilityText($r('app.string.source_manage_pin'))
            }
            if (item.source.isLocked) {
              SymbolGlyph($r('sys.symbol.lock')).fontSize(16).fontColor([$r('sys.color.font_secondary')])
                .accessibilityText($r('app.string.source_manage_locked'))
            }
            Text(item.source.bookSourceName)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .constraintSize({ minHeight: 40 })
              .onClick(() => this.toggleSourceExpanded(item.sourceUrl))
            if (!this.isEditMode) {
              Button() { SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18).fontColor([AppColor.Brand]) }
                .width(32).height(32).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText($r('app.string.source_manage_actions'))
                .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
                .bindMenu(this.buildSourceMenu(item))
            }
          }
          .width('100%')

          if (this.expandedSourceUrls.has(item.sourceUrl)) {
            Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center, wrap: FlexWrap.Wrap }) {
              Text(this.sourceTypeLabel(item.source))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_secondary'))

              if (this.sourceGroupLabels(item.source).length > 0) {
                ForEach(this.sourceGroupLabels(item.source), (groupName: string) => {
                  Text(groupName)
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .margin({ left: AppSpace.Xs })
                    .backgroundColor($r('sys.color.background_secondary'))
                    .borderRadius(AppRadius.Xs)
                }, (groupName: string) => groupName)
              }
            }
            .width('100%')

            Text(item.source.bookSourceUrl)
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.isEditMode) {
          Toggle({ type: ToggleType.Switch, isOn: item.source.enabled && item.source.canExecute() })
            .selectedColor(AppColor.Brand)
            .enabled(!item.source.isLocked && item.source.canExecute() && !this.isImporting && !this.isBulkTesting &&
              this.busySourceUrl.length === 0)
            .onChange((isOn: boolean) => this.changeEnabled(item.source, isOn))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.expandedSourceUrls.has(item.sourceUrl)) {
        Row({ space: AppSpace.Xs }) {
          Column()
            .width(8)
            .height(8)
            .backgroundColor(this.statusColor(item.source.validationStatus))
            .borderRadius(AppRadius.Pill)
          Text(this.statusLabel(item.source.validationStatus))
            .fontSize(AppFont.Caption)
            .fontColor(this.statusColor(item.source.validationStatus))
            .fontWeight(FontWeight.Medium)
          Text(this.statusMessage(item.source))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!this.isEditMode) {
          if (item.source.exploreUrl.length > 0 || item.source.loginUi.length > 0 ||
            RuleSourceAccountService.supports(item.source.bookSourceUrl) || this.canOpenSourceLogin(item.source)) {
            Row({ space: AppSpace.Xs }) {
              if (item.source.exploreUrl.length > 0) {
                Button($r('app.string.rule_source_explore'), { type: ButtonType.Normal })
                  .layoutWeight(1).height(40).borderRadius(AppRadius.Sm)
                  .backgroundColor(AppColor.BrandSoft).fontColor(AppColor.Brand)
                  .enabled(item.source.enabledExplore && !this.isBulkTesting && !this.isImporting)
                  .onClick(() => this.navStack.pushPathByName('ruleSourceExplore', item.source.bookSourceUrl))
              }
              if (item.source.loginUi.length > 0 || RuleSourceAccountService.supports(item.source.bookSourceUrl) ||
                this.canOpenSourceLogin(item.source)) {
                Button(this.sourceLoginLabel(item.source), { type: ButtonType.Normal })
                  .layoutWeight(1).height(40).borderRadius(AppRadius.Sm)
                  .backgroundColor($r('sys.color.comp_background_secondary')).fontColor(AppColor.Brand)
                  .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
                  .onClick(() => this.openLoginEntry(item.source))
              }
            }.width('100%')
          }
          Divider()
            .strokeWidth(0.5)
            .color($r('sys.color.comp_divider'))

          Row({ space: AppSpace.Xs }) {
            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(16)
                  .fontColor([AppColor.Brand])
                Text($r('app.string.source_manage_edit'))
                  .fontSize(AppFont.Caption)
                  .fontColor(AppColor.Brand)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor(AppColor.BrandSoft)
            .borderRadius(AppRadius.Sm)
            .enabled(!item.source.isLocked && !this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .onClick(() => this.editSource(item.source))

            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.scope'))
                  .fontSize(16)
                  .fontColor([AppColor.Brand])
                Text($r('app.string.source_manage_debug'))
                  .fontSize(AppFont.Caption)
                  .fontColor(AppColor.Brand)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .borderRadius(AppRadius.Sm)
            .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .onClick(() => this.debugSource(item.source))

            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.bolt'))
                  .fontSize(16)
                  .fontColor([item.source.canExecute() ? AppColor.Brand : $r('sys.color.font_tertiary')])
                Text($r('app.string.rule_source_test_action'))
                  .fontSize(AppFont.Caption)
                  .fontColor(item.source.canExecute() ? AppColor.Brand : $r('sys.color.font_tertiary'))
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor(item.source.canExecute() ? AppColor.BrandSoft : Color.Transparent)
            .borderRadius(AppRadius.Sm)
            .enabled(item.source.canExecute() && !this.isImporting && !this.isBulkTesting &&
              this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_test_action'))
            .onClick(() => this.testSource(item.source))

            if (RuleSourceChildService.supports(item.source.bookSourceUrl)) {
              Button() {
                Row({ space: AppSpace.Xxs }) {
                  SymbolGlyph($r('sys.symbol.list_bullet'))
                    .fontSize(16)
                    .fontColor([AppColor.Brand])
                  Text($r('app.string.rule_source_child_action'))
                    .fontSize(AppFont.Caption)
                    .fontColor(AppColor.Brand)
                }
                .justifyContent(FlexAlign.Center)
              }
              .layoutWeight(1)
              .height(36)
              .constraintSize({ minWidth: 0 })
              .backgroundColor($r('sys.color.background_secondary'))
              .borderRadius(AppRadius.Sm)
              .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
              .accessibilityText($r('app.string.rule_source_child_action'))
              .onClick(() => this.openSourceChildren(item.source))
            }

            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([RULE_SOURCE_DANGER])
                Text($r('app.string.rule_source_delete_action'))
                  .fontSize(AppFont.Caption)
                  .fontColor(RULE_SOURCE_DANGER)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor(RULE_SOURCE_DANGER_SOFT)
            .borderRadius(AppRadius.Sm)
            .enabled(!item.source.isLocked && !this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_delete_action'))
            .onClick(() => this.confirmDelete(item.source))
          }
          .width('100%')
          .height(36)
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
    .border({ width: 1, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 6, color: AppColor.Shadow, offsetY: 2 })
  }
}
