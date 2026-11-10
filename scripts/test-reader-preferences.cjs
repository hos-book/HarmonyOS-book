// Real settings model/service with an in-memory HarmonyOS preferences adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
let flushes = 0;
const preferences = { getPreferences: async () => ({
  getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
  putSync: (key, value) => values.set(key, value),
  put: async (key, value) => { values.set(key, value); },
  put: async (key, value) => { values.set(key, value); },
  getAll: async () => Object.fromEntries(values),
  deleteSync: key => values.delete(key),
  flush: async () => { flushes++; }
}) };
const cache = new Map();
function load(relative) {
  const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, $r: name => name, ObservedV2: value => value, Trace: () => {}, require: name => {
    if (name === '@kit.ArkData') return { preferences };
    if (name === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
    if (name === './TextToSpeechService') return { TextToSpeechService: { reloadSettings: async () => {} } };
    if (name === '../PreferenceService') return { PreferenceService: { promoteFavorite: async () => {} } };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  }, console }, { filename });
  return exports;
}
(async () => {
  const { TextReadingSettings, PageTurnMode, ReaderCornerLayout } = load('model/TextReading');
  assert.equal(new TextReadingSettings().textAlignment, 'justify');
  assert.equal(TextReadingSettings.normalizeTextAlignment('invalid'), 'justify');
  const { TextReadingSettingsService: service } = load('service/text/TextReadingSettingsService');
  values.set('font_size', 22); // Existing installations have no new preference keys.
  const migrated = await service.get({});
  const { ReaderDialogueRules } = load('model/ReaderDialogueRules');
  assert.equal(migrated.dialogueQuotePairs, ReaderDialogueRules.DEFAULT);
  migrated.dialogueQuotePairs = '‘’\n【】';
  assert.equal(migrated.chapterHeadingVisible, true);
  assert.equal(migrated.chapterHeadingSize, 26);
  assert.equal(migrated.chapterHeadingStyle, 'center');
  migrated.chapterHeadingVisible = false;
  migrated.chapterHeadingSize = 34;
  migrated.chapterHeadingStyle = 'bold';
  assert.equal(migrated.dialogueHighlightColor, '', 'legacy dialogue colors follow the reading theme');
  migrated.dialogueHighlight = true;
  migrated.dialogueHighlightColor = '#12ab34';
  assert.equal(migrated.speechMarkColor, '', 'legacy speech marks follow the reading theme');
  migrated.speechMarkColor = '#56cd78';
  assert.equal(migrated.speechFollowPage, true, 'existing readers retain page-following speech');
  migrated.speechFollowPage = false;
  assert.equal(migrated.showBrightnessBar, true);
  assert.equal(migrated.showPageRules, true, 'existing readers retain header and footer rules');
  migrated.showPageRules = false;
  assert.equal(migrated.pageTurnHaptic, 'none', 'existing readers must not start vibrating after upgrade');
  migrated.pageTurnHaptic = 'medium';
  assert.equal(migrated.brightness, -1, 'existing readers retain system brightness');
  assert.equal(migrated.cornerLayout, '0123', 'legacy settings keep their original four corners');
  for (let corner = 0; corner < 4; corner++) {
    for (let content = 0; content < 4; content++) {
      const swapped = ReaderCornerLayout.swap('0123', corner, content);
      assert.equal(ReaderCornerLayout.content(swapped, corner), content);
      assert.equal(ReaderCornerLayout.content(swapped, content), corner);
      assert.equal(new Set(swapped).size, 4, 'swapping never drops or duplicates a content item');
    }
  }
  assert.equal(ReaderCornerLayout.swap('0123', -1, 3), '0123');
  assert.equal(ReaderCornerLayout.normalize('0012'), '0123');
  migrated.cornerLayout = ReaderCornerLayout.swap('0123', 0, 3);
  assert.equal(migrated.fontSize, 22);
  assert.equal(migrated.paragraphSpacing, 0, 'old settings keep existing paragraph layout');
  assert.equal(TextReadingSettings.normalizeParagraphSpacing(NaN), 0);
  assert.equal(TextReadingSettings.normalizeParagraphSpacing(-1), 0);
  assert.equal(TextReadingSettings.normalizeParagraphSpacing(10), 2);
  migrated.paragraphSpacing = 1.2;
  assert.equal(migrated.textAlignment, 'justify', 'legacy preferences default to justified text');
  assert.equal(migrated.backgroundImageMode, 'cover', 'legacy images keep their existing crop');
  assert.equal(migrated.marginLeft, migrated.marginRight);
  assert.equal(migrated.followSystemTheme, true);
  assert.equal(migrated.alwaysShowStatusBar, true, 'existing installations show the status bar by default');
  assert.equal(migrated.volumeKeyPageTurn, false);
  assert.equal(migrated.smartKeyPageTurn, false);
  migrated.smartKeyPageTurn = true;
  migrated.volumeKeyPageTurn = true;
  migrated.showBrightnessBar = false;
  migrated.brightness = 0.37;
  migrated.followSystemTheme = true;
  migrated.alwaysShowStatusBar = false;
  migrated.pageTurnMode = PageTurnMode.Vertical;
  migrated.marginLeft = 8;
  migrated.marginRight = 26;
  migrated.marginTop = 32;
  migrated.marginBottom = 0;
  await service.save({}, migrated);
  const restored = await service.get({});
  assert.equal(restored.chapterHeadingVisible, false);
  assert.equal(restored.chapterHeadingSize, 34);
  assert.equal(restored.chapterHeadingStyle, 'bold');
  assert.equal(restored.dialogueQuotePairs, '‘’\n【】', 'dialogue delimiters persist independently of the enabled flag');
  assert.equal(restored.dialogueHighlight, true);
  assert.equal(restored.dialogueHighlightColor, '#12AB34', 'dialogue color survives reopening independently of text color');
  assert.equal(restored.speechMarkColor, '#56CD78', 'speech mark color persists independently of dialogue color');
  assert.equal(restored.speechFollowPage, false, 'independent browsing survives reload');
  assert.equal(restored.showBrightnessBar, false);
  assert.equal(restored.showPageRules, false, 'hidden page rules survive reopening');
  assert.equal(restored.brightness, 0.37);
  assert.equal(restored.cornerLayout, '3120', 'corner order survives a preferences reload');
  assert.equal(restored.pageTurnMode, 'vertical');
  assert.equal(restored.pageTurnHaptic, 'medium', 'haptic level survives reopening');
  for (const level of ['none', 'strong', 'medium', 'weak']) {
    restored.pageTurnHaptic = level;
    await service.save({}, restored);
    assert.equal((await service.get({})).pageTurnHaptic, level);
  }
  assert.equal(restored.paragraphSpacing, 1.2, 'paragraph spacing survives reload');
  assert.equal(restored.volumeKeyPageTurn, true);
  assert.equal(restored.smartKeyPageTurn, true);
  assert.equal(restored.followSystemTheme, true);
  assert.equal(restored.alwaysShowStatusBar, false, 'toolbar-following mode survives a preferences reload');
  assert.deepEqual([restored.marginLeft, restored.marginRight, restored.marginTop, restored.marginBottom], [8, 26, 32, 0]);
  restored.dialogueHighlightColor = '';
  await service.save({}, restored);
  const themeFollowing = await service.get({});
  assert.equal(themeFollowing.dialogueHighlightColor, '', 'enabling theme follow persists the mode without freezing a resolved color');
  assert.equal(themeFollowing.dialogueHighlight, true, 'theme follow does not disable dialogue highlighting');
  themeFollowing.dialogueHighlightColor = '#21dd21';
  await service.save({}, themeFollowing);
  assert.equal((await service.get({})).dialogueHighlightColor, '#21DD21', 'choosing a color leaves follow mode and survives reopening');
  values.set('marginLeft', -20);
  values.set('dialogue_highlight_color', '#invalid');
  values.set('speech_mark_color', '#invalid');
  values.set('corner_layout', 'invalid');
  values.set('marginRight', 1000);
  values.set('marginTop', 'bad');
  values.set('marginBottom', NaN);
  values.set('volume_key_page_turn', 'bad');
  values.set('smart_key_page_turn', 'bad');
  values.set('page_turn_mode', 'bad');
  values.set('page_turn_haptic', 'bad');
  values.set('always_show_status_bar', 'bad');
  const sanitized = await service.get({});
  assert.equal(TextReadingSettings.normalizeChapterHeadingSize(NaN), 26);
  assert.equal(TextReadingSettings.normalizeChapterHeadingSize(-1), 18);
  assert.equal(TextReadingSettings.normalizeChapterHeadingSize(99), 48);
  values.set('chapter_heading_size', 'broken');
  values.set('chapter_heading_style', 'broken');
  const invalidHeading = await service.get({});
  assert.equal(invalidHeading.chapterHeadingSize, 26);
  assert.equal(invalidHeading.chapterHeadingStyle, 'center');
  assert.equal(sanitized.dialogueHighlightColor, '', 'invalid persisted colors use the theme fallback');
  assert.equal(sanitized.speechMarkColor, '', 'invalid speech colors use the theme fallback');
  assert.equal(sanitized.cornerLayout, '0123', 'invalid corner layouts return to the original order');
  assert.deepEqual([sanitized.marginLeft, sanitized.marginRight, sanitized.marginTop, sanitized.marginBottom], [0, 64, 12, 12]);
  assert.equal(sanitized.pageTurnMode, PageTurnMode.Cover);
  assert.equal(sanitized.pageTurnHaptic, 'none');
  assert.equal(sanitized.volumeKeyPageTurn, false);
  assert.equal(sanitized.smartKeyPageTurn, false);
  assert.equal(sanitized.alwaysShowStatusBar, true, 'invalid status-bar preference falls back to visible');
  await service.save({}, new TextReadingSettings());
  const reset = await service.get({});
  assert.equal(reset.chapterHeadingVisible, true);
  assert.equal(reset.chapterHeadingSize, 26);
  assert.equal(reset.chapterHeadingStyle, 'center');
  assert.equal(reset.dialogueHighlightColor, '', 'reset restores automatic dialogue colors');
  assert.equal(reset.speechMarkColor, '', 'reset restores automatic speech mark colors');
  assert.equal(reset.speechFollowPage, true);
  assert.equal(reset.cornerLayout, '0123');
  assert.equal(reset.showPageRules, true, 'reset restores visible page rules');
  assert.equal(reset.pageTurnHaptic, 'none', 'reset disables haptics');
  assert.equal(reset.followSystemTheme, true);
  assert.equal(reset.volumeKeyPageTurn, false);
  assert.equal(reset.smartKeyPageTurn, false);
  assert.equal(reset.alwaysShowStatusBar, true);
  assert.equal(reset.marginLeft, 16);
  assert.equal(reset.paragraphSpacing, 0);
  assert.equal(reset.marginRight, 16);
  assert.equal(flushes, 8, 'each explicit save, including four haptic levels and follow/custom changes, flushes once');
  values.set('follow_system_theme', false);
  assert.equal((await service.get({})).followSystemTheme, false, 'explicit opt-out survives the new default');
  const { ReaderThemeId, resolvePalette } = load('model/ReaderTheme');
  const custom = new TextReadingSettings();
  custom.themeId = ReaderThemeId.Black;
  custom.pageTurnMode = PageTurnMode.None;
  await service.save({}, custom);
  const customRestored = await service.get({});
  assert.equal(customRestored.themeId, 'black');
  assert.equal(customRestored.pageTurnMode, 'none');
  assert.equal(resolvePalette(customRestored.themeId, '').background, '#000000');
  const typography = new TextReadingSettings();
  typography.fontSize = 50;
  typography.lineHeight = 1;
  typography.fontWeight = 537;
  typography.fontColor = '#123456';
  typography.fontName = 'Test.ttf';
  typography.fontPath = '/data/storage/el2/base/files/reader_fonts/test.ttf';
  typography.themeId = ReaderThemeId.Custom;
  typography.customBackground = '#BADA55';
  typography.screenOnMinutes = 5;
  await service.save({}, typography);
  const fontRestored = await service.get({});
  for (const alignment of ['justify', 'start', 'center', 'end']) {
    typography.textAlignment = alignment;
    await service.save({}, typography);
    assert.equal((await service.get({})).textAlignment, alignment);
  }
  values.set('text_alignment', 'invalid');
  assert.equal((await service.get({})).textAlignment, 'justify');
  for (const field of ['fontSize', 'lineHeight', 'fontWeight', 'fontColor', 'fontName', 'fontPath',
    'themeId', 'customBackground', 'screenOnMinutes']) assert.equal(fontRestored[field], typography[field], field);
  assert.equal(TextReadingSettings.normalizeFontSize(100), 50);
  assert.equal(TextReadingSettings.normalizeLineHeight(0), 1);
  assert.equal(TextReadingSettings.normalizeFontWeight(NaN), 400);
  assert.equal(TextReadingSettings.normalizeFontWeight(950), 900);
  assert.equal(TextReadingSettings.normalizeScreenOnMinutes(7), 0);
  for (const minutes of [0, 1, 5, 10, -1]) {
    typography.screenOnMinutes = minutes;
    await service.save({}, typography);
    assert.equal((await service.get({})).screenOnMinutes, minutes);
  }
  const { ReadingBackupService: backup } = load('service/text/ReadingBackupService');
  typography.volumeKeyPageTurn = true;
  typography.smartKeyPageTurn = true;
  typography.textAlignment = 'end';
  typography.showPageRules = false;
  typography.pageTurnHaptic = 'strong';
  typography.dialogueQuotePairs = '【】\n（）';
  typography.dialogueHighlight = true;
  typography.dialogueHighlightColor = '#3478AB';
  typography.speechMarkColor = '#AB7834';
  typography.paragraphSpacing = 1.4;
  typography.chapterHeadingVisible = false;
  typography.chapterHeadingSize = 42;
  typography.chapterHeadingStyle = 'plain';
  await service.save({}, typography);
  const snapshot = await backup.createSnapshot({});
  assert.equal(snapshot.settings.chapterHeadingVisible, false);
  assert.equal(snapshot.settings.chapterHeadingSize, 42);
  assert.equal(snapshot.settings.chapterHeadingStyle, 'plain');
  assert.equal(snapshot.settings.dialogueQuotePairs, '【】\n（）');
  assert.equal(snapshot.settings.dialogueHighlightColor, '#3478AB');
  assert.equal(snapshot.settings.speechMarkColor, '#AB7834');
  assert.equal(snapshot.settings.textAlignment, 'end');
  assert.equal(snapshot.settings.showPageRules, false);
  assert.equal(snapshot.settings.pageTurnHaptic, 'strong');
  assert.equal(snapshot.settings.paragraphSpacing, 1.4);
  assert.equal(snapshot.settings.volumeKeyPageTurn, true);
  assert.equal(snapshot.settings.smartKeyPageTurn, true);
  await service.save({}, new TextReadingSettings());
  await backup.restoreSnapshot({}, snapshot);
  const restoredHeading = await service.get({});
  assert.equal(restoredHeading.dialogueQuotePairs, '【】\n（）', 'backup roundtrip retains custom delimiters');
  restoredHeading.dialogueQuotePairs = '';
  await service.save({}, restoredHeading);
  assert.equal((await service.get({})).dialogueQuotePairs, '', 'empty selection remains empty on reopen');
  assert.equal(restoredHeading.chapterHeadingVisible, false);
  assert.equal(restoredHeading.chapterHeadingSize, 42);
  assert.equal(restoredHeading.chapterHeadingStyle, 'plain');
  assert.equal((await service.get({})).dialogueHighlightColor, '#3478AB', 'backup retains dialogue color');
  assert.equal((await service.get({})).speechMarkColor, '#AB7834', 'backup retains speech mark color');
  assert.equal((await service.get({})).textAlignment, 'end');
  assert.equal((await service.get({})).showPageRules, false, 'backup restores hidden page rules');
  assert.equal((await service.get({})).pageTurnHaptic, 'strong', 'backup restores haptic level');
  assert.equal((await service.get({})).paragraphSpacing, 1.4);
  assert.equal((await service.get({})).volumeKeyPageTurn, true);
  assert.equal((await service.get({})).smartKeyPageTurn, true);
  delete snapshot.settings.volumeKeyPageTurn;
  delete snapshot.settings.smartKeyPageTurn;
  delete snapshot.settings.textAlignment;
  delete snapshot.settings.showPageRules;
  delete snapshot.settings.pageTurnHaptic;
  delete snapshot.settings.paragraphSpacing;
  delete snapshot.settings.dialogueQuotePairs;
  delete snapshot.settings.dialogueHighlightColor;
  delete snapshot.settings.speechMarkColor;
  delete snapshot.settings.chapterHeadingVisible;
  delete snapshot.settings.chapterHeadingSize;
  delete snapshot.settings.chapterHeadingStyle;
  await backup.restoreSnapshot({}, snapshot);
  const legacyHeading = await service.get({});
  assert.equal(legacyHeading.dialogueQuotePairs, ReaderDialogueRules.DEFAULT, 'old backups retain existing quote behavior');
  assert.equal(legacyHeading.chapterHeadingVisible, true);
  assert.equal(legacyHeading.chapterHeadingSize, 26);
  assert.equal(legacyHeading.chapterHeadingStyle, 'center');
  assert.equal((await service.get({})).textAlignment, 'justify', 'old backups adopt justified text');
  assert.equal((await service.get({})).showPageRules, true, 'old backups retain visible page rules');
  assert.equal((await service.get({})).pageTurnHaptic, 'none', 'old backups disable haptics');
  assert.equal((await service.get({})).dialogueHighlightColor, '', 'old backups retain automatic dialogue colors');
  assert.equal((await service.get({})).speechMarkColor, '', 'old backups retain automatic speech colors');
  assert.equal((await service.get({})).paragraphSpacing, 0, 'old backups use the original paragraph layout');
  assert.equal((await service.get({})).volumeKeyPageTurn, false, 'old backups keep system volume behavior');
  assert.equal((await service.get({})).smartKeyPageTurn, false, 'old backups leave smart key disabled');
  // Theme ownership: each custom theme owns its image and colors; presets remain independent.
  const { resolveEffectiveThemeId, readerColorContrast, recommendedReaderFontColor } = load('model/ReaderTheme');
  const themeSettings = new TextReadingSettings();
  themeSettings.themeId = ReaderThemeId.Custom;
  themeSettings.customBackground = '#E8DBB8';
  themeSettings.fontColor = '#453321';
  themeSettings.customThemes[0].backgroundImage = '/data/storage/el2/base/files/reader_bg/test.jpg';
  themeSettings.customThemes[0].overlayAlpha = 0.6;
  themeSettings.backgroundImage = themeSettings.customThemes[0].backgroundImage;
  themeSettings.imageBackground = '#1C1F22';
  themeSettings.imageFontColor = '#F5F2EA';
  themeSettings.overlayAlpha = 0.6;
  for (const id of [ReaderThemeId.Custom, ReaderThemeId.Night,
    ReaderThemeId.Black, ReaderThemeId.Parchment, ReaderThemeId.Custom]) {
    themeSettings.themeId = id;
    themeSettings.pattern = id === ReaderThemeId.Custom ? 'image' : 'none';
    await service.save({}, themeSettings);
    const saved = await service.get({});
    assert.equal(saved.themeId, id);
    assert.equal(saved.customBackground, '#E8DBB8');
    assert.equal(saved.fontColor, '#453321');
    assert.equal(saved.imageBackground, '#1C1F22');
    assert.equal(saved.imageFontColor, '#F5F2EA');
    assert.equal(saved.backgroundImage, themeSettings.backgroundImage);
    assert.equal(saved.overlayAlpha, 0.6);
    const palette = resolvePalette(id, saved.customBackground, saved.fontColor,
      saved.imageBackground, saved.imageFontColor);
    if (id === ReaderThemeId.Custom) {
      assert.equal(palette.background, '#E8DBB8');
      assert.equal(palette.primary, '#453321');
    } else if (id === ReaderThemeId.Image) {
      assert.equal(palette.background, '#1C1F22');
      assert.equal(palette.primary, '#F5F2EA');
    } else {
      assert.equal(palette.primary, resolvePalette(id, '').primary, 'preset owns its text color');
      assert.equal(palette.background, resolvePalette(id, '').background);
    }
    assert.equal(resolveEffectiveThemeId(id, false, true), id);
    assert.equal(resolveEffectiveThemeId(id, true, true), ReaderThemeId.Night);
    assert.equal(resolveEffectiveThemeId(id, true, false),
      [ReaderThemeId.Night, ReaderThemeId.Black].includes(id) ? ReaderThemeId.Parchment : id);
  }
  assert.equal(readerColorContrast('#FFFFFF', '#FFFFFF'), 1);
  assert.equal(readerColorContrast('#FFFFFF', '#000000'), 21);
  for (const bg of ['#000000', '#FFFFFF', '#E8DBB8', '#777777']) {
    assert.ok(readerColorContrast(bg, recommendedReaderFontColor(bg)) > 3);
  }
  // Legacy global text colors are captured in a custom theme with the visible old background.
  values.clear();
  values.set('theme_id', 'black');
  values.set('font_color', '#BADA55');
  const legacyText = await service.get({});
  assert.equal(legacyText.themeId, ReaderThemeId.Custom);
  assert.equal(legacyText.customBackground, '#000000');
  assert.equal(legacyText.fontColor, '#BADA55');
  await service.save({}, legacyText);
  legacyText.themeId = ReaderThemeId.Black;
  await service.save({}, legacyText);
  assert.equal((await service.get({})).themeId, ReaderThemeId.Black, 'migration does not run twice');
  // Legacy image tint and text color migrate into the free custom theme.
  values.clear();
  values.set('theme_id', 'image');
  values.set('background_pattern', 'image');
  values.set('background_image', themeSettings.backgroundImage);
  values.set('custom_background', '#204060');
  values.set('font_color', '#EECCAA');
  values.set('overlay_alpha', 0.7);
  const legacyImage = await service.get({});
  assert.equal(legacyImage.themeId, ReaderThemeId.Custom);
  assert.equal(legacyImage.customThemeIndex, 0);
  assert.equal(legacyImage.customThemes[0].backgroundImage, themeSettings.backgroundImage);
  assert.equal(legacyImage.customThemes[0].background, '#204060');
  assert.equal(legacyImage.customThemes[0].fontColor, '#EECCAA');
  assert.equal(legacyImage.imageBackground, '#204060');
  assert.equal(legacyImage.imageFontColor, '#EECCAA');
  assert.equal(legacyImage.overlayAlpha, 0.7);
  await service.save({}, legacyImage);
  legacyImage.themeId = ReaderThemeId.Custom;
  legacyImage.pattern = 'none';
  legacyImage.customBackground = '#FFFFFF';
  legacyImage.fontColor = '#000000';
  await service.save({}, legacyImage);
  assert.equal((await service.get({})).imageBackground, '#204060');
  assert.equal((await service.get({})).imageFontColor, '#EECCAA');
  values.clear();
  values.set('theme_id', 'night');
  assert.equal((await service.get({})).themeId, ReaderThemeId.Night, 'unmodified legacy preset stays a preset');
  const { ReaderCustomTheme, isReaderHexColor, normalizeHex } = load('model/ReaderTheme');
  values.clear();
  values.set('theme_id', 'custom');
  values.set('custom_background', '#ABCDEF');
  values.set('font_color', '#123456');
  const fiveThemes = await service.get({});
  assert.equal(fiveThemes.customThemes.length, 5);
  assert.equal(fiveThemes.customThemeIndex, 0);
  assert.equal(fiveThemes.customThemes[0].background, '#ABCDEF');
  assert.equal(fiveThemes.customThemes[0].fontColor, '#123456');
  assert.equal(new Set(fiveThemes.customThemes.map(theme => theme.id)).size, 5);
  const slotColors = ['#111111', '#222222', '#333333', '#444444', '#555555'];
  for (let slot = 0; slot < 5; slot++) {
    fiveThemes.customThemeIndex = slot;
    fiveThemes.customBackground = slotColors[slot];
    fiveThemes.fontColor = '#FEDCBA';
    fiveThemes.customThemes[slot] = ReaderCustomTheme.of(slot, slotColors[slot], '#FEDCBA');
    fiveThemes.customThemes[slot].name = `主题 ${slot + 1}`;
    fiveThemes.customThemes[slot].backgroundImage = `/reader_bg/${slot}.jpg`;
    fiveThemes.customThemes[slot].imageMode = ['contain', 'tile', 'stretch', 'cover', 'contain'][slot];
    fiveThemes.customThemes[slot].overlayAlpha = 0.1 * (slot + 1);
    fiveThemes.applyCustomTheme(slot);
    await service.save({}, fiveThemes);
  }
  for (let slot = 0; slot < 5; slot++) {
    const loaded = await service.get({});
    assert.equal(loaded.customThemes[slot].background, slotColors[slot]);
    assert.equal(loaded.customThemes[slot].fontColor, '#FEDCBA');
    assert.equal(loaded.customThemes[slot].name, `主题 ${slot + 1}`);
    assert.equal(loaded.customThemes[slot].backgroundImage, `/reader_bg/${slot}.jpg`);
    assert.equal(loaded.customThemes[slot].imageMode, ['contain', 'tile', 'stretch', 'cover', 'contain'][slot]);
    assert.equal(loaded.customThemes[slot].overlayAlpha, Math.round(0.1 * (slot + 1) * 100) / 100);
  }
  assert.equal((await service.get({})).customThemeIndex, 4);
  assert.equal((await service.get({})).customBackground, '#555555');
  values.set('custom_theme_index', 100);
  assert.equal((await service.get({})).customThemeIndex, 0);
  for (const text of ['#123', 'abc', '#aAbBcC', 'AABBCC', ' #123456 ']) assert.equal(isReaderHexColor(text), true);
  for (const text of ['', '#', '#12', '#12345', '#1234567', '#GGGGGG', '#12345678']) assert.equal(isReaderHexColor(text), false);
  assert.equal(normalizeHex('#abc'), '#AABBCC');
  const imageSettings = await service.get({});
  for (const mode of ['contain', 'tile', 'stretch', 'cover']) {
    imageSettings.customThemes[0].imageMode = mode;
    imageSettings.applyCustomTheme(0);
    await service.save({}, imageSettings);
    assert.equal((await service.get({})).backgroundImageMode, mode, 'theme image display mode survives reload');
  }
  for (const invalid of ['invalid', '', 42, null]) {
    values.set('custom_theme_0_image_mode', invalid);
    assert.equal((await service.get({})).backgroundImageMode, 'cover');
  }
  imageSettings.customThemes[0].imageMode = 'tile';
  imageSettings.applyCustomTheme(0);
  await service.save({}, imageSettings);
  const themeBackup = await backup.createSnapshot({});
  assert.equal(themeBackup.settings.customThemes, undefined, 'backup excludes local themes and image paths');
  await backup.restoreSnapshot({}, themeBackup);
  assert.equal((await service.get({})).backgroundImageMode, 'tile', 'backup restore preserves local image options');
  assert.equal((await service.get({})).customThemes[4].name, '主题 5');

  for (const slot of [0, 1, 2, 3, 4]) {
    assert.equal(ReaderCustomTheme.canUse(slot, false), slot === 0);
    assert.equal(ReaderCustomTheme.canUse(slot, true), true);
  }
  for (const invalid of [-1, 5, 100, 0.5, NaN]) {
    assert.equal(ReaderCustomTheme.canUse(invalid, true), false);
  }
  imageSettings.applyCustomTheme(4);
  imageSettings.applyCustomThemeAccess(true);
  assert.equal(imageSettings.customThemeIndex, 4);
  imageSettings.applyCustomThemeAccess(false);
  assert.equal(imageSettings.customThemeIndex, 0, 'expired membership falls back to the free theme');
  assert.equal(imageSettings.backgroundImage, '/reader_bg/0.jpg');
  assert.equal(imageSettings.customThemes[4].backgroundImage, '/reader_bg/4.jpg', 'extra themes survive expiry');
  await service.save({}, imageSettings);
  const renewed = await service.get({});
  renewed.applyCustomTheme(4);
  renewed.applyCustomThemeAccess(true);
  assert.equal(renewed.backgroundImage, '/reader_bg/4.jpg', 'renewal can use the retained theme again');
  const draft = ReaderCustomTheme.copy(renewed.customThemes[4]);
  draft.name = '未保存';
  draft.backgroundImage = '/reader_bg/new.jpg';
  assert.equal(renewed.customThemes[4].name, '主题 5', 'editing a draft never mutates the saved theme');
  assert.equal(ReaderCustomTheme.normalizeName('  夜读  '), '夜读');
  assert.equal(ReaderCustomTheme.normalizeName('x'.repeat(30)).length, 20);
  assert.equal(ReaderCustomTheme.normalizeName('   '), '');
  renewed.customThemes[4].name = '改名后';
  renewed.customThemes[4].backgroundImage = '';
  renewed.applyCustomTheme(4);
  await service.save({}, renewed);
  const removed = await service.get({});
  assert.equal(removed.pattern, 'none', 'removing an image returns the theme to its solid background');
  assert.equal(removed.customThemes[4].name, '改名后');
  assert.equal(removed.customThemes[0].backgroundImage, '/reader_bg/0.jpg', 'removal does not affect another theme');

  values.clear();
  values.set('theme_id', 'custom');
  values.set('custom_background', '#112233');
  values.set('background_pattern', 'none');
  values.set('background_image', '/old-unused.jpg');
  const inactiveImage = await service.get({});
  assert.equal(inactiveImage.pattern, 'none', 'an inactive legacy image does not replace the current solid theme');
  assert.ok(inactiveImage.customThemes.some(theme => theme.backgroundImage === '/old-unused.jpg'));
  await service.save({}, inactiveImage);
  assert.equal((await service.get({})).pattern, 'none', 'image migration runs only once');
  values.clear();
  values.set('theme_id', 'custom');
  values.set('background_pattern', 'image');
  values.set('background_image', '/old-active.jpg');
  values.set('custom_background', '#102030');
  const earliestImage = await service.get({});
  assert.equal(earliestImage.customThemeIndex, 0);
  assert.equal(earliestImage.backgroundImage, '/old-active.jpg', 'pre-image-theme custom backgrounds remain selected');
  assert.equal(earliestImage.pattern, 'image');
  assert.equal(earliestImage.customBackground, '#102030');
  await service.save({}, new TextReadingSettings());
  assert.equal((await service.get({})).backgroundImageMode, 'cover', 'reset restores the default image display mode');

  // Execute the editor's real draft/lifecycle methods without mounting ArkUI.
  const editorSource = fs.readFileSync(path.join(root, 'components/ReaderThemeEditor.ets'), 'utf8');
  const editorLogic = editorSource.substring(editorSource.indexOf('export struct ReaderThemeEditor'),
    editorSource.indexOf('  @Builder')).replace('export struct', 'export class').replace(/@(Param|Event|Local)\s+/g, '') + '\n}';
  const editorExports = {};
  vm.runInNewContext(ts.transpileModule(editorLogic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports: editorExports, TextReadingSettings, ...load('model/ReaderTheme') });
  const Editor = editorExports.ReaderThemeEditor;
  const discarded = [];
  const editor = new Editor();
  editor.theme = ReaderCustomTheme.copy(renewed.customThemes[0]);
  editor.onDiscardImage = path => discarded.push(path);
  editor.aboutToAppear();
  editor.onPickImage = async () => '/draft-one.jpg';
  await editor.pickImage();
  editor.onPickImage = async () => '/draft-two.jpg';
  await editor.pickImage();
  editor.aboutToDisappear();
  assert.deepEqual(discarded, ['/draft-one.jpg', '/draft-two.jpg'], 'cancel discards only newly imported draft images');
  assert.equal(editor.theme.backgroundImage, '/reader_bg/0.jpg');
  const latePicker = new Editor();
  latePicker.onDiscardImage = path => discarded.push(path);
  latePicker.aboutToAppear();
  let finishPick;
  latePicker.onPickImage = () => new Promise(resolve => { finishPick = resolve; });
  const pendingPick = latePicker.pickImage();
  latePicker.aboutToDisappear();
  finishPick('/late-image.jpg');
  await pendingPick;
  assert.equal(discarded.at(-1), '/late-image.jpg', 'picker completion after closing does not retain orphan images');
  const savingEditor = new Editor();
  savingEditor.onDiscardImage = path => discarded.push(path);
  savingEditor.aboutToAppear();
  savingEditor.onPickImage = async () => '/saved-image.jpg';
  await savingEditor.pickImage();
  savingEditor.draftName = '  新名称  ';
  savingEditor.onSave = async () => false;
  await savingEditor.save();
  assert.equal(savingEditor.draftImage, '/saved-image.jpg', 'save failure retains the draft for retry');
  assert.equal(discarded.includes('/saved-image.jpg'), false);
  let finishSave;
  let submitted;
  savingEditor.onSave = theme => { submitted = theme; return new Promise(resolve => { finishSave = resolve; }); };
  const pendingSave = savingEditor.save();
  savingEditor.aboutToDisappear();
  assert.equal(discarded.includes('/saved-image.jpg'), false, 'closing during save must not delete the pending image');
  finishSave(true);
  await pendingSave;
  assert.equal(submitted.name, '新名称');
  assert.equal(submitted.backgroundImage, '/saved-image.jpg');
  assert.equal(discarded.includes('/saved-image.jpg'), false, 'success preserves the persisted image after closing');
  // Exercise the real dialogue page handlers while disk writes are deliberately held open.
  const dialogueSource = fs.readFileSync(path.join(root, 'pages/DialogueHighlightSettingsPage.ets'), 'utf8');
  const dialogueLogic = dialogueSource.substring(dialogueSource.indexOf('export struct DialogueHighlightSettingsPage'),
    dialogueSource.indexOf('  @Builder')).replace('export struct', 'export class')
    .replace(/@(Param|Local|Computed|Monitor)(\([^\n]*\))?\s*/g, '') + '\n}';
  const dialogueExports = {};
  const writes = [];
  const notices = [];
  const delayedSettings = {
    get: context => service.get(context),
    save: async (context, settings) => {
      await new Promise((resolve, reject) => { writes.push({ settings, resolve, reject }); });
      await service.save(context, settings);
    }
  };
  vm.runInNewContext(ts.transpileModule(dialogueLogic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, {
    exports: dialogueExports, TextReadingSettings, ReaderDialogueRules,
    ...load('model/ReaderTheme'), TextReadingSettingsService: delayedSettings,
    NavPathStack: class {}, WindowUtils: { getStatusBarHeightVp: () => 0, removeReaderColorListener() {} },
    $r: name => name
  });
  await service.save({}, new TextReadingSettings());
  const dialogue = new dialogueExports.DialogueHighlightSettingsPage();
  dialogue.getUIContext = () => ({ getHostContext: () => ({}),
    getPromptAction: () => ({ showToast: notice => notices.push(notice) }) });
  dialogue.readingSettings = await service.get({});
  dialogue.ready = true;
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const firstToggle = dialogue.saveDialogue(true, '');
  assert.equal(dialogue.dialogueHighlight, true, 'the first tap updates the switch and preview before disk flush');
  await tick();
  assert.equal(writes.length, 1);
  const latestToggle = dialogue.saveDialogue(false, '');
  assert.equal(dialogue.dialogueHighlight, false, 'a second tap is accepted while the previous write is pending');
  for (let tap = 0; tap < 20; tap++) dialogue.saveDialogue(tap % 2 === 0, '');
  assert.equal(dialogue.dialogueHighlight, false);
  assert.equal(writes.length, 1, 'writes must remain serialized');
  writes[0].resolve();
  await tick();
  assert.equal(dialogue.dialogueHighlight, false, 'an older completion cannot overwrite the newest selection');
  assert.equal(writes.length, 2, 'pending rapid toggles are coalesced');
  assert.equal(writes[1].settings.dialogueHighlight, false);
  dialogue.aboutToDisappear();
  writes[1].resolve();
  await Promise.all([firstToggle, latestToggle]);
  assert.equal((await service.get({})).dialogueHighlight, false, 'the final choice persists after leaving the page');
  await dialogue.saveDialogue(false, '');
  assert.equal(writes.length, 2, 'a duplicate control notification does not start another save');
  const failedToggle = dialogue.saveDialogue(true, '');
  await tick();
  writes[2].reject(new Error('disk failure'));
  await failedToggle;
  assert.equal(dialogue.dialogueHighlight, false, 'a failed latest save rolls the UI back to confirmed settings');
  assert.equal(dialogue.saving, false);
  assert.equal(notices.length, 1);
  const retryToggle = dialogue.saveDialogue(true, '');
  await tick();
  writes[3].resolve();
  await retryToggle;
  assert.equal((await service.get({})).dialogueHighlight, true, 'the switch remains usable after failure');
  const colorSave = dialogue.saveDialogue(true, '#3478AB', false, '【】');
  await tick();
  const duringColorSave = dialogue.saveDialogue(false, dialogue.dialogueColor);
  writes[4].resolve();
  await tick();
  assert.equal(dialogue.dialogueHighlight, false);
  writes[5].resolve();
  await Promise.all([colorSave, duringColorSave]);
  const finalDialogue = await service.get({});
  assert.equal(finalDialogue.dialogueHighlight, false);
  assert.equal(finalDialogue.dialogueHighlightColor, '#3478AB', 'toggling during a color save retains the chosen color');
  assert.equal(finalDialogue.dialogueQuotePairs, '【】');
  console.log('PASS: dialogue switch immediate response, rapid toggles, serialized saves, rollback/retry and leave/reopen persistence');
  console.log('PASS: real editor draft cancellation, delayed picker cleanup, failed save retry and closing during save');
  console.log('PASS: independent theme names/images/colors/modes/overlays, rename, image removal, legacy migration and backup isolation');
  console.log('PASS: free 1/member 5 limits, invalid slots, expiry fallback, retained themes on renewal and draft isolation');
  console.log('PASS: theme isolation, switching/reload, system override, legacy color/image migration, contrast');
  console.log('PASS: settings migration/reset, four alignments, persistence, backup round trip, legacy backup, typography and margins');
})().catch(error => { console.error(error); process.exitCode = 1; });
