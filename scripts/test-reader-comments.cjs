// Real marker parsing / normalized positions / layout anchors; platform geometry is deterministic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
function load(relative) {
  const filename = path.resolve(root, relative);
  if (modules.has(filename)) return modules.get(filename);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require(name) {
    if (name === '@kit.ArkGraphics2D') return { text: { RectWidthStyle: { TIGHT: 0 }, RectHeightStyle: { TIGHT: 0 } } };
    if (name.endsWith('/PlatformCompat')) return { PlatformCompat: { supports: () => false } };
    if (name.endsWith('/LocalTextImage')) return {};
    const file = path.resolve(path.dirname(filename), name);
    return load(fs.existsSync(file + '.ets') ? file + '.ets' : file + '.ts');
  } }, { filename });
  modules.set(filename, module.exports);
  return module.exports;
}
const { ReaderActionMarker: markers } = load('service/rulesource/light/upstream/core/book/ReaderActionMarker.ts');
const { ReaderCommentContent: content } = load('service/text/ReaderCommentContent.ets');
const { ReaderTextDocument, ReaderTextStage, ReaderTextEdit } = load('model/ReaderTools.ets');
const { ReaderCommentLayout: layout } = load('service/text/ReaderCommentLayout.ets');
const { ReaderCommentWebPolicy: policy } = load('service/text/ReaderCommentWebPolicy.ets');
const { OnlineTextPage } = load('service/text/OnlineTextPaginator.ets');
const { LightReaderCommentDocument: messages } = load('service/rulesource/light/LightReaderCommentDocument.ts');
const action = (n, url = 'https://comments.example/' + n) => markers.create('段评 ' + n, url, '段评');
const first = action(3);
const second = markers.createSourceScript('段评 99+', 'java.showBrowser("https://comments.example/2");', '段评');
const rich = '<p>　第一段&amp;中文。  ' + first + '</p>\r\n<p>第二段📚。' + second + '</p>';
const result = content.parse(markers.strip(rich), rich);
assert.equal(result.content, '第一段&中文。\n\n第二段📚。');
assert.equal(result.comments.length, 2);
assert.equal(result.comments[0].offset, '第一段&中文。'.length);
assert.equal(result.comments[1].offset, result.content.length);
assert.ok(result.comments[1].url.startsWith('legado-source-action:'));
assert.ok(!result.content.includes('JT_COMMENT') && !result.content.includes('showBrowser'));
const mixed = '首段' + action(0) + '\n末段' + action(7) + markers.create('本章说', 'https://example/chapter', '本章说');
assert.equal(content.parse(markers.strip(mixed), mixed).comments.length, 1);
assert.equal(content.parse('其他正文', rich).comments.length, 0, 'mismatched content never gets stale anchors');
const malformed = '保留正文' + markers.PREFIX + 'broken\n后续段落';
assert.equal(content.parse(markers.strip(malformed), malformed).comments.length, 0);
assert.equal(content.parse('没有评论', '没有评论').commentsLoaded, true);
for (const label of ['段评', '段评0', '段评（0）', '段评 0 条']) {
  assert.equal(content.parse('正文', '正文' + markers.create(label, 'https://comments.example/empty', '段评')).comments.length, 0);
}
for (const label of ['段评1', '段评（12）', '段评 1.2万+', '段评 3 条']) {
  assert.equal(content.parse('正文', '正文' + markers.create(label, 'https://comments.example/exists', '段评')).comments.length, 1);
}
const repeated = '同段' + first + first + '\n其他段';
assert.equal(content.parse(markers.strip(repeated), repeated).comments.length, 1);
const bounded = Array.from({ length: 400 }, (_, i) => '第' + i + '段' + action(1)).join('\n');
assert.equal(content.parse(markers.strip(bounded), bounded).comments.length, 320);
console.log('PASS Legado/native markers, CRLF/HTML/entities, emoji, malformed/zero/chapter actions and chapter bounds');

const doc = ReaderTextDocument.original(result.content);
const edit = new ReaderTextEdit(); edit.start = 0; edit.end = 2; edit.length = 5;
const stage = new ReaderTextStage(); stage.edits = [edit]; doc.stages = [stage];
doc.content = '替换后的开头' + result.content.slice(2);
const mapped = content.display(result.comments, doc);
assert.equal(mapped[0].offset, result.comments[0].offset + 3);
const deleted = ReaderTextDocument.original(result.content);
const remove = new ReaderTextEdit(); remove.start = 0; remove.end = result.comments[0].offset; remove.length = 0;
const removedStage = new ReaderTextStage(); removedStage.edits = [remove]; deleted.stages = [removedStage];
deleted.content = result.content.slice(remove.end);
assert.equal(content.display(result.comments, deleted).length, 1, 'deleted paragraph has no detached comment icon');

