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
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/ReaderSpreadGeometry.ts'), 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText, { exports: exportsObject, require: name => {
  assert.equal(name, './ReaderCurlGeometry');
  return exportsObject;
} });
const { ReaderSpreadGeometry } = exportsObject;
const close = (a, b, message) => assert.ok(Math.abs(a - b) < 1e-6, message);
const polygonArea = points => Math.abs(points.reduce((sum, a, i) => {
  const b = points[(i + 1) % points.length];
  return sum + a.x * b.y - b.x * a.y;
}, 0)) / 2;
for (const [width, height] of [[480, 800], [720, 900], [900, 600], [1, 1]]) {
  for (const anchor of [0, 0.1, 0.5, 0.9, 1]) {
    for (const vertical of [-height, 0, height]) {
      for (const p of [0, 0.00001, 0.1, 0.49, 0.5, 0.51, 0.9, 0.99999, 1]) {
        const shape = new ReaderSpreadGeometry(width, height, p, anchor, vertical);
        const held = shape.reflect(shape.corner);
        close(held.x, shape.touch.x, 'the folded corner stays on the constrained touch position');
        close(held.y, shape.touch.y, 'vertical movement directly steers the corner');
        close(shape.touch.x, width * (1 - 2 * p), 'horizontal corner motion follows finger travel one to one');
        for (const y of [0, height / 2, height]) {
          assert.ok(shape.ny * y - shape.fold <= 1e-6, 'fold cannot detach any part of the spine');
        }
        close(polygonArea(shape.front) + polygonArea(shape.back), width * height,
          'visible front and folded back retain the complete sheet area');
        assert.ok(shape.front.length <= 5 && shape.back.length <= 5, 'paper uses bounded polygons');
        for (const point of [...shape.front, ...shape.back]) {
          assert.ok(Number.isFinite(point.x) && Number.isFinite(point.y));
          assert.ok(Math.abs(point.x) + Math.abs(point.y) < 5 * (width + height));
        }
        const a = { x: width * 0.2, y: height * 0.3 };
        const b = { x: width * 0.8, y: height * 0.7 };
        const ra = shape.reflect(a), rb = shape.reflect(b);
        close(Math.hypot(ra.x - rb.x, ra.y - rb.y), Math.hypot(a.x - b.x, a.y - b.y),
          'paper reflection never squeezes text');
        if (p === 0) assert.equal(shape.back.length, 0);
        if (p === 1) {
          assert.equal(shape.front.length, 0);
          close(ra.x, -a.x, 'completed leaf lands on the opposite page');
          close(ra.y, a.y, 'completed leaf has no vertical jump');
        }
      }
    }
  }
}
assert.ok(new ReaderSpreadGeometry(600, 800, 0.4, 0.1, 0).ny < 0);
assert.ok(new ReaderSpreadGeometry(600, 800, 0.4, 0.9, 0).ny > 0);
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
