import { ReaderTapPolicy } from '../../utils/ReaderTapPolicy';
import { ReaderToolsSnapshot } from '../../model/ReaderTools';
import { ReaderToolsService } from './ReaderToolsService';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextReadingPosition, TextReadingSettings, ReaderCornerLayout } from '../../model/TextReading';
import { findThemePreset } from '../../model/ReaderTheme';
import { SpeechPosition } from '../../model/TextToSpeechState';
import { TextReadingProgressService } from './TextReadingProgressService';
import { TextReadingSettingsService } from './TextReadingSettingsService';
import { TextToSpeechService } from './TextToSpeechService';

/** 只迁移常规阅读选项；自定义图片、字体、配色及本机文件路径不进入快照。 */
export class ReadingSettingsBackup {
  cornerLayout: string | undefined = undefined;
  textAlignment: string = 'justify';
  fontSize: number = 18;
  lineHeight: number = 1.9;
  paragraphSpacing: number = TextReadingSettings.PARAGRAPH_SPACING_DEFAULT;
  fontWeight: number = 400;
  themeId: string | undefined = undefined;
  tapRegions: string = ReaderTapPolicy.DEFAULT;
  tapLeftPercent: number = 33;
  tapRightPercent: number = 33;
  tapTopPercent: number = 33;
  tapBottomPercent: number = 33;
  showHeader: boolean = true;
  showFooter: boolean = true;
  showChapterTitle: boolean = true;
  showPageNumber: boolean = true;
  showChapterNumber: boolean = true;
  showBookName: boolean = true;
  volumeKeyPageTurn: boolean = false;
  smartKeyPageTurn: boolean = false;
  pageTurnMode: string = 'cover';
  showReadingStatus: boolean = true;
  alwaysShowStatusBar: boolean = true;
  followSystemTheme: boolean = false;
  marginLeft: number = 16;
  marginRight: number = 16;
  marginTop: number = 12;
  marginBottom: number = 12;
  screenOnMinutes: number = 0;
}

export class SpeechPositionBackup extends SpeechPosition {
  bookId: string = '';
}

export class ReadingBackupSnapshot {
  tools: ReaderToolsSnapshot | undefined = undefined;
  positions: TextReadingPosition[] = [];
  settings: ReadingSettingsBackup = new ReadingSettingsBackup();
  speechPositions: SpeechPositionBackup[] = [];
  speechSpeed: number = 1;
  speechPerson: number = 13;
  speechLanguage: string = 'zh-CN';
  speechFollow: boolean = true;
}

export class ReadingBackupService {
  static async createSnapshot(context: common.Context): Promise<ReadingBackupSnapshot> {
    const snapshot = new ReadingBackupSnapshot();
    const tools = await ReaderToolsService.snapshot(context);
    tools.bookmarks = tools.bookmarks.filter((mark): boolean => !mark.bookId.startsWith('import_'));
    tools.rules = tools.rules.filter((rule): boolean => !rule.bookId.startsWith('import_'));
    snapshot.tools = tools;
    snapshot.positions = (await TextReadingProgressService.getAll(context))
      .filter((position: TextReadingPosition): boolean => !position.bookId.startsWith('import_'));
    const settings = await TextReadingSettingsService.get(context);
    const saved = snapshot.settings;
    saved.textAlignment = settings.textAlignment;
    saved.fontSize = settings.fontSize;
    saved.lineHeight = settings.lineHeight;
    saved.paragraphSpacing = settings.paragraphSpacing;
    saved.fontWeight = settings.fontWeight;
    if (findThemePreset(settings.themeId) !== null) saved.themeId = settings.themeId;
    saved.tapLeftPercent = settings.tapLeftPercent;
    saved.tapRightPercent = settings.tapRightPercent;
    saved.tapTopPercent = settings.tapTopPercent;
    saved.tapBottomPercent = settings.tapBottomPercent;
    saved.showHeader = settings.showHeader;
    saved.cornerLayout = ReaderCornerLayout.normalize(settings.cornerLayout);
    saved.showFooter = settings.showFooter;
    saved.showChapterTitle = settings.showChapterTitle;
    saved.showPageNumber = settings.showPageNumber;
    saved.showChapterNumber = settings.showChapterNumber;
    saved.showBookName = settings.showBookName;
    saved.tapRegions = settings.tapRegions;
    saved.volumeKeyPageTurn = settings.volumeKeyPageTurn;
    saved.smartKeyPageTurn = settings.smartKeyPageTurn;
    saved.pageTurnMode = settings.pageTurnMode;
    saved.showReadingStatus = settings.showReadingStatus;
    saved.alwaysShowStatusBar = settings.alwaysShowStatusBar;
    saved.followSystemTheme = settings.followSystemTheme;
    saved.marginLeft = settings.marginLeft;
    saved.marginRight = settings.marginRight;
    saved.marginTop = settings.marginTop;
    saved.marginBottom = settings.marginBottom;
    saved.screenOnMinutes = settings.screenOnMinutes;

    const speech = await preferences.getPreferences(context, { name: 'text_to_speech' });
    const speed = speech.getSync('speed', 1);
    const person = speech.getSync('person', 13);
    const language = speech.getSync('language', 'zh-CN');
    snapshot.speechSpeed = typeof speed === 'number' && Number.isFinite(speed) ? Math.max(0.5, Math.min(2, speed)) : 1;
    snapshot.speechPerson = typeof person === 'number' && Number.isSafeInteger(person) && person >= 0 ? person : 13;
    snapshot.speechLanguage = typeof language === 'string' && language.length > 0 && language.length <= 128 ?
      language : 'zh-CN';
    snapshot.speechFollow = speech.getSync('follow', true) !== false;
    for (const key of Object.keys(await speech.getAll())) {
      if (!key.startsWith('position_') || key.startsWith('position_import_')) continue;
      const raw = speech.getSync(key, '');
      if (typeof raw !== 'string' || !raw) continue;
      try {
        const position: SpeechPositionBackup = JSON.parse(raw);
        if (!position) continue;
        position.bookId = key.substring('position_'.length);
        if (ReadingBackupService.validSpeechPosition(position)) snapshot.speechPositions.push(position);
      } catch (_e) { /* 异常朗读进度只跳过本条。 */ }
    }
    return snapshot;
  }