const page = new OnlineTextPage();
page.startOffset = 0; page.endOffset = 4; page.text = '　　首段内容'; page.displayStart = 0;
page.layoutWidth = 180; page.layoutHeight = 58; page.commentLineExtra = [26];
page.lineMetrics = [{ baseline: 24, ascent: 24, descent: 8 }]; page.lineShifts = [0];
page.paragraph = { getRectsForRange(range) { assert.equal(range.end, 6); return [{ rect: { left: 168, right: 180, top: 4, bottom: 28 } }]; } };
const comment = { offset: 4, label: '段评 3', url: 'https://example/3', title: '段评' };
const anchors = layout.anchors(page, '首段内容', 0, [comment], 1);
assert.equal(anchors.length, 1);
assert.ok(anchors[0].x + anchors[0].size <= 180, 'full line icon stays inside symmetric body width');
assert.ok(anchors[0].y >= 32, 'full line icon moves below the final glyph without covering text');
assert.equal(layout.anchors(page, '首段内容', 4, [comment], 1).length, 0, 'next page does not repeat previous paragraph icon');
page.text = '末尾📚'; page.endOffset = 4;
page.paragraph = { getRectsForRange(range) {
  assert.equal(range.start, 2, 'paragraph-ending emoji keeps the whole surrogate pair');
  assert.equal(range.end, 4);
  return [{ rect: { left: 168, right: 180, top: 4, bottom: 28 } }];
} };
assert.equal(layout.anchors(page, '末尾📚', 0, [comment], 1).length, 1);
page.isHeading = true;
assert.equal(layout.anchors(page, '首段内容', 0, [comment], 1).length, 0);
assert.ok(policy.navigation('https://example/comments', false, true, ''));
for (const url of ['javascript:alert(1)', 'file:///data/local', 'intent://open', 'data:text/html,unsafe']) {
  assert.equal(policy.navigation(url, false, true, ''), false);
}
assert.ok(policy.navigation('data:text/html;base64,EXPECTED', true, true, 'EXPECTED'));
assert.equal(policy.navigation('data:text/html;base64,OTHER', true, true, 'EXPECTED'), false);
assert.equal(policy.navigation('https://example/comments', true, false, 'EXPECTED'), false);
console.log('PASS replacement mapping, paragraph/page boundaries, full-line geometry and offline navigation isolation');

const conversation = JSON.parse(messages.parse(JSON.stringify({data:{comments:[
  {id:'c1',content:'第一条评论<br>换行',user:{nickname:'读者甲',avatar:'https://example/avatar.png'},likeCount:12,
    replies:[{id:'r1',content:'回复内容',user:{nickname:'读者乙'}}]},
  {id:'c1',content:'重复评论'},
  {id:'c2',content:'另一条',nickname:'读者丙',avatar:'file:///private/avatar'}
]}})));
assert.equal(conversation.items.length,3);
assert.equal(conversation.items[0].text,'第一条评论\n换行');
assert.equal(conversation.items[0].author,'读者甲');
assert.equal(conversation.items[1].replyTo,'读者甲');
assert.equal(conversation.items[2].avatar,'');
assert.equal(JSON.parse(messages.parse('{"items":[],"empty":false}')).empty,false,'loading DOM is not an empty comment thread');
assert.equal(JSON.parse(messages.parse('{"comments":[]}')).empty,true);
assert.equal(JSON.parse(messages.parse('{"items":[],"empty":true}')).empty,true);
assert.equal(JSON.parse(messages.parse('{"content":"正文不能当评论"}')).items.length,0);
assert.equal(JSON.parse(messages.parse(JSON.stringify(conversation))).items[0].author,'读者甲','normalized results retain author');
assert.match(messages.formatTime('1499802542270'), /^2017-07-\d{2} \d{2}:\d{2}$/);
assert.equal(messages.formatTime('1499802542'),messages.formatTime('1499802542000'));
assert.equal(messages.formatTime('昨天'),'昨天');
console.log('PASS source comment records, replies, deduplication, safe avatars and loading/empty distinction');
