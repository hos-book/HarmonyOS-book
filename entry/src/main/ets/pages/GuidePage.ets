import { AppColor, AppRadius, AppSpace, AppFont, AppTheme } from '../theme/Theme';
import { LengthMetrics } from '@kit.ArkUI';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ListDataSource } from '../utils/ListDataSource';
import { WindowUtils } from '../utils/WindowUtils';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';

class GuideItem {
  id: string = '';
  action: ResourceStr = '';
  desc: ResourceStr = '';

  constructor(id: string, action: ResourceStr, desc: ResourceStr) {
    this.id = id;
    this.action = action;
    this.desc = desc;
  }
}

class GuideGroup {
  id: string = '';
  title: ResourceStr = '';
  items: GuideItem[] = [];

  constructor(id: string, title: ResourceStr, items: GuideItem[]) {
    this.id = id;
    this.title = title;
    this.items = items;
  }
}

/** 离线使用教程，文案对应当前页面中的真实入口。 */
const GUIDE_GROUPS: GuideGroup[] = [
  new GuideGroup('start', $r('app.string.guide_group_start'), [
    new GuideItem('start-source', $r('app.string.guide_start_source_action'),
      $r('app.string.guide_start_source_desc')),
    new GuideItem('start-book', $r('app.string.guide_start_book_action'),
      $r('app.string.guide_start_book_desc')),
    new GuideItem('start-continue', $r('app.string.guide_start_continue_action'),
      $r('app.string.guide_start_continue_desc')),
  ]),
  new GuideGroup('source', $r('app.string.guide_group_source'), [
    new GuideItem('source-import', $r('app.string.guide_source_import_action'),
      $r('app.string.guide_source_import_desc')),
    new GuideItem('source-test', $r('app.string.guide_source_test_action'),
      $r('app.string.guide_source_test_desc')),
    new GuideItem('source-login', $r('app.string.guide_source_login_action'),
      $r('app.string.guide_source_login_desc')),
    new GuideItem('source-manage', $r('app.string.guide_source_manage_action'),
      $r('app.string.guide_source_manage_desc')),
  ]),
  new GuideGroup('home', $r('app.string.guide_group_home'), [
    new GuideItem('home-search', $r('app.string.guide_home_search_action'),
      $r('app.string.guide_home_search_desc')),
    new GuideItem('home-source', $r('app.string.guide_home_source_action'),
      $r('app.string.guide_home_source_desc')),
    new GuideItem('home-refresh', $r('app.string.guide_home_refresh_action'),
      $r('app.string.guide_home_refresh_desc')),
    new GuideItem('home-double-tap', $r('app.string.guide_home_top_action'),
      $r('app.string.guide_home_top_desc')),
  ]),
  new GuideGroup('favorite', $r('app.string.guide_group_favorite'), [
    new GuideItem('favorite-add', $r('app.string.guide_favorite_add_action'),
      $r('app.string.guide_favorite_add_desc')),
    new GuideItem('favorite-open', $r('app.string.guide_favorite_open_action'),
      $r('app.string.guide_favorite_open_desc')),
    new GuideItem('favorite-refresh', $r('app.string.guide_favorite_refresh_action'),
      $r('app.string.guide_favorite_refresh_desc')),
    new GuideItem('favorite-remove', $r('app.string.guide_favorite_remove_action'),
      $r('app.string.guide_favorite_remove_desc')),
    new GuideItem('favorite-group', $r('app.string.guide_favorite_group_action'),
      $r('app.string.guide_favorite_group_desc')),
  ]),
  new GuideGroup('record', $r('app.string.guide_group_record'), [
    new GuideItem('record-select', $r('app.string.guide_record_select_action'),
      $r('app.string.guide_record_select_desc')),
    new GuideItem('record-play', $r('app.string.guide_record_play_action'),
      $r('app.string.guide_record_play_desc')),
  ]),
  new GuideGroup('player', $r('app.string.guide_group_player'), [
    new GuideItem('player-chapter', $r('app.string.guide_player_chapter_action'),
      $r('app.string.guide_player_chapter_desc')),
    new GuideItem('player-speed-reset', $r('app.string.guide_player_speed_action'),
      $r('app.string.guide_player_speed_desc')),
    new GuideItem('player-sleep', $r('app.string.guide_player_sleep_action'),
      $r('app.string.guide_player_sleep_desc')),
    new GuideItem('player-skip-clear', $r('app.string.guide_player_skip_action'),
      $r('app.string.guide_player_skip_desc')),
    new GuideItem('player-source', $r('app.string.guide_player_source_action'),
      $r('app.string.guide_player_source_desc')),
  ]),
  new GuideGroup('reader', $r('app.string.guide_group_reader'), [
    new GuideItem('reader-open', $r('app.string.guide_reader_open_action'),
      $r('app.string.guide_reader_open_desc')),
    new GuideItem('reader-toolbar', $r('app.string.guide_reader_toolbar_action'),
      $r('app.string.guide_reader_toolbar_desc')),
    new GuideItem('reader-settings', $r('app.string.guide_reader_settings_action'),
      $r('app.string.guide_reader_settings_desc')),
    new GuideItem('reader-theme', $r('app.string.guide_reader_theme_action'),
      $r('app.string.guide_reader_theme_desc')),
    new GuideItem('reader-speech', $r('app.string.guide_reader_speech_action'),
      $r('app.string.guide_reader_speech_desc')),
    new GuideItem('reader-bookmark', $r('app.string.guide_reader_bookmark_action'),
      $r('app.string.guide_reader_bookmark_desc')),
  ]),
  new GuideGroup('comic', $r('app.string.guide_group_comic'), [
    new GuideItem('comic-read', $r('app.string.guide_comic_read_action'),
      $r('app.string.guide_comic_read_desc')),
    new GuideItem('comic-settings', $r('app.string.guide_comic_settings_action'),
      $r('app.string.guide_comic_settings_desc')),
  ]),
  new GuideGroup('import', $r('app.string.guide_group_import'), [
    new GuideItem('import-files', $r('app.string.guide_import_files_action'),
      $r('app.string.guide_import_files_desc')),
    new GuideItem('import-save', $r('app.string.guide_import_save_action'),
      $r('app.string.guide_import_save_desc')),
    new GuideItem('import-formats', $r('app.string.guide_import_formats_action'),
      $r('app.string.guide_import_formats_desc')),
  ]),
  new GuideGroup('download', $r('app.string.guide_group_download'), [
    new GuideItem('download-chapter', $r('app.string.guide_download_chapter_action'),
      $r('app.string.guide_download_chapter_desc')),
    new GuideItem('download-export', $r('app.string.guide_download_export_action'),
      $r('app.string.guide_download_export_desc')),
  ]),
  new GuideGroup('backup', $r('app.string.guide_group_backup'), [
    new GuideItem('backup-local', $r('app.string.guide_backup_local_action'),
      $r('app.string.guide_backup_local_desc')),
    new GuideItem('backup-cloud', $r('app.string.guide_backup_cloud_action'),
      $r('app.string.guide_backup_cloud_desc')),
    new GuideItem('backup-files', $r('app.string.guide_backup_files_action'),
      $r('app.string.guide_backup_files_desc')),
  ]),
  new GuideGroup('mini-player', $r('app.string.guide_group_mini_player'), [
    new GuideItem('mini-cover-progress', $r('app.string.guide_mini_cover_action'),
      $r('app.string.guide_mini_cover_desc')),
    new GuideItem('mini-cover-expand', $r('app.string.guide_mini_expand_action'),
      $r('app.string.guide_mini_expand_desc')),
  ]),
  new GuideGroup('system-media', $r('app.string.guide_group_system_media'), [
    new GuideItem('system-media-open', $r('app.string.guide_system_media_open_action'),
      $r('app.string.guide_system_media_open_desc')),
    new GuideItem('system-media-speed', $r('app.string.guide_system_speed_action'),
      $r('app.string.guide_system_speed_desc')),
  ]),
  new GuideGroup('common', $r('app.string.guide_group_common'), [
    new GuideItem('common-settings', $r('app.string.guide_common_settings_action'),
      $r('app.string.guide_common_settings_desc')),
    new GuideItem('tab-double-tap', $r('app.string.guide_common_top_action'),
      $r('app.string.guide_common_top_desc')),
  ]),
  new GuideGroup('problems', $r('app.string.guide_group_problems'), [
    new GuideItem('problems-search', $r('app.string.guide_problems_search_action'),
      $r('app.string.guide_problems_search_desc')),
    new GuideItem('problems-content', $r('app.string.guide_problems_content_action'),
      $r('app.string.guide_problems_content_desc')),
    new GuideItem('problems-import', $r('app.string.guide_problems_import_action'),
      $r('app.string.guide_problems_import_desc')),
    new GuideItem('problems-logs', $r('app.string.guide_problems_logs_action'),
      $r('app.string.guide_problems_logs_desc')),
  ]),
];

