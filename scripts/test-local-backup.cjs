// DEVECO_HOME=<Release IDE> node scripts/test-local-backup.cjs
const { assert, fs, path, fixtures, snapshot, harness } = require('./backup-test-harness.cjs');

function sourceFixture(h) {
  const { LocalRuleSource, LocalRuleSourceType } = h.load('model/LocalRuleSource');
  const source = new LocalRuleSource();
  Object.assign(source, {
    bookSourceUrl: 'https://source.example.com', bookSourceName: '测试音频书源',
    bookSourceType: LocalRuleSourceType.AUDIO, bookSourceGroup: '收藏分组', bookSourceComment: '保留备注',
    enabled: false, enabledExplore: true, enabledCookieJar: false, isLocked: true, isPinned: true, customOrder: -7,
    searchUrl: '/search?key={{key}}', exploreUrl: '/discover',
    header: JSON.stringify({ 'User-Agent': 'reader', Accept: 'text/html', Cookie: 'PRIVATE_COOKIE', Authorization: 'PRIVATE_TOKEN' }),
    loginUrl: '/login', loginUi: '登录页定义', loginCheckJs: 'return true;', variable: '变量定义',
    jsLib: '// bounded source helpers\n' + ' '.repeat(300000),
    rawSourceJson: '{"Authorization":"PRIVATE_RAW"}', respondTime: 19000, concurrentRate: '3', lastUpdateTime: 1700000000000
  });
  for (const name of ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent']) {
    for (const key of Object.keys(source[name])) source[name][key] = name + '.' + key;
  }
  return source;
}

function selectBackup(h, data = snapshot()) {
  fs.writeFileSync(h.documentPath, JSON.stringify(data));
  h.control.selectUris = [h.documentUri];
}

function untouched(h) {
  assert.equal(h.control.localRestores, 0);
  assert.equal(h.control.restoredSources.length, 0);
  assert.equal(fs.existsSync(path.join(h.context.filesDir, 'backup/before_local_restore.json')), false);
}

