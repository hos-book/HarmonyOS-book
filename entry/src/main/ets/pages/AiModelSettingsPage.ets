import { sendableContextManager } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { RoleModelCard } from '../components/RoleModelCard';
import { SettingsHintButton } from '../components/SettingsHintButton';
import { AiModelPack, AiModelPackState, AiModelPackUsage, AI_MODEL_PACKS } from '../model/AiModelPack';
import { AiModelPackService } from '../service/AiModelPackService';
import { ComicColorizationService } from '../service/ComicColorizationService';
import { AudioSubtitleService } from '../service/subtitle/AudioSubtitleService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct AiModelSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local state: AiModelPackState = AiModelPackService.instance.state;
  @Local colorUsage: AiModelPackUsage = new AiModelPackUsage();
  @Local subtitleUsage: AiModelPackUsage = new AiModelPackUsage();
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local picking: boolean = false;
  @Local roleChanging: boolean = false;
  private alive: boolean = false;
  private service: AiModelPackService = AiModelPackService.instance;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.service.cancel(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.loading = true; this.failed = false;
    try {
      await this.service.recover(context);
      this.refresh();
    } catch (_error) { this.failed = true; }
    finally { if (this.alive) this.loading = false; }
  }

  private refresh(): void {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive) return;
    this.colorUsage = this.service.usage(context, 'comic-color-v1');
    this.subtitleUsage = this.service.usage(context, 'audio-subtitle-v1');
  }

  private title(id: string): Resource {
    return id === 'comic-color-v1' ? $r('app.string.model_pack_color') : $r('app.string.model_pack_subtitle');
  }

  private usage(id: string): AiModelPackUsage { return id === 'comic-color-v1' ? this.colorUsage : this.subtitleUsage; }

  private async beforeMutation(id: string): Promise<void> {
    if (id === 'comic-color-v1') await ComicColorizationService.pauseForModelChange();
    else await AudioSubtitleService.instance.pauseForModelChange();
  }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async importPack(id: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.state.busyId || this.picking || this.roleChanging) return;
    this.picking = true;
    try {
      const imported = await this.service.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), id, (): boolean => this.alive,
        (): Promise<void> => this.beforeMutation(id));
      if (imported) this.toast($r('app.string.model_pack_imported'));
    } catch (error) {
      this.toast(AiModelPackService.errorMessage(error instanceof Error ? error.message : ''));
    } finally {
      this.picking = false; this.refresh();
      emitter.emit('app.ai.models.changed');
    }
  }

  private confirmRemove(id: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.model_pack_delete'), message: $r('app.string.model_pack_delete_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(id); } }
    });
  }

  private async remove(id: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.state.busyId || this.picking || this.roleChanging) return;
    try { await this.service.remove(context, id, (): Promise<void> => this.beforeMutation(id)); }
    catch (_error) { this.toast($r('app.string.model_pack_write')); }
    finally { this.refresh(); emitter.emit('app.ai.models.changed'); }
  }

  @Builder
  packCard(pack: AiModelPack) {
    Column({ space: AppSpace.Sm }) {
      Row() {
        Row({ space: AppSpace.Xxs }) {
          Text(this.title(pack.id)).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: this.title(pack.id), message: pack.id === 'comic-color-v1' ?
            $r('app.string.model_pack_color_hint') : $r('app.string.model_pack_subtitle_hint') })
            .id(`model-pack-hint-${pack.id}`)
        }.layoutWeight(1)
        Text(this.usage(pack.id).installed ? $r('app.string.model_pack_installed') : $r('app.string.model_pack_missing'))
          .fontSize(AppFont.Caption).fontColor(this.usage(pack.id).installed ? AppColor.Brand : AppTheme.TextSecondary)
      }.width('100%')
      Text($r('app.string.model_pack_size', Math.round(pack.bytes() / 1024 / 1024),
        Math.round(this.usage(pack.id).bytes / 1024 / 1024))).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      if (this.state.busyId === pack.id) {
        Row({ space: AppSpace.Sm }) {
          LoadingProgress().width(22).height(22).color(AppColor.Brand)
          Text(this.state.removing ? $r('app.string.model_pack_deleting') :
            this.state.verifying ? $r('app.string.model_pack_verifying') :
            $r('app.string.model_pack_importing', this.state.progress)).fontSize(AppFont.Body)
            .fontColor(AppTheme.TextSecondary).layoutWeight(1)
          if (!this.state.removing) {
            Button($r('app.string.common_cancel')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => this.service.cancel()).id(`model-pack-cancel-${pack.id}`)
          }
        }.width('100%')
      } else {
        Row({ space: AppSpace.Sm }) {
          Button(this.usage(pack.id).installed ? $r('app.string.model_pack_replace') : $r('app.string.model_pack_import'))
            .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).layoutWeight(1)
            .enabled(!this.state.busyId && !this.picking && !this.roleChanging).onClick((): void => { this.importPack(pack.id); })
            .id(`model-pack-import-${pack.id}`)
          if (this.usage(pack.id).bytes > 0) {
            Button($r('app.string.common_delete')).fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent)
              .enabled(!this.state.busyId && !this.picking && !this.roleChanging).onClick((): void => this.confirmRemove(pack.id))
              .id(`model-pack-delete-${pack.id}`)
          }
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
      .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: AppSpace.Md }) {
          if (this.loading) {
            LoadingProgress().width(32).height(32).color(AppColor.Brand)
          } else if (this.failed) {
            Text($r('app.string.model_pack_write')).fontColor(AppTheme.TextSecondary)
            Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => { this.load(); })
          } else {
            ForEach(AI_MODEL_PACKS, (pack: AiModelPack) => { this.packCard(pack) }, (pack: AiModelPack): string => pack.id)
            RoleModelCard({ blocked: this.state.busyId.length > 0 || this.picking,
              onChanging: (changing: boolean): void => { this.roleChanging = changing; } })
          }
        }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: this.headerHeight + AppSpace.Md, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }.width('100%').height('100%').scrollBar(BarState.Off)
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.model_pack_manage')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: $r('app.string.model_pack_manage'), message: $r('app.string.model_pack_help') })
            .id('model-pack-help')
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
