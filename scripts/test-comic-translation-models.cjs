const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'comic-model-test-'));
const context = { filesDir: path.join(root, 'files'), cacheDir: path.join(root, 'cache') };
fs.mkdirSync(context.cacheDir, { recursive: true });
const body = Buffer.from('pinned model fixture');
const assets = ['ja-en', 'ko-en', 'en-zh', 'zh-en'].map(model => ({model, revision:'revision', path:'config.json',
  size:body.length, sha256:crypto.createHash('sha256').update(body).digest('hex')}));
let calls = 0, mode = 'success';
const fileIo = { OpenMode:{READ_ONLY:1, READ_WRITE:2, CREATE:4, TRUNC:8}, accessSync:fs.existsSync, statSync:fs.statSync,
  openSync:(p,mode)=>({fd:fs.openSync(p,mode===1?'r':'w')}), writeSync:(fd,b)=>fs.writeSync(fd,new Uint8Array(b)),
  closeSync:f=>fs.closeSync(f.fd), read:async(fd,b,o)=>fs.readSync(fd,new Uint8Array(b),0,b.byteLength,o.offset),
  unlinkSync:fs.unlinkSync, mkdirSync:(p)=>{if(fs.existsSync(p))throw Error('File exists');fs.mkdirSync(p,{recursive:true});}, renameSync:fs.renameSync };
const http = {RequestMethod:{GET:'GET'},createHttp() {
  const handlers=new Map();let rejectRequest;let timer;
  return {on:(key,fn)=>handlers.set(key,fn),destroy:()=>{clearTimeout(timer);rejectRequest?.(Error('destroyed'));},
    requestInStream:()=>{calls++;return new Promise((resolve,reject)=>{
      rejectRequest=reject;timer=setTimeout(()=>{
        if(mode==='hang')return;
        const data=mode==='corrupt'?Buffer.alloc(body.length):body;
        handlers.get('dataReceive')?.(Uint8Array.from(data).buffer);resolve(200);
      },10);
    });}};
}};
const exported={};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/service/ComicTranslationModelService.ets'),'utf8'),
  {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{
  exports:exported, setTimeout,setInterval,clearInterval, Uint8Array,ArrayBuffer,
  require:name=>name.includes('NetworkKit')?{http}:name.includes('CoreFile')?{fileIo}:name.includes('Crypto')?
    {cryptoFramework:{createMd:()=>{const hash=crypto.createHash('sha256');return {update:async b=>hash.update(b.data),digest:async()=>({data:hash.digest()})};}}}:
    {COMIC_MODEL_ASSETS:assets}
});
const service=exported.ComicTranslationModelService;
(async()=>{
  assert.equal(await service.missingBytes(context,'ja-zh',()=>true),body.length*2);
  await service.ensure(context,'ja-zh',()=>true,()=>{});
  assert.equal(calls,2);
  assert.equal(await service.missingBytes(context,'ja-zh',()=>true),0);
  await service.ensure(context,'ko-zh',()=>true,()=>{});
  assert.equal(calls,3,'shared en-zh must not download twice');
  assert.equal(service.localPath(context,'models/ja-en/../../other'),'');
  mode='corrupt';await assert.rejects(service.ensure(context,'zh-en',()=>true,()=>{}),/invalid/);
  assert.equal(service.localPath(context,'models/zh-en/config.json'),'');
  mode='hang';let active=true;
  const pending=service.ensure(context,'zh-en',()=>active,()=>{});
  await assert.rejects(service.ensure(context,'zh-en',()=>true,()=>{}),/busy/);
  setTimeout(()=>active=false,20);
  await assert.rejects(pending,/cancelled/);
  mode='success';await service.ensure(context,'zh-en',()=>true,()=>{});
  assert.equal(await service.missingBytes(context,'zh-en',()=>true),0);
  console.log('model download: verified persistence, shared assets, corruption, cancellation, retry and concurrency passed');
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>fs.rmSync(root,{recursive:true,force:true}));
