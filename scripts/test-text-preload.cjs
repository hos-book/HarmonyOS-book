const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
let count = 3;
const exportsObject = {};
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/text/TextChapterPreloader.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
vm.runInNewContext(code, { exports: exportsObject, require: () => ({ PreferenceService: { getPreloadChapters: async () => count } }) });
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const loader = new exportsObject.TextChapterPreloader();
  const fetched = [];
  const fetch = async index => { fetched.push(index); };
  loader.start(2, 10, fetch, () => true); await loader.queue;
  assert.deepEqual(fetched, [3, 4, 5]);
  count = 0; fetched.length = 0;
  loader.start(2, 10, fetch, () => true); await loader.queue;
  assert.deepEqual(fetched, []);
  count = 50;
  loader.start(0, 100, fetch, () => true); await loader.queue;
  assert.deepEqual(fetched, Array.from({ length: 50 }, (_, i) => i + 1), 'all 50 configured chapters are fetched');
  fetched.length = 0;
  loader.start(8, 10, fetch, () => true); await loader.queue;
  assert.deepEqual(fetched, [9]);
  fetched.length = 0; count = 3;
  loader.start(0, 10, async i => { fetched.push(i); if (i === 1) throw new Error('one bad chapter'); }, () => true);
  await loader.queue; assert.deepEqual(fetched, [1, 2, 3]);
  fetched.length = 0;
  let finish;
  loader.start(0, 10, async i => { fetched.push(i); await new Promise(resolve => { finish = resolve; }); }, () => true);
  await flush();
  loader.start(5, 10, fetch, () => true);
  await flush(); assert.deepEqual(fetched, [1], 'no overlapping background downloads');
  finish(); await loader.queue;
  assert.deepEqual(fetched, [1, 6, 7, 8], 'old lookahead discarded on chapter change');
  fetched.length = 0;
  loader.start(0, 10, async i => { fetched.push(i); count = 0; }, () => true);
  await loader.queue; assert.deepEqual(fetched, [1], 'disabling stops additional downloads');
  count = 3; fetched.length = 0;
  loader.start(0, 10, fetch, () => true); loader.cancel(); await loader.queue;
  assert.deepEqual(fetched, []);
  console.log('PASS text preload count, disabled, end of book, errors, sequential requests and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
