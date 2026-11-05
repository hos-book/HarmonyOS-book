const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
// 仅转译组件的真实生命周期和加载方法，ArkUI 声明式 build 由设备验证。
let source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/CoverImage.ets'), 'utf8').replace(/\r\n/g, '\n');
source = source.slice(0, source.indexOf('  @Builder\n')) + '\n}';
source = source.replace('export struct CoverImage', 'export class CoverImage')
  .replace(/@ComponentV2\s*/g, '').replace(/@(Param|Local|Event)\s*/g, '').replace(/@Monitor\([^\n]*\)\s*/g, '');
const handlers = new Map(), pending = [], exportsObject = {};
const emitter = { on: (event, callback) => handlers.set(event, callback), off: event => handlers.delete(event) };
const dependencies = {
  '../theme/Theme': { AppRadius: { Md: 12 } }, '@kit.BasicServicesKit': { emitter },
  '../utils/CoverAspectRatio': { CoverAspectRatio: { get: () => 0.75 } },
  '../service/CoverPrefetcher': { CoverPrefetcher: { cached: () => '', acquire: url => {
    const request = { url, cancelled: false, cancel() { this.cancelled = true; } };
    request.promise = new Promise(resolve => { request.resolve = resolve; });
    pending.push(request); return request;
  } } }
};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020 } }).outputText, { exports: exportsObject, require: key => dependencies[key] || {},
  ImageFit: { Cover: 0 }, setTimeout, clearTimeout });
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const cover = new exportsObject.CoverImage(); cover.url = 'https://example.test/cover'; cover.eagerLoad = true;
  cover.aboutToAppear();
  assert.equal(pending.length, 1, 'mini cover starts without any visible-area callback');
  handlers.get('app.reader.background')();
  assert.equal(pending[0].cancelled, true);
  handlers.get('app.reader.foreground')();
  assert.equal(pending.length, 2, 'foreground resumes without scrolling');
  pending[0].resolve('old-file'); await flush(); assert.equal(cover.resolvedUrl, '');
  pending[1].resolve('file:///new-cover'); await flush();
  cover.imageReady = true;
  handlers.get('app.reader.background')(); handlers.get('app.reader.foreground')();
  assert.equal(cover.resolvedUrl, 'file:///new-cover'); assert.equal(cover.imageReady, true);
  assert.equal(pending.length, 2, 'loaded image preserved across foreground to avoid flicker');
  cover.aboutToDisappear(); assert.equal(handlers.size, 0);
  const listCover = new exportsObject.CoverImage(); listCover.url = 'https://example.test/list';
  listCover.aboutToAppear(); assert.equal(pending.length, 2, 'list covers remain lazy');
  listCover.visibilityChanged(true); assert.equal(pending.length, 3);
  listCover.aboutToDisappear();
  console.log('PASS mini cover eager load, foreground resume, stale results, no flicker and lazy lists');
})().catch(error => { console.error(error); process.exitCode = 1; });
