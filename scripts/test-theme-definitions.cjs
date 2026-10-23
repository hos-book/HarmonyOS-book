const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const resources = path.join(__dirname, '../entry/src/main/resources');
const modules = new Map();
const platform = { immersiveMaterial: true };
class Material {
  constructor(options) { this.options = options; }
}
const kit = {
  curves: { cubicBezierCurve: (...values) => values, springMotion: (...values) => values },
  uiMaterial: {
    Material, ImmersiveMaterial: Material,
    ImmersiveStyle: { ULTRA_THIN: 1, THIN: 2, REGULAR: 3, THICK: 4, ULTRA_THICK: 5 }
  }
};
const context = vm.createContext({
  ObservedV2: value => value, Trace: () => {}, $r: id => ({ id }),
  BlurStyle: { BACKGROUND_THIN: 1, BACKGROUND_REGULAR: 2, COMPONENT_ULTRA_THIN: 1,
    COMPONENT_THIN: 2, COMPONENT_REGULAR: 3, COMPONENT_THICK: 4, COMPONENT_ULTRA_THICK: 5 },
  ThemeColorMode: { SYSTEM: 0, DARK: 1 }, AdaptiveColor: { AVERAGE: 0 },
  BlurStyleActivePolicy: { FOLLOWS_WINDOW_ACTIVE_STATE: 0 }
});
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const exports = {};
  modules.set(name, exports);
  // The harness runs pure theme logic; native lazy loading is verified by the SDK build.
  const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8').replace(/^import lazy /gm, 'import ');
  const output = ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
  } }).outputText;
  const localRequire = request => {
    if (request === '@kit.ArkUI') return kit;
    if (request.endsWith('/PlatformCompat')) return { PlatformCompat: platform };
    return load(path.posix.normalize(path.posix.join(path.posix.dirname(name), request)));
  };
  vm.runInContext(`(function(exports, require) {\n${output}\n})`, context,
    { filename: name + '.ets' })(exports, localRequire);
  return exports;
}
const { AppAppearance } = load('model/AppAppearance');
const { ThemeBundles } = load('theme/ThemeBundles');
const { AppTheme, AppColor, HomeTheme, AppMaterial } = load('theme/Theme');
const { ThemeIcons, ThemeIconRole } = load('theme/ThemeIcons');
const { CoverTheme } = load('theme/CoverTheme');
const { ThemeBackgroundKind, ThemeCoverDecoration } = load('model/AppThemeVisual');
const state = AppAppearance.current;
const select = bundle => {
  state.themeBundleId = bundle.id;
  state.accent = bundle.accent;
  state.material = bundle.material;
};
const id = resource => resource.id;

// Preserve the public semantic contract for existing default and paper appearances.
select(ThemeBundles.resolve('default'));
assert.equal(id(AppTheme.Background), 'sys.color.background_primary');
assert.equal(id(AppTheme.TextPrimary), 'sys.color.font_primary');
assert.equal(id(AppColor.Brand), 'app.color.app_brand');
assert.equal(id(HomeTheme.BgWarmTop), 'app.color.home_bg_warm_top');
assert.equal(id(HomeTheme.CardSurface), 'app.color.home_card_surface');
assert.equal(AppTheme.ShowCoverBackdrop, true);
assert.equal(ThemeIcons.resolve(ThemeIconRole.Search), undefined);
assert.equal(id(CoverTheme.playerPlaceholder()), 'app.media.app_icon_legacy');
assert.equal(CoverTheme.decoration(), ThemeCoverDecoration.None);
assert.equal(AppTheme.resolve().visual.background.imageOpacity, 1);
assert.equal(CoverTheme.authorBackground(), '#00000000');

select(ThemeBundles.resolve('paper-study'));
assert.equal(id(AppTheme.Background), 'app.color.theme_paper_background');
assert.equal(id(AppColor.Brand), 'app.color.theme_paper_brand');
assert.equal(id(AppColor.OnBrand), 'app.color.theme_paper_on_brand');
assert.equal(id(HomeTheme.CardSurface), 'app.color.theme_paper_surface');
assert.equal(AppTheme.ShowCoverBackdrop, false);
assert.equal(id(ThemeIcons.resolve(ThemeIconRole.Search)), 'app.media.theme_paper_search');
assert.equal(id(CoverTheme.playerPlaceholder()), 'app.media.theme_paper_cover');
assert.equal(CoverTheme.decoration(), ThemeCoverDecoration.Spine);
assert.equal(AppTheme.resolve().visual.background.imageOpacity, 1);
assert.equal(CoverTheme.authorBackground(), '#00000000');
state.accent = '';
assert.equal(id(AppColor.Brand), 'app.color.app_brand', 'invalid legacy accent keeps original fallback');
assert.equal(id(HomeTheme.Accent), 'app.color.home_accent');
select(ThemeBundles.resolve('paper-study'));

