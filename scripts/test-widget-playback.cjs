const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/WidgetPlaybackService.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const calls = [];
const book = { id: 'text', contentType: 'text', chapters: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] };
const speech = { state: { active: true }, currentBook: () => book,
  async initialize() {}, async resume() { calls.push('resume'); }, pause() { calls.push('pause'); },
  async moveChapter(step) { calls.push(step); }, async start(...args) { calls.push(Array.from(args.slice(1))); } };
const prefs = { snapshot: { playbackKind: 'tts', bookId: 'text', chapterId: 'b', charOffset: 73 },
  async getWidgetPlayerSnapshot() { return this.snapshot; }, async applyTocOrder() {} };
const audio = { async whenReady() {}, async play() { calls.push('audio-play'); },
  async pause(source) { calls.push(`audio-pause:${source}`); },
  async playNext() { calls.push('audio-next'); }, async playPrevious() { calls.push('audio-prev'); } };
const playback = { playing: false, isPlayingNow() { return this.playing; } };
const data = { async getBookById() { return book; } };
const deps = { './AudioService': { AudioService: { getInstance: () => audio } },
  './PlaybackStore': { PlaybackStore: { getInstance: () => playback } },
  './text/TextToSpeechService': { TextToSpeechService: { getInstance: () => speech } },
  './PreferenceService': { PreferenceService: prefs }, './DataService': { DataService: data },
  './BookSourceService': { BookSourceService: {} } };
const moduleContext = { exports: {} };
vm.runInNewContext(code, { module: moduleContext, exports: moduleContext.exports, require: name => {
  if (!deps[name]) throw new Error(name); return deps[name];
} });
const router = moduleContext.exports.WidgetPlaybackService;
(async () => {
  // Execute the real card command sender: controls must never route to a foreground window.
  const cardSource = fs.readFileSync(path.join(__dirname,
    '../entry/src/main/ets/widget/pages/PlayerCard.ets'), 'utf8');
  const sender = cardSource.slice(cardSource.indexOf('  private postCall('), cardSource.indexOf('  /** 手机卡片'));
  const actions = [];
  const cardScope = { postCardAction: (_card, action) => actions.push(action) };
  vm.runInNewContext(ts.transpileModule(`class CardHost { ${sender} } globalThis.CardHost = CardHost;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, cardScope);
  const card = new cardScope.CardHost();
  for (const method of ['toggle', 'prev', 'next']) card.postCall(method);
  assert.deepEqual(actions.map(action => action.action), ['call', 'call', 'call']);
  assert.deepEqual(actions.map(action => action.params.method), ['toggle', 'prev', 'next']);
  for (const command of ['play', 'pause', 'next', 'prev']) await router.execute({}, command);
  assert.deepEqual(calls, ['resume', 'pause', 1, -1]);
  calls.length = 0; speech.state.active = false; speech.currentBook = () => null;
  await router.execute({}, 'play');
  assert.deepEqual(Array.from(calls[0]), [1, 73, true]);
  await router.execute({}, 'next');
  assert.deepEqual(Array.from(calls[1]), [2, 0, false]);
  book.chaptersDescending = true;
  await router.execute({}, 'next');
  assert.deepEqual(Array.from(calls[2]), [2, 0, false]);
  await router.execute({}, 'prev');
  assert.deepEqual(Array.from(calls[3]), [0, 0, false]);
  prefs.snapshot = { bookId: 'old-audio' };
  await router.execute({}, 'play');
  assert.equal(calls.at(-1), 'audio-play');
  prefs.snapshot = { playbackKind: 'tts', bookId: 'text' }; calls.length = 0;
  let finish;
  data.getBookById = () => new Promise(resolve => { finish = resolve; });
  const pending = router.execute({}, 'play');
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  await router.execute({}, 'pause');
  finish(book); await pending;
  assert.deepEqual(calls, ['audio-pause:widget'], 'pause cancels pending cold-start play and reaches the audio player');

  const readSnapshot = prefs.getWidgetPlayerSnapshot;
  prefs.getWidgetPlayerSnapshot = async () => { throw new Error('PreferenceService not initialized'); };
  audio.whenReady = () => new Promise(() => {});
  calls.length = 0;
  const immediatePause = router.execute({}, 'pause');
  assert.deepEqual(calls, ['audio-pause:widget'], 'pause must not wait for initialization or card preferences');
  await immediatePause;
  speech.state.active = true; speech.currentBook = () => book;
  calls.length = 0;
  const immediateSpeechPause = router.execute({}, 'pause');
  assert.deepEqual(calls, ['pause'], 'active speech also pauses immediately');
  await immediateSpeechPause;
  speech.state.active = false; speech.currentBook = () => null;
  audio.whenReady = async () => {};
  playback.playing = true; calls.length = 0;
  for (const command of ['play', 'next', 'prev']) await router.execute({}, command);
  assert.deepEqual(calls, ['audio-play', 'audio-next', 'audio-prev'], 'live audio commands bypass unavailable snapshots');
  prefs.getWidgetPlayerSnapshot = readSnapshot;
  calls.length = 0;
  await router.execute({}, 'next');
  assert.deepEqual(calls, ['audio-next'], 'stale TTS snapshot cannot redirect currently playing audio');
  playback.playing = false;
  prefs.snapshot = { bookId: 'cold-audio', isPlaying: true };
  let initialized;
  router.setInitializer(() => new Promise(resolve => { initialized = resolve; }));
  calls.length = 0;
  const coldToggle = router.execute({}, 'toggle');
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, [], 'cold playback waits for actual restoration, not the audio readiness timeout');
  initialized(); await coldToggle;
  assert.deepEqual(calls, ['audio-play'], 'stale playing card resumes a reclaimed process instead of pausing nothing');
  playback.playing = true;
  await router.execute({}, 'toggle');
  assert.equal(calls.at(-1), 'audio-pause:widget', 'warm toggle pauses immediately');
  playback.playing = false;
  calls.length = 0;
  const cancelled = router.execute({}, 'play');
  await router.execute({}, 'pause');
  initialized(); await cancelled;
  assert.deepEqual(calls, ['audio-pause:widget'], 'pause cancels queued restoration playback');
  console.log('PASS widget active/cold commands, stale toggle, restoration gate, position restore and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
