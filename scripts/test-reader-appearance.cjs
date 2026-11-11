// Real appearance models and comic geometry; no image downloads or platform service calls.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compile = text => ts.transpileModule(text, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
function load(name) {
  const exports = {};
  vm.runInNewContext(compile(fs.readFileSync(path.join(root, name), 'utf8')), {
    exports, require: () => ({}), console
  });
  return exports;
}
const { ComicReaderAppearance } = load('model/ComicReaderAppearance.ets');
const { ReaderRegionStyle } = load('model/ReaderRegionStyle.ets');
const { ComicReaderService, ComicPage } = load('service/ComicReaderService.ets');
const { ComicCropRect } = load('utils/ComicWhiteBorderGeometry.ts');
const appearance = ComicReaderAppearance.decode('{"cropLeft":12,"cropRight":8,"cropTop":5,"cropBottom":9,"lightBackground":2,"darkBackground":3,"split":2}');
assert.equal(appearance.background(false), '#D8BE91');
assert.equal(appearance.background(true), '#1F2924');
assert.equal(ComicReaderAppearance.decode(JSON.stringify(appearance)).cropLeft, 12);
assert.equal(ComicReaderAppearance.decode('{"cropTop":999,"cropBottom":-2,"split":99}').cropTop, 25);
assert.equal(ComicReaderAppearance.decode('null').split, 0);
assert.equal(ReaderRegionStyle.decode('{"left":20,"color":"#123456"}').pixels(2).left, 40);
assert.equal(ReaderRegionStyle.decode('bad').color, '');
const portrait = new ComicPage();
Object.assign(portrait, { key: 'portrait', width: 800, height: 1200, index: 0 });
const spread = new ComicPage();
Object.assign(spread, { key: 'spread', width: 1600, height: 1000, index: 1, url: 'file://original' });
const unknown = new ComicPage();
unknown.key = 'pending'; unknown.index = 2;
const pages = [portrait, spread, unknown];
const views = ComicReaderService.splitViews(pages, 2);
assert.equal(views.length, 4);
assert.equal(views[0], portrait);
assert.deepEqual(Array.from(views.slice(1, 3), p => p.splitSide), [2, 1]);
assert.equal(views[1].index, 1);
assert.equal(views[1].url, spread.url);
assert.equal(spread.splitSide, 0, 'split never mutates cached source pages');
assert.equal(new Set(views.map(p => p.key)).size, views.length);
assert.equal(ComicReaderService.splitViews(pages, 0).length, 3);
const imageSource = fs.readFileSync(path.join(root, 'components/ComicPageImage.ets'), 'utf8');
const start = imageSource.indexOf('  private displayCrop(');
const end = imageSource.indexOf('  private originalRatio()', start);
const scope = { ComicCropRect };
vm.runInNewContext(compile(`class ImageView { ${imageSource.slice(start, end)} } globalThis.ImageView = ImageView;`), scope);
const view = new scope.ImageView(); view.appearance = appearance; view.page = views[1];
const crop = view.displayCrop(new ComicCropRect(0.1, 0.1, 0.8, 0.8));
assert.ok(Math.abs(crop.x - 0.51) < 1e-9);
assert.ok(Math.abs(crop.width - 0.39) < 1e-9, 'manual and automatic crops use the larger edge, not their sum');
assert.ok(Math.abs(crop.height - 0.8) < 1e-9);
console.log('PASS independent day/night preferences, normalization, split ordering/stable keys/original ownership and combined crop geometry');
