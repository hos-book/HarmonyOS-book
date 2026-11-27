import { AppThemeBundle } from '../model/AppThemeBundle';
import { AppAppearance } from '../model/AppAppearance';
import { ThemeIconRole, ThemeButtonRole } from '../model/AppThemeVisual';
import { ThemePageBackdrop } from '../model/ThemeDocument';
import { ThemeBackdropComponent } from './ThemeBackdropComponent';

@ComponentV2
export struct ThemeEditorPreview {
  @Param bundle: AppThemeBundle = new AppThemeBundle('', '', '', '');
  @Param scene: string = 'home';
  @Param night: boolean = false;
  @Param buttonPreview: string = '';
  @Local appearance: AppAppearance = AppAppearance.current;

  private backdrop(): ThemePageBackdrop { return this.bundle.visual.pages.get(this.scene) ?? new ThemePageBackdrop(); }

  private previewRole(normal: ThemeButtonRole, variants: ThemeButtonRole[]): ThemeButtonRole {
    return variants.find((role: ThemeButtonRole): boolean => role === this.buttonPreview) ?? normal;
  }

  private headerButtons(): ThemeButtonRole[] {
    if (this.scene === 'shelf') {
      const collection: ThemeButtonRole[] = [ThemeButtonRole.ShelfAdd, ThemeButtonRole.ShelfExpand,
        ThemeButtonRole.ShelfCollapse, ThemeButtonRole.ShelfClose];
      if (collection.some((role: ThemeButtonRole): boolean => role === this.buttonPreview)) {
        return [ThemeButtonRole.ShelfAdd,
          this.previewRole(ThemeButtonRole.ShelfExpand, [ThemeButtonRole.ShelfCollapse]), ThemeButtonRole.ShelfClose];
      }
      return [this.previewRole(ThemeButtonRole.ShelfSearch, [ThemeButtonRole.ShelfSearchActive]),
        ThemeButtonRole.ShelfFilter,
        this.previewRole(ThemeButtonRole.ShelfGroup, [ThemeButtonRole.ShelfGroupActive, ThemeButtonRole.ShelfGroupManage]),
        ThemeButtonRole.ShelfImport, ThemeButtonRole.ShelfUpdates,
        this.previewRole(ThemeButtonRole.ShelfViewList, [ThemeButtonRole.ShelfViewCollection, ThemeButtonRole.ShelfViewGrid])];
    }
    const record: ThemeButtonRole[] = [this.previewRole(ThemeButtonRole.RecordFilter, [ThemeButtonRole.RecordFilterActive]),
      ThemeButtonRole.RecordExcerpt, ThemeButtonRole.RecordHistory,
      this.previewRole(ThemeButtonRole.RecordEdit, [ThemeButtonRole.RecordDone, ThemeButtonRole.RecordLocked])];
    if (this.buttonPreview === ThemeButtonRole.RecordBack) record.unshift(ThemeButtonRole.RecordBack);
    return record;
  }

  private headerSymbol(role: ThemeButtonRole): Resource {
    switch (role) {
      case ThemeButtonRole.ShelfSearch:
      case ThemeButtonRole.ShelfSearchActive: return $r('sys.symbol.magnifyingglass');
      case ThemeButtonRole.ShelfFilter:
      case ThemeButtonRole.RecordFilter:
      case ThemeButtonRole.RecordFilterActive: return $r('sys.symbol.funnel');
      case ThemeButtonRole.ShelfGroup:
      case ThemeButtonRole.ShelfGroupActive:
      case ThemeButtonRole.ShelfGroupManage: return $r('sys.symbol.folder');
      case ThemeButtonRole.ShelfImport: return $r('sys.symbol.doc_text_badge_arrow_up');
      case ThemeButtonRole.ShelfUpdates: return $r('sys.symbol.arrow_clockwise');
      case ThemeButtonRole.ShelfViewList: return $r('sys.symbol.list_bullet');
      case ThemeButtonRole.ShelfViewCollection: return $r('sys.symbol.bookshelf');
      case ThemeButtonRole.ShelfViewGrid: return $r('sys.symbol.square_grid_2x2');
      case ThemeButtonRole.ShelfAdd: return $r('sys.symbol.plus');
      case ThemeButtonRole.ShelfExpand: return $r('sys.symbol.arrow_up_left_and_arrow_down_right');
      case ThemeButtonRole.ShelfCollapse: return $r('sys.symbol.arrow_down_right_and_arrow_up_left');
      case ThemeButtonRole.ShelfClose: return $r('sys.symbol.xmark');
      case ThemeButtonRole.RecordBack: return $r('sys.symbol.chevron_left');
      case ThemeButtonRole.RecordExcerpt: return $r('sys.symbol.bookmark');
      case ThemeButtonRole.RecordHistory: return $r('sys.symbol.clock');
      case ThemeButtonRole.RecordDone: return $r('sys.symbol.checkmark');
      case ThemeButtonRole.RecordLocked: return $r('sys.symbol.lock');
      default: return $r('sys.symbol.square_and_pencil');
    }
  }

