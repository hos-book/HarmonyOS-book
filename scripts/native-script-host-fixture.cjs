// Node worker stands in for taskpool/NAPI; the production JSON mailbox is loaded unchanged.
// Device tests are required for QuickJS interrupt timing and the native callback ABI.
const {Worker,isMainThread,parentPort,workerData}=require('node:worker_threads');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

function loadChannel() {
  const ts=require(path.join(process.env.DEVECO_HOME,'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
  const filename=path.join(__dirname,'../entry/src/main/ets/service/rulesource/LocalRuleQuickJsHostChannel.ets');
  const output=ts.transpileModule(fs.readFileSync(filename,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText;
  const module={exports:{}};
  vm.runInNewContext(output,{module,exports:module.exports,SharedArrayBuffer,Int32Array,Uint8Array,Atomics,Date,Error,
    require:()=>({taskpool:{Task:{sendData:(...args)=>parentPort.postMessage({call:args})}},util:{
      TextEncoder:class {encodeInto(s){return new TextEncoder().encode(s)}},
      TextDecoder:{create:()=>({decodeToString:b=>new TextDecoder().decode(b)})}
    }})},{filename});
  return module.exports.LocalRuleQuickJsHostChannel;
}

if(!isMainThread) {
  const Channel=loadChannel();
  let calls=0,bytes=0,exhausted=false;
  const host=(name,payload)=>{
    if(++calls>4096 || name.length>128 || Buffer.byteLength(payload)>4*1024*1024) {
      exhausted=true;throw Error('Script host input budget exceeded');
    }
    bytes+=Buffer.byteLength(payload);
    const reply=Channel.call(workerData.control,workerData.response,name,payload);
    bytes+=Buffer.byteLength(reply);
    if(bytes>64*1024*1024){exhausted=true;throw Error('Script host byte budget exceeded');}
    return reply;
  };
  parentPort.postMessage({ready:true});
  Promise.resolve().then(()=>vm.runInNewContext(workerData.script,{__boundedHost:host}))
    .then(value=>{
      if(exhausted)throw Error('Script host budget exceeded');
      parentPort.postMessage({value});
    }).catch(error=>parentPort.postMessage({error:error.message}));
} else {
  module.exports=function createNativeHostEvaluator(onTask=()=>{}) {
    const Channel=loadChannel();
    return async(script,source,timeout,handler,check)=>{
      onTask();check();
      const channel=new Channel(handler,check);
      const worker=new Worker(__filename,{workerData:{script,control:channel.control,response:channel.response}});
      let started=0,waiting=0,waited=0,closed=false,timer;
      try {
        return await new Promise((resolve,reject)=>{
          timer=setInterval(()=>{
            try {
              check();
              if(started && Date.now()-started-waited-(waiting?Date.now()-waiting:0)>timeout)
                throw Error('Script execution timed out');
            } catch(e){reject(e);}
          },5);
          worker.on('error',reject);
          worker.on('exit',code=>{if(!closed)reject(Error('Worker exited '+code));});
          worker.on('message',async m=>{
            if(closed)return;
            if(m.ready){started=Date.now();return;}
            if(m.call){
              waiting=Date.now();
              try {await channel.answer(...m.call);if(channel.error)reject(Error(channel.error));}
              catch(e){reject(e);}
              finally {waited+=Date.now()-waiting;waiting=0;}
            } else if(m.error)reject(Error(m.error));else resolve(m.value);
          });
        });
      } finally {closed=true;clearInterval(timer);channel.close();await worker.terminate();}
    };
  };
}