class GuideTopic {
  id: string;
  title: Resource;
  summary: Resource;
  icon: Resource;
  groupIds: string[];

  constructor(id: string, title: Resource, summary: Resource, icon: Resource, groupIds: string[]) {
    this.id = id;
    this.title = title;
    this.summary = summary;
    this.icon = icon;
    this.groupIds = groupIds;
  }
}

const START_TOPIC: GuideTopic = new GuideTopic('start', $r('app.string.guide_group_start'),
  $r('app.string.guide_start_summary'), $r('sys.symbol.book'), ['start']);
const HELP_TOPIC: GuideTopic = new GuideTopic('help', $r('app.string.guide_group_problems'),
  $r('app.string.guide_help_summary'), $r('sys.symbol.questionmark_circle'), ['problems']);
const GUIDE_TOPICS: GuideTopic[] = [
  new GuideTopic('find', $r('app.string.guide_topic_find'), $r('app.string.guide_topic_find_summary'),
    $r('sys.symbol.magnifyingglass'), ['source', 'home']),
  new GuideTopic('read', $r('app.string.guide_topic_read'), $r('app.string.guide_topic_read_summary'),
    $r('sys.symbol.book'), ['reader', 'comic']),
  new GuideTopic('listen', $r('app.string.guide_topic_listen'), $r('app.string.guide_topic_listen_summary'),
    $r('sys.symbol.music_note_list'), ['player', 'mini-player', 'system-media']),
  new GuideTopic('shelf', $r('app.string.guide_topic_shelf'), $r('app.string.guide_topic_shelf_summary'),
    $r('sys.symbol.bookshelf'), ['favorite', 'record']),
  new GuideTopic('local', $r('app.string.guide_topic_local'), $r('app.string.guide_topic_local_summary'),
    $r('sys.symbol.arrow_down_circle'), ['import', 'download']),
  new GuideTopic('settings', $r('app.string.guide_topic_settings'), $r('app.string.guide_topic_settings_summary'),
    $r('sys.symbol.gearshape'), ['backup', 'common'])
];

