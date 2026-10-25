// Exercise the real local service; unexpected platform/network imports fail immediately.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const resources = JSON.parse(fs.readFileSync(path.join(__dirname, '../entry/src/main/resources/base/element/daily_quote_array.json')));
const lines = resources.strarray.flatMap(group => group.value.map(item => item.value));
assert.equal(resources.strarray.length, 5);
for (const group of resources.strarray) {
  assert.ok(group.value.reduce((total, item) => total + Buffer.byteLength(item.value, 'utf8'), 0) < 65535);
}
assert.equal(resources.strarray[0].name, 'daily_quote_poems');
assert.equal(lines.length, 1365);
assert.equal(new Set(lines.map(line => line.split('|')[0])).size, 1365, 'no duplicate excerpts');
for (const line of lines) {
  const fields = line.split('|');
  assert.equal(fields.length, 3);
  assert.ok(fields.every(field => field.trim().length > 0), 'text, author and title required');
}
function scenario(data = lines, seed = 42, randomOverride) {
  const modules = new Map();
  let reads = 0;
  const seededMath = Object.create(Math);
  seededMath.random = randomOverride || (() => {
    seed = (Math.imul(1664525, seed) + 1013904223) >>> 0;
    return seed / 4294967296;
  });
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const filename = path.join(__dirname, '../entry/src/main/ets', relative + '.ets');
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const module = { exports: {} };
    vm.runInNewContext(code, { module, exports: module.exports, Math: seededMath,
      $r: name => ({ id: name }),
      require: name => {
        if (name === '../model/DailyQuote') return load('model/DailyQuote');
        throw new Error('Unexpected dependency: ' + name);
      }
    }, { filename });
    modules.set(relative, module.exports);
    return module.exports;
  }
  return { service: load('service/DailyQuoteService').DailyQuoteService,
    context: { resourceManager: { getStringArrayValueSync: id => {
      reads++;
      const group = resources.strarray.findIndex(item => 'app.strarray.' + item.name === id);
      assert.ok(group >= 0, 'resource must exist');
      return data.slice(group * 300, (group + 1) * 300);
    } } },
    reads: () => reads };
}
const local = scenario();
const quotes = Array.from({ length: lines.length }, () => local.service.next(local.context));
assert.equal(new Set(quotes.map(quote => quote.text)).size, 1365, 'no repeats within a complete cycle');
assert.equal(local.reads(), 5, 'read each bundled resource once');
for (const quote of quotes) assert.ok(lines.includes(`${quote.text}|${quote.author}|${quote.source}`));
const nextCycle = Array.from({ length: lines.length }, () => local.service.next(local.context));
assert.equal(new Set(nextCycle.map(quote => quote.text)).size, 1365);
assert.notEqual(nextCycle[0].text, quotes[quotes.length - 1].text, 'no immediate repeat across cycles');
assert.notDeepEqual(quotes.map(q => q.text), lines.map(line => line.split('|')[0]), 'shuffle the resource order');
assert.notDeepEqual(nextCycle.map(q => q.text), quotes.map(q => q.text), 'reshuffle each cycle');
quotes[0].text = 'mutated';
for (let i = 0; i < lines.length; i++) assert.ok(lines.includes((q => `${q.text}|${q.author}|${q.source}`)(local.service.next(local.context))));
const restart = scenario(lines, 123);
assert.notEqual(restart.service.next(restart.context).text, nextCycle[0].text, 'new process uses a fresh random order');
const choices = [0, 0.999, 0];
const boundary = scenario(lines.slice(0, 2), 0, () => choices.shift() ?? 0);
boundary.service.next(boundary.context);
const last = boundary.service.next(boundary.context);
assert.notEqual(boundary.service.next(boundary.context).text, last.text, 'repair a forced cycle-boundary collision');
const malformed = scenario(['missing', 'text||title', lines[0]]);
assert.equal(malformed.service.next(malformed.context).text, lines[0].split('|')[0]);
const empty = scenario([]);
assert.throws(() => empty.service.next(empty.context), /Missing bundled poems/);
console.log('PASS: 1365 unique poems, attribution, offline shuffle, cycle uniqueness, boundary collision, restart, resource validation');
