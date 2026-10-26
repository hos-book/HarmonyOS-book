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
let page = Transform.fit(360, 1440, 400, 1120);
assert.equal(page.scale, 1, 'reading starts at the original size without a modal or double tap');
assert.equal(page.x, 0); assert.equal(page.y, 0);
const anchor = [150, 700];
const pixel = [(anchor[0] - page.x) / page.width(), (anchor[1] - page.y) / page.height()];
let enlarged = page.zoom(3.5, ...anchor);
close((anchor[0] - enlarged.x) / enlarged.width(), pixel[0]);
close((anchor[1] - enlarged.y) / enlarged.height(), pixel[1]);
assert.equal(enlarged.pan(100000, 100000).x, 0);
assert.equal(enlarged.pan(-100000, -100000).x, 360 - enlarged.width());
assert.equal(enlarged.pan(100000, 100000).y, 400, 'top of a long image can reach the visible window');
assert.equal(enlarged.pan(-100000, -100000).y, 1120 - enlarged.height(), 'bottom can reach the visible window');
assert.equal(enlarged.zoom(100, ...anchor).scale, 4);
const reset = enlarged.pan(-500, -2000).zoom(0, ...anchor);
assert.equal(reset.scale, 1); assert.equal(reset.x, 0); assert.equal(reset.y, 0);
const moved = enlarged.viewport(500, 1200);
assert.equal(moved.scale, enlarged.scale);
const landscape = Transform.fit(360, 90, -400, 320).zoom(2, 180, 45);
assert.equal(landscape.pan(0, 99999).y, 0);
assert.equal(landscape.pan(0, -99999).y, -90);
const lastPanel = Transform.fit(360, 7200, 6480, 7200).zoom(2, 180, 6800);
assert.equal(lastPanel.pan(0, -99999).y + lastPanel.height(), 7200);
assert.equal(lastPanel.pan(0, 99999).y, 6480, 'last screen can pan all the way back to the first panel');
assert.notEqual(page, enlarged, 'each gesture replaces reactive state without mutating its baseline');
assert.equal(page.scale, 1);
console.log('PASS inline comic pinch: focal point, visible-window pan bounds, long/landscape pages, reset and 1–4x limits');