@ComponentV2
export struct GuidePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param topicId: string = '';
  @Local topic: GuideTopic = START_TOPIC;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local leftSafeVp: number = WindowUtils.getLeftSafeVp();
  @Local rightSafeVp: number = WindowUtils.getRightSafeVp();
  private groupSource: ListDataSource<GuideGroup> = new ListDataSource<GuideGroup>();
  private safeAreaListener = (topVp: number, bottomVp: number): void => {
    this.topSafeVp = topVp;
    this.bottomSafeVp = bottomVp;
    this.leftSafeVp = WindowUtils.getLeftSafeVp();
    this.rightSafeVp = WindowUtils.getRightSafeVp();
  };

  aboutToAppear(): void {
    this.topic = this.topicId === HELP_TOPIC.id ? HELP_TOPIC :
      GUIDE_TOPICS.find((item: GuideTopic): boolean => item.id === this.topicId) ?? START_TOPIC;
    const groups: GuideGroup[] = [];
    for (const id of this.topic.groupIds) {
      const group = GUIDE_GROUPS.find((item: GuideGroup): boolean => item.id === id);
      if (group) groups.push(group);
    }
    this.groupSource.setItems(groups);
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
  }

  aboutToDisappear(): void {
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
  }

  private openTopic(topic: GuideTopic): void {
    this.navStack.pushPathByName('guideDetail', topic.id);
  }

  @Builder
  forwardIndicator(): void {
    Stack() {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(24).fontWeight(FontWeight.Medium).fontColor([AppColor.Brand])
    }
    .width(48).height(48).flexShrink(0)
    .accessibilityLevel('no')
  }

  @Builder
  startCard(): void {
    Button({ type: ButtonType.Normal }) {
      Column({ space: AppSpace.Lg }) {
        Row({ space: AppSpace.Md }) {
          Column({ space: AppSpace.Sm }) {
            Text($r('app.string.guide_start_eyebrow'))
              .fontSize(AppFont.Caption).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
            Text($r('app.string.guide_start_headline'))
              .fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
            Text($r('app.string.guide_start_summary'))
              .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).lineSpacing(LengthMetrics.vp(3))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(56).fontWeight(FontWeight.Lighter).fontColor([AppColor.Brand])
            .opacity(0.3).rotate({ angle: -10 }).width(64).height(72)
            .flexShrink(0).accessibilityLevel('no')
        }.width('100%').alignItems(VerticalAlign.Center)
        Row() {
          Text($r('app.string.guide_start_cta'))
            .fontSize(AppFont.Body).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
          Blank()
          this.forwardIndicator()
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Lg)
    }
    .width('100%').padding(0)
    .backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Xl)
    .accessibilityText($r('app.string.guide_group_start'))
    .onClick((): void => this.openTopic(START_TOPIC))
  }

  @Builder
  topicCard(topic: GuideTopic): void {
    Button({ type: ButtonType.Normal }) {
      Column({ space: AppSpace.Md }) {
        Row() {
          SymbolGlyph(topic.icon)
            .fontSize(26).fontColor([AppColor.Brand]).accessibilityLevel('no')
          Blank()
          this.forwardIndicator()
        }.width('100%').alignItems(VerticalAlign.Center)
        Column({ space: 6 }) {
          Text(topic.title)
            .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
          Text(topic.summary)
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).lineSpacing(LengthMetrics.vp(3))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').constraintSize({ minHeight: 144 })
      .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween).padding(20)
    }
    .width('100%').padding(0).borderRadius(AppRadius.Xl).backgroundColor(AppTheme.Surface)
    .accessibilityText(topic.title)
    .onClick((): void => this.openTopic(topic))
  }

  @Builder
  topicGrid(): void {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text($r('app.string.guide_topics_heading'))
          .fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        Blank()
        Text($r('app.string.guide_topics_hint'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
      }.width('100%').padding({ left: 4, right: 4 })
      GridRow({ columns: { xs: 2, sm: 3 }, gutter: { x: 12, y: 12 },
        breakpoints: { value: [`${AdaptiveLayout.MEDIUM_WIDTH}vp`], reference: BreakpointsReference.ComponentSize } }) {
        ForEach(GUIDE_TOPICS, (topic: GuideTopic) => {
          GridCol() { this.topicCard(topic) }
        }, (topic: GuideTopic) => topic.id)
      }.width('100%')
    }.width('100%')
  }

  @Builder
  helpCard(): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpace.Md }) {
        SymbolGlyph(HELP_TOPIC.icon)
          .fontSize(24).fontColor([AppTheme.IconSecondary]).accessibilityLevel('no')
        Column({ space: 6 }) {
          Text(HELP_TOPIC.title)
            .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
          Text(HELP_TOPIC.summary)
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        this.forwardIndicator()
      }.width('100%').padding(20)
    }
    .width('100%').padding(0).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Xl)
    .accessibilityText(HELP_TOPIC.title)
    .onClick((): void => this.openTopic(HELP_TOPIC))
  }

  @Builder
  homeContent(): void {
    List({ space: AppSpace.Lg }) {
      ListItem() { this.startCard() }
      ListItem() { this.topicGrid() }
      ListItem() { this.helpCard() }
      ListItem() {
        Text($r('app.string.guide_offline_hint'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
          .textAlign(TextAlign.Center).width('100%')
      }
    }
    .width('100%').height('100%').layoutWeight(1)
    .constraintSize({ maxWidth: AdaptiveLayout.LARGE_WIDTH })
    .padding({ left: this.leftSafeVp + AppSpace.Md, right: this.rightSafeVp + AppSpace.Md })
    .contentStartOffset(AppSpace.Md).contentEndOffset(this.bottomSafeVp + AppSpace.Lg)
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  groupCard(group: GuideGroup): void {
    Column({ space: AppSpace.Sm }) {
      Text(group.title)
        .fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        .margin({ left: 4 })
      Column() {
        ForEach(group.items, (item: GuideItem, index: number) => {
          Row({ space: AppSpace.Sm }) {
            Text((index + 1).toString().padStart(2, '0'))
              .fontSize(AppFont.Caption).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
              .width(24).flexShrink(0).margin({ top: 3 }).accessibilityLevel('no')
            Column({ space: AppSpace.Sm }) {
              Text(item.action)
                .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
                .lineSpacing(LengthMetrics.vp(3))
              Text(item.desc)
                .fontSize(15).fontColor(AppTheme.TextSecondary).lineSpacing(LengthMetrics.vp(6))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top).padding(20)
          if (index < group.items.length - 1) {
            Divider().strokeWidth(0.5).color(AppTheme.Divider).margin({ left: 56, right: 20 })
          }
        }, (item: GuideItem) => item.id)
      }.width('100%').backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Xl)
    }.alignItems(HorizontalAlign.Start).width('100%')
  }

  @Builder
  detailContent(): void {
    List({ space: AppSpace.Lg }) {
      ListItem() {
        Row({ space: AppSpace.Md }) {
          SymbolGlyph(this.topic.icon)
            .fontSize(28).fontColor([AppColor.Brand]).accessibilityLevel('no')
          Text(this.topic.summary)
            .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).lineSpacing(LengthMetrics.vp(4)).layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4, top: AppSpace.Xs, bottom: AppSpace.Xs })
      }
      LazyForEach(this.groupSource, (group: GuideGroup) => {
        ListItem() { this.groupCard(group) }
      }, (group: GuideGroup) => group.id)
      ListItem() {
        Button($r('app.string.guide_back_to_topics'), { type: ButtonType.Normal })
          .width('100%').constraintSize({ minHeight: 48 }).fontSize(AppFont.Body)
          .backgroundColor(AppColor.BrandSoft).fontColor(AppColor.Brand).borderRadius(AppRadius.Lg)
          .onClick((): void => { this.navStack.pop(); })
      }
    }
    .width('100%').height('100%').layoutWeight(1)
    .constraintSize({ maxWidth: AdaptiveLayout.LARGE_WIDTH })
    .padding({ left: this.leftSafeVp + AppSpace.Md, right: this.rightSafeVp + AppSpace.Md })
    .contentStartOffset(AppSpace.Md).contentEndOffset(this.bottomSafeVp + AppSpace.Lg)
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.common_back'),
          diameter: 40, iconSize: 22, iconColor: AppTheme.IconPrimary,
          onPress: (): void => { this.navStack.pop(); } })
        Text(this.topicId.length > 0 ? this.topic.title : $r('app.string.guide_title'))
          .fontSize(AppFont.Title).fontColor(AppTheme.TextPrimary).fontWeight(FontWeight.Medium)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.guide_offline_label'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary).flexShrink(0)
      }
      .width('100%')
      .padding({ top: this.topSafeVp + AppSpace.Xs, bottom: AppSpace.Xs,
        left: this.leftSafeVp + AppSpace.Md, right: this.rightSafeVp + AppSpace.Md })
      if (this.topicId.length > 0) {
        this.detailContent()
      } else {
        this.homeContent()
      }
    }
    .width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
