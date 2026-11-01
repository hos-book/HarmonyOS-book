const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const exportsRef = {};
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/HomeCategoryOverviewDataSource.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
vm.runInNewContext(code, { exports: exportsRef, Map, Set, JSON, require: () => ({}) });
const { HomeCategoryOverviewDataSource: Groups } = exportsRef;
const category = (name, url, group = '') => ({ name, url, group });
const categories = [
  category('全部 · 古代言情', '/ancient', '小说'), category('经商种田', '/farm', '小说'),
  category('古代情缘', '/love', '小说'), category('全部', '/comic', '漫画'),
  category('穿越奇情', '/travel', '小说'), category('全部·现代言情', '/modern', '小说'),
  category('都市情缘', '/city', '小说'), category('热血', '/hot', '漫画')
];
let rows = Groups.group(categories);
assert.deepEqual(Array.from(rows, row => row.title), ['古代言情', '漫画', '现代言情']);
assert.deepEqual(Array.from(rows[0].categories, item => item.label), ['', '经商种田', '古代情缘', '穿越奇情']);
assert.equal(rows[0].categories[0].category, categories[0], 'all tag retains the original parent URL');
assert.deepEqual(Array.from(rows[1].categories, item => item.label), ['全部', '热血']);
assert.equal(rows.reduce((n, row) => n + row.categories.length, 0), categories.length, 'no categories lost');
rows = Groups.group(categories, '古代言情');
assert.equal(rows.length, 1); assert.equal(rows[0].categories.length, 4, 'parent search includes its children');
rows = Groups.group(categories, '穿越');
assert.equal(rows[0].title, '古代言情'); assert.equal(rows[0].categories[0].category.url, '/travel');
assert.equal(Groups.group(categories, '不存在').length, 0);
rows = Groups.group([category('全部小说', '/all'), category('科幻', '/sf'), category('玄幻', '/fantasy')]);
assert.equal(rows.length, 1); assert.equal(rows[0].categories.length, 3, 'plain sources retain their menu without guessing hierarchy');
const sameUrl = [category('全部', '/same', '小说'), category('全部', '/same', '听书')];
assert.equal(Groups.group(sameUrl).length, 2, 'same URLs in different channels do not merge');
const source = new Groups(); let reloads = 0;
source.registerDataChangeListener({ onDataReloaded() { reloads++; } });
source.setCategories(categories); source.setCategories(categories, '现代');
assert.equal(source.totalCount(), 1); assert.equal(reloads, 2);
console.log('PASS grouped hierarchy, parent links, cross-channel order, search, ordinary sources and reloads');
