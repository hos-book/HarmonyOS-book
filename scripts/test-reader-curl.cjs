const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/ReaderCurlGeometry.ts'), 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText, { exports: exportsObject });
const { ReaderCurlGeometry } = exportsObject;
const close = (a, b, message) => assert.ok(Math.abs(a - b) < 1e-6, message);
for (const [w, h] of [[360, 780], [780, 360], [1200, 900], [1, 1]]) {
  for (const anchor of [0, 0.5, 1]) {
    for (const vertical of [-h, 0, h]) {
      const initial = new ReaderCurlGeometry(w, h, 0, anchor, vertical);
      const final = new ReaderCurlGeometry(w, h, 1, anchor, vertical);
      close(initial.project(w / 2), w / 2, 'first frame must retain the original page');
      assert.ok(final.project(w / 2) < 0, 'completed turn must leave the viewport');
      for (const p of [0.0001, 0.05, 0.25, 0.5, 0.75, 0.95, 0.9999]) {
        const g = new ReaderCurlGeometry(w, h, p, anchor, vertical);
        close(g.nx * g.nx + g.ny * g.ny, 1, 'normal must not stretch the page along the fold');
        const arcEnd = g.fold + Math.PI * g.radius;
        close(g.project(g.fold), g.fold, 'front must join the curl without a gap');
        close(g.project(arcEnd), g.fold, 'back must join the curl without a gap');
        close(g.project(arcEnd + 10), g.fold - 10, 'paper back must reverse the texture direction');
        for (const v of g.shadowOutline(w, h)) {
          assert.ok(Number.isFinite(v.x) && Number.isFinite(v.y), 'corner clipping must stay finite');
          assert.ok(Math.abs(v.x) + Math.abs(v.y) < 5 * (w + h), 'projection must remain bounded');
        }
      }
    }
  }
}
const upper = new ReaderCurlGeometry(400, 800, 0.3, 0.1, 0);
const lower = new ReaderCurlGeometry(400, 800, 0.3, 0.9, 0);
assert.ok(upper.ny < 0 && lower.ny > 0, 'upper and lower corners must curl in different directions');
assert.notEqual(new ReaderCurlGeometry(400, 800, 0.3, 0.5, 100).ny,
  new ReaderCurlGeometry(400, 800, 0.3, 0.5, -100).ny, 'vertical finger movement must steer the fold');
console.log('PASS: curl continuity, complete/initial frames, mirrored paper back, vertical steering, portrait/landscape and bounded shadow');