(async () => {
  const exported = harness();
  exported.auth.isLoggedIn = false;
  exported.auth.openID = '';
  const original = sourceFixture(exported);
  exported.control.sources = [original];
  // Older device records can retain the player's unknown-duration sentinel.
  exported.control.backupPreferences.lastPlayed = {
    bookId: 'online-book', chapterId: 'chapter-1', progressMs: 100, durationMs: -1
  };
  exported.control.backupPreferences.history = [{
    bookId: 'online-book', chapterId: 'chapter-1', progressMs: 100, durationMs: -1, updatedAt: 1700000000000
  }];
  exported.control.backupPreferences.progresses = [{
    bookId: 'online-book', chapterId: 'chapter-1', chapterTitle: 'Chapter 1', chapterIndex: 0,
    positionMs: 100, durationMs: -1, updatedAt: 1700000000000
  }];
  exported.control.saveUris = [exported.documentUri];
  exported.control.maxRead = 73001;
  exported.control.maxWrite = 20003;
  const result = await exported.local.backup(exported.context);
  const saved = JSON.parse(fs.readFileSync(exported.documentPath, 'utf8'));
  assert.equal(result.ruleSources.length, 1);
  assert.equal(saved.preferences.favorites[0], 'online-book');
  assert.equal(saved.preferences.progresses[0].durationMs, -1);
  assert.equal(saved.ruleSources[0].ruleExplore.nextPageUrl, original.ruleExplore.nextPageUrl);
  assert.equal(saved.ruleSources[0].jsLib, original.jsLib, 'multiple short reads/writes preserve all bytes');
  assert.equal(fs.readFileSync(exported.documentPath, 'utf8').includes('PRIVATE_'), false);
  assert.equal(exported.control.restoreCount, 0, 'local export does not query the Huawei account');
  assert.equal(exported.syncTasks.length, 0);
  assert.equal(fs.readdirSync(exported.context.cacheDir).length, 0);
  exported.settled();

  // Imported comic definitions can carry a JSON object instead of a header string.
  const comicBackup = harness();
  const comicSource = sourceFixture(comicBackup);
  comicSource.bookSourceType = comicBackup.load('model/LocalRuleSource').LocalRuleSourceType.COMIC;
  comicSource.header = { 'User-Agent': 'comic-reader', Referer: 'https://comic.example/',
    Cookie: 'PRIVATE_COOKIE', Authorization: 'PRIVATE_TOKEN', Accept: 123 };
  const originalHeader = JSON.stringify(comicSource.header);
  comicBackup.control.sources = [comicSource];
  await comicBackup.service.backup(comicBackup.context);
  const comicSaved = JSON.parse(fs.readFileSync(comicBackup.cloudPath(), 'utf8'));
  assert.equal(comicSaved.ruleSources[0].bookSourceType, comicSource.bookSourceType);
  assert.deepEqual(JSON.parse(comicSaved.ruleSources[0].header), {
    'User-Agent': 'comic-reader', Referer: 'https://comic.example/'
  });
  assert.equal(JSON.stringify(comicSaved).includes('PRIVATE_'), false);
  assert.equal(JSON.stringify(comicSource.header), originalHeader, 'backup must not mutate imported headers');
  selectBackup(comicBackup, comicSaved);
  assert.equal(await comicBackup.local.restore(comicBackup.context, async () => true), true);
  assert.equal(comicBackup.control.restoredSources[0].header, comicSaved.ruleSources[0].header);
  comicBackup.settled();

  // Released builds wrote several generations of obfuscated numeric keys.
  for (const [timeKey, indexKey, positionKey] of [
    ['h15', 'chapterIndex', 'm56'], ['q11', 'chapterIndex', 'l50'],
    ['q11', 'chapterIndex', 'n49'], ['c10', 'h26', 'x47'], ['c10', 'h26', 'u47']
  ]) {
    const oldDevice = harness();
    oldDevice.control.backupPreferences.history = [{
      bookId: 'online-book', chapterId: 'chapter-1', progressMs: 1234, [timeKey]: 1700000000000
    }];
    oldDevice.control.backupPreferences.progresses = [{
      bookId: 'online-book', chapterId: 'chapter-1', chapterTitle: 'Chapter 1',
      [timeKey]: 1700000000000, [indexKey]: 4, [positionKey]: 1234, durationMs: -1
    }];
    const originalData = JSON.stringify(oldDevice.control.backupPreferences);
    oldDevice.control.saveUris = [oldDevice.documentUri];
    const migrated = await oldDevice.local.backup(oldDevice.context);
    assert.equal(migrated.preferences.history[0].updatedAt, 1700000000000);
    assert.equal(migrated.preferences.progresses[0].updatedAt, 1700000000000);
    assert.equal(migrated.preferences.progresses[0].chapterIndex, 4);
    assert.equal(migrated.preferences.progresses[0].positionMs, 1234);
    assert.equal(JSON.stringify(oldDevice.control.backupPreferences), originalData, 'export must not mutate local records');
    oldDevice.control.selectUris = [oldDevice.documentUri];
    assert.equal(await oldDevice.local.restore(oldDevice.context, async () => true), true);
    assert.equal(oldDevice.control.selectedData.progresses[0].positionMs, 1234);
    oldDevice.settled();
  }

  const restored = harness();
  restored.auth.isLoggedIn = false;
  restored.control.maxRead = 73001;
  restored.control.maxWrite = 20003;
  selectBackup(restored, saved);
  assert.equal(await restored.local.restore(restored.context, async info => {
    assert.equal(info.exportedAt, result.exportedAt);
    assert.equal(info.ruleSources.length, 1);
    assert.equal(info.preferences.favorites.length, 1);
    untouched(restored);
    await assert.rejects(restored.service.backup(restored.context), /busy or unavailable/);
    await assert.rejects(restored.local.backup(restored.context), /busy or unavailable/);
    assert.equal(restored.auth.dataOperation, true, 'rejected concurrent work must not release the active lock');
    return true;
  }), true);
  const source = restored.control.restoredSources[0];
  for (const key of ['bookSourceUrl', 'bookSourceName', 'bookSourceType', 'bookSourceGroup', 'bookSourceComment',
    'enabled', 'enabledExplore', 'enabledCookieJar', 'isLocked', 'isPinned', 'customOrder',
    'searchUrl', 'exploreUrl', 'loginUrl', 'loginUi', 'loginCheckJs', 'variable', 'jsLib',
    'respondTime', 'concurrentRate', 'lastUpdateTime']) assert.equal(source[key], original[key], key);
  for (const key of ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent']) {
    assert.equal(JSON.stringify(source[key]), JSON.stringify(original[key]), key);
  }
  assert.equal(source.rawSourceJson, '');
  assert.equal(source.validationStatus, 0);
  assert.deepEqual(JSON.parse(source.header), { 'User-Agent': 'reader', Accept: 'text/html' });
  assert.equal(restored.control.localRestores, 3);
  assert.deepEqual(Array.from(restored.control.selectedData.favorites), ['online-book']);
  assert.ok(fs.existsSync(path.join(restored.context.filesDir, 'backup/before_local_restore.json')));
  assert.equal(fs.readdirSync(restored.context.cacheDir).length, 0);
  restored.settled();

  const legacy = harness();
  const old = JSON.parse(JSON.stringify(saved));
  for (const key of ['ruleExplore', 'isLocked', 'isPinned', 'customOrder']) delete old.ruleSources[0][key];
  delete old.ruleSources[0].ruleSearch.nextPageUrl;
  selectBackup(legacy, old);
  assert.equal(await legacy.local.restore(legacy.context, async () => true), true);
  assert.equal(legacy.control.restoredSources[0].ruleExplore.bookList, '');
  assert.equal(legacy.control.restoredSources[0].ruleSearch.nextPageUrl, '');
  assert.equal(legacy.control.restoredSources[0].isLocked, false);
  legacy.settled();

  for (const action of ['backup', 'restore']) {
    const cancelled = harness();
    assert.equal(await cancelled.local[action](cancelled.context, async () => true), action === 'backup' ? null : false);
    assert.equal(fs.existsSync(cancelled.documentPath), false);
    untouched(cancelled);
    cancelled.settled();
  }
  const declined = harness();
  selectBackup(declined);
  assert.equal(await declined.local.restore(declined.context, async () => false), false);
  untouched(declined);
  declined.settled();

  const leave = harness();
  selectBackup(leave);
  await assert.rejects(leave.local.restore(leave.context, async () => {
    leave.local.cancel(); return true;
  }), error => error.code === leave.localCodes.CANCELLED);
  untouched(leave);
  leave.settled();

  for (const invalidData of [null, [], [{ bookSourceUrl: 'https://source.example.com', bookSourceName: '普通书源数组' }],
    { ...snapshot(), version: 99 }, { ...snapshot(), preferences: { ...snapshot().preferences, favorites: [123] } },
    { ...saved, ruleSources: [{ ...saved.ruleSources[0], ruleExplore: { bookList: 5 } }] },
    { ...saved, ruleSources: [{ ...saved.ruleSources[0], isLocked: 'yes' }] },
    ...[-2, null, 'unknown'].map(durationMs => ({ ...saved, preferences: {
      ...saved.preferences, progresses: [{ ...saved.preferences.progresses[0], durationMs }]
    } })),
    { ...saved, ruleSources: [{ ...saved.ruleSources[0], ruleSearch: { ...saved.ruleSources[0].ruleSearch, nextPageUrl: 12 } }] }]) {
    const invalid = harness();
    selectBackup(invalid, invalidData);
    await assert.rejects(invalid.local.restore(invalid.context, async () => {
      invalid.control.confirmed++; return true;
    }), error => error.code === invalid.localCodes.INVALID_BACKUP);
    assert.equal(invalid.control.confirmed, 0);
    untouched(invalid);
    invalid.settled();
  }
  const oversized = harness();
  selectBackup(oversized);
  fs.truncateSync(oversized.documentPath, 32 * 1024 * 1024 + 1);
  await assert.rejects(oversized.local.restore(oversized.context, async () => true),
    error => error.code === oversized.localCodes.TOO_LARGE);
  untouched(oversized);
  oversized.settled();

  for (const mode of ['fileWriteError', 'pickerError', 'maxWrite']) {
    const failed = harness();
    failed.control.saveUris = [failed.documentUri];
    failed.control[mode] = mode === 'maxWrite' ? 0 : true;
    await assert.rejects(failed.local.backup(failed.context), error => error.code === failed.localCodes.FILE_ACCESS);
    failed.settled();
  }
  for (const mode of ['sourceError', 'snapshotShortWrite', 'flushError']) {
    const failed = harness();
    failed.control[mode] = true;
    await assert.rejects(failed.local.backup(failed.context), error => error.code === failed.localCodes.BACKUP_FAILED);
    assert.equal(failed.control.pickerCalls, 0, 'incomplete snapshot is never offered for export');
    assert.equal(fs.readdirSync(failed.context.cacheDir).length, 0);
    failed.settled();
  }
  const unsafe = harness();
  selectBackup(unsafe);
  unsafe.control.sourceError = true;
  await assert.rejects(unsafe.local.restore(unsafe.context, async () => true),
    error => error.code === unsafe.localCodes.BACKUP_FAILED);
  untouched(unsafe);
  unsafe.settled();
  const partial = harness();
  selectBackup(partial);
  partial.control.restoreError = true;
  await assert.rejects(partial.local.restore(partial.context, async () => true),
    error => error.code === partial.localCodes.RESTORE_FAILED);
  assert.ok(fs.existsSync(path.join(partial.context.filesDir, 'backup/before_local_restore.json')));
  partial.settled();
  console.log('PASS: local backup without login, complete source round trip, legacy snapshots, short I/O, cancellation, invalid/oversize files, failures, exclusive operations and cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
