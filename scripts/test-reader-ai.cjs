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
const menuGlobals = { TextMenuItemId: { of: id } };
const menu = load('utils/ReaderSelectionMenu.ets', {}, menuGlobals);
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
    '../service/text/SpeechTextHighlighter': highlight
  }, menuGlobals, code => {
    const imports = code.split('\n').filter(line => line.startsWith('import ')).join('\n');
    const fragment = code.slice(code.indexOf('struct ReaderTextFragment'), code.lastIndexOf('  build() {'))
      .replace(/  @LocalBuilder\b[\s\S]*?(?=\n  @Computed\b)/g, '');
    return imports + '\n' + fragment.replace('struct ReaderTextFragment', 'export class ReaderTextFragment')
      .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/  @Monitor\([\s\S]*?\)\s*/g, '') + '\n}';
  });
  const fragment = new Fragment();
  fragment.text = 'before chosen after'; fragment.source = fragment.text; fragment.sourceStart = 100;
  const events = [];
  fragment.onAi = (...args) => events.push(args); fragment.onReadFrom = offset => events.push(offset);
  const options = fragment.speechSelectionMenu();
  assert.deepEqual(Array.from(options.onCreateMenu([{ id: id('copy') }, { id: id('selectAll') }]), item => item.id.value),
    ['reader-save-excerpt', 'reader-listen-from-paragraph', 'reader-ai-dictionary', 'reader-ai-summarize']);
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
  assert.equal(webMenu.onCreateMenu([]).length, 3);
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
