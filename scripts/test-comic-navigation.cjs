// Exercise the actual comic jump/undo, page-turn feedback and preference methods.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'pages/ComicReaderPage.ets'), 'utf8');
const prefs = fs.readFileSync(path.join(root, 'service/PreferenceService.ets'), 'utf8');
const compile = text => ts.transpileModule(text, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
function method(text, name) {
  const match = new RegExp(`  (?:private )?(?:static )?(?:async )?${name}\\(`).exec(text);
  assert.ok(match, name);
  const start = match.index, body = text.indexOf('{', start);
  let depth = 1, end = body + 1;
  while (depth && end < text.length) {
    if (text[end] === '{') depth++;
    if (text[end] === '}') depth--;
    end++;
  }
  return text.slice(start, end);
}
const SliderChangeMode = { Begin: 0, Moving: 1, End: 2, Click: 3 };
const pulses = [];
const scope = { SliderChangeMode, ComicChapterJumpPosition: class {},
  ReaderHapticService: { play: value => { if (value !== 'none') pulses.push(value); } }, Curve: { EaseInOut: 0 } };
vm.runInNewContext(compile(`class Reader { ${['chapterOrdinal', 'chapterAtOrdinal', 'resetChapterSlider',
  'chapterSliderPercent', 'changeChapterSlider', 'undoChapterSlider', 'playPageTurnHaptic',
  'onSwiperPageChanged', 'turnPage', 'turnToAdjacentChapter'].map(name => method(source, name)).join('\n')}
} globalThis.Reader = Reader;`), scope);
function reader() {
  const r = new scope.Reader();
  Object.assign(r, { book: { id: 'comic', chapters: new Array(4), chaptersDescending: false },
    chapterIndex: 0, pageIndex: 3, pageFraction: 0.375, pageCount: 8,
    alive: true, readerVisible: true, foreground: true, chrome: true, busy: false, failed: false,
    chapterPreview: -1, chapterSliderDragging: false, chapterSliderCommitting: false,
    chapterSliderUndoPosition: null, chapterSliderGeneration: 0, autoPageRunning: false,
    pageTurnHaptic: 'medium', restoreTimer: -1, mode: 3, turning: false, calls: [],
    scheduleSave() {}, usesContinuousPages: () => false,
    canChange: direction => r.chapterIndex + direction >= 0 && r.chapterIndex + direction < 4,
    adjacent: direction => r.chapterIndex + direction,
    getUIContext: () => ({ animateTo: (options, update) => { update(); options.onFinish(); } }),
    loadChapter: async (chapter, page = 0, force = false, fraction = 0, keepHint = false) => {
      r.calls.push([chapter, page, fraction, keepHint]);
      r.chapterIndex = chapter; r.pageIndex = page; r.pageFraction = fraction; return true;
    } });
  return r;
}
(async () => {
  const r = reader();
  await r.changeChapterSlider(3, SliderChangeMode.Moving);
  assert.equal(r.calls.length, 0, 'dragging only previews');
  assert.equal(r.chapterSliderPercent(), '100.00%');
  await r.changeChapterSlider(3, SliderChangeMode.End);
  assert.equal(r.chapterIndex, 3, 'release jumps without any dialog API');
  await r.changeChapterSlider(2, SliderChangeMode.Click);
  assert.equal(r.chapterSliderUndoPosition.chapterIndex, 0, 'consecutive jumps retain the original chapter');
  await r.undoChapterSlider();
  assert.deepEqual(r.calls.at(-1), [0, 3, 0.375, true], 'undo restores image and long-image fraction');
  assert.equal(r.chapterSliderUndoPosition, null);
  r.book.chaptersDescending = true;
  await r.changeChapterSlider(0, SliderChangeMode.Click);
  assert.equal(r.chapterIndex, 3, 'reverse TOC maps its displayed slider ordinal');
  r.loadChapter = async () => false;
  await r.undoChapterSlider();
  assert.ok(r.chapterSliderUndoPosition, 'failed undo remains retryable');
  r.resetChapterSlider();
  await r.changeChapterSlider(2, SliderChangeMode.End);
  assert.equal(r.chapterSliderUndoPosition, null, 'failed first jump has no false undo');
  let finish;
  r.loadChapter = () => new Promise(resolve => { finish = resolve; });
  const pending = r.changeChapterSlider(2, SliderChangeMode.End);
  r.resetChapterSlider(); r.chrome = false; finish(false); await pending;
  assert.equal(r.chapterSliderUndoPosition, null, 'late completion cannot restore a dismissed hint');
  await r.changeChapterSlider(1, SliderChangeMode.Click);
  assert.equal(r.chapterPreview, -1, 'hidden controls ignore stale callbacks');

  const h = reader();
  h.onSwiperPageChanged(4); h.onSwiperPageChanged(4);
  assert.deepEqual(pulses, ['medium'], 'one real swipe change produces one pulse');
  h.autoPageRunning = true; h.onSwiperPageChanged(5);
  h.autoPageRunning = false; h.restoreTimer = 1; h.onSwiperPageChanged(6);
  assert.equal(pulses.length, 1, 'automatic and restoring changes are silent');
  h.restoreTimer = -1; h.turnPage(1);
  assert.equal(pulses.length, 2, 'manual dissolve turn produces feedback');
  h.chapterIndex = 3; h.pageIndex = 7; h.turnPage(1);
  assert.equal(pulses.length, 2, 'end boundary cannot vibrate');
  h.chapterIndex = 0; await h.turnToAdjacentChapter(1);
  assert.equal(pulses.length, 3, 'successful manual chapter boundary turn vibrates');
  h.loadChapter = async () => false; await h.turnToAdjacentChapter(1);
  assert.equal(pulses.length, 3, 'failed chapter load stays silent');
  h.pageTurnHaptic = 'none'; h.onSwiperPageChanged(1);
  assert.equal(pulses.length, 3, 'disabled feedback remains silent');

  const saved = new Map(); let fail = false;
  const prefScope = { store: { getSync: (key, fallback) => saved.has(key) ? saved.get(key) : fallback,
    put: async (key, value) => saved.set(key, value), flush: async () => { if (fail) throw Error('disk full'); } } };
  const session = () => {
    vm.runInNewContext(compile(`(() => { class PreferenceService {
      static async ensureStore() { return store; }
      ${['getComicPageTurnHaptic', 'setComicPageTurnHaptic', 'saveComicPreference'].map(name => method(prefs, name)).join('\n')}
    } globalThis.PreferenceService = PreferenceService; })();`), prefScope);
    return prefScope.PreferenceService;
  };
  assert.equal(await session().getComicPageTurnHaptic(), 'none');
  for (const level of ['none', 'strong', 'medium', 'weak']) {
    await session().setComicPageTurnHaptic(level);
    assert.equal(await session().getComicPageTurnHaptic(), level, 'selection survives reopening');
  }
  fail = true; await assert.rejects(session().setComicPageTurnHaptic('strong'));
  assert.equal(await session().getComicPageTurnHaptic(), 'weak', 'save failure restores the previous level');
  fail = false; await session().setComicPageTurnHaptic('invalid');
  assert.equal(await session().getComicPageTurnHaptic(), 'none');
  console.log('PASS comic navigation: direct jump, undo fraction, reverse order, failure, stale callbacks, manual haptics and persistence');
})().catch(error => { console.error(error); process.exitCode = 1; });
