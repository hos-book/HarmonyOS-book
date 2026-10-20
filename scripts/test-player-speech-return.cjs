// Run the actual close handler against navigation and progress storage mocks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(source, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, JSON, ...globals });
  return exports;
}
const model = fs.readFileSync(path.join(root, 'model/TextReading.ets'), 'utf8');
const route = model.slice(model.indexOf('export class TextReaderRouteParams'), model.indexOf('export class TextSourceError'));
const { TextReaderRouteParams, ReaderJumpChapterEvent, EVT_READER_JUMP_CHAPTER } = compile(route);
const source = fs.readFileSync(path.join(root, 'pages/PlayerPage.ets'), 'utf8');
const method = source.slice(source.indexOf('  private async closeSpeechToReader'), source.indexOf('  /** 长按恢复默认值'));
async function scenario(names, params, failSave = false, keepSpeaking = false) {
  const actions = [], events = [], saved = [];
  const book = { id: 'book', chapters: [{ title: 'one' }, { title: 'two' }] };
  const { Player } = compile(`export class Player { ${method} }`, {
    TextReaderRouteParams, ReaderJumpChapterEvent, EVT_READER_JUMP_CHAPTER,
    TextReadingPosition: { atChar: (bookId, resourceIndex, domPos, charOffset) => ({ bookId, resourceIndex, domPos, charOffset }) },
    TextReadingProgressService: { save: async (_, value) => { saved.push(value); if (failSave) throw Error('disk'); } },
    SearchCache: { put: value => assert.equal(value, book) },
    TextToSpeechService: { getInstance: () => ({ currentBook: () => book, stop: () => actions.push('stop') }) },
    emitter: { emit: (id, value) => events.push([id, value.data]) }
  });
  const page = new Player();
  page.book = book;
  page.speechState = { bookId: 'book', chapterIndex: 1, charOffset: 123 };
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  page.navStack = {
    getAllPathName: () => names, getParamByIndex: i => params[i],
    popToIndex: i => actions.push(['pop', i]),
    replacePathByName: (name, param) => actions.push(['replace', name, param.bookId])
  };
  await page.closeSpeechToReader(keepSpeaking);
  await page.closeSpeechToReader(keepSpeaking); // Repeated taps cannot navigate twice.
  assert.equal(saved.length, 1);
  assert.equal(saved[0].charOffset, 123);
  assert.equal(saved[0].resourceIndex, 1);
  assert.equal(actions.includes('stop'), !keepSpeaking);
  return { actions, events };
}
(async () => {
  const existing = await scenario(['reader', 'detail', 'player'], [TextReaderRouteParams.of('book')]);
  assert.deepEqual(existing.actions, ['stop', ['pop', 0]]);
  assert.equal(existing.events[0][1].charOffset, 123);
  assert.equal(existing.events[0][1].resourceIndex, 1);
  const fromShelf = await scenario(['player'], []);
  assert.deepEqual(fromShelf.actions, ['stop', ['replace', 'reader', 'book']]);
  const otherReader = await scenario(['reader', 'player'], [TextReaderRouteParams.of('other')], true);
  assert.deepEqual(otherReader.actions, ['stop', ['replace', 'reader', 'book']]);
  assert.equal(otherReader.events.length, 0);
  const continuing = await scenario(['reader', 'player'], [TextReaderRouteParams.of('book')], false, true);
  assert.deepEqual(continuing.actions, [['pop', 0]]);
  assert.equal(continuing.events.length, 0, 'live reader follows speech rather than a stale saved offset');
  const continuingFromShelf = await scenario(['player'], [], false, true);
  assert.deepEqual(continuingFromShelf.actions, [['replace', 'reader', 'book']]);
  console.log('PASS: close returns to matching text, restores speech position, handles shelf entry/storage failure and repeated taps');
})().catch(error => { console.error(error); process.exitCode = 1; });
