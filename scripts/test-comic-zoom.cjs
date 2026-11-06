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
const contained = Transform.contain(180, 720, 360, 720);
assert.equal(contained.x, 90, 'fit-screen long page has centered side margins');
assert.equal(contained.y, 0);
const containZoom = contained.zoom(3, 180, 360);
assert.equal(containZoom.x, -90, 'zoom can expand across the former side margins');
assert.equal(containZoom.pan(9999, 9999).x, 0);
assert.equal(containZoom.pan(-9999, -9999).x, -180);
assert.equal(containZoom.zoom(1, 180, 360).x, 90, 'shrinking restores centered fit-screen placement');
const wideFit = Transform.contain(360, 90, 360, 720).zoom(4, 180, 360);
assert.equal(wideFit.pan(0, 9999).y, 180, 'short images remain vertically centered until taller than viewport');
console.log('PASS inline comic pinch: focal point, visible-window pan bounds, long/landscape pages, reset and 1–4x limits');

const small = Transform.fit(180, 270, 0, 270, 600);
assert.equal(small.x, 210, 'native-size image starts centered in the reading window');
assert.equal(small.zoom(2, 300, 135).x, 120, 'small image stays centered while narrower than the window');
const smallZoom = small.zoom(4, 300, 135);
assert.equal(smallZoom.pan(9999, 0).x, 0);
assert.equal(smallZoom.pan(-9999, 0).x, -120, 'zoom can use the entire window beyond the original image width');
assert.equal(smallZoom.zoom(1, 300, 135).x, 210, 'reset restores native-size centering');

// Exercise the actual display sizing at high density, including full-width tablet layouts.
const root = path.resolve(__dirname, '../entry/src/main/ets');
const imageSource = fs.readFileSync(path.join(root, 'components/ComicPageImage.ets'), 'utf8');
const readerSource = fs.readFileSync(path.join(root, 'pages/ComicReaderPage.ets'), 'utf8');
const preferenceSource = fs.readFileSync(path.join(root, 'service/PreferenceService.ets'), 'utf8');
function method(text, name) {
  const match = text.match(new RegExp(`  (?:private |static )(?:async )?${name}\\([^]*?\\n  }`));
  assert.ok(match, name);
  return match[0];
}
const compile = code => ts.transpileModule(code, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
const layoutScope = { exports: {}, ComicZoomTransform: Transform };
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'utils/AdaptiveLayout.ets'), 'utf8')), layoutScope);
layoutScope.AdaptiveLayout = layoutScope.exports.AdaptiveLayout;
vm.runInNewContext(compile(`class Reader { ${method(readerSource, 'imageWidth')} }
  class ImageLayout { ${['imageRatio', 'fitsViewport', 'imageWidth', 'imageHeight', 'contentHeight']
    .map(name => method(imageSource, name)).join('\n')} }
  globalThis.Reader = Reader; globalThis.ImageLayout = ImageLayout;`), layoutScope);
const layoutReader = new layoutScope.Reader();
Object.assign(layoutReader, { widthVp: 1200, leftSafe: 20, rightSafe: 20, displayMode: 0 });
assert.equal(layoutReader.imageWidth(), 760, 'default preserves the existing comfortable width');
layoutReader.displayMode = 1;
assert.equal(layoutReader.imageWidth(), 1160, 'full width removes the text gutter while preserving safe areas');
const layoutImage = new layoutScope.ImageLayout();
Object.assign(layoutImage, { pageWidth: 1160, pageHeight: 600, page: { width: 1200, height: 1800 },
  ratio: 0, displayMode: 1, paged: false, fitScreen: true,
  getUIContext: () => ({ vp2px: vp => vp * 2, px2vp: px => px / 2 }) });
assert.equal(layoutImage.imageWidth(), 1160);
assert.equal(layoutImage.imageHeight(), 1740, 'fill-width keeps all of a tall image without stretching or cropping');
assert.equal(layoutImage.fitsViewport(), false, 'full width overrides legacy fit-screen pagination');
layoutImage.displayMode = 2;
assert.equal(layoutImage.imageWidth(), 400);
assert.equal(layoutImage.imageHeight(), 600, 'complete display fits both window dimensions');
layoutImage.displayMode = 3;
assert.equal(layoutImage.imageWidth(), 600, 'native pixels are converted to vp before limiting enlargement');
assert.equal(layoutImage.imageHeight(), 900, 'continuous native-size mode retains all of the long image');
layoutImage.paged = true;
assert.equal(layoutImage.imageHeight(), 600, 'paged native-size mode shrinks an oversized page to fit');
layoutImage.page = { width: 300, height: 150 };
assert.equal(layoutImage.imageWidth(), 150, 'small source image is never enlarged');
assert.equal(layoutImage.imageHeight(), 75);
assert.equal(layoutImage.contentHeight(), 600, 'paged small image has room to center vertically');
layoutImage.paged = false; layoutImage.displayMode = 2;
assert.equal(layoutImage.imageWidth(), 1160);
assert.equal(layoutImage.imageHeight(), 580);
assert.equal(layoutImage.contentHeight(), 580, 'continuous complete display does not insert blank page-sized gaps');

(async () => {
  const saved = new Map();
  let fail = false;
  const prefScope = { store: { getSync: (key, fallback) => saved.has(key) ? saved.get(key) : fallback,
    put: async (key, value) => saved.set(key, value), flush: async () => { if (fail) throw new Error('disk full'); } } };
  const preferenceSession = () => {
    vm.runInNewContext(compile(`(() => { class PreferenceService {
      static async ensureStore() { return store; }
      ${['getComicDisplayMode', 'setComicDisplayMode'].map(name => method(preferenceSource, name)).join('\n')}
      ${preferenceSource.match(/  private static async saveComicPreference\([^]*?\n  }/)[0]}
    } globalThis.PreferenceService = PreferenceService; })();`), prefScope);
    return prefScope.PreferenceService;
  };
  assert.equal(await preferenceSession().getComicDisplayMode(), 0, 'existing users keep their original layout');
  for (const mode of [1, 2, 3, 0]) {
    await preferenceSession().setComicDisplayMode(mode);
    assert.equal(await preferenceSession().getComicDisplayMode(), mode, 'selection survives reopening');
  }
  await assert.rejects(preferenceSession().setComicDisplayMode(99));
  await preferenceSession().setComicDisplayMode(1);
  fail = true;
  await assert.rejects(preferenceSession().setComicDisplayMode(2));
  assert.equal(await preferenceSession().getComicDisplayMode(), 1, 'failed save retains the previous selection');
  console.log('PASS comic display: safe-area width, four modes, density, aspect ratio, small-image zoom and preference rollback');
})().catch(error => { console.error(error); process.exitCode = 1; });
