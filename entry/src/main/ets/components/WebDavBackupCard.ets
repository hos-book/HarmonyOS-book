import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { AppBackupSnapshot } from '../service/AppBackupService';
import { WebDavBackupService, WebDavSettings, WebDavBackupError, WebDavErrorCode, WebDavPhase } from '../service/WebDavBackupService';

@ComponentV2
export struct WebDavBackupCard {
  @Param available: boolean = true;
  @Event runManual: (action: () => Promise<void>) => Promise<void> = async () => {};
  @Event confirm: (title: ResourceStr, message: ResourceStr, button: ResourceStr) => Promise<boolean> = async () => false;
  @Local service: WebDavBackupService = WebDavBackupService.instance;
  @Local expanded: boolean = false;
  @Local ready: boolean = false;
  @Local address: string = '';
  @Local username: string = '';
  @Local password: string = '';
  @Local message: ResourceStr = '';
  @Local hasMessage: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.service.cancel(); this.password = ''; }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      const settings = await this.service.loadSettings(context);
      if (!this.alive) return;
      this.address = settings.address;
      this.username = settings.username;
      this.password = settings.password;
      this.ready = true;
    } catch (_error) {
      this.message = $r('app.string.webdav_settings_failed');
      this.hasMessage = true;
    }
  }

  private settings(): WebDavSettings {
    const result = new WebDavSettings();
    result.address = this.address;
    result.username = this.username;
    result.password = this.password;
    return result;
  }

  private async action(kind: number): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive) return;
    this.hasMessage = false;
    try {
      const settings = WebDavBackupService.normalize(this.settings());
      if (kind === 2 && !await this.confirm($r('app.string.webdav_upload'),
        $r('app.string.webdav_upload_confirm'), $r('app.string.webdav_upload'))) return;
      if (!this.alive) return;
      try { await this.service.saveSettings(context, settings); }
      catch (_error) { this.message = $r('app.string.webdav_settings_failed'); this.hasMessage = true; return; }
      this.address = settings.address;
      if (kind === 0) this.message = $r('app.string.webdav_saved');
      else if (kind === 1) {
        await this.service.test(settings);
        this.message = $r('app.string.webdav_connected');
      } else if (kind === 2) {
        await this.service.backup(context, settings);
        this.message = $r('app.string.webdav_uploaded');
      } else {
        const restored = await this.service.restore(context, settings, (snapshot: AppBackupSnapshot): Promise<boolean> =>
          this.confirm($r('app.string.webdav_restore'),
            $r('app.string.cloud_restore_confirm_message', this.formatDate(snapshot.exportedAt),
              snapshot.preferences.favorites.length, snapshot.ruleSources.length), $r('app.string.cloud_restore_confirm')));
        if (!restored) return;
        this.message = $r('app.string.cloud_restore_success');
      }
      this.hasMessage = true;
    } catch (error) {
      if (error instanceof WebDavBackupError && error.code === WebDavErrorCode.CANCELLED) return;
      this.message = this.errorText(error instanceof WebDavBackupError ? error.code : WebDavErrorCode.SERVER);
      this.hasMessage = true;
    }
  }

  private async clear(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      await this.service.clearSettings(context);
      this.address = ''; this.username = ''; this.password = '';
      this.message = $r('app.string.webdav_cleared'); this.hasMessage = true;
    } catch (_error) { this.message = $r('app.string.webdav_settings_failed'); this.hasMessage = true; }
  }

  private formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')} ` +
      `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  private errorText(code: WebDavErrorCode): ResourceStr {
    switch (code) {
      case WebDavErrorCode.CONFIG: return $r('app.string.webdav_config_error');
      case WebDavErrorCode.AUTH: return $r('app.string.webdav_auth_error');
      case WebDavErrorCode.NOT_FOUND: return $r('app.string.webdav_not_found');
      case WebDavErrorCode.NETWORK: return $r('app.string.webdav_network_error');
      case WebDavErrorCode.TOO_LARGE: return $r('app.string.local_backup_too_large');
      case WebDavErrorCode.INVALID: return $r('app.string.local_backup_invalid');
      case WebDavErrorCode.RESTORE: return $r('app.string.cloud_error_restore');
      default: return $r('app.string.webdav_server_error');
    }
  }

  private phaseText(): ResourceStr {
    switch (this.service.phase) {
      case WebDavPhase.CONNECTING: return $r('app.string.webdav_connecting');
      case WebDavPhase.UPLOADING: return $r('app.string.webdav_uploading');
      case WebDavPhase.DOWNLOADING: return $r('app.string.cloud_phase_downloading');
      case WebDavPhase.CONFIRMING: return $r('app.string.cloud_phase_confirming');
      case WebDavPhase.RESTORING: return $r('app.string.cloud_phase_restoring');
      default: return $r('app.string.cloud_phase_preparing');
    }
  }

  @Builder
  private transferRow(upload: boolean) {
    Row({ space: AppSpace.Sm }) {
      SymbolGlyph(upload ? $r('sys.symbol.arrow_up_circle') : $r('sys.symbol.arrow_down_circle'))
        .fontSize(24).fontColor([AppColor.Brand]).width(28)
      Text(upload ? $r('app.string.webdav_upload') : $r('app.string.webdav_restore'))
        .fontSize(AppFont.BodyL).fontColor($r('sys.color.font_primary')).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%').constraintSize({ minHeight: 56 })
    .enabled(this.ready && this.available)
    .opacity(this.ready && this.available ? 1 : 0.5)
    .onClick(() => this.runManual((): Promise<void> => this.action(upload ? 2 : 3)))
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.webdav_title')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20).fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%').constraintSize({ minHeight: 40 }).onClick(() => { this.expanded = !this.expanded; })
      if (this.expanded) {
        Text($r('app.string.webdav_description')).fontSize(AppFont.Body).lineHeight(21)
          .fontColor($r('sys.color.font_secondary'))
        Column({ space: AppSpace.Sm }) {
          Text($r('app.string.webdav_address')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          TextInput({ text: this.address, placeholder: $r('app.string.webdav_address_hint') })
            .type(InputType.URL).maxLength(2048).onChange((value: string): void => { this.address = value; })
            .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(AppRadius.Md)
          Text($r('app.string.webdav_username')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          TextInput({ text: this.username, placeholder: $r('app.string.webdav_username') })
            .maxLength(512).onChange((value: string): void => { this.username = value; })
            .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(AppRadius.Md)
          Text($r('app.string.webdav_password')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          TextInput({ text: this.password, placeholder: $r('app.string.webdav_password') })
            .type(InputType.Password).maxLength(2048).onChange((value: string): void => { this.password = value; })
            .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(AppRadius.Md)
          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.webdav_save'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
              .onClick(() => this.runManual((): Promise<void> => this.action(0)))
            Button($r('app.string.webdav_test'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
              .onClick(() => this.runManual((): Promise<void> => this.action(1)))
            Button($r('app.string.webdav_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor($r('sys.color.font_secondary')).onClick(() => this.runManual((): Promise<void> => this.clear()))
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).enabled(this.ready && this.available)
        this.transferRow(true)
        Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: 36 })
        this.transferRow(false)
        if (this.service.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text(this.phaseText()).fontSize(AppFont.Body).fontColor(AppColor.Brand).layoutWeight(1)
            if (this.service.phase !== WebDavPhase.RESTORING && this.service.phase !== WebDavPhase.CONFIRMING) {
              Button($r('app.string.hw_auth_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .fontColor(AppColor.Brand).onClick(() => this.service.cancel())
            }
          }.width('100%')
        }
        if (this.hasMessage) {
          Text(this.message).fontSize(AppFont.Body).lineHeight(21).fontColor($r('sys.color.font_secondary'))
        }
        if (!this.ready) {
          Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontColor(AppColor.Brand).onClick(() => this.load())
        }
        Text($r('app.string.local_backup_exclusions')).fontSize(AppFont.Caption).lineHeight(19)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
  }
}