  static async restoreSnapshot(context: common.Context, snapshot: ReadingBackupSnapshot): Promise<void> {
    if (snapshot.tools !== undefined) await ReaderToolsService.restore(context, snapshot.tools);
    await TextReadingProgressService.restoreBackupPositions(context, snapshot.positions);
    const settings = await TextReadingSettingsService.get(context);
    const saved = snapshot.settings;
    settings.textAlignment = TextReadingSettings.normalizeTextAlignment(saved.textAlignment);
    settings.fontSize = saved.fontSize;
    settings.lineHeight = saved.lineHeight;
    settings.paragraphSpacing = TextReadingSettings.normalizeParagraphSpacing(saved.paragraphSpacing);
    settings.fontWeight = saved.fontWeight;
    if (saved.themeId !== undefined) {
      settings.themeId = saved.themeId;
      settings.pattern = 'none';
      // 不删除本机自定义文件，也不将源设备的路径带入恢复。
      settings.backgroundImage = '';
    }
    settings.tapLeftPercent = typeof saved.tapLeftPercent === 'number' ? ReaderTapPolicy.percent(saved.tapLeftPercent) : 33;
    settings.tapRightPercent = typeof saved.tapRightPercent === 'number' ? ReaderTapPolicy.percent(saved.tapRightPercent, settings.tapLeftPercent) : 33;
    settings.tapTopPercent = typeof saved.tapTopPercent === 'number' ? ReaderTapPolicy.percent(saved.tapTopPercent) : 33;
    settings.tapBottomPercent = typeof saved.tapBottomPercent === 'number' ? ReaderTapPolicy.percent(saved.tapBottomPercent, settings.tapTopPercent) : 33;
    settings.showHeader = saved.showHeader !== false;
    settings.cornerLayout = ReaderCornerLayout.normalize(saved.cornerLayout ?? ReaderCornerLayout.DEFAULT);
    settings.showFooter = saved.showFooter !== false;
    settings.showChapterTitle = saved.showChapterTitle !== false;
    settings.showPageNumber = saved.showPageNumber !== false;
    settings.showChapterNumber = saved.showChapterNumber !== false;
    settings.showBookName = saved.showBookName !== false;
    settings.tapRegions = ReaderTapPolicy.normalize(typeof saved.tapRegions === 'string' ? saved.tapRegions : ReaderTapPolicy.DEFAULT);
    settings.volumeKeyPageTurn = saved.volumeKeyPageTurn === true;
    settings.smartKeyPageTurn = saved.smartKeyPageTurn === true;
    settings.pageTurnMode = saved.pageTurnMode;
    settings.showReadingStatus = saved.showReadingStatus;
    settings.alwaysShowStatusBar = saved.alwaysShowStatusBar;
    settings.followSystemTheme = saved.followSystemTheme;
    settings.marginLeft = saved.marginLeft;
    settings.marginRight = saved.marginRight;
    settings.marginTop = saved.marginTop;
    settings.marginBottom = saved.marginBottom;
    settings.screenOnMinutes = saved.screenOnMinutes;
    await TextReadingSettingsService.save(context, settings);

    const speech = await preferences.getPreferences(context, { name: 'text_to_speech' });
    for (const key of Object.keys(await speech.getAll())) {
      if (key.startsWith('position_') && !key.startsWith('position_import_')) speech.deleteSync(key);
    }
    for (const position of snapshot.speechPositions) {
      // 白名单重建，避免把备份中的额外属性写入长期存储。
      const value = new SpeechPosition();
      value.sourceUrl = position.sourceUrl;
      value.bookUrl = position.bookUrl;
      value.chapterUrl = position.chapterUrl;
      value.chapterIndex = position.chapterIndex;
      value.charOffset = position.charOffset;
      speech.putSync(`position_${position.bookId}`, JSON.stringify(value));
    }
    speech.putSync('speed', snapshot.speechSpeed);
    speech.putSync('person', snapshot.speechPerson);
    speech.putSync('language', snapshot.speechLanguage);
    speech.putSync('follow', snapshot.speechFollow);
    await speech.flush();
    await TextToSpeechService.reloadSettings(context);
  }

