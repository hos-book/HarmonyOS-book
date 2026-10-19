const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/rulesource/light/upstream/core/book');
async function run(readyAt, maxAttempts, timeoutMs) {
  let now = 0, seq = 0, polls = 0, url = '', result;
  const timers = new Map();
  const timer = (fn, ms) => { const id = ++seq; timers.set(id, {fn, at:now+ms}); return id; };
  const exports = {};
  const js = ts.transpileModule(fs.readFileSync(path.join(root, 'WebBookFetchRuntime.ts'), 'utf8'), {
    compilerOptions: {module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}
  }).outputText;
  vm.runInNewContext(js, {exports, setTimeout:timer, clearTimeout:id=>timers.delete(id),
    require: name => name.endsWith('WebJsAwaitScript') ? {WebJsAwaitScript:{start:()=> 'fixture-poll'}} : {},
    console});
  const runtime = new exports.WebBookFetchRuntime();
  const controller = { stop() {}, loadUrl(value) { url=value; timer(()=>runtime.onPageEnd(controller),0); },
    runJavaScript: async script => script === 'fixture-poll' ? (++polls >= readyAt ? '<img src="page.webp">' : '') :
      JSON.stringify({url, title:'chapter', ready:'complete',html:'<html>waiting</html>'}) };
  runtime.attach(controller);
  runtime.fetch({url:'https://fixture/chapter',method:'GET',headers:{},webJs:'wait',
    webJsAcceptPattern:'\\S',webJsMaxAttempts:maxAttempts,timeoutMs}).then(value=>result=value);
  for (let i=0; !result && i<500; i++) {
    for(let j=0;j<8;j++) await Promise.resolve();
    if(result) break;
    const next=[...timers].sort((a,b)=>a[1].at-b[1].at)[0];
    assert.ok(next, 'request must remain bounded by a timer');
    timers.delete(next[0]); now=next[1].at; next[1].fn();
  }
  assert.ok(result);
  return {result, now, polls};
}
(async()=>{
  const late=await run(25,40,20000);
  assert.equal(late.result.success,true,'image arriving after ten seconds must still be accepted');
  assert.equal(late.polls,25);
  assert.match(late.result.body,/page.webp/);
  const absent=await run(Infinity,3,20000);
  assert.equal(absent.result.success,false,'unmet selector cannot return initial HTML as success');
  assert.equal(absent.result.statusCode,200,'loaded page is retained for challenge/login classification');
  assert.equal(absent.result.body,'<html>waiting</html>');
  assert.match(absent.result.error,/等待条件未满足/);
  const timeout=await run(Infinity,120,3000);
  assert.equal(timeout.result.success,false);
  assert.equal(timeout.now,3000,'requested deadline remains enforced');
  console.log('PASS comic browser wait: late images, unmet selector and hard deadline');
})().catch(error=>{console.error(error);process.exitCode=1;});
