const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const source = file => fs.readFileSync(path.join(root, file), 'utf8');
function load(file, imports = {}, globals = {}, transform = code => code) {
  const exports = {};
  const code = ts.transpileModule(transform(source(file)), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    assert.ok(name in imports, name); return imports[name];
  }, Error, setTimeout, clearTimeout, $r: id => id, ...globals });
  return exports;
}
const models = load('model/JianjianAi.ets');
const actions = load('model/ReaderAi.ets');
const images = load('service/text/LocalTextImage.ets');
const highlight = load('service/text/SpeechTextHighlighter.ets');
const positions = load('service/text/EpubOriginalPosition.ets', { './LocalTextImage': images });
const { ReaderAiAction: Action } = actions;
const id = value => ({ value, equals(other) { return value === other.value; } });
const menuGlobals = { TextMenuItemId: { of: id, TRANSLATE: id('translate'), COPY: id('copy'),
  SHARE: id('share'), SEARCH: id('search'), SELECT_ALL: id('selectAll'), askAI: id('askAI') } };
const menuState = { selectionMenuOrder: '', selectionMenuHidden: '' };
const menuSettings = load('model/ReaderSelectionSettings.ets');
const menu = load('utils/ReaderSelectionMenu.ets', {
  '../model/GeneralSettings': { GeneralSettings: { current: menuState } },
  '../model/ReaderSelectionSettings': menuSettings
}, menuGlobals);
const nativeTranslate = { id: id('translate'), content: '小艺翻译' };
const nativeDictionary = { id: id('system-dictionary'), content: '小艺字典' };
const nativeCopy = { id: id('copy'), content: '复制' };
const orderedMenu = menu.ReaderSelectionMenu.items(true, [nativeCopy, nativeDictionary, nativeTranslate]);
assert.deepEqual(Array.from(orderedMenu, item => item.id.value), [
  menu.ReaderSelectionMenu.LISTEN, menu.ReaderSelectionMenu.EXCERPT, menu.ReaderSelectionMenu.SUMMARIZE,
  'translate', 'system-dictionary', 'copy', menu.ReaderSelectionMenu.CONFIGURE
]);
assert.equal(orderedMenu[3], nativeTranslate, 'system actions keep the native identity and handler');
assert.ok(!orderedMenu.some(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY),
  'a native dictionary takes precedence over the AI fallback');
const fallbackMenu = menu.ReaderSelectionMenu.items(true, [nativeCopy, nativeTranslate]);
assert.equal(fallbackMenu.filter(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY).length, 1,
  'dictionary remains available when the system does not return a dictionary action');
assert.equal(fallbackMenu.find(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY).content,
  'app.string.reader_ai_dictionary', 'the fallback is explicitly labeled as AI dictionary');
assert.equal(fallbackMenu.find(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY).icon,
  'app.media.reader_menu_dictionary', 'AI dictionary has its own menu icon');
assert.equal(menu.ReaderSelectionMenu.items(true, fallbackMenu)
  .filter(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY).length, 1,
  'preparing an existing menu does not duplicate the dictionary action');
const nativeAskAi = { id: id('askAI'), content: '问问小艺' };
const contextualActions = menu.ReaderSelectionMenu.items(true, [nativeAskAi,
  { id: id('dateTime'), content: '新建日程' }, { id: id('phoneNumber'), content: '呼叫' },
  { id: id('address'), content: '导航前往' }, { id: id('unrecognized'), content: '小艺其他操作' }]);
assert.equal(contextualActions.find(item => item.id.value === 'askAI'), nativeAskAi,
  'Ask Xiaoyi keeps its native identity and handler');
assert.ok(!contextualActions.some(item => ['dateTime', 'phoneNumber', 'address', 'unrecognized'].includes(item.id.value)),
  'context-dependent system actions are not grouped under Ask Xiaoyi');
menuState.selectionMenuOrder = 'copy,translate,copy,invalid';
menuState.selectionMenuHidden = 'listen,dictionary';
const configured = menu.ReaderSelectionMenu.items(true, [nativeTranslate, nativeDictionary, nativeCopy]);
assert.equal(configured[0], nativeCopy);
assert.equal(configured[1], nativeTranslate);
assert.ok(!configured.some(item => ['reader-listen-from-paragraph', 'system-dictionary'].includes(item.id.value)));
assert.ok(!menu.ReaderSelectionMenu.items(true, [nativeCopy])
  .some(item => item.id.value === menu.ReaderSelectionMenu.DICTIONARY), 'the dictionary switch also hides the fallback');
menuState.selectionMenuHidden = 'other';
assert.ok(!menu.ReaderSelectionMenu.items(true, [nativeAskAi]).some(item => item.id.value === 'askAI'),
  'the existing other preference now controls only Ask Xiaoyi');
