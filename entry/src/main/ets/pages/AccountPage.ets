import { BusinessError } from '@kit.BasicServicesKit';
import { AccountAvatar } from '../components/AccountAvatar';
import { MembershipBadge } from '../components/MembershipBadge';
import { VipFeatureBadge } from '../components/VipFeatureBadge';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { AuthService, HwAuthErrorCode } from '../service/AuthService';
import { AppBackupSnapshot } from '../service/AppBackupService';
import { AutoBackupService } from '../service/AutoBackupService';
import { MembershipState } from '../model/MembershipState';
import { MembershipService } from '../service/MembershipService';
import {
  LocalBackupError, LocalBackupErrorCode, LocalBackupPhase, LocalBackupService
} from '../service/LocalBackupService';
import {
  CloudBackupError, CloudBackupErrorCode, CloudBackupInfo, CloudBackupPhase, CloudBackupService
} from '../service/CloudBackupService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct AccountPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local auth: AuthService = AuthService.instance;
  @Local cloud: CloudBackupService = CloudBackupService.instance;
  @Local local: LocalBackupService = LocalBackupService.instance;
  @Local automatic: AutoBackupService = AutoBackupService.instance;
  @Local membership: MembershipState = MembershipState.current;
  @Local membershipService: MembershipService = MembershipService.instance;
  @Local checkingMembership: boolean = false;
  @Local manualPending: boolean = false;
  @Local autoReady: boolean = false;
  @Local message: ResourceStr = '';
  @Local hasMessage: boolean = false;
  @Local cloudSystemCode: number = 0;
  @Local localMessage: ResourceStr = '';
  @Local hasLocalMessage: boolean = false;
  @Local localBackupExpanded: boolean = false;
  @Local cloudBackupExpanded: boolean = false;
  private finishConfirmation: ((confirmed: boolean) => void) | null = null;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.auth.restore(context).then(async (): Promise<void> => {
        await this.automatic.refresh(context);
        this.autoReady = true;
        await this.cloud.refresh(context);
      });
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.finishConfirmation?.(false);
    this.finishConfirmation = null;
    if (!this.automatic.running) this.cloud.cancel();
    this.local.cancel();
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private interceptBack(): boolean {
    if (!this.manualPending && ((!this.auth.dataOperation && !this.auth.logging) || this.automatic.running)) return false;
    this.toast($r('app.string.account_wait_operation'));
    return true;
  }

  private manualAvailable(): boolean {
    return !this.manualPending && !this.automatic.configuring && !this.auth.logging &&
      (!this.auth.restoring || this.automatic.running) && (!this.auth.dataOperation || this.automatic.running);
  }

  private async runManual(action: () => Promise<void>): Promise<void> {
    if (!this.manualAvailable()) return;
    this.manualPending = true;
    await this.automatic.pauseForManual();
    try {
      await action();
    } finally {
      this.automatic.resumeAfterManual();
      this.manualPending = false;
    }
  }

  private async requireAutoMembership(): Promise<boolean> {
    if (!MembershipState.featureEnabled) return this.alive;
    if (this.checkingMembership) return false;
    this.checkingMembership = true;
    try {
      const entitled = await this.membershipService.hasCurrentEntitlement();
      if (!this.alive) return false;
      if (entitled) return true;
      if (this.membership.confirmedInactive) {
        this.navStack.pushPathByName('membershipSubscription', '');
      } else {
        this.toast(this.membershipService.message);
      }
      return false;
    } finally {
      this.checkingMembership = false;
    }
  }

  private async setAutomatic(enabled: boolean, days: number): Promise<void> {
    if (!await this.requireAutoMembership()) return;
    const context = this.getUIContext().getHostContext();
    if (!context || !this.auth.isLoggedIn || !this.manualAvailable()) return;
    try {
      await this.automatic.configure(context, enabled, days);
    } catch (_error) {
      if (!this.alive) return;
      this.toast(this.membership.hasAccess ? $r('app.string.auto_backup_save_failed') :
        this.membership.confirmedInactive ? $r('app.string.auto_backup_membership_required') : this.membershipService.message);
    }
  }

  private autoFrequency(): ResourceStr {
    return this.automatic.settings.intervalDays === 7 ? $r('app.string.auto_backup_weekly') :
      this.automatic.settings.intervalDays === 3 ? $r('app.string.auto_backup_three_days') :
        $r('app.string.auto_backup_daily');
  }

  private async chooseFrequency(): Promise<void> {
    if (!await this.requireAutoMembership()) return;
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.auto_backup_frequency'),
      buttons: [
        { text: $r('app.string.auto_backup_daily'), color: AppColor.Brand },
        { text: $r('app.string.auto_backup_three_days'), color: AppColor.Brand },
        { text: $r('app.string.auto_backup_weekly'), color: AppColor.Brand }
      ]
    }).then((result): void => {
      this.setAutomatic(this.automatic.settings.enabled, result.index === 2 ? 7 : result.index === 1 ? 3 : 1);
    }).catch((): void => {});
  }

  private autoStatus(): ResourceStr {
    if (this.membershipService.busy || this.checkingMembership) return $r('app.string.membership_syncing');
    if (!this.membership.hasAccess) return this.membership.confirmedInactive ?
      $r('app.string.auto_backup_membership_required') : this.membershipService.message;
    if (!this.auth.isLoggedIn) return $r('app.string.auto_backup_login_required');
    if (this.automatic.storageFailed) return $r('app.string.auto_backup_save_failed');
    if (this.automatic.accountId !== this.auth.openID || !this.automatic.settings.enabled) {
      return $r('app.string.auto_backup_off');
    }
    if (this.automatic.settings.needsDecision) return $r('app.string.auto_backup_existing');
    if (this.automatic.running && this.cloud.busy) return $r('app.string.auto_backup_running');
    if (this.automatic.settings.errorCode === CloudBackupErrorCode.CANCELLED) {
      return $r('app.string.auto_backup_waiting');
    }
    if (this.automatic.settings.errorCode !== 0) return this.cloudErrorText(this.automatic.settings.errorCode);
    return $r('app.string.auto_backup_ready');
  }

  private lastBackupAt(): number {
    return Math.max(this.cloud.lastBackupAt,
      this.automatic.accountId === this.auth.openID ? this.automatic.settings.lastSuccessAt : 0);
  }

  private async updateProfile(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      await this.auth.login(context);
      await this.automatic.refresh(context);
      await this.cloud.refresh(context);
      this.toast($r('app.string.account_profile_updated'));
    } catch (error) {
      const failure: BusinessError = error;
      if (failure.code === HwAuthErrorCode.USER_CANCEL || failure.code === HwAuthErrorCode.REQUEST_REFUSE) return;
      this.toast(failure.code === HwAuthErrorCode.NETWORK ? $r('app.string.hw_auth_network_error') :
        failure.code === HwAuthErrorCode.CERT_INVALID ? $r('app.string.hw_auth_unavailable') :
          $r('app.string.account_profile_failed'));
    }
  }

  private profileActionColor(): ResourceColor {
    return this.auth.isLoggedIn ? AppColor.Brand : $r('sys.color.font_tertiary');
  }

  private logout(): void {
    if (!this.manualAvailable()) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.hw_auth_logout_title'),
      message: $r('app.string.hw_auth_logout_message'),
      primaryButton: {
        value: $r('app.string.hw_auth_logout_title'),
        fontColor: '#FF3B30',
        action: () => {
          this.runManual(async (): Promise<void> => {
            await this.auth.logout();
            const context = this.getUIContext().getHostContext();
            if (context) await this.automatic.refresh(context);
            this.cloud.lastBackupAt = 0;
            this.navStack.pop();
            this.toast($r('app.string.hw_auth_logout_success'));
          }).catch(() => this.toast($r('app.string.hw_auth_logout_failed')));
        }
      },
      secondaryButton: { value: $r('app.string.hw_auth_cancel'), action: () => {} }
    });
  }

  private async backup(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasMessage = false;
    this.cloudSystemCode = 0;
    try {
      if (this.automatic.settings.needsDecision && !await this.confirmRestore(
        $r('app.string.auto_backup_use_local_title'), $r('app.string.auto_backup_use_local_message'),
        $r('app.string.auto_backup_use_local_title'))) return;
      const result = await this.cloud.backup(context);
      await this.automatic.recordManualSuccess(context, result);
      this.message = $r('app.string.cloud_backup_success');
      this.hasMessage = true;
    } catch (error) {
      this.showCloudError(error);
    }
  }

  private async restore(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasMessage = false;
    this.cloudSystemCode = 0;
    const accountId = this.auth.openID;
    try {
      const restored = await this.cloud.restore(context,
        (info: CloudBackupInfo): Promise<boolean> => this.confirmRestore(
          $r('app.string.cloud_restore_confirm_title'),
          $r('app.string.cloud_restore_confirm_message', this.formatDate(info.exportedAt),
            info.bookCount, info.sourceCount)));
      if (restored) {
        await this.automatic.recordRestoreSuccess(context, accountId);
        this.message = $r('app.string.cloud_restore_success');
        this.hasMessage = true;
      }
    } catch (error) {
      this.showCloudError(error);
    }
  }

  private async exportLocal(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasLocalMessage = false;
    try {
      const snapshot = await this.local.backup(context);
      if (snapshot) {
        this.localMessage = $r('app.string.local_backup_success', snapshot.ruleSources.length);
        this.hasLocalMessage = true;
      }
    } catch (error) {
      this.showLocalError(error);
    }
  }

  private async restoreLocal(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasLocalMessage = false;
    try {
      const restored = await this.local.restore(context,
        (snapshot: AppBackupSnapshot): Promise<boolean> => this.confirmRestore(
          $r('app.string.local_restore_confirm_title'),
          $r('app.string.cloud_restore_confirm_message', this.formatDate(snapshot.exportedAt),
            snapshot.preferences.favorites.length, snapshot.ruleSources?.length ?? 0)));
      if (restored) {
        this.localMessage = $r('app.string.cloud_restore_success');
        this.hasLocalMessage = true;
      }
    } catch (error) {
      this.showLocalError(error);
    }
  }

  private showLocalError(error: LocalBackupError): void {
    if (error.code === LocalBackupErrorCode.CANCELLED) return;
    switch (error.code) {
      case LocalBackupErrorCode.INVALID_BACKUP:
        this.localMessage = $r('app.string.local_backup_invalid'); break;
      case LocalBackupErrorCode.TOO_LARGE:
        this.localMessage = $r('app.string.local_backup_too_large'); break;
      case LocalBackupErrorCode.FILE_ACCESS:
        this.localMessage = $r('app.string.local_backup_file_error'); break;
      case LocalBackupErrorCode.RESTORE_FAILED:
        this.localMessage = $r('app.string.cloud_error_restore'); break;
      default:
        this.localMessage = $r('app.string.local_backup_prepare_error'); break;
    }
    this.hasLocalMessage = true;
  }

  private localPhaseText(): ResourceStr {
    switch (this.local.phase) {
      case LocalBackupPhase.SELECTING: return $r('app.string.local_backup_selecting');
      case LocalBackupPhase.COPYING: return $r('app.string.local_backup_copying');
      case LocalBackupPhase.CONFIRMING: return $r('app.string.cloud_phase_confirming');
      case LocalBackupPhase.RESTORING: return $r('app.string.cloud_phase_restoring');
      default: return $r('app.string.cloud_phase_preparing');
    }
  }

  private confirmRestore(title: ResourceStr, message: ResourceStr,
    confirmText: ResourceStr = $r('app.string.cloud_restore_confirm')): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const finish = (confirmed: boolean): void => {
        this.finishConfirmation = null;
        resolve(confirmed);
      };
      this.finishConfirmation = finish;
      this.getUIContext().showAlertDialog({
        title,
        message,
        primaryButton: { value: confirmText, action: () => finish(true) },
        secondaryButton: { value: $r('app.string.hw_auth_cancel'), action: () => finish(false) },
        cancel: () => finish(false)
      });
    });
  }

  private showCloudError(error: CloudBackupError): void {
    this.message = this.cloudErrorText(error.code);
    this.cloudSystemCode = error.systemCode ?? 0;
    this.hasMessage = true;
  }

  private cloudErrorText(code: CloudBackupErrorCode): ResourceStr {
    switch (code) {
      case CloudBackupErrorCode.UNAVAILABLE: return $r('app.string.cloud_error_unavailable');
      case CloudBackupErrorCode.NOT_READY: return $r('app.string.cloud_error_not_ready');
      case CloudBackupErrorCode.NETWORK: return $r('app.string.cloud_error_network');
      case CloudBackupErrorCode.BATTERY: return $r('app.string.cloud_error_battery');
      case CloudBackupErrorCode.CLOUD_FULL: return $r('app.string.cloud_error_cloud_full');
      case CloudBackupErrorCode.LOCAL_FULL: return $r('app.string.cloud_error_local_full');
      case CloudBackupErrorCode.HOT: return $r('app.string.cloud_error_hot');
      case CloudBackupErrorCode.SERVER: return $r('app.string.cloud_error_server');
      case CloudBackupErrorCode.TIMEOUT: return $r('app.string.cloud_error_timeout');
      case CloudBackupErrorCode.CANCELLED: return $r('app.string.cloud_error_cancelled');
      case CloudBackupErrorCode.ACCOUNT_CHANGED: return $r('app.string.cloud_error_account');
      case CloudBackupErrorCode.NO_BACKUP: return $r('app.string.cloud_error_empty');
      case CloudBackupErrorCode.INVALID_BACKUP: return $r('app.string.cloud_error_invalid');
      case CloudBackupErrorCode.RESTORE_FAILED: return $r('app.string.cloud_error_restore');
      case CloudBackupErrorCode.CLOUD_FILE_FAILURE: return $r('app.string.cloud_error_file');
      default: return $r('app.string.cloud_error_local');
    }
  }

  private phaseText(): ResourceStr {
    switch (this.cloud.phase) {
      case CloudBackupPhase.SYNCING: return $r('app.string.cloud_phase_syncing');
      case CloudBackupPhase.DOWNLOADING: return $r('app.string.cloud_phase_downloading');
      case CloudBackupPhase.CONFIRMING: return $r('app.string.cloud_phase_confirming');
      case CloudBackupPhase.RESTORING: return $r('app.string.cloud_phase_restoring');
      default: return $r('app.string.cloud_phase_preparing');
    }
  }

  private formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')} ` +
      `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}:` +
      `${String(date.getSeconds()).padStart(2, '0')}`;
  }

  build() {
    ProfileMenuDestination({
      pageBackground: $r('sys.color.background_secondary'),
      onBackRequested: (): boolean => this.interceptBack()
    }) {
      Column() {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .width(40)
            .height(40)
            .onClick(() => { if (!this.interceptBack()) this.navStack.pop(); })
            .accessibilityText($r('app.string.account_back'))
          Text($r('app.string.account_title'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        .padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })

        Scroll() {
          Column({ space: AppSpace.Lg }) {
            this.profileCard()
            this.localBackupCard()
            this.backupCard()
            if (this.auth.isLoggedIn) {
              Button($r('app.string.hw_auth_logout_title'), { type: ButtonType.Normal })
                .width('100%')
                .height(52)
                .fontSize(AppFont.BodyL)
                .fontColor($r('sys.color.font_secondary'))
                .backgroundColor($r('sys.color.comp_background_primary'))
                .borderRadius(AppRadius.Lg)
                .enabled(this.manualAvailable())
                .onClick(() => this.logout())
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm,
            bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  profileCard() {
    Row({ space: AppSpace.Md }) {
      AccountAvatar({ uri: this.auth.avatarUri, avatarSize: 48 })
      Column({ space: 4 }) {
        Text(this.auth.isLoggedIn ? (this.auth.nickName || $r('app.string.hw_auth_account_title')) :
          $r('app.string.hw_auth_login_title'))
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.auth.isLoggedIn ? this.membership.nameColor : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.membership.displayActive) {
          MembershipBadge({ productId: this.membership.displayProductId, badgeHeight: 28, compact: true })
        }
        Text(this.auth.isLoggedIn ? $r('app.string.account_huawei_connected') : $r('app.string.account_local_available'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.profileActionIndicator()
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
    .enabled(this.manualAvailable())
    .accessibilityText(this.auth.isLoggedIn ? $r('app.string.account_profile_refresh') :
      $r('app.string.hw_auth_login_title'))
    .onClick(() => this.runManual((): Promise<void> => this.updateProfile()))
  }

  @Builder
  profileActionIndicator() {
    Stack() {
      if (this.auth.logging || this.auth.restoring) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AppColor.Brand)
      } else {
        SymbolGlyph(this.auth.isLoggedIn ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([this.profileActionColor()])
      }
    }
    .width(40)
    .height(40)
  }

  @Builder
  localBackupCard() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.local_backup_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.localBackupExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .onClick(() => { this.localBackupExpanded = !this.localBackupExpanded; })
      if (this.localBackupExpanded) {
        Text($r('app.string.local_backup_description'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(21)
        Column() {
          this.backupAction(true, true)
          Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: 36 })
          this.backupAction(false, true)
        }
        .width('100%')
        .enabled(this.manualAvailable())
        .opacity(this.manualAvailable() ? 1 : 0.5)
        if (this.local.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text(this.localPhaseText()).fontSize(AppFont.Body).fontColor(AppColor.Brand).layoutWeight(1)
          }
          .width('100%')
          .constraintSize({ minHeight: 40 })
        }
        if (this.hasLocalMessage) {
          Text(this.localMessage)
            .fontSize(AppFont.Body)
            .lineHeight(21)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        Text($r('app.string.local_backup_exclusions'))
          .fontSize(AppFont.Caption)
          .lineHeight(19)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  automaticBackupSettings() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.auto_backup_title'))
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .flexShrink(1)
          if (MembershipState.featureEnabled) {
            VipFeatureBadge()
          }
        }.layoutWeight(1)
        Stack() {
        Toggle({ type: ToggleType.Switch, isOn: this.membership.hasAccess && this.auth.isLoggedIn &&
          this.automatic.accountId === this.auth.openID && this.automatic.settings.enabled })
          .selectedColor(AppColor.Brand)
          .enabled(this.membership.hasAccess && this.autoReady && this.auth.isLoggedIn && this.manualAvailable() &&
            !this.membershipService.busy && !this.checkingMembership)
          .accessibilityText($r('app.string.auto_backup_title'))
          .onChange((enabled: boolean): void => { this.setAutomatic(enabled, this.automatic.settings.intervalDays); })
          if (!this.membership.hasAccess) {
            Button({ type: ButtonType.Normal }) {
              Row().width(52).height(32)
            }
            .backgroundColor(Color.Transparent)
            .accessibilityText(this.membership.confirmedInactive ?
              $r('app.string.auto_backup_membership_required') : $r('app.string.common_retry'))
            .enabled(!this.membershipService.busy && !this.checkingMembership)
            .onClick(() => this.requireAutoMembership())
          }
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 44 })
      if (this.auth.isLoggedIn && this.automatic.accountId === this.auth.openID) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.auto_backup_frequency'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(this.autoFrequency()).fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([$r('sys.color.font_tertiary')])
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .enabled((!this.membership.hasAccess || this.automatic.settings.enabled) && this.manualAvailable() &&
          !this.membershipService.busy && !this.checkingMembership)
        .onClick(() => this.chooseFrequency())
      }
      Text(this.autoStatus()).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor($r('sys.color.font_secondary'))
      if (this.membershipService.busy || this.checkingMembership) {
        LoadingProgress().width(18).height(18).color(AppColor.Brand)
      } else if (!this.membership.hasAccess && !this.membership.confirmedInactive) {
        Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontColor(AppColor.Brand).onClick(() => this.requireAutoMembership())
      }
      if (this.auth.isLoggedIn && this.automatic.accountId === this.auth.openID &&
        this.automatic.settings.enabled && this.automatic.settings.errorCode !== 0 &&
        !this.automatic.settings.needsDecision) {
        Text($r('app.string.auto_backup_retry')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.automatic.settings.systemCode !== 0) {
          Text($r('app.string.cloud_error_code', this.automatic.settings.systemCode)).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      Text($r('app.string.auto_backup_description')).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  backupCard() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.cloud_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.cloudBackupExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .onClick(() => { this.cloudBackupExpanded = !this.cloudBackupExpanded; })
      if (this.cloudBackupExpanded) {
        Text($r('app.string.cloud_description'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(21)
        this.automaticBackupSettings()

        Column() {
          this.backupAction(true, false)
          Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: 36 })
          this.backupAction(false, false)
        }
        .width('100%')
        .enabled(this.auth.isLoggedIn && this.manualAvailable())
        .opacity(this.auth.isLoggedIn && this.manualAvailable() ? 1 : 0.5)

        if (this.cloud.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text(this.phaseText()).fontSize(AppFont.Body).fontColor(AppColor.Brand).layoutWeight(1)
            if (this.cloud.phase !== CloudBackupPhase.RESTORING && this.cloud.phase !== CloudBackupPhase.CONFIRMING) {
              Button($r('app.string.hw_auth_cancel'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_secondary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .onClick(() => this.cloud.cancel())
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 40 })
        }
        if (this.hasMessage) {
          Text(this.message)
            .fontSize(AppFont.Body)
            .lineHeight(21)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          if (this.cloudSystemCode !== 0) {
            Text($r('app.string.cloud_error_code', this.cloudSystemCode))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
        }
        Text(this.auth.isLoggedIn && this.lastBackupAt() > 0
          ? $r('app.string.cloud_last_backup', this.formatDate(this.lastBackupAt()))
          : $r('app.string.cloud_last_backup_unknown'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .id('cloud-last-backup-time')
        Text($r('app.string.cloud_backup_exclusions'))
          .fontSize(AppFont.Caption)
          .lineHeight(19)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  backupAction(upload: boolean, local: boolean) {
    Row({ space: AppSpace.Sm }) {
      SymbolGlyph(upload ? $r('sys.symbol.arrow_up_circle') : $r('sys.symbol.arrow_down_circle'))
        .fontSize(24)
        .fontColor([AppColor.Brand])
        .width(28)
        .height(28)
      Column({ space: 2 }) {
        Text(local ? (upload ? $r('app.string.local_backup_export') : $r('app.string.local_backup_restore')) :
          (upload ? $r('app.string.cloud_backup_now') : $r('app.string.cloud_restore')))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        Text(local ? (upload ? $r('app.string.local_backup_export_desc') : $r('app.string.local_backup_restore_desc')) :
          (upload ? $r('app.string.cloud_backup_now_desc') : $r('app.string.cloud_restore_desc')))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(24).fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .onClick(() => {
      if (local) {
        this.runManual((): Promise<void> => upload ? this.exportLocal() : this.restoreLocal());
      } else {
        this.runManual((): Promise<void> => upload ? this.backup() : this.restore());
      }
    })
  }
}
