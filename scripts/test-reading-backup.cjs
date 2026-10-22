// Real backup/reading services with temporary files and isolated Preferences stores.
const { assert, fs, path, fixtures, snapshot, harness } = require('./backup-test-harness.cjs');

(async () => {
  const preferencesHarness = harness();
  const realPreferences = preferencesHarness.load('service/PreferenceService').PreferenceService;
  await realPreferences.init(preferencesHarness.context);
  const values = preferencesHarness.stored('listenbook_prefs');
  values.set('play_history', JSON.stringify([null, { progressMs: 1 }, { bookId: 123 }]));
  values.set('last_played', JSON.stringify({ bookId: 123 }));
  await realPreferences.saveTocOrder('online-novel', true);
  await realPreferences.saveTocOrder('import_local', true);
  values.set('favorite_book_ids', JSON.stringify(['online-novel', 'import_local']));
  await realPreferences.setFavoritesPinned(['online-novel', 'import_local'], true);
  const portable = await realPreferences.exportBackupSnapshot();
  assert.deepEqual(Array.from(portable.pinnedFavorites), ['online-novel']);
  await realPreferences.setFavoritesPinned(['online-novel'], false);
  assert.equal(portable.history.length, 0, 'bad identity fields are skipped before filtering imported books');
  assert.equal(portable.lastPlayed, null);
  assert.deepEqual(Array.from(portable.descendingBookIds), ['online-novel']);
  values.set('play_history', '[]');
  await realPreferences.saveTocOrder('stale-online', true);
  await realPreferences.restoreBackupSnapshot(portable);
  assert.equal(await realPreferences.getTocOrder('online-novel'), true);
  assert.equal(await realPreferences.getTocOrder('stale-online'), false);
  assert.deepEqual(Array.from(await realPreferences.getPinnedFavorites()), ['import_local', 'online-novel']);
  assert.equal(await realPreferences.getTocOrder('import_local'), true);
  delete portable.descendingBookIds;
  delete portable.pinnedFavorites;
  await realPreferences.restoreBackupSnapshot(portable);
  assert.equal(await realPreferences.getTocOrder('online-novel'), true, 'old backups leave directory order intact');
  assert.deepEqual(Array.from(await realPreferences.getPinnedFavorites()), ['import_local', 'online-novel'],
    'legacy backups preserve pins for remaining favorites');
  preferencesHarness.settled();
  for (const mode of ['local', 'cloud']) {
    const h = harness();
    const { TextReadingPosition, TextReadingSettings } = h.load('model/TextReading');
    const { TextReadingProgressService: progress } = h.load('service/text/TextReadingProgressService');
    const { TextReadingSettingsService: settings } = h.load('service/text/TextReadingSettingsService');
    const { ReaderToolsService: tools } = h.load('service/text/ReaderToolsService');
    const { ReaderBookmark, ReaderReplaceRule } = h.load('model/ReaderTools');
    const bookmark = new ReaderBookmark();
    Object.assign(bookmark, { id: 'bookmark', bookId: 'online-novel', chapterId: 'chapter', chapterUrl: '/chapter/419',
      chapterTitle: 'Chapter 420', charOffset: 1234, createdAt: 1700000000000 });
    const localBookmark = new ReaderBookmark();
    Object.assign(localBookmark, bookmark, { id: 'local-mark', bookId: 'import_local' });
    await tools.addBookmark(h.context, bookmark);
    await tools.addBookmark(h.context, localBookmark);
    const replaceRule = new ReaderReplaceRule();
    Object.assign(replaceRule, { id: 'rule', pattern: '广告', bookId: 'online-novel' });
    await tools.saveRule(h.context, replaceRule);
    const position = TextReadingPosition.atChar('online-novel', 419, 'paragraph-7', 1234, 6, 'Chapter 420');
    await progress.save(h.context, position);
    await progress.save(h.context, TextReadingPosition.atChar('import_local', 2, '', 99, 0, 'Local'));
    h.stored('online_text_reading_progress').set('position_broken', '{bad json');
    h.stored('online_text_reading_progress').set('position_negative', JSON.stringify({ ...position, charOffset: -1 }));
    const options = new TextReadingSettings();
    Object.assign(options, { fontSize: 24, lineHeight: 2, pageTurnMode: 'vertical', marginTop: 45, cornerLayout: '3210',
      alwaysShowStatusBar: false, screenOnMinutes: 5, themeId: 'image', pattern: 'image',
      backgroundImage: '/PRIVATE_background.jpg', fontPath: '/PRIVATE_font.ttf', fontName: 'PRIVATE_FONT' });
    await settings.save(h.context, options);
    const speech = h.stored('text_to_speech');
    const speechPosition = { sourceUrl: 'https://source.example', bookUrl: '/novel', chapterUrl: '/chapter/419',
      chapterIndex: 419, charOffset: 1333 };
    speech.set('position_online-novel', JSON.stringify(speechPosition));
    speech.set('position_import_local', JSON.stringify(speechPosition));
    speech.set('position_bad', 'null');
    speech.set('speed', 1.5);
    speech.set('follow', false);
    const history = { bookId: 'online-book', chapterId: 'c1', progressMs: 456, updatedAt: 1700000000000 };
    const playback = { ...history, chapterTitle: 'Chapter 1', chapterIndex: 2, positionMs: 456, durationMs: -1 };
    h.control.backupPreferences.history = [history, { ...history, updatedAt: undefined, unrecognizedKey: 123 }, null,
      { ...history, progressMs: -1 }, { ...history, bookId: 123 }];
    h.control.backupPreferences.progresses = [playback, { ...playback, chapterIndex: undefined }, null,
      { ...playback, positionMs: 'bad' }, { ...playback, durationMs: -2 }];
    h.control.backupPreferences.lastPlayed = { ...history, progressMs: 'bad' };
    const stats = { bookId: 'online-book', title: 'Book', author: '', cover: '', listenSeconds: 456,
      updatedAt: 1700000000000, days: [] };
    h.control.backupStats = [stats, null, { ...stats, listenSeconds: -1 }, { ...stats, days: [null] }];
    const original = JSON.stringify(h.control.backupPreferences);
    const localReading = Array.from(h.stored('online_text_reading_progress'));
    h.control.saveUris = [h.documentUri];
    if (mode === 'local') await h.local.backup(h.context);
    else await h.service.backup(h.context);
    const savedPath = mode === 'local' ? h.documentPath : h.cloudPath();
    const exported = JSON.parse(fs.readFileSync(savedPath, 'utf8'));
    assert.equal(exported.preferences.history.length, 1);
    assert.equal(exported.preferences.progresses.length, 1);
    assert.equal(exported.preferences.lastPlayed, null);
    assert.equal(exported.stats.length, 1);
    assert.equal(exported.reading.positions.length, 1);
    assert.equal(exported.reading.positions[0].charOffset, 1234);
    assert.equal(exported.reading.tools.bookmarks.length, 1);
    assert.equal(exported.reading.tools.rules[0].pattern, '广告');
    await tools.removeBookmark(h.context, 'bookmark');
    await tools.deleteRule(h.context, 'rule');
    assert.equal(exported.reading.settings.fontSize, 24);
    assert.equal(exported.reading.settings.cornerLayout, '3210');
    assert.equal(exported.reading.speechPositions.length, 1);
    assert.equal(exported.reading.speechSpeed, 1.5);
    assert.equal(fs.readFileSync(savedPath, 'utf8').includes('PRIVATE_'), false);
    assert.equal(JSON.stringify(h.control.backupPreferences), original, 'export never edits local listening records');
    assert.deepEqual(Array.from(h.stored('online_text_reading_progress')), localReading);

    await progress.save(h.context, TextReadingPosition.atChar('stale-online', 3, '', 0, 0, 'Stale'));
    const target = new TextReadingSettings();
    target.themeId = 'image'; target.pattern = 'image'; target.backgroundImage = '/target-background.jpg';
    target.fontPath = '/target-font.ttf';
    await settings.save(h.context, target);
    speech.set('position_stale-online', JSON.stringify(speechPosition));
    h.control.selectUris = [h.documentUri];
    if (mode === 'local') assert.equal(await h.local.restore(h.context, async () => true), true);
    else assert.equal(await h.service.restore(h.context, async () => true), true);
    assert.equal((await progress.get(h.context, 'online-novel')).charOffset, 1234);
    assert.equal((await progress.get(h.context, 'online-novel')).resourceIndex, 419);
    assert.equal((await progress.get(h.context, 'online-novel')).pageOffset, 6);
    assert.equal(await progress.get(h.context, 'stale-online'), null);
    assert.equal((await progress.get(h.context, 'import_local')).charOffset, 99);
    assert.equal((await tools.bookmarks(h.context, 'online-novel'))[0].charOffset, 1234);
    assert.equal((await tools.bookmarks(h.context, 'import_local')).length, 1);
    assert.equal((await tools.rules(h.context))[0].id, 'rule');
    const restored = await settings.get(h.context);
    assert.equal(restored.cornerLayout, '3210', 'local/cloud backups preserve all four corner positions');
    assert.equal(restored.fontSize, 24);
    assert.equal(restored.pageTurnMode, 'vertical');
    assert.equal(restored.alwaysShowStatusBar, false);
    assert.equal(restored.backgroundImage, '/target-background.jpg');
    assert.equal(restored.fontPath, '/target-font.ttf');
    assert.equal(speech.has('position_stale-online'), false);
    assert.equal(speech.has('position_import_local'), true);
    assert.equal(JSON.parse(speech.get('position_online-novel')).charOffset, 1333);
    assert.equal(h.control.speechReloads, 1);
    h.settled();

    // Old snapshots must not reset reading data or settings.
    fs.writeFileSync(savedPath, JSON.stringify(snapshot()));
    if (mode === 'local') await h.local.restore(h.context, async () => true);
    else await h.service.restore(h.context, async () => true);
    assert.equal((await progress.get(h.context, 'online-novel')).charOffset, 1234);
    assert.equal((await settings.get(h.context)).fontSize, 24);
    assert.equal(h.control.speechReloads, 1);

    // Export is tolerant, but importing a damaged snapshot still fails before any writes.
    exported.reading.positions[0].charOffset = -1;
    fs.writeFileSync(savedPath, JSON.stringify(exported));
    const restores = h.control.localRestores;
    await assert.rejects(mode === 'local' ? h.local.restore(h.context, async () => true) :
      h.service.restore(h.context, async () => true), error => error.code ===
        (mode === 'local' ? h.localCodes.INVALID_BACKUP : h.codes.INVALID_BACKUP));
    assert.equal(h.control.localRestores, restores);
    h.settled();
  }
  console.log('PASS: local/cloud skip invalid records, reading and speech round trip, custom assets excluded, local books preserved, legacy restore, strict import');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
