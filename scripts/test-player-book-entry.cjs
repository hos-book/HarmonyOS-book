// Execute the real player entry and control methods with two different books.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/PlayerPage.ets'), 'utf8');
function method(name) {
  const match = new RegExp(`^  private (?:async )?${name}\\(`, 'm').exec(source);
  assert.ok(match, `missing player method: ${name}`);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const methods = ['primeFromCache', 'loadBook', 'isSameBook', 'promptSourceRecovery', 'audioMatchesBook',
  'isSpeechBook', 'speechMatchesBook', 'playbackLoading', 'playbackPlaying', 'playbackChapter',
  'sliderMaxMs', 'displayDurationMs', 'progressValueMs', 'canSkipPlayback', 'skipPlayback', 'togglePlay',
  'playPrev', 'playNext', 'currentChapterIndex', 'loadSourceName'];
const compiled = ts.transpileModule(`export class Player { ${methods.map(method).join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
function book(id, sourceUrl = id) {
  return { id, title: id, bookUrl: `https://books/${id}`, sourceUrl, contentType: 'audio',
    chapters: [{ id: `${id}-c0`, title: '第一章', source: { type: 'url', value: 'https://audio/chapter.mp3' } }] };
}
function setup({ cached, stored = null, current = book('正在播放的书'), available = false, answer = 1 } = {}) {
  const events = [], dialogs = [], exports = {};
  const audio = { whenReady: async () => {}, setPlayMode: () => {}, bind: () => {},
    prewarmBookSource: () => {}, toggle: async () => events.push('toggle'),
    seekBy: () => events.push('seek'),
    playChapterFromSavedProgress: async b => events.push(`play:${b.id}`) };
  vm.runInNewContext(compiled, { exports, console: { error() {} },
    SearchCache: { get: () => cached }, TextToSpeechService: { getInstance: () => ({ currentBook: () => null }) },
    AudioService: { getInstance: () => audio }, DataService: { getBookById: async () => stored,
      resolveChapterIndex: (b, id) => b.chapters.findIndex(ch => ch.id === id) },
    SourceDataService: { getSourceByUrl: async () => available ? { bookSourceName: '可用源', enabled: false } : null },
    PreferenceService: { applySkipConfig: async () => {}, applyTocOrder: async () => {},
      orderedChapters: b => b.chapters, isFavorite: async () => true },
    BookSourceService: { pendingAudioBook: () => undefined }, LocalRuleSource: class {},
    Curve: {}, PlayMode: { Sequence: 0 }, AppColor: { Brand: '#123456' },
    $r: (id, ...args) => ({ id, args })
  });
  const page = new exports.Player();
  Object.assign(page, { bookId: '失效书籍', book: null, isLeaving: false, sourceRecoveryPrompted: false,
    showSourceSwitch: false, context: {}, resumeChapterId: '',
    playerState: { currentBook: current, currentChapter: current.chapters[0], isPlaying: true,
      isLoading: true, progressMs: 1200, durationMs: 9000, savedDurationMs: 8000 },
    syncSpeechParagraphs() {}, sourceVoices: { setVoices() {} },
    chapterDataSource: { setChapters() {} }, needsChapterHydration: b => b.chapters.length === 0,
    hydrateBookChapters: async b => { events.push('hydrate'); return b; },
    isLiveBook: () => false, chapterDownloadRecord: () => undefined,
    navStack: { pop: () => events.push('pop') },
    getUIContext: () => ({ animateTo: (_, fn) => fn(), getPromptAction: () => ({
      showDialog: options => { dialogs.push(options); return Promise.resolve({ index: answer }); }
    }) })
  });
  return { page, events, dialogs };
}
(async () => {
  const target = book('失效书籍');
  let run = setup({ cached: target });
  run.page.primeFromCache();
  await run.page.loadBook();
  assert.equal(run.page.book, target);
  assert.equal(run.page.playerState.currentBook.id, '正在播放的书');
  assert.equal(run.dialogs.length, 1);
  assert.equal(run.dialogs[0].message.args[0], '失效书籍');
  assert.equal(run.page.showSourceSwitch, true);
  run.page.promptSourceRecovery(target);
  assert.equal(run.dialogs.length, 1, 'repeated errors do not stack recovery dialogs');
  assert.equal(run.page.playbackPlaying(), false);
  assert.equal(run.page.playbackLoading(), false);
  assert.equal(run.page.playbackChapter(), null);
  assert.equal(run.page.currentChapterIndex(), -1);
  assert.equal(run.page.progressValueMs(), 0);
  assert.equal(run.page.displayDurationMs(), 0);
  assert.equal(run.page.canSkipPlayback(), false);
  run.page.skipPlayback(1);
  await run.page.playNext();
  await run.page.playPrev();
  await run.page.togglePlay();
  assert.deepEqual(run.events, [], 'viewing failed book cannot control the other playing book');
  console.log('PASS failed source opens requested book and recovery prompt; live controls stay scoped to that book');

  run = setup({ cached: target, answer: 0 });
  await run.page.loadBook();
  assert.equal(run.page.showSourceSwitch, false);
  assert.equal(run.page.book, target);
  run.page.chapterDownloadRecord = () => ({ status: 'completed' });
  await run.page.togglePlay();
  assert.deepEqual(run.events, ['play:失效书籍'], 'downloaded chapters remain playable without their source');
  run = setup({ cached: target });
  run.page.book = target;
  run.page.promptSourceRecovery(target);
  run.page.isLeaving = true;
  await Promise.resolve();
  assert.equal(run.page.showSourceSwitch, false, 'late dialog result must not reopen a departed page');
  console.log('PASS cancel, departure and downloaded playback');

  run = setup();
  run.page.primeFromCache();
  assert.equal(run.page.book, null);
  await run.page.loadBook();
  assert.equal(run.page.book, null);
  assert.deepEqual(run.events, ['pop']);
  run = setup({ stored: target });
  await run.page.loadBook();
  assert.equal(run.page.book, target);
  const emptyTarget = { ...target, chapters: [] };
  run = setup({ cached: emptyTarget });
  await run.page.loadBook();
  assert.equal(run.page.book, emptyTarget);
  assert.equal(run.events.includes('hydrate'), false, 'removed sources must not start online TOC work');
  assert.equal(run.dialogs.length, 1);
  console.log('PASS cache misses never fall back to an unrelated book; stored and empty target books retain identity');

  run = setup({ cached: target, current: target, available: true });
  await run.page.loadBook();
  assert.equal(run.dialogs.length, 0, 'disabled but installed sources remain resolvable');
  assert.equal(run.page.playbackPlaying(), true);
  assert.equal(run.page.playbackChapter(), target.chapters[0]);
  assert.equal(run.page.progressValueMs(), 1200);
  await run.page.togglePlay();
  assert.deepEqual(run.events, ['toggle']);
  console.log('PASS same-book live playback and disabled source definitions remain usable');
})().catch(error => { console.error(error); process.exitCode = 1; });
