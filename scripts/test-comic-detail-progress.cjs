// Run real detail/TOC controllers with deterministic storage and layout timing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function method(file, name) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const start = source.indexOf('  private ' + name);
  assert.ok(start >= 0, name);
  const body = source.indexOf('{', start);
  let end = body + 1, depth = 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(start, end);
}
const timers = new Map();
let timerId = 0, stored = null, getPosition = async () => stored;
const scope = {
  ScrollAlign: { CENTER: 'center' },
  TextReadingProgressService: { get: (...args) => getPosition(...args) },
  setTimeout: callback => { timers.set(++timerId, callback); return timerId; },
  clearTimeout: id => timers.delete(id),
  hilog: { warn() {} }, DETAIL_LOG_DOMAIN: 0, DETAIL_LOG_TAG: 'test'
};
function controller(name, file, names) {
  const code = `class ${name} { ${names.map(value => method(file, value)).join('\n')} }
    globalThis.${name} = ${name};`;
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
  } }).outputText, scope);
}
controller('Detail', 'pages/BookDetailPage.ets', [
  'readingProgressHandler', 'async loadTextReadingProgress', 'currentChapterIndex', 'currentChapterId'
]);
controller('Sheet', 'components/ChapterSheet.ets', [
  'onBookChanged', 'onCurrentChanged', 'isReadingBook', 'chapters', 'currentIndex',
  'refresh', 'applyQuery', 'scrollToCurrentChapter', 'shouldShowJumpButton'
]);
function layout() {
  const callbacks = [...timers.values()]; timers.clear();
  for (const callback of callbacks) callback();
}
(async () => {
  const book = { id: 'comic', contentType: 'comic', chapters: Array.from({length:100},
    (_, index) => ({id: `chapter-${index}`, title: `Chapter ${index}`})) };
  const detail = new scope.Detail();
  Object.assign(detail, { book, detailActive:true, textReadingProgress:null,
    getUIContext: () => ({getHostContext: () => ({})}) });
  assert.equal(detail.currentChapterId(), '', 'unread books have no current chapter');
  stored = {resourceIndex:70};
  detail.readingProgressHandler();
  await new Promise(setImmediate);
  assert.equal(detail.currentChapterId(), 'chapter-70', 'reader save refreshes the retained detail');
  const sheet = new scope.Sheet(), jumps = [];
  Object.assign(sheet, {book, currentId:'', query:'', segmentMode:false,
    positionTimer:-1, offsetFromCurrent:0,
    listScroller:{scrollToIndex: (...args) => jumps.push(args)} });
  sheet.onBookChanged(); layout();
  assert.equal(jumps.length, 0);
  assert.equal(sheet.shouldShowJumpButton(), false);
  sheet.currentId = detail.currentChapterId(); sheet.onCurrentChanged(); layout();
  assert.deepEqual(jumps.at(-1), [70, false, 'center'], 'late progress locates after layout');
  assert.equal(sheet.isReadingBook(), true);
  assert.equal(sheet.shouldShowJumpButton(), true, 'comic location remains directly accessible');
  book.chaptersDescending = true; sheet.onBookChanged(); layout();
  assert.equal(jumps.at(-1)[0], 29, 'descending TOC resolves the same chapter identity');
  sheet.scrollToCurrentChapter();
  sheet.currentId = 'chapter-80'; sheet.onCurrentChanged(); layout();
  assert.equal(jumps.at(-1)[0], 19, 'pending positioning uses the latest chapter');
  const count = jumps.length;
  sheet.scrollToCurrentChapter(); sheet.applyQuery('Chapter 3'); layout();
  assert.equal(jumps.length, count, 'search must not be interrupted by pending positioning');
  assert.equal(sheet.shouldShowJumpButton(), false);
  sheet.applyQuery(''); layout(); assert.equal(jumps.at(-1)[0], 19);
  sheet.book = {...book, chapters:[]}; sheet.onBookChanged(); layout();
  sheet.book = book; sheet.onBookChanged(); layout();
  assert.equal(jumps.at(-1)[0], 19, 'late TOC data restores the saved chapter');
  let resolve;
  getPosition = () => new Promise(done => { resolve=done; });
  const pending = detail.loadTextReadingProgress(book.id);
  detail.detailActive = false; resolve({resourceIndex:2}); await pending;
  assert.equal(detail.currentChapterId(), 'chapter-70', 'disposed detail ignores late progress');
  for (const type of ['text', 'audio']) {
    sheet.book = {...book, contentType:type}; sheet.offsetFromCurrent = 0;
    assert.equal(sheet.isReadingBook(), type === 'text');
    assert.equal(sheet.shouldShowJumpButton(), false, 'non-comic jump visibility is preserved');
    sheet.offsetFromCurrent = 300; assert.equal(sheet.shouldShowJumpButton(), true);
  }
  console.log('PASS comic detail: progress refresh, unread state, late TOC/progress, descending order, search and stale callbacks');
})().catch(error => { console.error(error); process.exitCode = 1; });
