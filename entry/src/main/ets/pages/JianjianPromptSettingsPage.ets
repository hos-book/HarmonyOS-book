import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { SettingsHintButton } from '../components/SettingsHintButton';
import { JianjianAiPrompts, JIANJIAN_PROMPT_MAX_LENGTH } from '../model/JianjianAi';
import { JianjianAiService } from '../service/JianjianAiService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct JianjianPromptSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local bookMode: boolean = false;
  @Local chatPrompt: string = '';
  @Local bookPrompt: string = '';
  @Local ready: boolean = false;
  @Local saving: boolean = false;
  @Local message: ResourceStr = '';
  private alive: boolean = false;
  private generation: number = 0;
  private defaults: JianjianAiPrompts = new JianjianAiPrompts();

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.generation++; }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    this.message = '';
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Settings context unavailable');
      const prompts = await JianjianAiService.loadPrompts(context);
      if (!this.alive || generation !== this.generation) return;
      this.defaults = JianjianAiService.defaultPrompts(context);
      this.chatPrompt = prompts.chat;
      this.bookPrompt = prompts.book;
      this.ready = true;
    } catch (_error) { if (this.alive) this.message = $r('app.string.settings_load_failed'); }
  }

  private restoreDefault(): void {
    if (!this.ready || this.saving) return;
    if (this.bookMode) this.bookPrompt = this.defaults.book;
    else this.chatPrompt = this.defaults.chat;
    this.message = $r('app.string.jianjian_prompt_restored');
  }

  private async save(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.ready || this.saving) return;
    const prompts = new JianjianAiPrompts();
    prompts.chat = this.chatPrompt;
    prompts.book = this.bookPrompt;
    this.saving = true;
    this.message = '';
    try {
      const saved = await JianjianAiService.savePrompts(context, prompts);
      if (!this.alive) return;
      this.chatPrompt = saved.chat;
      this.bookPrompt = saved.book;
      this.message = $r('app.string.jianjian_prompt_saved');
    } catch (_error) { if (this.alive) this.message = $r('app.string.settings_save_failed'); }
    finally { if (this.alive) this.saving = false; }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: AppSpace.Md }) {
        if (this.ready) {
          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.jianjian_prompt_chat'), { type: ButtonType.Normal })
              .layoutWeight(1).height(44).borderRadius(AppRadius.Md)
              .backgroundColor(this.bookMode ? AppTheme.Surface : AppColor.Brand)
              .fontColor(this.bookMode ? AppTheme.TextPrimary : AppColor.OnBrand)
              .enabled(!this.saving).onClick((): void => { this.bookMode = false; })
              .id('jianjian-prompt-chat').accessibilitySelected(!this.bookMode)
            Button($r('app.string.jianjian_prompt_book'), { type: ButtonType.Normal })
              .layoutWeight(1).height(44).borderRadius(AppRadius.Md)
              .backgroundColor(this.bookMode ? AppColor.Brand : AppTheme.Surface)
              .fontColor(this.bookMode ? AppColor.OnBrand : AppTheme.TextPrimary)
              .enabled(!this.saving).onClick((): void => { this.bookMode = true; })
              .id('jianjian-prompt-book').accessibilitySelected(this.bookMode)
          }.width('100%')
          TextArea({ text: this.bookMode ? this.bookPrompt : this.chatPrompt,
            placeholder: $r('app.string.jianjian_prompt_placeholder') })
            .width('100%').layoutWeight(1).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
            .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg).padding(16)
            .maxLength(JIANJIAN_PROMPT_MAX_LENGTH).caretColor(AppColor.Brand).enabled(!this.saving)
            .onChange((value: string): void => {
              if (this.bookMode) this.bookPrompt = value;
              else this.chatPrompt = value;
              this.message = '';
            }).id('jianjian-prompt-editor')
            .accessibilityText(this.bookMode ? $r('app.string.jianjian_prompt_book') : $r('app.string.jianjian_prompt_chat'))
          Text($r('app.string.jianjian_prompt_count',
            this.bookMode ? this.bookPrompt.length : this.chatPrompt.length, JIANJIAN_PROMPT_MAX_LENGTH))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%').textAlign(TextAlign.End)
          if (this.message) {
            Text(this.message).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).width('100%')
          }
          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.jianjian_prompt_restore'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(AppColor.Brand).enabled(!this.saving).onClick((): void => { this.restoreDefault(); })
              .id('jianjian-prompt-restore')
            Blank()
            if (this.saving) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
            Button($r('app.string.common_save')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
              .enabled(!this.saving).onClick((): void => { this.save(); }).id('jianjian-prompt-save')
          }.width('100%')
        } else {
          if (!this.message) { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
          else {
            Text(this.message).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
            Button($r('app.string.common_retry')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
              .onClick((): void => { this.load(); })
          }
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 760 })
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: this.headerHeight + AppSpace.Sm,
          bottom: WindowUtils.getBottomSafeVp() + AppSpace.Md })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.jianjian_prompt_settings')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: $r('app.string.jianjian_prompt_settings'),
            message: $r('app.string.jianjian_prompt_help') })
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
