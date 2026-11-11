import { sendableContextManager } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { RoleModelState, RoleSpeaker, RoleSpeechSample, RoleSpeechState } from '../model/RoleSpeech';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { RoleModelService } from '../service/text/RoleModelService';
import { RoleSpeechService } from '../service/text/RoleSpeechService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { VoicePreviewService, VoicePreviewState } from '../service/text/VoicePreviewService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { ReaderTtsDataSource } from './ReaderTtsTabs';

class RoleSpeakerDataSource implements IDataSource {
  private items: RoleSpeaker[] = [];
  private listeners: DataChangeListener[] = [];
  update(items: RoleSpeaker[]): void {
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  totalCount(): number { return this.items.length; }
  getData(index: number): RoleSpeaker { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}

/** 阅读器与设置页共用配音交互，模型统一在“我的 → 模型管理”中管理。 */
@ComponentV2
export struct RoleSpeechPanel {
  @Param bookId: string = '';
  @Param bookTitle: string = '';
  @Param embedded: boolean = false;
  @Param active: boolean = true;
  @Param topInset: number = 0;
  @Param bottomInset: number = 0;
  @Event onClose: () => void = () => {};
  @Local model: RoleModelState = RoleModelService.getInstance().state;
  @Local liveRoles: RoleSpeechState = RoleSpeechService.getInstance().state;
  @Local savedRoles: RoleSpeechState = new RoleSpeechState();
  @Local speech: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local targetId: string = '';
  @Local targetTitle: string = '';
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local saving: boolean = false;
  @Local editing: boolean = false;
  @Local selectedRole: string = '';
  @Local selectedName: ResourceStr = '';
  @Local selectedVoice: string = '';
  @Local voiceQuery: string = '';
  @Local sampleText: string = '';
  private service: TextToSpeechService = TextToSpeechService.getInstance();
  private preview: VoicePreviewService = new VoicePreviewService();
  @Local previewState: VoicePreviewState = this.preview.state;
  private speakers: RoleSpeakerDataSource = new RoleSpeakerDataSource();
  private voices: ReaderTtsDataSource = new ReaderTtsDataSource();
  private alive: boolean = false;
  private readonly backgroundHandler = (): void => this.preview.stop();

  aboutToAppear(): void {
    this.alive = true;
    emitter.on('app.reader.background', this.backgroundHandler);
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    emitter.off('app.reader.background', this.backgroundHandler);
    this.finishPreview();
  }

  @Monitor('active')
  activeChanged(): void { if (!this.active) this.finishPreview(); }

  private async finishPreview(): Promise<void> {
    try { await this.preview.stopAndResume(); } catch (_error) { /* 原会话错误由播放器展示。 */ }
  }

  private roles(): RoleSpeechState {
    return this.targetId && this.liveRoles.bookId === this.targetId ? this.liveRoles : this.savedRoles;
  }

  private primary(): Resource { return this.embedded ? $r('sys.color.font_primary') : AppTheme.TextPrimary; }
  private secondary(): Resource { return this.embedded ? $r('sys.color.font_secondary') : AppTheme.TextSecondary; }
  private surface(): Resource { return this.embedded ? $r('sys.color.comp_background_tertiary') : AppTheme.Surface; }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try {
      await this.service.initialize(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)));
      await RoleModelService.getInstance().initialize(context);
      const book = this.service.currentBook();
      this.targetId = this.bookId || book?.id || '';
      this.targetTitle = this.bookTitle || book?.title || '';
      if (this.targetId) {
        // 独立读配置，不让设置页切换播放服务的书籍/章节上下文。
        const stored = new RoleSpeechService();
        await stored.selectBook(context, this.targetId, this.targetTitle);
        if (!this.alive) return;
        this.savedRoles = stored.state;
      }
      if (!this.alive) return;
      this.refreshSpeakers(); this.refreshVoices(); this.ready = true;
    } catch (_error) { if (this.alive) this.failed = true; }
  }

  @Monitor('liveRoles.speakers', 'liveRoles.bookId', 'savedRoles.speakers', 'targetId')
  refreshSpeakers(): void { this.speakers.update(this.roles().speakers); }

  @Monitor('voiceQuery', 'speech.customTtsConfigs')
  refreshVoices(): void {
    const query = this.voiceQuery.trim().toLowerCase();
    this.voices.update(this.speech.customTtsConfigs.filter((item: CustomTtsConfig): boolean =>
      item.enabled && (!query || item.name.toLowerCase().includes(query))), false);
  }

  private toast(message: ResourceStr): void { if (this.alive) this.getUIContext().getPromptAction().showToast({ message }); }
  private voiceName(id: string): ResourceStr {
    if (!id) return $r('app.string.role_follow_voice');
    return this.speech.customTtsConfigs.find((item: CustomTtsConfig): boolean => item.id === id && item.enabled)?.name ??
      $r('app.string.role_voice_unavailable');
  }

  private chooseVoice(id: string, name: ResourceStr, voice: string): void {
    if (this.saving || this.model.busy) return;
    this.finishPreview();
    this.selectedRole = id; this.selectedName = name; this.selectedVoice = voice; this.voiceQuery = '';
    this.sampleText = this.liveRoles.bookId === this.targetId ? RoleSpeechService.getInstance().sample(id) : '';
    if (!this.sampleText) {
      this.sampleText = this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.tts_preview_sample').id) ?? '';
    }
    this.refreshVoices(); this.editing = true;
  }

  private async saveVoice(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || !this.targetId || this.model.busy) return;
    if (this.selectedVoice && !this.speech.customTtsConfigs.some((item: CustomTtsConfig): boolean =>
      item.id === this.selectedVoice && item.enabled)) { this.toast($r('app.string.role_voice_unavailable')); return; }
    this.saving = true;
    try {
      await this.finishPreview();
      let roles = RoleSpeechService.getInstance();
      if (roles.state.bookId !== this.targetId) {
        roles = new RoleSpeechService();
        await roles.selectBook(context, this.targetId, this.targetTitle);
      }
      await roles.setVoice(this.selectedRole, this.selectedVoice);
      this.savedRoles = roles.state;
      this.service.roleVoiceChanged(this.targetId);
      if (this.alive) { this.editing = false; this.refreshSpeakers(); this.toast($r('app.string.role_voice_saved')); }
    } catch (_error) { this.toast($r('app.string.role_save_error')); }
    finally { this.saving = false; }
  }

  private async change(action: () => Promise<void>): Promise<void> {
    if (this.saving || this.model.busy) return;
    this.saving = true;
    await this.finishPreview();
    const bookId = this.speech.bookId;
    const ticket = this.service.pauseForPreview();
    try { await action(); }
    catch (_error) { this.toast($r('app.string.role_save_error')); }
    finally {
      if (this.speech.bookId === bookId && !this.speech.playing && !this.speech.loading) {
        try { await this.service.refreshRoleSpeech(this.service.canResumePreview(ticket)); }
        catch (_error) { this.toast($r('app.string.role_save_error')); }
      }
      this.saving = false;
    }
  }

  private async audition(): Promise<void> {
    if (this.previewState.active) { await this.finishPreview(); return; }
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.model.busy || !this.active) return;
    const samples: RoleSpeechSample[] = this.editing ? [new RoleSpeechSample(this.sampleText, this.selectedVoice)] :
      this.liveRoles.bookId === this.targetId ? RoleSpeechService.getInstance().preview(this.speech.playbackOffset) : [];
    if (samples.length === 0) { this.toast($r('app.string.role_preview_empty')); return; }
    try { await this.preview.playSequence(context, this.speech, samples, true); }
    catch (_error) { this.toast($r('app.string.tts_preview_error')); }
    if (this.previewState.error) this.toast($r('app.string.tts_preview_error'));
  }

  @Builder
  roleRow(id: string, name: ResourceStr, voice: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpace.Sm }) {
        Column({ space: AppSpace.Xxs }) {
          Text(name).fontSize(AppFont.BodyL).fontColor(this.primary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.voiceName(voice)).fontSize(AppFont.Caption).fontColor(this.secondary())
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.secondary()])
      }.width('100%')
    }.width('100%').padding(AppSpace.Md).constraintSize({ minHeight: 64 }).borderRadius(AppRadius.Lg)
      .backgroundColor(this.surface()).enabled(!this.saving && !this.model.busy)
      .onClick((): void => this.chooseVoice(id, name, voice)).id(`role-voice-${id}`)
  }

  @Builder
  voiceChoice(id: string, label: ResourceStr) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpace.Sm }) {
        Text(label).layoutWeight(1).fontSize(AppFont.BodyL).fontColor(this.primary())
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([AppColor.Brand])
          .opacity(id === this.selectedVoice ? 1 : 0)
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 56 }).padding(AppSpace.Md).borderRadius(AppRadius.Lg)
      .backgroundColor(this.surface()).accessibilitySelected(id === this.selectedVoice).enabled(!this.saving)
      .onClick((): void => { this.finishPreview(); this.selectedVoice = id; }).id(`role-choice-${id || 'default'}`)
  }

  @Builder
  previewButton() {
    Button(this.previewState.loading ? $r('app.string.role_preview_loading') :
      this.previewState.active ? $r('app.string.tts_preview_stop') :
        this.editing ? $r('app.string.tts_preview') : $r('app.string.role_preview_passage'))
      .fontSize(AppFont.Body).fontColor(AppColor.Brand)
      .backgroundColor(this.editing ? this.surface() : Color.Transparent)
      .padding({ left: this.editing ? AppSpace.Md : 0, right: this.editing ? AppSpace.Md : 0 })
      .flexShrink(0)
      .constraintSize({ minHeight: 44 }).enabled(!this.saving && !this.model.busy)
      .onClick((): void => { this.audition(); }).id('role-preview')
  }

  @Builder
  roleList() {
    List({ space: AppSpace.Xs }) {
      ListItem() {
        if (this.model.model === null) {
          Column({ space: AppSpace.Sm }) {
            Text($r('app.string.role_prepare_title')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(this.primary())
            Text($r('app.string.role_prepare_hint')).fontSize(AppFont.Body).fontColor(this.secondary())
          }.alignItems(HorizontalAlign.Start).width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg).backgroundColor(this.surface())
        } else {
          Row({ space: AppSpace.Sm }) {
            Column({ space: AppSpace.Xxs }) {
              Text($r('app.string.role_speech_enable')).fontSize(AppFont.BodyL).fontColor(this.primary())
              Text($r('app.string.role_global_scope')).fontSize(AppFont.Caption).fontColor(this.secondary())
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.model.enabled }).selectedColor(AppColor.Brand)
              .enabled(!this.saving && !this.model.busy).accessibilityText($r('app.string.role_speech_enable'))
              .onChange((enabled: boolean): void => {
                if (enabled !== this.model.enabled) this.change((): Promise<void> => RoleModelService.getInstance().setEnabled(enabled));
              }).id('role-speech-toggle')
          }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg).backgroundColor(this.surface())
        }
      }
      if (this.targetId) {
        ListItem() {
          Column({ space: AppSpace.Xxs }) {
            Row({ space: AppSpace.Sm }) {
              Text(this.targetTitle).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(this.primary())
                .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.liveRoles.bookId === this.targetId && this.model.enabled) {
                this.previewButton()
              }
            }.width('100%')
            Text($r('app.string.role_book_scope')).fontSize(AppFont.Caption).fontColor(this.secondary())
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: AppSpace.Md, bottom: AppSpace.Xs, left: AppSpace.Xxs })
        }
        ListItem() { this.roleRow('@narrator', $r('app.string.role_narrator'), this.roles().narratorVoiceId) }
        ListItem() { this.roleRow('@dialogue', $r('app.string.role_unknown'), this.roles().dialogueVoiceId) }
        LazyForEach(this.speakers, (speaker: RoleSpeaker): void => {
          ListItem() { this.roleRow(speaker.id, speaker.name, speaker.voiceId) }
        }, (speaker: RoleSpeaker): string => speaker.id)
        ListItem() {
          Column({ space: AppSpace.Xs }) {
            if (this.roles().analysing) {
              Row({ space: AppSpace.Xs }) {
                LoadingProgress().width(20).height(20).color(AppColor.Brand)
                Text($r('app.string.role_analysing')).fontSize(AppFont.Caption).fontColor(this.secondary())
              }
            }
            Text(this.roles().speakers.length > 0 ? $r('app.string.role_discovered', this.roles().speakers.length) :
              $r('app.string.role_waiting_characters')).fontSize(AppFont.Caption).fontColor(this.secondary())
            if (this.roles().error) {
              Text($r('app.string.role_fallback_hint')).fontSize(AppFont.Body).fontColor(this.secondary())
              Text(this.roles().error).fontSize(AppFont.Caption).fontColor(this.secondary())
              Button($r('app.string.role_retry_chapter')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
                .enabled(!this.saving && !this.model.busy && this.model.enabled)
                .onClick((): void => { this.change((): Promise<void> => RoleSpeechService.getInstance().retryChapter()); })
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Xxs)
        }
      } else {
        ListItem() { Text($r('app.string.role_book_empty')).fontSize(AppFont.Body).fontColor(this.secondary()).padding(AppSpace.Md) }
      }
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      // 安全区留白随列表滚动，保持视口延伸到底部。
      .contentStartOffset(this.embedded ? 0 : this.topInset + AppSpace.Xs)
      .contentEndOffset(this.bottomInset + AppSpace.Lg)
  }

  @Builder
  voiceEditor() {
    Text($r('app.string.role_voice_confirm_hint')).fontSize(AppFont.Caption).fontColor(this.secondary()).width('100%')
    TextInput({ text: this.voiceQuery, placeholder: $r('app.string.role_voice_search') })
      .fontSize(AppFont.BodyL).height(44).fontColor(this.primary()).backgroundColor(this.surface())
      .onChange((value: string): void => { this.voiceQuery = value; })
    List({ space: AppSpace.Xs }) {
      ListItem() { this.voiceChoice('', $r('app.string.role_follow_voice')) }
      LazyForEach(this.voices, (config: CustomTtsConfig): void => {
        ListItem() { this.voiceChoice(config.id, config.name) }
      }, (config: CustomTtsConfig): string => config.id)
      if (this.voices.totalCount() === 0) {
        ListItem() {
          Text(this.voiceQuery.trim() ? $r('app.string.role_voice_no_results') : $r('app.string.role_voice_empty'))
            .fontSize(AppFont.Caption).fontColor(this.secondary()).padding(AppSpace.Xs)
        }
      }
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    Text(this.sampleText).fontSize(AppFont.Body).fontColor(this.secondary()).width('100%')
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    Row({ space: AppSpace.Sm }) {
      this.previewButton()
      Button($r('app.string.role_voice_apply')).layoutWeight(1).constraintSize({ minHeight: 44 })
        .fontSize(AppFont.Body).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).enabled(!this.saving)
        .onClick((): void => { this.saveVoice(); }).id('role-voice-apply')
    }.width('100%')
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      if (this.embedded || this.editing) {
        Row({ space: AppSpace.Xs }) {
          Text(this.editing ? this.selectedName : $r('app.string.role_cast_title'))
            .fontSize(AppFont.Title).fontWeight(FontWeight.Medium).fontColor(this.primary()).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(this.editing ? $r('app.string.common_cancel') : $r('app.string.common_close'))
            .fontColor(AppColor.Brand).backgroundColor(Color.Transparent).enabled(!this.saving)
            .onClick((): void => {
              this.finishPreview();
              if (this.editing) this.editing = false;
              else this.onClose();
            }).id('role-panel-close')
        }.width('100%')
      }
      if (this.ready) {
        if (this.editing) { this.voiceEditor() }
        else { this.roleList() }
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(this.secondary()).fontSize(AppFont.Body)
        Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => { this.load(); })
      } else {
        LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: AppSpace.Lg })
      }
    }.width('100%').height('100%').constraintSize({ maxWidth: 760 })
      .padding({ left: AppSpace.Md, right: AppSpace.Md,
        top: this.embedded || this.editing || !this.ready ? this.topInset + AppSpace.Xs : 0,
        bottom: this.editing ? this.bottomInset + AppSpace.Lg : 0 })
      .backgroundColor(Color.Transparent).id('role-speech-panel')
  }
}
