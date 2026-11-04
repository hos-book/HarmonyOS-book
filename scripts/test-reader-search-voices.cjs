const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, deps = {}, slice = false) {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  if (slice) source = source.split('@ComponentV2')[0];
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(output, { module, exports: module.exports, Promise, setTimeout, require: name => {
    if (!(name in deps)) throw new Error(`Unexpected dependency ${name}`);
    return deps[name];
  } });
  return module.exports;
}
async function main() {
  const { EpubBackgroundImages: Backgrounds } = load('service/text/EpubBackgroundImages.ets');
  const backgrounds = new Backgrounds();
  const html = '<html><head><link rel="stylesheet" href="../Styles/book.css"/></head><body class="cover" id="front">正文</body></html>';
  let cssReads = 0;
  const readCss = async relative => {
    cssReads++;
    assert.equal(relative, '../Styles/book.css');
    return 'body {background-image:url(../Images/default.jpg)} .cover {background:url(../Images/cover.webp)} #front {background-image:url(../Images/front.jpg)} @media print {#front {background:none}}';
  };
  assert.ok((await backgrounds.expand(html, 'OPS/Text/one.xhtml', readCss)).includes('<img src="../Images/front.jpg"/>正文'));
  await backgrounds.expand(html, 'OPS/Text/two.xhtml', readCss);
  assert.equal(cssReads, 1, 'shared stylesheet is cached across chapters');
  const inline = html.replace('id="front"', 'id="front" style="background-image:url(../Images/inline.jpg)"');
  assert.ok((await backgrounds.expand(inline, 'OPS/Text/one.xhtml', readCss)).includes('src="../Images/inline.jpg"'));
  const important = new Backgrounds();
  assert.ok((await important.expand(inline, 'OPS/Text/one.xhtml', async () => '.cover {background-image:url(../Images/priority.jpg)!important}')).includes('src="../Images/priority.jpg"'));
  for (const unsafe of ['https://example.com/a.jpg', '../../../outside.jpg', '//example.com/a.jpg', '%2e%2e/%2e%2e/%2e%2e/out.jpg']) {
    assert.equal(Backgrounds.resolve('OPS/Text/one.xhtml', unsafe), '');
  }
  assert.equal(await new Backgrounds().expand('<body style="background:url(https://example.com/a.jpg)">正文</body>', 'OPS/Text/one.xhtml', async () => ''), '<body style="background:url(https://example.com/a.jpg)">正文</body>');
  console.log('PASS EPUB backgrounds: actual CSS selection, priority, inline override, shared cache and confined resources');
  const { ReaderFullTextSearch: Search } = load('service/text/ReaderFullTextSearch.ets');
  const contents = ['首章目标与目标', '甲'.repeat(16383) + '目标😀下一段', '无匹配'];
  let last;
  await Search.search('目标', contents.length, async index => contents[index], () => false, value => { last = value; });
  assert.equal(last.completed, 3);
  assert.equal(last.failed, 0);
  assert.deepEqual(Array.from(last.matches, m => [m.chapterIndex, m.offset]), [[0, 2], [0, 5], [1, 16383]]);
  for (const match of last.matches) assert.equal(contents[match.chapterIndex].slice(match.offset, match.offset + 2), '目标');
  await Search.search('aa', 1, async () => 'b'.repeat(16383) + 'aaa', () => false, value => { last = value; });
  assert.deepEqual(Array.from(last.matches, m => m.offset), [16383, 16384]);
  const reads = [];
  let cancel = false;
  await Search.search('目标', 10, async index => { reads.push(index); cancel = true; return '目标'; }, () => cancel,
    () => assert.fail('cancelled read cannot publish stale results'));
  assert.deepEqual(reads, [0]);
  await Search.search('目标', 3, async index => { if (index === 1) throw new Error('unreadable'); return '目标'; }, () => false, value => { last = value; });
  assert.equal(last.failed, 1); assert.equal(last.completed, 3); assert.equal(last.matches.length, 2);
  await Search.search('目标', 2, async () => '目标'.repeat(1000), () => false, value => { last = value; });
  assert.equal(last.matches.length, Search.MAX_RESULTS); assert.equal(last.limited, true);
  await Search.search('  ', 1, async () => assert.fail('empty query must not read'), () => false, value => { last = value; });
  assert.equal(last.matches.length, 0);
  console.log('PASS full text: cross-chapter/chunk matches, exact offsets, cancellation, failure and result budget');
  const configModel = load('model/CustomTtsConfig.ets');
  const { ReaderTtsDataSource: Source } = load('components/ReaderTtsTabs.ets', { '../model/CustomTtsConfig': configModel }, true);
  const configs = Array.from({ length: 50 }, (_, index) => Object.assign(new configModel.CustomTtsConfig(), { id: `voice-${index}`, name: `发音人 ${index}` }));
  const source = new Source();
  source.update(configs);
  const events = [];
  source.registerDataChangeListener({ onDataReloaded: () => events.push('reload'), onDataDelete: i => events.push(`delete:${i}`), onDataChange: i => events.push(`change:${i}`) });
  const updated = configs.map(c => c.id === 'voice-40' ? Object.assign(new configModel.CustomTtsConfig(), c, { enabled: false }) : c);
  source.update(updated);
  assert.ok(!events.includes('reload')); assert.ok(events.includes('change:41'));
  events.length = 0;
  const remaining = updated.filter(c => c.id !== 'voice-41');
  source.update(remaining);
  assert.ok(!events.includes('reload')); assert.ok(events.includes('delete:42'));
  const playback = new Source();
  playback.update(remaining.filter(c => c.enabled), false);
  assert.deepEqual(Array.from({ length: playback.totalCount() }, (_, i) => playback.getData(i).id), remaining.filter(c => c.enabled).map(c => c.id));
  assert.equal(playback.getData(playback.totalCount() - 1).name, '发音人 49');
  console.log('PASS voice lists: incremental management updates and identical imported order/names for enabled voices');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