  @Builder
  private headerButton(role: ThemeButtonRole) {
    if (this.bundle.visual.buttons.get(role)) {
      Image(this.bundle.visual.buttons.get(role) ?? '').width(30).height(30).objectFit(ImageFit.Contain)
    } else {
      Stack() {
        if ((role === ThemeButtonRole.RecordFilter || role === ThemeButtonRole.RecordFilterActive) &&
          this.bundle.visual.icons.get(ThemeIconRole.Filter)) {
          Image(this.bundle.visual.icons.get(ThemeIconRole.Filter) ?? '').width(18).height(18).objectFit(ImageFit.Contain)
        } else {
          SymbolGlyph(this.headerSymbol(role)).fontSize(18)
            .fontColor([role === ThemeButtonRole.ShelfSearchActive || role === ThemeButtonRole.ShelfGroupActive ||
              role === ThemeButtonRole.RecordFilterActive || role === ThemeButtonRole.RecordDone || role === ThemeButtonRole.RecordLocked ?
              this.bundle.visual.colors.brand : this.bundle.visual.colors.iconPrimary])
        }
      }.width(30).height(30).borderRadius(15).backgroundColor(this.bundle.visual.colors.controlFallback)
    }
  }

  @Builder
  private cover() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(this.scene === 'player' ? this.bundle.visual.cover.playerPlaceholder : this.bundle.visual.cover.placeholder)
        .width('100%').height('100%').objectFit(ImageFit.Cover)
      if (this.bundle.visual.cover.illustratedPlaceholder) {
        Text($r('app.string.theme_editor_preview_book')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(this.bundle.visual.cover.title).padding(12)
      }
    }.width(this.scene === 'player' ? 148 : 90).height(this.scene === 'player' ? 148 : 122)
      .borderRadius(8).clip(true).border({ width: this.bundle.visual.cover.decoration === 0 ? 0 : 2,
        color: this.bundle.visual.cover.edge })
  }

  @Builder
  private tab(role: ThemeIconRole, symbol: Resource, title: Resource, selected: boolean) {
    Column({ space: 4 }) {
      if (this.bundle.visual.icons.get(role) || this.bundle.visual.selectedIcons.get(role)) {
        Image((selected ? this.bundle.visual.selectedIcons.get(role) : undefined) ?? this.bundle.visual.icons.get(role) ?? '')
          .width(25).height(25).objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph(symbol).fontSize(24).fontColor([selected ?
          this.bundle.visual.tabSelectedColor ?? this.bundle.visual.colors.brand :
          this.bundle.visual.tabNormalColor ?? this.bundle.visual.colors.textSecondary])
      }
      Text(title).fontSize(10).fontColor(selected ? this.bundle.visual.tabSelectedColor ?? this.bundle.visual.colors.brand :
        this.bundle.visual.tabNormalColor ?? this.bundle.visual.colors.textSecondary)
    }.layoutWeight(1)
  }

  build() {
    Stack() {
      if (this.backdrop().mode === 'image' || this.backdrop().mode === 'solid') {
        ThemeBackdropComponent({ backdrop: this.backdrop(), night: this.night || this.scene === 'player' })
      } else if (this.scene === 'player') {
        Image(this.bundle.visual.cover.playerPlaceholder).width('100%').height('100%').objectFit(ImageFit.Cover)
          .blur(this.backdrop().blur)
        Column().width('100%').height('100%').backgroundColor('#0D0D0D').opacity(this.backdrop().veil / 100)
      } else {
        Column().width('100%').height('100%').linearGradient({ angle: 180, colors: [
          [this.bundle.visual.colors.homeTop, 0],
          [this.bundle.visual.colors.homeMid, 0.35],
          [this.bundle.visual.colors.homeBottom, 1]
        ] })
      }
      Column({ space: 16 }) {
        Row() {
          Text($r('app.string.theme_editor_preview')).fontSize(12)
            .fontColor(this.scene === 'player' ? '#FFFFFF' : this.bundle.visual.colors.textSecondary)
          Blank()
          if (this.scene === 'shelf' || this.scene === 'record') {
            Row({ space: 4 }) {
              ForEach(this.headerButtons(), (role: ThemeButtonRole) => {
                this.headerButton(role)
              }, (role: ThemeButtonRole): string => role)
            }
          } else if (this.bundle.visual.icons.get(ThemeIconRole.Search)) {
            Image(this.bundle.visual.icons.get(ThemeIconRole.Search) ?? '').width(20).height(20)
          } else {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(20).fontColor([this.bundle.visual.colors.iconPrimary])
          }
        }.width('100%')
        Text(this.bundle.name).fontSize(24).fontWeight(FontWeight.Bold).maxLines(1)
          .fontColor(this.scene === 'player' ? '#FFFFFF' : this.bundle.visual.colors.textPrimary).width('100%')
        Text($r('app.string.theme_editor_preview_hint')).fontSize(12).width('100%')
          .fontColor(this.scene === 'player' ? '#DDFFFFFF' : this.bundle.visual.colors.textSecondary)
        if (this.scene === 'record') {
          Column({ space: 12 }) {
            Text($r('app.string.theme_editor_preview_record')).fontSize(14).fontColor(this.bundle.visual.colors.textSecondary)
            Text($r('app.string.theme_editor_preview_record_value')).fontSize(32).fontColor(this.bundle.visual.colors.brand)
          }.width('100%').padding(24).backgroundColor(this.bundle.visual.colors.surface).borderRadius(16)
        } else if (this.scene === 'profile') {
          Stack() {
            if (this.bundle.visual.background.profileCardImage) {
              Image(this.bundle.visual.background.profileCardImage ?? '').width('100%').height(148).objectFit(ImageFit.Cover)
            }
            Column({ space: 16 }) {
              SymbolGlyph($r('sys.symbol.person_fill')).fontSize(40).fontColor([this.bundle.visual.colors.brand])
              Text($r('app.string.theme_editor_preview_author')).fontSize(18).fontColor(this.bundle.visual.colors.textPrimary)
            }.width('100%').height(148)
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.bundle.visual.colors.surface)
        } else if (this.scene === 'player') {
          this.cover()
          Text($r('app.string.theme_editor_preview_progress')).fontSize(12).fontColor('#DDFFFFFF')
          Row({ space: 32 }) {
            SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(22).fontColor(['#FFFFFF'])
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(36).fontColor(['#FFFFFF'])
            SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(22).fontColor(['#FFFFFF'])
          }.height(48)
        } else {
          Row({ space: 16 }) {
            this.cover()
            Column({ space: 12 }) {
              Text($r('app.string.theme_editor_preview_book')).fontSize(18).fontWeight(FontWeight.Medium)
                .fontColor(this.bundle.visual.colors.textPrimary)
              Text($r('app.string.theme_editor_preview_author')).fontSize(12).fontColor(this.bundle.visual.colors.textSecondary)
              Row().width(70).height(5).borderRadius(3).backgroundColor(this.bundle.visual.colors.brand)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%').padding(12).borderRadius(16).backgroundColor(this.bundle.visual.colors.surface)
        }
        Blank()
        if (this.scene !== 'player') {
          if (this.bundle.custom ? this.appearance.verticalBottomTabs : this.bundle.verticalBottomTabs) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([this.bundle.visual.colors.brand])
              Text($r('app.string.theme_editor_preview_book')).fontSize(12).fontColor(this.bundle.visual.colors.textPrimary)
              Blank()
            }.width('100%').padding(10).backgroundColor(this.bundle.visual.colors.controlFallback).borderRadius(20)
          }
          Row() {
            this.tab(ThemeIconRole.Home, $r('sys.symbol.house_fill'), $r('app.string.theme_editor_home'), this.scene === 'home')
            this.tab(ThemeIconRole.Shelf, $r('sys.symbol.bookshelf'), $r('app.string.theme_editor_shelf'), this.scene === 'shelf')
            this.tab(ThemeIconRole.Record, $r('sys.symbol.calendar_fill'), $r('app.string.theme_editor_record'), this.scene === 'record')
            this.tab(ThemeIconRole.Profile, $r('sys.symbol.person_fill'), $r('app.string.theme_editor_profile'), this.scene === 'profile')
          }.width('100%').padding({ top: 12, bottom: 12 }).borderRadius(28)
            .backgroundColor(this.bundle.visual.colors.controlFallback)
        }
      }.width('100%').height('100%').padding(20)
    }.width('100%').height(440).borderRadius(24).clip(true)
      .backgroundColor(this.bundle.visual.colors.background)
  }
}
