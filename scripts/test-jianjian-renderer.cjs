const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const service = path.join(__dirname, '../entry/src/main/ets/service');
const intervals = new Map();
const maps = [];
let nextId = 0, delayDecode = false, completeDecode;
class FrameNode { setMeasuredSize() {} setLayoutPosition() {} invalidate() {} dispose() { this.disposed = true; } }
class Brush { setAntiAlias() {} }
const moduleMap = {
  '@kit.ArkGraphics2D': { drawing: { Brush } },
  '@kit.ArkUI': {},
  '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
  '@ohos.arkui.node': { FrameNode, NodeController: class {} },
  '@kit.ImageKit': { image: { createImageSource: () => ({
    createPixelMap: async () => {
      if (delayDecode) await new Promise(resolve => { completeDecode = resolve; });
      const map = { released: 0, release: async function() { this.released++; } };
      maps.push(map); return map;
    }, release: async () => {}
  }) } }
};
function load(name) {
  const exportsObject = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(service, name+'.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports: exportsObject, Math, Date, Uint8Array,
    $r: id => ({ id }), require: key => {
      assert.ok(moduleMap[key], `unexpected dependency ${key}`); return moduleMap[key];
    }, setInterval: callback => { intervals.set(++nextId, callback); return nextId; },
    clearInterval: id => intervals.delete(id) });
  return exportsObject;
}
moduleMap['./JianjianRig'] = load('JianjianRig');
const { JianjianRenderController } = load('JianjianRenderController');
const context = { getHostContext: () => ({ resourceManager: { getMediaContent: async () => new Uint8Array(4) } }),
  runScopedTask: callback => callback() };
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const renderer = new JianjianRenderController();
  renderer.update(true, false, -1);
  const node = renderer.makeNode(context);
  await tick();
  assert.equal(maps.length, 3);
  assert.equal(intervals.size, 1);
  let attached = false, draws = 0;
  const canvas = { save() {}, restore() {}, translate() {}, scale() {},
    attachBrush() { attached = true; }, detachBrush() { attached = false; },
    drawPixelMapMesh(map, cols, rows, vertices) {
      assert.ok(attached, 'native mesh requires an attached brush');
      assert.equal(map.released, 0);
      assert.equal(vertices.length, (cols+1)*(rows+1)*2); draws++;
    } };
  renderer.setEyes(true, true);
  node.onDraw({ canvas, sizeInPixel: { width: 336, height: 392 } });
  assert.equal(draws, 3, 'base and eyelids use the same mesh');
  assert.equal(attached, false);
  renderer.update(false, false, -1);
  assert.equal(intervals.size, 0, 'background stops frame updates');
  renderer.update(true, true, 6);
  assert.equal(intervals.size, 1);
  renderer.release();
  assert.equal(intervals.size, 0);
  assert.ok(node.disposed);
  assert.ok(maps.every(map => map.released===1));
  delayDecode = true;
  const cancelled = new JianjianRenderController();
  cancelled.makeNode(context);
  await tick();
  cancelled.release();
  completeDecode();
  await tick();
  assert.equal(maps.length, 4);
  assert.ok(maps.every(map => map.released===1), 'late decode is released after unmount');
  assert.equal(intervals.size, 0);
  console.log('PASS: native brush binding, mesh/eye rendering, background pause, disposal and late decode cleanup');
})().catch(error => { console.error(error); process.exitCode=1; });
