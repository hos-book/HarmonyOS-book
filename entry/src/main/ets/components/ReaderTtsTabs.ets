import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppColor, AppMaterial } from '../theme/Theme';

class ReaderTtsDataSource implements IDataSource {
  private configs: CustomTtsConfig[] = [];
  private listeners: DataChangeListener[] = [];
  update(configs: CustomTtsConfig[]): void {
    this.configs = [new CustomTtsConfig(), ...configs];
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
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
  @Event onSelect: (config: CustomTtsConfig) => void = () => {};
  @Event onDelete: (config: CustomTtsConfig) => void = () => {};
  @Local expanded: boolean = false;
  private source: ReaderTtsDataSource = new ReaderTtsDataSource();
  private pendingDelete: CustomTtsConfig | null = null;

  aboutToAppear(): void { this.refresh(); }
  @Monitor('configs')
  refresh(): void { this.source.update(this.configs); }

  private selectedName(): ResourceStr {
    return this.configs.find((config: CustomTtsConfig): boolean => config.id === this.selectedId)?.name ??
      $r('app.string.tts_system_voice');
  }

  private menuOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.BottomRight,
      onDisappear: (): void => {
        this.expanded = false;
        const config = this.pendingDelete;
        this.pendingDelete = null;
        if (config !== null) this.onDelete(config);
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    return options;
  }

  @Builder
  voiceMenu() {
    List() {
      LazyForEach(this.source, (config: CustomTtsConfig) => {
        ListItem() {
          Row({ space: 8 }) {
            Row({ space: 10 }) {
              Text(config.id.length > 0 ? config.name : $r('app.string.tts_system_voice'))
                .fontSize(15).maxLines(1).textOverflow({ overflow: TextOverflow.MARQUEE })
                .marqueeOptions({ start: this.expanded, step: 0.5, loop: -1 }).clip(true)
                .layoutWeight(1)
                .fontWeight(config.id === this.selectedId ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(config.id === this.selectedId ? AppColor.Brand : $r('sys.color.font_primary'))
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([AppColor.Brand])
                .opacity(config.id === this.selectedId ? 1 : 0)
            }.layoutWeight(1).height(48)
              .onClick((): void => {
                this.expanded = false;
                if (config.id !== this.selectedId) this.onSelect(config);
              })
            if (config.id.length > 0) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
              }.width(40).height(40).backgroundColor(Color.Transparent)
              .accessibilityText($r('app.string.rule_source_delete_action'))
              .onClick((): void => { this.pendingDelete = config; this.expanded = false; })
            }
          }.padding({ left: 16, right: 8 }).width('100%')
            .backgroundColor(Color.Transparent)
        }
      }, (config: CustomTtsConfig): string => config.id || 'system')
    }.width(280).height(Math.min(304, (this.configs.length + 1) * 48 + 8))
      .padding({ top: 4, bottom: 4 }).scrollBar(BarState.Auto)
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
      .bindMenu(this.expanded, this.voiceMenu(), this.menuOptions())
  }
}
