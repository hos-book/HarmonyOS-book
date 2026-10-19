// Exercise the actual slider controller without ArkUI rendering or network access.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/ComicReaderPage.ets'), 'utf8');
function method(name) {
  const start = source.indexOf('  private ' + name);
  assert.ok(start >= 0, name);
  const body = source.indexOf('{', start);
  let depth = 1, end = body + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    else if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(start, end);
}
const controller = `exports.Controller = class Controller {
  constructor() {
    this.book = {id:'comic', chapters:[{title:'one'},{title:'two'},{title:'three'}]};
    this.chapterIndex=0; this.chapterPreview=-1; this.chapterSliderDragging=false;
    this.chapterSliderConfirming=false; this.chrome=true; this.busy=false; this.alive=true;
    this.generation=1; this.loads=[]; this.dialogs=[]; this.answer=0;
  }
  getUIContext() {return {getPromptAction:()=>({showDialog: async options=>{
    this.dialogs.push(options); return this.reply ? this.reply() : {index:this.answer};
  }})};}
  async loadChapter(index) {this.loads.push(index); this.chapterIndex=index;}
  ${method('chapterOrdinal')}
  ${method('chapterAtOrdinal')}
  ${method('async changeChapterSlider')}
};`;
const exportsContext = {};
vm.runInNewContext(ts.transpileModule(controller, { compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
} }).outputText, { exports: exportsContext, SliderChangeMode: {Begin:0, Moving:1, End:2, Click:3},
  $r: (...args) => args.join(':'), AppColor: {Brand:'brand'}, hilog: {warn() {}} });
(async () => {
  const c = new exportsContext.Controller();
  await c.changeChapterSlider(2, 1);
  assert.equal(c.chapterSliderDragging, true); assert.equal(c.chapterOrdinal(), 2);
  assert.equal(c.dialogs.length, 0); assert.equal(c.loads.length, 0);
  await c.changeChapterSlider(2, 2);
  assert.match(c.dialogs[0].message, /three/); assert.equal(c.loads.length, 0);
  assert.equal(c.chapterPreview, -1); assert.equal(c.chapterSliderDragging, false);
  c.answer=1; await c.changeChapterSlider(1, 3);
  assert.equal(c.loads.at(-1), 1);
  c.book.chaptersDescending=true;
  await c.changeChapterSlider(0, 2); assert.equal(c.loads.at(-1), 2);
  const before = c.loads.length;
  await c.changeChapterSlider(0, 2); assert.equal(c.loads.length, before);
  let resolve;
  c.reply = () => new Promise(done => { resolve=done; });
  const pending = c.changeChapterSlider(2, 2);
  await c.changeChapterSlider(1, 2);
  assert.equal(c.chapterSliderConfirming, true);
  c.generation++; resolve({index:1}); await pending;
  assert.equal(c.loads.length, before, 'a stale confirmation cannot change a newer chapter');
  assert.equal(c.chapterSliderConfirming, false);
  console.log('PASS comic slider preview, cancel, confirmation, reversed TOC and stale dialog protection');
})().catch(error => {console.error(error); process.exitCode=1;});
