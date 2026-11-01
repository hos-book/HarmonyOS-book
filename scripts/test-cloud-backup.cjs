// DEVECO_HOME=<Release IDE> node scripts/test-cloud-backup.cjs
const { assert, fs, path, fixtures, snapshot, harness, until } = require('./backup-test-harness.cjs');

async function retryStart(h) {
  await until(() => h.timers.size === 2);
  const [id, callback] = [...h.timers.entries()].at(-1);
  h.timers.delete(id);
  callback();
}

(async () => {
  const manual = harness();
  manual.control.auto = false;
  const backup = manual.service.backup(manual.context);
  await until(() => manual.syncTasks.length === 1);
  assert.equal(manual.service.lastBackupAt, 0);
  assert.equal(manual.control.cloudWrites, 0);
  manual.syncTasks[0].emit(4, 0);
  await until(() => manual.syncTasks.length === 2);
  assert.equal(manual.service.lastBackupAt, 0, 'start() and local writes alone must not imply success');
  assert.equal(manual.service.busy, true);
  manual.syncTasks[1].emit(4, 0);
  await backup;
  assert.ok(manual.service.lastBackupAt > 0);
  assert.equal(JSON.parse(fs.readFileSync(manual.cloudPath(), 'utf8')).preferences.favorites[0], 'online-book');
  manual.settled();

  // Cloud directories may reject optimized copy operations while ordinary reads/writes work.
  const streamed = harness();
  streamed.control.cloudCopyUnsupported = true;
  streamed.control.maxRead = 71;
  streamed.control.maxWrite = 23;
  await streamed.service.backup(streamed.context);
  streamed.control.backupPreferences.favorites = ['updated-book'];
  await streamed.service.backup(streamed.context);
  assert.deepEqual(JSON.parse(fs.readFileSync(streamed.cloudPath(), 'utf8')).preferences.favorites, ['updated-book']);
  assert.equal(await streamed.service.restore(streamed.context, async () => true), true);
  assert.deepEqual(Array.from(streamed.control.selectedData.favorites), ['updated-book']);
  streamed.control.fileStates.set(streamed.cloudPath(), 3);
  await streamed.service.restore(streamed.context, async () => true);
  assert.deepEqual(Array.from(streamed.control.selectedData.favorites), ['online-book'], 'restore skips an upload that is not confirmed');
  streamed.control.fileStates.clear();
  await streamed.service.backup(streamed.context);
  assert.equal(fs.readdirSync(streamed.context.cloudFileDir).filter(name => name.endsWith('.json')).length, 2,
    'keep the new backup and one previous confirmed backup');
  streamed.settled();

  for (const systemCode of [13900025, 13900020, 13900028]) {
    const failedWrite = harness();
    failedWrite.seed();
    const previous = fs.readFileSync(failedWrite.cloudPath(), 'utf8');
    failedWrite.control.cloudWriteError = systemCode;
    await assert.rejects(failedWrite.service.backup(failedWrite.context), error =>
      error.code === (systemCode === 13900025 ? failedWrite.codes.LOCAL_FULL : failedWrite.codes.CLOUD_FILE_FAILURE) &&
      error.systemCode === systemCode);
    assert.equal(fs.readFileSync(failedWrite.cloudPath(), 'utf8'), previous, 'failed uploads preserve the previous backup');
    assert.equal(fs.existsSync(failedWrite.cloudPath() + '.pending'), false);
    assert.equal(fs.readdirSync(failedWrite.context.cloudFileDir).some(name => name.endsWith('.pending')), false);
    assert.equal(failedWrite.service.lastBackupAt, 0);
    failedWrite.settled();
  }

  const cancelledCopy = harness();
  cancelledCopy.seed();
  const beforeCancel = fs.readFileSync(cancelledCopy.cloudPath(), 'utf8');
  cancelledCopy.control.maxWrite = 23;
  cancelledCopy.control.onCloudWrite = () => cancelledCopy.service.cancel();
  await assert.rejects(cancelledCopy.service.backup(cancelledCopy.context), error => error.code === cancelledCopy.codes.CANCELLED);
  assert.equal(fs.readFileSync(cancelledCopy.cloudPath(), 'utf8'), beforeCancel);
  assert.equal(fs.existsSync(cancelledCopy.cloudPath() + '.pending'), false);
  cancelledCopy.settled();

  for (const stage of ['startError', 'cloudStateError']) {
    const serverError = harness();
    serverError.control[stage] = 22400005;
    await assert.rejects(serverError.service.backup(serverError.context), error =>
      error.code === serverError.codes.SERVER && error.systemCode === 22400005);
    assert.equal(serverError.service.lastBackupAt, 0);
    serverError.settled();
  }

  const unavailable = harness();
  // A system IPC outage must not be reported as a disabled account/cloud switch.
  for (const operation of ['backup', 'restore']) {
    const ipc = harness();
    ipc.seed();
    const previous = fs.readFileSync(ipc.cloudPath(), 'utf8');
    ipc.control.startError = 13600001;
    await assert.rejects(ipc.service[operation](ipc.context, async () => true), error =>
      error.code === ipc.codes.SYSTEM_SERVICE && error.systemCode === 13600001);
    assert.equal(ipc.control.cloudWrites, 0);
    assert.equal(ipc.control.localRestores, 0);
    assert.equal(ipc.service.lastBackupAt, 0);
    assert.equal(fs.readFileSync(ipc.cloudPath(), 'utf8'), previous);
    ipc.settled();
  }

  unavailable.control.initialCompleted = true;
  unavailable.control.startError = 22400001;
  const unavailableTask = unavailable.service.backup(unavailable.context);
  const unavailableRejected = assert.rejects(unavailableTask, e =>
    e.code === unavailable.codes.NOT_READY && e.systemCode === 22400001);
  await retryStart(unavailable);
  await retryStart(unavailable);
  await unavailableRejected;
  assert.equal(unavailable.syncTasks.length, 3, 'cloud-not-ready retries are bounded');
  assert.equal(unavailable.control.cloudWrites, 0);
  assert.equal(unavailable.service.lastBackupAt, 0);
  unavailable.settled();

  const warming = harness();
  warming.control.startErrors = [22400001, 22400001, 0];
  const warmingTask = warming.service.backup(warming.context);
  await retryStart(warming);
  assert.equal(warming.control.cloudWrites, 0);
  await retryStart(warming);
  await warmingTask;
  assert.ok(warming.service.lastBackupAt > 0, 'transient cloud initialization recovers within the same backup');
  warming.settled();

  for (const mode of ['cancel', 'switch']) {
    const waiting = harness();
    waiting.control.startError = 22400001;
    const task = waiting.service.backup(waiting.context);
    const rejected = assert.rejects(task, e => e.code ===
      (mode === 'cancel' ? waiting.codes.CANCELLED : waiting.codes.ACCOUNT_CHANGED));
    await until(() => waiting.timers.size === 2);
    if (mode === 'cancel') waiting.service.cancel();
    else {
      waiting.control.identity = 'account-B';
      await retryStart(waiting);
    }
    await rejected;
    assert.equal(waiting.syncTasks.length, 1, 'cancel/account change prevents another cloud start');
    assert.equal(waiting.control.cloudWrites, 0);
    waiting.settled();
  }

  // A removed source must not make its bookshelf, playback history or progress disappear in backup.
  const orphan = harness();
  orphan.control.backupBooks = [{ id: 'online-book', title: '保留的书', author: '作者', narrator: '',
    cover: '', category: '', intro: '', totalDuration: 0, chapterCount: 10, rating: 0,
    tags: [], chapters: [], bookUrl: 'https://removed.example/book/1', sourceUrl: 'https://removed.example' }];
  orphan.control.backupPreferences.history = [{ bookId: 'online-book', chapterId: 'c3',
    chapterTitle: '第三章', progressMs: 12000, durationMs: 60000, updatedAt: Date.now() }];
  orphan.control.backupPreferences.progresses = [{ bookId: 'online-book', chapterId: 'c3',
    chapterTitle: '第三章', chapterIndex: 2, positionMs: 12000, durationMs: 60000, updatedAt: Date.now() }];
  await orphan.service.backup(orphan.context);
  const orphanSnapshot = JSON.parse(fs.readFileSync(orphan.cloudPath(), 'utf8'));
  assert.equal(orphanSnapshot.ruleSources.length, 0);
  assert.equal(orphanSnapshot.books[0].sourceUrl, 'https://removed.example');
  assert.deepEqual(orphanSnapshot.preferences.favorites, ['online-book']);
  assert.equal(orphanSnapshot.preferences.history[0].progressMs, 12000);
  assert.equal(orphanSnapshot.preferences.progresses[0].chapterIndex, 2);
  assert.equal(await orphan.service.restore(orphan.context, async () => true), true);
  assert.equal(orphan.control.restoredBooks[0].sourceUrl, 'https://removed.example');
  assert.deepEqual(Array.from(orphan.control.selectedData.favorites), ['online-book']);
  assert.equal(orphan.control.selectedData.history[0].progressMs, 12000);
  orphan.settled();

  const full = harness();
  full.control.auto = false;
  const fullTask = full.service.backup(full.context);
  const fullReject = assert.rejects(fullTask, e => e.code === full.codes.CLOUD_FULL);
  await until(() => full.syncTasks.length === 1);
  full.syncTasks[0].emit(1, 5);
  await fullReject;
  assert.equal(full.control.stopCount, 1);
  full.settled();

  for (const mode of ['cancel', 'timeout', 'switch']) {
    const h = harness();
    h.control.auto = false;
    const task = h.service.backup(h.context);
    const code = mode === 'cancel' ? h.codes.CANCELLED : mode === 'timeout' ? h.codes.TIMEOUT : h.codes.ACCOUNT_CHANGED;
    const rejected = assert.rejects(task, e => e.code === code);
    await until(() => h.syncTasks.length === 1);
    if (mode === 'cancel') h.service.cancel();
    if (mode === 'timeout') [...h.timers.values()][0]();
    if (mode === 'switch') { h.control.identity = 'account-B'; [...h.intervals.values()][0](); }
    await rejected;
    assert.equal(h.control.cloudWrites, 0);
    assert.equal(h.control.stopCount, 1);
    h.settled();
  }

  const sourceFailure = harness();
  sourceFailure.control.sourceError = true;
  await assert.rejects(sourceFailure.service.backup(sourceFailure.context));
  assert.equal(sourceFailure.control.cloudWrites, 0, 'unreadable sources must not become an empty cloud backup');
  sourceFailure.settled();

  const unconfirmed = harness();
  unconfirmed.control.uploadState = 3;
  const unconfirmedTask = unconfirmed.service.backup(unconfirmed.context);
  const unconfirmedReject = assert.rejects(unconfirmedTask, e => e.code === unconfirmed.codes.TIMEOUT);
  await until(() => unconfirmed.syncTasks.length === 2);
  assert.equal(unconfirmed.service.busy, true, 'completed callback must wait for this file to finish uploading');
  [...unconfirmed.timers.values()][0]();
  await unconfirmedReject;
  assert.equal(unconfirmed.service.lastBackupAt, 0, 'completed app sync with an unuploaded file is not backup success');
  unconfirmed.settled();

  const delayed = harness();
  delayed.control.uploadState = 3;
  const delayedTask = delayed.service.backup(delayed.context);
  await until(() => delayed.syncTasks.length === 2);
  assert.equal(delayed.service.lastBackupAt, 0);
  delayed.control.uploadState = 1;
  for (const tick of [...delayed.intervals.values()]) tick();
  assert.equal(delayed.service.busy, true);
  delayed.control.uploadState = 4;
  for (const tick of [...delayed.intervals.values()]) tick();
  await delayedTask;
  assert.ok(delayed.service.lastBackupAt > 0);
  delayed.settled();

  const restore = harness();
  restore.seed();
  assert.equal(await restore.service.restore(restore.context, async info => {
    assert.equal(info.exportedAt, snapshot().exportedAt);
    assert.equal(info.bookCount, 1);
    assert.equal(restore.control.localRestores, 0, 'no local writes before concrete confirmation');
    return true;
  }), true);
  assert.equal(restore.control.localRestores, 3);
  assert.ok(fs.existsSync(path.join(restore.context.filesDir, 'backup/before_cloud_restore.json')));
  restore.settled();

  const declined = harness(); declined.seed();
  assert.equal(await declined.service.restore(declined.context, async () => false), false);
  assert.equal(declined.control.localRestores, 0);
  declined.settled();

  const changed = harness(); changed.seed();
  await assert.rejects(changed.service.restore(changed.context, async () => {
    changed.control.identity = 'account-B'; return true;
  }), e => e.code === changed.codes.ACCOUNT_CHANGED);
  assert.equal(changed.control.localRestores, 0);
  changed.settled();

  const foreign = harness(); foreign.seed(snapshot(), 'account-B');
  await assert.rejects(foreign.service.restore(foreign.context, async () => true), e => e.code === foreign.codes.NO_BACKUP);
  assert.equal(foreign.control.localRestores, 0);
  foreign.settled();

  for (const corrupt of [null, { ...snapshot(), version: 99 },
    { ...snapshot(), preferences: { ...snapshot().preferences, favorites: [123] } },
    { ...snapshot(), preferences: { ...snapshot().preferences, accentColor: {} } },
    { ...snapshot(), ruleSources: [{ bookSourceUrl: 123 }] },
    { ...snapshot(), stats: [{ bookId: 'book', days: null }] }]) {
    const invalid = harness(); invalid.seed(corrupt);
    await assert.rejects(invalid.service.restore(invalid.context, async () => {
      invalid.control.confirmed++; return true;
    }), e => e.code === invalid.codes.INVALID_BACKUP);
    assert.equal(invalid.control.localRestores, 0);
    assert.equal(invalid.control.confirmed, 0);
    invalid.settled();
  }

  const remote = harness(); remote.seed(); remote.control.remoteOnly = true;
  const download = remote.service.restore(remote.context, async () => true);
  await until(() => remote.downloadTasks.length === 1);
  assert.equal(remote.control.localRestores, 0);
  remote.downloadTasks[0].emit(1, 0, 'file://unrelated');
  assert.equal(remote.control.localRestores, 0);
  remote.downloadTasks[0].emit(1);
  assert.equal(await download, true);
  remote.settled();

  const partial = harness(); partial.seed(); partial.control.restoreError = true;
  await assert.rejects(partial.service.restore(partial.context, async () => true), e => e.code === partial.codes.RESTORE_FAILED);
  assert.ok(fs.existsSync(path.join(partial.context.filesDir, 'backup/before_cloud_restore.json')));
  partial.settled();
  console.log('PASS: cloud streaming round trip, overwrite, failed/cancelled upload preserves backup, system error codes, completion, account isolation, restore validation');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
