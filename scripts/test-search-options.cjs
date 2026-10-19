const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/SearchOptions.ets'), 'utf8');
const code = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText;
const exportsObject = {};
vm.runInNewContext(code, { exports: exportsObject });
const { SearchOptions } = exportsObject;
for (let mask = 0; mask < 8; mask++) {
  const flags = [Boolean(mask & 1), Boolean(mask & 2), Boolean(mask & 4)];
  for (const [sourceType, contentType, flag] of [[0, 'text', 0], [3, 'text', 0], [1, 'audio', 1], [2, 'comic', 2]]) {
    const expected = mask === 0 || flags[flag];
    assert.equal(SearchOptions.matchesSourceType(sourceType, ...flags), expected);
    assert.equal(SearchOptions.matchesContentType(contentType, ...flags), expected);
  }
  assert.equal(SearchOptions.matchesSourceType(undefined, ...flags), mask === 0);
}
assert.equal(SearchOptions.matchesSourceType(2, false, false), true);
assert.equal(SearchOptions.matchesContentType('comic', true, false), false);
console.log('PASS: all 8 search type combinations, comic source/result filtering and default compatibility');
