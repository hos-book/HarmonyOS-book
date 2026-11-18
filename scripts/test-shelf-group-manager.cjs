const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const modelSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/BookPresentation.ets'), 'utf8');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(modelSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsObject, Set });
const { BookPresentation: model, BookPresentationEdit: Edit } = exportsObject;
const pageSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/FavoritePage.ets'), 'utf8');
const start = pageSource.indexOf('      onSave: async (previous: string, name: string)');
const end = pageSource.indexOf('\n    })', start);
assert.ok(start > 0 && end > start);
const callback = pageSource.slice(start, end).trim().replace(/^onSave: /, '');
let fail = false;
const page = { shelfGroup: 'Old', shelfGroups: [],
  shelfDisplaySettings: { showAllShelfGroup: true, showUngroupedShelfGroup: true, shelfCollectionOrder: '[]',
    isShelfGroupVisible(name) { return !JSON.parse(this.hiddenShelfGroups || '[]').includes(name); } },
  selectShelfGroup(name) { this.shelfGroup = name; } };
const code = ts.transpileModule(`const save = ${callback};`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 }
}).outputText;
const context = { BookPresentation: model, PreferenceService: {
  async saveBookPresentation(edits, groups) {
    if (fail) throw new Error('write failed');
    model.edits = edits; model.groups = groups;
  },
  async setShelfCollectionOrder(groups) {
    if (fail) throw new Error('write failed');
    page.shelfDisplaySettings.shelfCollectionOrder = JSON.stringify(groups);
  }
} };
const save = vm.runInNewContext(`(function() { ${code}; return save; })`, context).call(page);
const deleteStart = pageSource.indexOf('  private async deleteShelfGroup(');
const deleteEnd = pageSource.indexOf('\n  @LocalBuilder', deleteStart);
assert.ok(deleteStart > 0 && deleteEnd > deleteStart);
const visibleStart = pageSource.indexOf('  private visibleGroupOptions(');
const visibleEnd = pageSource.indexOf('\n  }', visibleStart) + 4;
assert.ok(visibleStart > 0 && visibleEnd > visibleStart);
const pageMember = signature => {
  const start = pageSource.indexOf(`  ${signature}(`);
  assert.ok(start >= 0, signature);
  return pageSource.slice(start, pageSource.indexOf('\n  }', start) + 4);
};
const deleteCode = ts.transpileModule(`class GroupPage {
  ${pageMember('get shelfGroupOrder')} ${pageMember('private async saveShelfGroupOrder')}
  ${pageSource.slice(deleteStart, deleteEnd)} ${pageSource.slice(visibleStart, visibleEnd)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 }
}).outputText;
const groupPagePrototype = vm.runInNewContext(`${deleteCode}; GroupPage.prototype`, context);
const remove = groupPagePrototype.deleteShelfGroup.bind(page);
page.visibleGroupOptions = groupPagePrototype.visibleGroupOptions.bind(page);
page.saveShelfGroupOrder = groupPagePrototype.saveShelfGroupOrder.bind(page);
Object.defineProperty(page, 'shelfGroupOrder', Object.getOwnPropertyDescriptor(groupPagePrototype, 'shelfGroupOrder'));
const reorderStart = pageSource.indexOf('      onReorder: async (groups: string[])');
const reorderEnd = pageSource.indexOf('\n      onSave:', reorderStart);
const reorderCode = ts.transpileModule(`const reorder = ${pageSource.slice(reorderStart, reorderEnd).trim()
  .replace(/^onReorder: /, '').replace(/,$/, '')};`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
const reorder = vm.runInNewContext(`(function() { ${reorderCode}; return reorder; })`, context).call(page);
(async () => {
  model.groups = ['Old', 'Other'];
  page.shelfGroups = model.groups.slice();
  const book = new Edit();
  Object.assign(book, { bookId: 'book', title: 'Custom title', cover: 'local-cover', group: 'Old' });
  model.edits = [book];
  await reorder(['', 'Other', model.UNGROUPED, 'Old']);
  assert.equal(page.shelfGroupOrder.join(','), `,Other,${model.UNGROUPED},Old`);
  assert.equal(model.groups.join(','), 'Old,Other', 'reordering does not change group definitions');
  assert.equal(page.shelfGroup, 'Old');
  assert.equal(model.edits[0].title, 'Custom title');
  await assert.rejects(reorder(['', 'Old', 'Old', model.UNGROUPED]));
  await assert.rejects(reorder(['Old', '', 'Other', model.UNGROUPED]), /Invalid shelf group order/);
  fail = true;
  await assert.rejects(reorder(['', 'Old', 'Other', model.UNGROUPED]), /write failed/);
  assert.equal(page.shelfGroupOrder.join(','), `,Other,${model.UNGROUPED},Old`);
  fail = false;
  await save('Old', 'Renamed');
  assert.equal(model.edits[0].group, 'Renamed');
  assert.equal(model.edits[0].title, 'Custom title');
  assert.equal(model.edits[0].cover, 'local-cover');
  assert.equal(book.group, 'Old', 'do not mutate old data before persistence');
  assert.equal(page.shelfGroup, 'Renamed');
  await save('', 'Empty');
  assert.equal(model.groups.includes('Empty'), true);
  assert.equal(model.edits.length, 1, 'creating a group does not assign books');
  await assert.rejects(save('Renamed', 'Other'));
  await assert.rejects(save('', model.UNGROUPED));
  fail = true;
  await assert.rejects(save('Renamed', 'Failed'));
  assert.equal(model.edits[0].group, 'Renamed');
  assert.equal(page.shelfGroup, 'Renamed');
  await assert.rejects(remove('Renamed'));
  assert.equal(model.groups.includes('Renamed'), true, 'failed deletion preserves the group');
  assert.equal(model.edits[0].group, 'Renamed');
  fail = false;
  await remove('Renamed');
  assert.equal(model.groups.includes('Renamed'), false);
  assert.equal(model.groups.includes('Other'), true);
  assert.equal(model.edits.length, 1, 'deleting a group keeps book presentation records');
  assert.equal(model.edits[0].group, '');
  assert.equal(model.edits[0].title, 'Custom title');
  assert.equal(model.edits[0].cover, 'local-cover');
  assert.equal(page.shelfGroup, model.UNGROUPED);
  page.shelfDisplaySettings.showUngroupedShelfGroup = false;
  page.shelfGroup = 'Empty';
  await remove('Empty');
  assert.equal(model.groups.includes('Empty'), false, 'empty groups can also be deleted');
  assert.equal(page.shelfGroup, '', 'deleting current group falls back to visible all when ungrouped is hidden');
  await save('', 'HiddenFallback');
  page.shelfDisplaySettings.showAllShelfGroup = false;
  page.shelfGroup = 'HiddenFallback';
  await remove('HiddenFallback');
  assert.equal(page.shelfGroup, 'Other', 'both default groups hidden falls back to remaining visible named group');
  await remove(model.UNGROUPED);
  assert.equal(model.edits.length, 1);
  const preferenceSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/PreferenceService.ets'), 'utf8')
    .replace(/\r\n/g, '\n');
  const member = name => {
    const start = preferenceSource.indexOf(`  static async ${name}(`);
    assert.ok(start >= 0);
    return preferenceSource.slice(start, preferenceSource.indexOf('\n  }', start) + 4);
  };
  const values = new Map();
  const settings = page.shelfDisplaySettings;
  Object.assign(settings, { showAllShelfGroup: true, showUngroupedShelfGroup: true, hiddenShelfGroups: '[]' });
  const store = { getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
    put: async (key, value) => values.set(key, value), flush: async () => { if (fail) throw new Error('disk full'); } };
  const serviceCode = ts.transpileModule(`class PreferenceService {
    static async ensureStore() { return store; }
    ${member('setShelfGroupVisible')} ${member('saveBookPresentation')}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const service = vm.runInNewContext(`${serviceCode}; PreferenceService`, {
    store, GeneralSettings: { current: settings }, BookPresentation: model, JSON, Set,
    emitter: { emit() {} }, EVT_FAVORITES_CHANGED: 'favorites'
  });
  model.groups = ['Other', 'Named']; page.shelfGroups = model.groups.slice();
  const priorOrder = JSON.stringify(['Named', 'Other', '', model.UNGROUPED]);
  values.set('shelf_collection_order', priorOrder);
  settings.shelfCollectionOrder = priorOrder;
  await service.setShelfGroupVisible('', false);
  await service.setShelfGroupVisible(model.UNGROUPED, false);
  await service.setShelfGroupVisible('Other', false);
  assert.equal(page.visibleGroupOptions().join(','), 'Named', 'page options reflect hidden named/default groups');
  await assert.rejects(service.setShelfGroupVisible('Named', false), /Last visible/);
  assert.equal(settings.isShelfGroupVisible('Named'), true);
  await service.setShelfGroupVisible('Other', true);
  fail = true;
  const before = settings.hiddenShelfGroups;
  await assert.rejects(service.setShelfGroupVisible('Other', false));
  assert.equal(settings.hiddenShelfGroups, before, 'failed save preserves live visibility');
  assert.equal(values.get('hidden_shelf_groups'), before, 'failed save rolls back stored visibility');
  fail = false;
  await service.setShelfGroupVisible('Other', false);
  await service.saveBookPresentation(model.edits, ['RenamedHidden', 'Named']);
  page.shelfGroups = model.groups.slice();
  assert.equal(settings.isShelfGroupVisible('RenamedHidden'), false, 'rename preserves disabled state');
  assert.equal(page.shelfGroupOrder.join(','), `,Named,RenamedHidden,${model.UNGROUPED}`, 'rename keeps the shared position');
  await service.saveBookPresentation(model.edits, ['RenamedHidden']);
  assert.equal(settings.showAllShelfGroup, true, 'deleting last enabled named group restores all');
  assert.equal(values.get('show_all_shelf_group'), true);
  const switchStart = pageSource.indexOf('  private async setGroupVisibility(');
  const switchEnd = pageSource.indexOf('\n  }', switchStart) + 4;
  assert.ok(switchStart >= 0 && switchEnd > switchStart);
  const switchCode = ts.transpileModule(`class GroupSwitchPage {
    ${pageSource.slice(switchStart, switchEnd)}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  let resolveSave;
  let rejectSave;
  const pendingService = { setShelfGroupVisible: () => new Promise((resolve, reject) => {
    resolveSave = resolve;
    rejectSave = reject;
  }) };
  const switchPage = vm.runInNewContext(`${switchCode}; new GroupSwitchPage()`, { PreferenceService: pendingService });
  const menu = [];
  Object.assign(switchPage, {
    shelfGroup: 'Named', groupSelectionRevision: 0, savedSelection: '',
    shelfGroupOrder: ['', 'Named'],
    visibleGroupOptions: () => ['', 'Named'],
    groupMenuData: { setItems(groups) { menu.push(Array.from(groups)); } },
    selectShelfGroup(group) { this.shelfGroup = group; this.groupSelectionRevision++; },
    persistShelfGroup(group) { this.savedSelection = group; },
    syncDefaultGroupVisibility() { menu.push(this.visibleGroupOptions()); }
  });
  const saveVisibility = switchPage.setGroupVisibility('Named', false);
  assert.deepEqual(menu.at(-1), [''], 'one click updates the menu while the preference write is pending');
  assert.equal(switchPage.shelfGroup, '', 'the active filter also changes before the write completes');
  rejectSave(new Error('disk full'));
  await assert.rejects(saveVisibility, /disk full/);
  assert.equal(switchPage.shelfGroup, 'Named', 'failed write restores the original filter');
  assert.deepEqual(menu.at(-1), ['', 'Named']);
  const successfulVisibility = switchPage.setGroupVisibility('Named', false);
  switchPage.visibleGroupOptions = () => [''];
  resolveSave();
  await successfulVisibility;
  assert.equal(switchPage.pendingVisibleGroups, undefined);
  assert.equal(switchPage.savedSelection, '');
  assert.deepEqual(menu.at(-1), ['']);

  const managerSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ShelfGroupManager.ets'), 'utf8');
  const managerMember = signature => {
    const start = managerSource.indexOf(`  private ${signature}(`);
    assert.ok(start >= 0, signature);
    return managerSource.slice(start, managerSource.indexOf('\n  }', start) + 4);
  };
  const managerCode = ts.transpileModule(`class Manager {
    ${managerMember('refreshGroups')} ${managerMember('renderGroups')} ${managerMember('async reorder')}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  const manager = vm.runInNewContext(`${managerCode}; new Manager()`);
  let renderedRows = [];
  const drops = [];
  Object.assign(manager, {
    groups: ['', 'Other', 'Named', model.UNGROUPED], // Simulate delayed propagation of the parent's @Param.
    groupData: { setItems(rows) { renderedRows = Array.from(rows); } },
    onBusy() {}, onReorder: async groups => drops.push(Array.from(groups))
  });
  manager.refreshGroups();
  await manager.reorder(2, 0);
  assert.deepEqual(renderedRows, [model.UNGROUPED, 'Other', 'Named'], 'saved order stays visible before @Param catches up');
  await manager.reorder(0, 1);
  assert.deepEqual(drops.at(-1), ['', 'Other', model.UNGROUPED, 'Named'], 'next drag starts from the order on screen');
  manager.onReorder = async () => { throw new Error('disk full'); };
  await manager.reorder(1, 2);
  assert.deepEqual(renderedRows, ['Other', model.UNGROUPED, 'Named'], 'failure restores the preceding visible order');
  assert.equal(manager.failed, true);
  console.log('PASS all group switches, last-enabled guard, live filtering, failure rollback, rename and deletion fallback');
  console.log('PASS group creation, rename, deletion, metadata preservation, selection, duplicates and failed save');
  console.log('PASS immediate manager reorder, consecutive drags and delayed parent update');
})().catch(error => { console.error(error); process.exitCode = 1; });
