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
const page = { shelfGroup: 'Old', selectShelfGroup(name) { this.shelfGroup = name; } };
const code = ts.transpileModule(`const save = ${callback};`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 }
}).outputText;
const context = { BookPresentation: model, PreferenceService: {
  async saveBookPresentation(edits, groups) {
    if (fail) throw new Error('write failed');
    model.edits = edits; model.groups = groups;
  }
} };
const save = vm.runInNewContext(`(function() { ${code}; return save; })`, context).call(page);
const deleteStart = pageSource.indexOf('  private async deleteShelfGroup(');
const deleteEnd = pageSource.indexOf('\n  @LocalBuilder', deleteStart);
assert.ok(deleteStart > 0 && deleteEnd > deleteStart);
const deleteCode = ts.transpileModule(`class GroupPage { ${pageSource.slice(deleteStart, deleteEnd)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 }
}).outputText;
const remove = vm.runInNewContext(`${deleteCode}; GroupPage.prototype.deleteShelfGroup`, context).bind(page);
const reorderStart = pageSource.indexOf('      onReorder: async (groups: string[])');
const reorderEnd = pageSource.indexOf('\n      onSave:', reorderStart);
const reorderCode = ts.transpileModule(`const reorder = ${pageSource.slice(reorderStart, reorderEnd).trim()
  .replace(/^onReorder: /, '').replace(/,$/, '')};`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
const reorder = vm.runInNewContext(`(function() { ${reorderCode}; return reorder; })`, context).call(page);
(async () => {
  model.groups = ['Old', 'Other'];
  const book = new Edit();
  Object.assign(book, { bookId: 'book', title: 'Custom title', cover: 'local-cover', group: 'Old' });
  model.edits = [book];
  await reorder(['Other', 'Old']);
  assert.equal(model.groups.join(','), 'Other,Old');
  assert.equal(page.shelfGroup, 'Old');
  assert.equal(model.edits[0].title, 'Custom title');
  await assert.rejects(reorder(['Old', 'Old']));
  fail = true;
  await assert.rejects(reorder(['Old', 'Other']));
  assert.equal(model.groups.join(','), 'Other,Old');
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
  await remove('Empty');
  assert.equal(model.groups.includes('Empty'), false, 'empty groups can also be deleted');
  await remove(model.UNGROUPED);
  assert.equal(model.edits.length, 1);
  console.log('PASS group creation, rename, deletion, metadata preservation, selection, duplicates and failed save');
})().catch(error => { console.error(error); process.exitCode = 1; });
