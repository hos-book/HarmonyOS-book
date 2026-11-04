import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppColor, AppMaterial } from '../theme/Theme';

export class ReaderTtsDataSource implements IDataSource {
  private configs: CustomTtsConfig[] = [];
  private listeners: DataChangeListener[] = [];
  update(configs: CustomTtsConfig[], includeSystem: boolean = true): void {
    const next = includeSystem ? [new CustomTtsConfig(), ...configs] : configs;
    // 管理时只删除/更新对应行，避免全量 reload 重置滚动位置。
    for (let index = this.configs.length - 1; index >= 0; index--) {
      if (!next.some((item: CustomTtsConfig): boolean => item.id === this.configs[index].id)) {
        this.configs.splice(index, 1);
        this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(index));
      }
    }
    for (let index = 0; index < next.length; index++) {
      if (this.configs[index]?.id !== next[index].id) {
        this.configs = next.slice();
        this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
        return;
      }
      if (this.configs[index] !== next[index]) {
        this.configs[index] = next[index];
        this.listeners.forEach((listener: DataChangeListener): void => listener.onDataChange(index));
      }
    }
  }
  totalCount(): number { return this.configs.length; }
  getData(index: number): CustomTtsConfig { return this.configs[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct ReaderTtsTabs {
  @Param configs: CustomTtsConfig[] = [];
  @Param selectedId: string = '';
  @Param management: boolean = false;
  @Param busy: boolean = false;
  @Event onSelect: (config: CustomTtsConfig) => void = () => {};
  @Event onEnabledChange: (config: CustomTtsConfig, enabled: boolean) => void = () => {};
  @Event onDelete: (config: CustomTtsConfig) => void = () => {};
  @Local expanded: boolean = false;
  private source: ReaderTtsDataSource = new ReaderTtsDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.refresh(); }
  @Monitor('configs', 'management')
  refresh(): void { this.source.update(this.configs); }

  private selectedName(): ResourceStr {
    return this.configs.find((config: CustomTtsConfig): boolean => config.id === this.selectedId)?.name ??
      $r('app.string.tts_system_voice');
  }

  private menuOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: this.voiceMenu,
      placement: Placement.BottomRight,
      popupColor: AppMaterial.SheetBackground,
      enableArrow: false,
      radius: 16,
      focusable: true,
      onStateChange: (event): void => { this.expanded = event.isVisible; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    return options;
  }

  @LocalBuilder
  voiceMenu() {
    List({ scroller: this.scroller }) {
      LazyForEach(this.source, (config: CustomTtsConfig) => {
        ListItem() {
          Row({ space: 8 }) {
            Row({ space: 10 }) {
              Text(config.id.length > 0 ? config.name : $r('app.string.tts_system_voice'))
                .fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .fontWeight(config.id === this.selectedId ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(config.id === this.selectedId ? AppColor.Brand : $r('sys.color.font_primary'))
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([AppColor.Brand])
                .opacity(config.id === this.selectedId ? 1 : 0)
            }.layoutWeight(1).height(48)
              .onClick((): void => {
                if (this.busy) return;
                if (!this.management) this.expanded = false;
                if (config.enabled && config.id !== this.selectedId) this.onSelect(config);
              })
              .opacity(config.enabled ? 1 : 0.5)
            if (this.management && config.id.length > 0) {
              Toggle({ type: ToggleType.Switch, isOn: config.enabled })
                .enabled(!this.busy)
                .selectedColor(AppColor.Brand)
                .accessibilityText($r('app.string.tts_custom_enabled', config.name))
                .onChange((enabled: boolean): void => {
                  if (enabled !== config.enabled) this.onEnabledChange(config, enabled);
                })
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
              }.width(40).height(40).backgroundColor(Color.Transparent)
              .enabled(!this.busy)
              .accessibilityText($r('app.string.rule_source_delete_action'))
              .onClick((): void => { this.onDelete(config); })
            }
          }.padding({ left: 16, right: 8 }).width('100%')
            .backgroundColor(Color.Transparent)
        }
      }, (config: CustomTtsConfig): string => `${config.id || 'system'}:${config.enabled}:${config.name}`)
    }.width(this.management ? 320 : 280).height(Math.min(304, (this.configs.length + 1) * 48 + 8))
      .padding({ top: 4, bottom: 4 }).scrollBar(BarState.Auto)
      .maintainVisibleContentPosition(true)
  }

  build() {
    Row({ space: 8 }) {
      Text(this.selectedName()).fontSize(14).fontColor(AppColor.Brand).fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 204 })
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([AppColor.Brand])
    }.width(LayoutPolicy.wrapContent).constraintSize({ maxWidth: '100%' })
      .height(38).padding({ left: 14, right: 12 }).borderRadius(19)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .shadow(ShadowStyle.OUTER_DEFAULT_XS)
      .onClick((): void => { this.expanded = !this.expanded; })
      .bindPopup(this.expanded, this.menuOptions())
  }
}