assert.equal(configured.at(-1).id.value, menu.ReaderSelectionMenu.CONFIGURE, 'configuration remains reachable');
menuState.selectionMenuOrder = ''; menuState.selectionMenuHidden = '';
const calls = [];
let behavior = async () => '摘要';
class Client {
  cancel() {}
  async chat(config, messages, prompt) {
    calls.push({ messages, prompt });
    return behavior(messages[0].content, prompt);
  }
}
const { ReaderAiService: Service } = load('service/text/ReaderAiService.ets', {
  '../../model/JianjianAi': models, '../../model/ReaderAi': actions,
  '../JianjianAiService': { JianjianAiService: Client }, './LocalTextImage': images
});

async function main() {
  const service = new Service();
  const config = new models.JianjianAiConfig();
  await service.run(config, Action.Dictionary, 'Selected text.\uFFF9/private/cover.img\uFFFB', () => {});
  assert.equal(calls[0].messages[0].content, 'Selected text.');
  assert.equal(calls.length, 1);
  calls.length = 0;
  const chapter = '甲'.repeat(11999) + '😀' + '\n' + '乙'.repeat(18000) + '\n章末关键结局';
  const progress = [];
  await service.run(config, Action.Summarize, chapter, (...value) => progress.push(value));
  const originals = calls.filter(call => !call.prompt.includes('按顺序合并'));
  assert.equal(originals.map(call => call.messages[0].content).join(''), chapter);
  assert.ok(originals.length > 1);
  assert.ok(originals.every(call => !/[\uD800-\uDBFF]$/.test(call.messages[0].content)));
  assert.ok(calls.at(-1).prompt.includes('按顺序合并'));
  assert.ok(progress.some(([, , merging]) => merging));
  calls.length = 0;
  let resolve;
  behavior = () => new Promise(done => { resolve = done; });
  const pending = service.run(config, Action.Summarize, chapter, () => {});
  service.cancel(); resolve('迟到的第一段摘要');
  await assert.rejects(pending, error => error.code === models.JianjianAiErrorCode.CANCELLED);
  assert.equal(calls.length, 1, 'cancelled chapters must not issue another request');
  behavior = async () => '摘要';
  await assert.rejects(service.run(config, Action.Dictionary, '字'.repeat(20001), () => {}),
    error => error.code === models.JianjianAiErrorCode.TOO_LARGE);
  assert.equal(calls.length, 1, 'oversized selections must not be silently truncated');

  const { ReaderTextFragment: Fragment } = load('components/ReaderSpeechText.ets', {
    '../service/text/ReaderCommentLayout': {},
    '../service/text/ReaderParagraphNode': { ReaderParagraphNodeController: class {} },
    '../service/text/ReaderSelectionGeometry': {},
    '../theme/Theme': { AppMaterial: {} },
    '../utils/PlatformCompat': { PlatformCompat: {} },
    '../utils/ReaderTapPolicy': { ReaderTouchTracker: class {} },
    '../service/text/OnlineTextPaginator': { OnlineTextPage: class {} },
    '../model/TextToSpeechState': { TextToSpeechState: class {} },
    '../model/ReaderTheme': { ReaderPalette: class {} },
    '../model/ReaderAi': actions, '../utils/ReaderSelectionMenu': menu,
    './ReaderSelectionSettingsPanel': { ReaderSelectionSettingsDialog: { open() {} } },
    '../service/text/SpeechTextHighlighter': highlight
  }, menuGlobals, code => {
    const imports = code.split('\n').filter(line => line.startsWith('import ')).join('\n');
    const fragment = code.slice(code.indexOf('struct ReaderTextFragment'), code.lastIndexOf('  build() {'))
      .replace(/  @LocalBuilder\b[\s\S]*?(?=\n  @Computed\b)/g, '');
    return imports + '\n' + fragment.replace('struct ReaderTextFragment', 'export class ReaderTextFragment')
      .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/  @Monitor\([\s\S]*?\)\s*/g, '') + '\n}';
  });
  const fragment = new Fragment();
  fragment.updateSelection(2, 5);
  fragment.showSelectionMenu();
  const firstMenuRevision = fragment.selectionMenuRevision;
  fragment.showSelectionMenu();
  assert.equal(fragment.selectionMenuRevision, firstMenuRevision + 1,
    'tapping a handle recreates the native menu even when its previous instance was dismissed');
  assert.equal(fragment.selectionStart, 2);
  assert.equal(fragment.selectionEnd, 5, 'reopening the menu preserves the existing selection');
  fragment.updateSelection(-1, -1);
  fragment.showSelectionMenu();
  assert.equal(fragment.selectionMenuVisible, false, 'a cleared selection cannot reopen a stale menu');
  fragment.text = 'before chosen after'; fragment.source = fragment.text; fragment.sourceStart = 100;
  fragment.runSelectionAction(id('selectAll'), 7, 13);
  assert.equal(fragment.selectionStart, 0);
  assert.equal(fragment.selectionEnd, fragment.text.length,
    'select-all operates on the actual body rather than the transparent menu anchor');
  fragment.updateSelection(-1, -1);
  const { Fixture: NativeMenuFixture } = load('components/ReaderNativeSelectionMenu.ets', {}, {
    ...menuGlobals, ReaderSelectionMenu: menu.ReaderSelectionMenu
  }, code => 'export class Fixture {\n' + code.slice(code.indexOf('  private menuOptions('), code.indexOf('  build() {')) + '\n}');
  const nativeMenu = new NativeMenuFixture();
  const nativeActions = [];
  nativeMenu.onAction = value => nativeActions.push(value.value);
  assert.equal(nativeMenu.menuOptions().onMenuItemClick({ id: id('selectAll') }), true);
  assert.deepEqual(nativeActions, ['selectAll'], 'select-all is forwarded to the body selection');
  assert.equal(nativeMenu.menuOptions().onMenuItemClick({ id: id('copy') }), false,
    'copy still uses the original system action');
  assert.equal(nativeMenu.menuOptions().onMenuItemClick({ id: id('askAI') }), false,
    'Ask Xiaoyi still uses the original system action');
  const events = [];
  fragment.onAi = (...args) => events.push(args); fragment.onReadFrom = offset => events.push(offset);
  const options = fragment.speechSelectionMenu();
  assert.deepEqual(Array.from(options.onCreateMenu([{ id: id('copy') }, { id: id('selectAll') }]), item => item.id.value),
    ['reader-listen-from-paragraph', 'reader-save-excerpt', 'reader-ai-summarize', 'reader-ai-dictionary', 'copy', 'selectAll', 'reader-selection-configure']);
  options.onMenuItemClick({ id: id('reader-ai-dictionary') }, { start: 7, end: 13 });
  assert.deepEqual(events[0], [Action.Dictionary, 'chosen']);
  options.onMenuItemClick({ id: id('reader-ai-summarize') }, { start: 7, end: 13 });
  assert.deepEqual(events[1], [Action.Summarize, '']);
  options.onMenuItemClick({ id: id('reader-listen-from-paragraph') }, { start: 7, end: 13 });
  assert.equal(events[2], 107);
  assert.equal(fragment.selecting, false);
  fragment.onExcerpt = (...args) => events.push(args);
  options.onMenuItemClick({ id: id('reader-save-excerpt') }, { start: 7, end: 13 });
  assert.deepEqual(events.at(-1), [107, 113, 'chosen'], 'excerpts preserve fragment origin and exact chosen text');
  const { Fixture } = load('components/EpubOriginalReader.ets', {}, {
    ...menuGlobals, ReaderSelectionMenu: menu.ReaderSelectionMenu, ReaderAiAction: Action,
    EpubOriginalPositionIndex: positions.EpubOriginalPositionIndex
  }, code => 'export class Fixture {\n' + code.slice(code.indexOf('  private validSelectionSpot('), code.indexOf('  build() {')) + '\n}');
  const web = new Fixture();
  Object.assign(web, { alive: true, loading: false, checkpoint: null, serial: 8, selectionSerial: 8,
    paged: false, frames: [{ id: 42, request: { chapter: 5 } }], active: { chapter: 4 },
    selectionFrame: 42, selectionText: 'the selected next chapter',
    onAi: (...args) => events.push(args), onSelectionChange() {},
    controller: { runJavaScript: async () => '' } });
  const webMenu = web.selectionMenu();
  assert.equal(webMenu.onCreateMenu([]).length, 4);
  webMenu.onMenuItemClick({ id: id('reader-ai-dictionary') }, { start: -1, end: -1 });
  assert.deepEqual(events.at(-1), [5, Action.Dictionary, 'the selected next chapter']);
  web.selectionSerial = 8;
  webMenu.onMenuItemClick({ id: id('reader-ai-summarize') }, { start: -1, end: -1 });
  assert.deepEqual(events.at(-1), [5, Action.Summarize, '']);
  web.selectionSerial = 8; web.selectionText = 'next chapter excerpt';
  const raw = '开头。重复句子。  重复句子。  尾声';
  const start = raw.lastIndexOf('重复句子'), end = start + 5;
  web.frames[0].request.text = raw; web.frames[0].parts = [{ offset: 0, length: raw.length }]; web.frames[0].index = 0;
  web.selectionStart = positions.EpubOriginalPosition.spot(raw, start);
  web.selectionEnd = positions.EpubOriginalPosition.spot(raw, end);
  web.onExcerpt = (...args) => events.push(args);
  webMenu.onMenuItemClick({ id: id('reader-save-excerpt') }, {});
  assert.deepEqual(events.at(-1), [5, start, end, 'next chapter excerpt'], 'EPUB selection uses its frame and disambiguates repeated sentences');
  const count = events.length;
  web.selectionSerial = 7;
  webMenu.onMenuItemClick({ id: id('reader-ai-summarize') }, {});
  assert.equal(events.length, count, 'old document selections must be ignored');
  console.log('reader AI passed: exact selection, full chapter, chunk merge, cancellation, budgets, image cleanup and menus');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
