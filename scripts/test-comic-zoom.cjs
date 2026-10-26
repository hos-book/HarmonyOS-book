const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const exportsValue = {};
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/ComicZoomGeometry.ts'), 'utf8');
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, { exports: exportsValue });
const { ComicZoomTransform: Transform } = exportsValue;
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-8, `${actual} != ${expected}`);
const focus = value => [(value.viewportWidth / 2 - value.x) / value.width(),
  (value.viewportHeight / 2 - value.y) / value.height()];
let page = Transform.open(360, 720, 4, 0.7);
close(focus(page)[1], 0.7);
assert.equal(page.scale, 2);
const anchor = [150, 300];
const pixel = [(anchor[0] - page.x) / page.width(), (anchor[1] - page.y) / page.height()];
let enlarged = page.zoom(3.5, ...anchor);
close((anchor[0] - enlarged.x) / enlarged.width(), pixel[0]);
close((anchor[1] - enlarged.y) / enlarged.height(), pixel[1]);
assert.equal(enlarged.pan(100000, 100000).x, 0);
assert.equal(enlarged.pan(-100000, -100000).x, 360 - enlarged.width());
assert.equal(enlarged.pan(-100000, -100000).y, 720 - enlarged.height());
assert.equal(enlarged.zoom(100, ...anchor).scale, 4);
assert.equal(enlarged.zoom(0, ...anchor).scale, 1);
const before = focus(enlarged);
const resized = enlarged.resize(720, 960);
close(focus(resized)[0], before[0]); close(focus(resized)[1], before[1]);
assert.equal(resized.scale, enlarged.scale);
const landscape = Transform.open(360, 720, 0.25, 0.1);
close(landscape.y, (720 - landscape.height()) / 2);
assert.equal(landscape.pan(0, 99999).y, landscape.y, 'short image remains centered');
const lastPanel = Transform.open(360, 720, 20, 0.98);
assert.equal(lastPanel.y, 720 - lastPanel.height(), 'last panel remains reachable without blank space');
assert.notEqual(page, enlarged, 'each gesture replaces reactive state without mutating its baseline');
assert.equal(page.scale, 2);
console.log('PASS comic zoom: focal point, pan bounds, long/landscape pages, resize continuity and 1–4x limits');