const beforePreview = [state.themeBundleId, state.accent, state.material];
const mist = AppTheme.resolve('mist-blue');
assert.equal(mist.visual.background.kind, ThemeBackgroundKind.Solid);
assert.equal(id(CoverTheme.placeholder(mist.id)), 'app.media.theme_mist_cover');
assert.equal(id(ThemeIcons.resolve(ThemeIconRole.Home, mist.id)), 'app.media.theme_mist_home');
const ink = AppTheme.resolve('ink-wash');
assert.equal(ink.id, 'ink-wash');
assert.equal(ink.visual.background.kind, ThemeBackgroundKind.Image);
assert.equal(id(ink.visual.background.image), 'app.media.theme_ink_background');
assert.equal(ink.visual.background.showCoverBackdrop, false);
assert.equal(ink.visual.background.imageOpacity, 1);
assert.equal(id(CoverTheme.authorBackground(ink.id)), 'app.color.theme_ink_cover_label');
assert.equal(id(CoverTheme.localPlaceholder(ink.id)), 'app.media.theme_ink_local_cover');
assert.equal(CoverTheme.decoration(ink.id), ThemeCoverDecoration.Spine);
for (const role of Object.values(ThemeIconRole).filter(value => typeof value === 'number' && value !== ThemeIconRole.None)) {
  assert.ok(ThemeIcons.resolve(role, ink.id), `ink icon role ${role}`);
}
assert.deepEqual([state.themeBundleId, state.accent, state.material], beforePreview);
assert.equal(ThemeBundles.resolve('removed-theme').id, 'default');
assert.equal(ThemeIcons.resolve(ThemeIconRole.None, mist.id), undefined);
const listed = ThemeBundles.list();
listed.pop();
assert.equal(ThemeBundles.list().length, 4, 'a consumer cannot remove a registry entry');

for (const bundle of ThemeBundles.list()) {
  select(bundle);
  const originalMaterial = AppMaterial.FloatingControl;
  assert.equal(AppMaterial.FloatingControl, originalMaterial, 'reuse material while appearance is unchanged');
  assert.equal(originalMaterial.options.lightEffect.color.id, bundle.visual.colors.brand.id);
  state.accent = '#2255AA';
  assert.equal(AppColor.Brand, '#2255AA');
  assert.equal(AppColor.BrandSoft, '#222255AA');
  assert.equal(HomeTheme.Accent, '#2255AA');
  const customizedMaterial = AppMaterial.FloatingControl;
  assert.notEqual(customizedMaterial, originalMaterial);
  assert.equal(customizedMaterial.options.lightEffect.color, '#2255AA');
  state.material = 2;
  assert.equal(AppMaterial.FloatingControl.options.style, 2);
  assert.equal(AppMaterial.ReaderSheetThick.options.style, 4, 'reader sheets keep fixed thickness');
  assert.equal(AppTheme.Background.id, bundle.visual.colors.background.id);
}
platform.immersiveMaterial = false;
assert.equal(AppMaterial.FloatingControl, undefined);
assert.equal(AppMaterial.ReaderSheetBlur, 4);

// Resource references must ship with the app; each palette must have both color modes.
const tables = {};
for (const mode of ['base', 'dark']) {
  const table = JSON.parse(fs.readFileSync(path.join(resources, mode, 'element/color.json'), 'utf8')).color;
  assert.equal(new Set(table.map(row => row.name)).size, table.length, `${mode}: duplicate colors`);
  tables[mode] = new Map(table.map(row => [row.name, row.value]));
}
const strings = new Set(JSON.parse(fs.readFileSync(path.join(resources, 'base/element/string.json'), 'utf8'))
  .string.map(row => row.name));
function verifyResource(resource) {
  if (!resource || typeof resource !== 'object') return;
  if (resource.id) {
    const [scope, type, name] = resource.id.split('.');
    if (scope !== 'app') return;
    if (type === 'color') {
      assert.ok(tables.base.has(name), `missing base color: ${name}`);
      if (name.startsWith('theme_')) assert.ok(tables.dark.has(name), `missing dark color: ${name}`);
    } else if (type === 'string') {
      assert.ok(strings.has(name), `missing string: ${name}`);
    } else if (type === 'media') {
      const entries = fs.readdirSync(path.join(resources, 'base/media'));
      assert.ok(entries.some(entry => path.parse(entry).name === name), `missing media: ${name}`);
    }
    return;
  }
  if (Object.prototype.toString.call(resource) === '[object Map]') {
    for (const value of resource.values()) verifyResource(value);
  } else {
    for (const value of Object.values(resource)) verifyResource(value);
  }
}
function luminance(hex) {
  const rgb = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}
function contrast(a, b) {
  const first = luminance(a), second = luminance(b);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}
for (const bundle of ThemeBundles.list()) verifyResource(bundle);
for (const asset of ['background', 'cover', 'local_cover']) {
  for (const mode of ['base', 'dark']) {
    const file = path.join(resources, mode, 'media', `theme_ink_${asset}.webp`);
    const data = fs.readFileSync(file);
    assert.equal(data.toString('ascii', 0, 4), 'RIFF');
    assert.equal(data.toString('ascii', 8, 12), 'WEBP');
    assert.ok(data.length > 1000 && data.length < 450 * 1024, `ink ${mode}/${asset}: packaged image size`);
  }
}
for (const mode of ['base', 'dark']) {
  for (const prefix of ['theme_mist_', 'theme_ink_']) {
    const c = key => tables[mode].get(prefix + key);
    for (const [foreground, background] of [['text_primary', 'background'], ['text_secondary', 'background'],
      ['text_tertiary', 'background'], ['text_secondary', 'surface'], ['text_tertiary', 'surface'],
      ['on_brand', 'brand'], ['brand', 'background']]) {
      assert.ok(contrast(c(foreground), c(background)) >= 4.5, `${prefix}${mode}: ${foreground}/${background} contrast`);
    }
  }
}
console.log('PASS: theme resolution, legacy semantic roles, preview isolation, icon fallback, material invalidation, resources, ink assets and palette contrast');
