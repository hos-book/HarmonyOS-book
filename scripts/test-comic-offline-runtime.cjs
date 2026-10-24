const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/ComicOfflineTranslationService.ets'), 'utf8');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2021 } }).outputText, { exports: exportsObject, require: () => ({}),
  setTimeout, canIUse: () => true, Error });
const service = exportsObject.ComicOfflineTranslationService;
let id, state = 'done', cancelled = false, cancelCalls = 0, payload;
const controller = { async runJavaScript(script) {
  if (script.startsWith('typeof')) return 'true';
  if (script.includes('.start(')) {
    const args = JSON.parse('[' + script.slice(script.indexOf('(') + 1, -1) + ']');
    id = args[0];payload = args[1];return 'true';
  }
  if (script.includes('.snapshot(')) {
    return JSON.stringify(JSON.stringify({ id, status: state,
      translations: payload.map(item => ({id:item.id,text:'Hello world'})) }));
  }
  if (script.includes('cancel(')) { cancelCalls++; return ''; }
  throw Error('Unexpected script');
} };
(async () => {
  service.attach(controller);
  const result = await service.translate([{id:0,text:'你好，世界！'}], 'zh-en', () => true);
  assert.equal(result[0].text,'Hello world');
  state='error';
  await assert.rejects(service.translate([{id:0,text:'你好'}], 'zh-en',()=>true), /offline_failed/);
  assert.equal(cancelCalls,1);
  state='running';
  const pending=service.translate([{id:0,text:'你好'}], 'zh-en',()=>!cancelled);
  await assert.rejects(service.translate([{id:1,text:'再见'}], 'zh-en',()=>true), /offline_busy/);
  cancelled=true;
  await assert.rejects(pending,/cancelled/);
  assert.equal(cancelCalls,2);
  service.detach(controller);
  console.log('offline runtime: result validation, single task limit, failures and cancellation passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