  static isValidSnapshot(snapshot: ReadingBackupSnapshot): boolean {
    if (snapshot?.tools !== undefined && !ReaderToolsService.validSnapshot(snapshot.tools)) return false;
    if (!snapshot || !Array.isArray(snapshot.positions) || snapshot.positions.length > 10000 ||
      !snapshot.positions.every((position: TextReadingPosition): boolean =>
        TextReadingProgressService.isValidPosition(position) && !position.bookId.startsWith('import_')) ||
      !Array.isArray(snapshot.speechPositions) || snapshot.speechPositions.length > 10000 ||
      !snapshot.speechPositions.every((position: SpeechPositionBackup): boolean =>
        ReadingBackupService.validSpeechPosition(position)) ||
      !ReadingBackupService.inRange(snapshot.speechSpeed, 0.5, 2) ||
      !Number.isSafeInteger(snapshot.speechPerson) || snapshot.speechPerson < 0 ||
      typeof snapshot.speechLanguage !== 'string' || snapshot.speechLanguage.length === 0 ||
      snapshot.speechLanguage.length > 128 || typeof snapshot.speechFollow !== 'boolean') return false;
    const settings = snapshot.settings;
    return !!settings && ReadingBackupService.inRange(settings.fontSize, 14, 50) &&
      (settings.cornerLayout === undefined || (typeof settings.cornerLayout === 'string' &&
        ReaderCornerLayout.normalize(settings.cornerLayout) === settings.cornerLayout)) &&
      (settings.textAlignment === undefined || ['justify', 'start', 'center', 'end'].includes(settings.textAlignment)) &&
      ReadingBackupService.inRange(settings.lineHeight, 1, 2.4) &&
      (settings.paragraphSpacing === undefined || ReadingBackupService.inRange(settings.paragraphSpacing, 0, 2)) &&
      ReadingBackupService.inRange(settings.fontWeight, 100, 900) &&
      (settings.themeId === undefined || findThemePreset(settings.themeId) !== null) &&
      ['cover', 'none', 'simulation', 'slide', 'vertical'].includes(settings.pageTurnMode) &&
      (settings.volumeKeyPageTurn === undefined || typeof settings.volumeKeyPageTurn === 'boolean') &&
      (settings.smartKeyPageTurn === undefined || typeof settings.smartKeyPageTurn === 'boolean') &&
      typeof settings.showReadingStatus === 'boolean' && typeof settings.alwaysShowStatusBar === 'boolean' &&
      typeof settings.followSystemTheme === 'boolean' &&
      [settings.marginLeft, settings.marginRight, settings.marginBottom]
        .every((margin: number): boolean => ReadingBackupService.inRange(margin, 0, 64)) &&
      ReadingBackupService.inRange(settings.marginTop, 0, TextReadingSettings.MARGIN_MAX_LIMIT) &&
      [-1, 0, 1, 5, 10].includes(settings.screenOnMinutes);
  }

  private static validSpeechPosition(position: SpeechPositionBackup): boolean {
    return !!position && typeof position.bookId === 'string' && position.bookId.length > 0 &&
      position.bookId.length <= 8192 && !position.bookId.startsWith('import_') &&
      [position.sourceUrl, position.bookUrl, position.chapterUrl]
        .every((value: string): boolean => typeof value === 'string' && value.length <= 1024 * 1024) &&
      Number.isSafeInteger(position.chapterIndex) && position.chapterIndex >= 0 &&
      Number.isSafeInteger(position.charOffset) && position.charOffset >= 0;
  }

  private static inRange(value: number, min: number, max: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
  }
}
