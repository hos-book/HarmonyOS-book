// Exercise the real preferences methods with independent process caches and whole-file flushes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/PreferenceService.ets'), 'utf8').replace(/import lazy /g, 'import '), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const disk = new Map();
const context = {};
const legacyIds = 'widget_form_ids_v1';
const snapshotKey = 'widget_player_snapshot_v1';
const snapshot = { bookId: 'audio', bookTitle: 'fixture', author: '', cover: '', chapterId: 'one',
  chapterTitle: 'one', progressMs: 0, durationMs: 10000, playbackKind: 'audio', isPlaying: true, updatedAt: 1 };
disk.set('listenbook_prefs', { [legacyIds]: JSON.stringify([{ name: 'PlayerCard', ids: ['legacy'] }]),
  [snapshotKey]: JSON.stringify(snapshot) });

async function newProcess() {
  const cache = new Map();
  const preferences = {
    async removePreferencesFromCache(_context, { name }) { cache.delete(name); },
    async getPreferences(_context, { name }) {
      if (!cache.has(name)) {
        const memory = structuredClone(disk.get(name) || {});
        cache.set(name, {
          async get(key, fallback) { return memory[key] ?? fallback; },
          async put(key, value) { memory[key] = value; },
          async delete(key) { delete memory[key]; },
          async getAll() { return { ...memory }; },
          async flush() { disk.set(name, structuredClone(memory)); }
        });
      }
      return cache.get(name);
    }
  };
  const exports = {};
  vm.runInNewContext(code, { exports, console, require: name => {
    if (name === '@kit.ArkData') return { preferences };
    if (name === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
    return {};
  } });
  const service = exports.PreferenceService;
  // General preference/theme startup is unrelated; retain an open application cache in each process.
  service.store = await preferences.getPreferences(context, { name: 'listenbook_prefs' });
  await service.init(context);
  return service;
}

(async () => {
  const main = await newProcess(), form = await newProcess();
  assert.deepEqual(Array.from(await main.getWidgetFormIds('PlayerCard')), ['legacy']);
  assert.equal((await form.getWidgetPlayerSnapshot()).bookId, 'audio');
  await form.addWidgetFormId('PlayerCard', 'new-card');
  // The main process still has a pre-registration general preferences cache.
  await main.store.put('unrelated_setting', true);
  await main.store.flush();
  assert.deepEqual(Array.from(await main.getWidgetFormIds('PlayerCard')), ['legacy', 'new-card']);
  await main.setWidgetPlayerSnapshot({ ...snapshot, isPlaying: false, updatedAt: 2 });
  await form.store.flush();
  assert.equal((await form.getWidgetPlayerSnapshot()).isPlaying, false,
    'form process flushing an older general cache cannot restore a stale playing snapshot');
  await Promise.all([
    form.addWidgetFormId('PlayerCard', 'second'), form.addWidgetFormId('PlayerCard', 'third'),
    main.setWidgetPlayerSnapshot({ ...snapshot, updatedAt: 3 }),
    main.setWidgetPlayerSnapshot({ ...snapshot, isPlaying: false, updatedAt: 4 })
  ]);
  assert.deepEqual(Array.from(await main.getWidgetFormIds('PlayerCard')), ['legacy', 'new-card', 'second', 'third']);
  assert.equal((await form.getWidgetPlayerSnapshot()).updatedAt, 4);
  for (const id of ['legacy', 'new-card', 'second', 'third']) await form.removeWidgetFormId('PlayerCard', id);
  assert.deepEqual(Array.from(await main.getWidgetFormIds('PlayerCard')), [], 'deleted legacy IDs must not return');
  await main.clearBookshelfAndHistory();
  assert.equal(await form.getWidgetPlayerSnapshot(), null, 'clearing books also clears the dedicated widget snapshot');
  await main.setWidgetPlayerSnapshot(snapshot);
  await main.clearOnlineFavoritesAndHistory();
  assert.equal(await form.getWidgetPlayerSnapshot(), null);
  const restarted = await newProcess();
  assert.equal(await restarted.getWidgetPlayerSnapshot(), null);
  assert.deepEqual(Array.from(await restarted.getWidgetFormIds('PlayerCard')), []);
  console.log('PASS widget cross-process registration/snapshot isolation, legacy migration, queued writes, removal and clearing');
})().catch(error => { console.error(error); process.exitCode = 1; });
