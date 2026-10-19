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
  async getWidgetPlayerSnapshot() { return this.snapshot; }, async applyTocOrder() {}, chapterStep: () => 1 };
const audio = { async whenReady() {}, async play() { calls.push('audio-play'); } };
const data = { async getBookById() { return book; } };
const deps = { './AudioService': { AudioService: { getInstance: () => audio } },
  './text/TextToSpeechService': { TextToSpeechService: { getInstance: () => speech } },
  './PreferenceService': { PreferenceService: prefs }, './DataService': { DataService: data },
  './BookSourceService': { BookSourceService: {} } };
const moduleContext = { exports: {} };
vm.runInNewContext(code, { module: moduleContext, exports: moduleContext.exports, require: name => {
  if (!deps[name]) throw new Error(name); return deps[name];
} });
const router = moduleContext.exports.WidgetPlaybackService;
(async () => {
  for (const command of ['play', 'pause', 'next', 'prev']) await router.execute({}, command);
  assert.deepEqual(calls, ['resume', 'pause', 1, -1]);
  calls.length = 0; speech.state.active = false; speech.currentBook = () => null;
  await router.execute({}, 'play');
  assert.deepEqual(Array.from(calls[0]), [1, 73, true]);
  await router.execute({}, 'next');
  assert.deepEqual(Array.from(calls[1]), [2, 0, false]);
  prefs.chapterStep = () => -1;
  await router.execute({}, 'next');
  assert.deepEqual(Array.from(calls[2]), [0, 0, false]);
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
  assert.equal(calls.length, 0, 'pause cancels pending cold-start play');
  console.log('PASS widget active/cold TTS commands, position restore, reverse chapters, legacy audio and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
