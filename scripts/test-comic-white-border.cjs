const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, dependencies = {}) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8').replace(/@Concurrent\s*/g, ''), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (!(name in dependencies)) throw new Error(name);
    return dependencies[name];
  } });
  return exports;
}
const geometry = load('utils/ComicWhiteBorderGeometry.ts');
const { ComicWhiteBorderGeometry: detector } = geometry;
function picture(width, height, x0, y0, x1, y1) {
  const pixels = new Uint8Array(width * height * 4).fill(255);
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const p = (y * width + x) * 4;
    pixels[p] = pixels[p + 1] = pixels[p + 2] = 40;
  }
  return pixels;
}
const rect = r => [r.x, r.y, r.width, r.height];
async function main() {
  assert.deepEqual(rect(detector.detect(picture(100, 200, 20, 30, 80, 170), 100, 200)), [0.18, 0.14, 0.64, 0.72]);
  assert.deepEqual(rect(detector.detect(new Uint8Array(40000).fill(255), 100, 100)), [0, 0, 1, 1], 'blank page stays blank');
  assert.deepEqual(rect(detector.detect(picture(100, 100, 0, 0, 100, 100), 100, 100)), [0, 0, 1, 1], 'full bleed is unchanged');
  const textAtEdge = picture(100, 100, 20, 20, 80, 80);
  textAtEdge[(10 * 100 + 1) * 4] = 100;
  assert.equal(detector.detect(textAtEdge, 100, 100).x, 0, 'isolated caption at an edge must survive');
  const transparent = new Uint8Array(40000);
  assert.deepEqual(rect(detector.detect(transparent, 100, 100)), [0, 0, 1, 1], 'transparent edges are not white');
  const tiny = detector.detect(picture(100, 100, 49, 49, 51, 51), 100, 100);
  assert.ok(tiny.width >= 0.5 && tiny.height >= 0.5, 'each edge has a crop limit');
  let released = 0, decodedSize;
  const image = { PixelMapFormat: { RGBA_8888: 3 }, createImageSource: () => ({
    getImageInfo: async () => ({ size: { width: 2000, height: 4000 } }),
    createPixelMap: async options => {
      decodedSize = options.desiredSize;
      return { getImageInfo: async () => ({ size: decodedSize }),
        readPixelsToBuffer: async buffer => new Uint8Array(buffer).fill(255), release: async () => { released++; } };
    }, release: async () => { released++; }
  }) };
  const worker = load('service/ComicWhiteBorderWorker.ets', {
    '@kit.ImageKit': { image }, '@kit.CoreFileKit': { fileUri: { FileUri: class { constructor(uri) { this.path = uri.slice(7); } } } },
    '../utils/ComicWhiteBorderGeometry': geometry
  });
  assert.deepEqual(Array.from(await worker.detectComicWhiteBorder('file:///image')), [0, 0, 1, 1]);
  assert.ok(decodedSize.width * decodedSize.height <= 768 * 768);
  assert.equal(released, 2, 'both native decoder and bitmap are released');
  let calls = 0, running = 0, maxRunning = 0;
  const { ComicWhiteBorderService: service } = load('service/ComicWhiteBorderService.ets', {
    '@kit.ArkTS': { taskpool: { execute: async () => {
      calls++; running++; maxRunning = Math.max(maxRunning, running);
      await Promise.resolve(); running--; return [0.1, 0.1, 0.8, 0.8];
    } } }, '../utils/ComicWhiteBorderGeometry': geometry, './ComicWhiteBorderWorker': worker
  });
  const results = await Promise.all([service.inspect('/a'), service.inspect('/a'), service.inspect('/b')]);
  assert.equal(calls, 2); assert.equal(maxRunning, 1);
  assert.equal(results[0], results[1], 'same image shares the pending job');
  await service.inspect('/a'); assert.equal(calls, 2, 'reuse bounded detection cache');
  console.log('PASS comic white borders, caption protection, blank/full-bleed/transparent pages, decode budget, resource release and bounded serial cache');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
