const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const transpile = source => ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
const source = fs.readFileSync(path.join(root, 'pages/MainPage.ets'), 'utf8');
const methods = source.slice(source.indexOf('  private clearMiniPlayerIdleTimer'),
  source.indexOf('  private cancelLayoutTimers')).replace(/  @Monitor\([\s\S]*?\)\r?\n/g, '');
function create(minutes = 1, speech = false) {
  let now = 100000;
  let serial = 0;
  const timers = new Map();
  const exports = {};
  vm.runInNewContext(transpile(`export class Page { ${methods} }`), {
    exports, Date: { now: () => now },
    setTimeout: (callback, delay) => { const id = ++serial; timers.set(id, { callback, at: now + delay }); return id; },
    clearTimeout: id => timers.delete(id)
  });
  const page = new exports.Page();
  Object.assign(page, { miniPlayerIdleAlive: true, miniPlayerIdleHidden: false,
    miniPlayerIdleTimer: -1, miniPlayerIdleSince: 0, miniPlayerIdleBook: '', miniPlayerWasBusy: false,
    generalSettings: { miniPlayerHideMinutes: minutes },
    playerState: { currentBook: { id: 'audio' }, isPlaying: !speech, isLoading: false, progressMs: 1234 },
    speechState: { active: speech, bookId: 'text', playing: speech, loading: false }, syncVerticalBars() {} });
  page.refreshMiniPlayerIdle(true);
  return { page, timers, advance(ms) {
    now += ms;
    for (const [id, timer] of [...timers]) {
      if (timer.at <= now) { timers.delete(id); timer.callback(); }
    }
  } };
}
(async () => {
  for (const speech of [false, true]) {
    for (const minutes of [1, 5, 10, 20]) {
      const h = create(minutes, speech), p = h.page;
      h.advance(60 * 60000);
      assert.equal(p.miniPlayerVisible(), true, 'playing never expires');
      if (speech) p.speechState.playing = false; else p.playerState.isPlaying = false;
      p.onMiniPlayerPlaybackChanged();
      h.advance(minutes * 60000 - 1);
      assert.equal(p.miniPlayerVisible(), true, 'pause gets a full interval');
      h.advance(1);
      assert.equal(p.miniPlayerVisible(), false, 'idle audio and TTS hide at selected deadline');
      assert.equal(p.playerState.progressMs, 1234, 'hiding preserves playback state');
      if (speech) p.speechState.loading = true; else p.playerState.isLoading = true;
      p.onMiniPlayerPlaybackChanged();
      assert.equal(p.miniPlayerVisible(), true, 'loading restores controls');
      assert.equal(h.timers.size, 0);
    }
  }
  const h = create(), p = h.page;
  p.playerState.isPlaying = false; p.onMiniPlayerPlaybackChanged();
  h.advance(59000); p.refreshMiniPlayerIdle(true); h.advance(1000);
  assert.equal(p.miniPlayerVisible(), true, 'touch resets idle interval');
  h.advance(59000); assert.equal(p.miniPlayerVisible(), false);
  p.generalSettings.miniPlayerHideMinutes = 0; p.onMiniPlayerHidePreferenceChanged();
  h.advance(24 * 60 * 60000);
  assert.equal(p.miniPlayerVisible(), true, 'permanent restores and never hides');
  p.generalSettings.miniPlayerHideMinutes = 1; p.onMiniPlayerHidePreferenceChanged();
  p.miniPlayerIdleAlive = false; p.clearMiniPlayerIdleTimer();
  h.advance(60000); assert.equal(p.miniPlayerVisible(), true, 'unmount cancels timeout');

  const values = new Map(); let failFlush = false;
  const settings = { miniPlayerHideMinutes: 0 };
  const store = { getSync: (k, fallback) => values.get(k) ?? fallback,
    put: async (k, v) => values.set(k, v), flush: async () => { if (failFlush) throw Error('disk full'); } };
  const exports = {};
  vm.runInNewContext(transpile(fs.readFileSync(path.join(root, 'service/PreferenceService.ets'), 'utf8')), {
    exports, require: name => name === '../model/GeneralSettings' ? { GeneralSettings: { current: settings } } : {}
  });
  const prefs = exports.PreferenceService; prefs.store = store;
  for (const minutes of [0, 1, 5, 10, 20]) {
    await prefs.setMiniPlayerHideMinutes(minutes);
    assert.equal(values.get('mini_player_hide_minutes'), minutes);
    assert.equal(settings.miniPlayerHideMinutes, minutes);
  }
  await assert.rejects(prefs.setMiniPlayerHideMinutes(2));
  failFlush = true;
  await assert.rejects(prefs.setMiniPlayerHideMinutes(1));
  assert.equal(settings.miniPlayerHideMinutes, 20, 'failed save preserves UI choice');
  assert.equal(values.get('mini_player_hide_minutes'), 20, 'failed save rolls back preference');
  for (const invalid of [-1, 2, Infinity, NaN]) assert.equal(prefs.normalizeMiniPlayerHideMinutes(invalid), 0);
  console.log('Mini player idle: audio/TTS, all durations, permanent, touch, loading, cleanup and save rollback passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
