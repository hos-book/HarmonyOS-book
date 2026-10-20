// Invoked by the shared engine harness; real host/runner, VM stands in for native taskpool QuickJS.
const assert = require('node:assert/strict');
const vm = require('node:vm');
module.exports = async ({load,prefix,runtime,parser,codec,engine,fixtures,states}) => {
  let nativeCalls=0;
  runtime.host.evaluateNative = async (script, _source, timeout) => {
    nativeCalls++;
    const start=Date.now();
    const value=await vm.runInNewContext(script,{}, {timeout});
    return JSON.stringify({value,elapsedMs:Date.now()-start});
  };
  const {LightNativeScripts}=load(prefix+'LightNativeScripts');
  const {BookSource}=load(prefix+'upstream/model/data/Book');
  const source=new BookSource();source.bookSourceUrl='https://native-js.test';
  const ports=LightNativeScripts.create(source,{
    jsonPath:(r,p)=>[r[p.slice(2)]], select:()=>[],digest:(_a,t)=>'hash:'+t,
    cookie:()=>'', crypto:(_n,a)=>'hash:'+a[0]
  });
  const code='let counter=0; const title=(s)=>s.toUpperCase(); function plus(n){counter++;return native.sum([n,2]);}';
  assert.equal(await ports.evaluateExpression(code,'','title(item.name)',{item:{name:'hello'}},false,()=>false),'HELLO');
  assert.equal(await ports.evaluateExpression(code,'','{{title(key)}}',{key:'abc'},true,()=>false),'ABC');
  assert.equal(await ports.evaluateExpression('function hash(s){return native.md5(s)}','','hash(key)',{key:'abc'},false,()=>false),'hash:abc');
  const opts={cpuMs:2000,wallMs:10000,cancelled:()=>false};
  let calls=[];
  const stage=ports.scriptEngine('const go=async function(){var x=http.get("https://native-js.test/a").json();vars.set("n",x.n);return {n:x.n};}');
  const result=await stage.run('go',{},async (name,args)=>{
    calls.push(name);return name==='@http'?{ok:true,status:200,body:'{"n":7}'}:null;
  },opts);
  assert.equal(result.n,7);assert.deepEqual(calls,['@http','@varsSet']);
  calls=[];
  const caught=ports.scriptEngine('function go(){try{http.get("https://native-js.test/a")}catch(e){};return vars.get("x")}');
  assert.equal(await caught.run('go',{},(n)=>{calls.push(n);if(n==='@http')throw Error('network');return 'ok';},opts),'ok');
  assert.deepEqual(calls,['@http','@varsGet']);
  const isolated=ports.scriptEngine('var n=0;function go(){return ++n}');
  assert.equal(await isolated.run('go',{},()=>null,opts),1);
  assert.equal(await isolated.run('go',{},()=>null,opts),1);
  await assert.rejects(isolated.run('go',{},()=>null,{...opts,cancelled:()=>true}),/已取消/);
  let cancelled=false;
  const waiting=ports.scriptEngine('function go(){return http.get("https://native-js.test/wait")}')
    .run('go',{},()=>new Promise(()=>{}),{...opts,cancelled:()=>cancelled});
  setTimeout(()=>{cancelled=true;},10);
  await assert.rejects(waiting,/已取消/);
  await assert.rejects(ports.scriptEngine('function go(){while(true){}}').run('go',{},()=>null,{...opts,cpuMs:30}),/timed out|超时|时间/);
  const native={sourceFormat:'native',version:1,name:'JS Host',url:source.bookSourceUrl,
    js:'function upper(s){return s.toUpperCase()} function search(ctx){var r=http.get("https://native-js.test/search").json();vars.set("last",ctx.key);return r;}'+
      'function detail(){return {name:"BOOK",tocUrl:"/toc"}} function toc(){return [{title:"One",url:"/chapter"}]} '+
      'function content(){return "Native JS chapter"} function choices(){return ["a","b"]} '+
      'function blockedOptions(){throw Error("unrelated option must not run")} '+
      'function action(){ui.toast("hello");ui.refreshExplore();return "done"}',
    vars:[{key:'line',label:'Line',default:'a',options:['a'],optionsScript:'choices'},
      {key:'server',label:'Server',default:'saved',optionsScript:'blockedOptions'}],
    actions:[{label:'Action',script:'action'}],
    search:{script:'search',fields:{name:'=upper(item.name)',bookUrl:'$.bookUrl'}},
    detail:{script:'detail'},toc:{script:'toc'},content:{script:'content'}};
  fixtures.set(source.bookSourceUrl+'/search',JSON.stringify([{name:'book',bookUrl:'/book'}]));
  const local=parser.parse(JSON.stringify(native)).sources[0];assert.ok(local);
  local.definition=codec.stringify(local);
  const books=JSON.parse(await engine.search(JSON.stringify(local),'book',1));
  assert.ok(books.length,JSON.stringify({local,state:states.get(source.bookSourceUrl)}));
  assert.equal(books[0].name,'BOOK');assert.equal(books[0].bookUrl,source.bookSourceUrl+'/book');
  assert.ok(states.get(source.bookSourceUrl).includes('book'));
  const detail=JSON.parse(await engine.detail(JSON.stringify(local),books[0].bookUrl,'{}'));
  const toc=JSON.parse(await engine.toc(JSON.stringify(local),detail.tocUrl,JSON.stringify({bookUrl:books[0].bookUrl})));
  assert.equal(toc[0].url,source.bookSourceUrl+'/chapter');
  assert.equal(JSON.parse(await engine.content(JSON.stringify(local),toc[0].url,'{}')).content,'Native JS chapter');
  nativeCalls=0;
  const panel=JSON.parse(await engine.panel(JSON.stringify(local),true,'Save','Login'));
  const select=panel.controls.find(c=>c.id==='light-native-var:line');
  assert.equal(select.type,'dynamic-select');assert.equal(nativeCalls,0,'opening a panel must not probe option servers');
  assert.deepEqual(JSON.parse(await engine.panelOptions(JSON.stringify(local),select.id)),['a','b']);
  assert.equal(nativeCalls,1,'only the selected optionsScript runs');
  await engine.panelAction(JSON.stringify(local),JSON.stringify({...select,action:'light-native-set:line',value:'b'}),'[]');
  assert.equal(JSON.parse(await engine.panel(JSON.stringify(local),true,'Save','Login')).controls.find(c=>c.id===select.id).value,'b');
  let toast='',refresh='';runtime.host.toast=m=>{toast=m};runtime.host.refreshExplore=async u=>{refresh=u};
  await engine.panelAction(JSON.stringify(local),JSON.stringify({action:'light-native-action:0'}),'[]');
  assert.equal(toast,'hello');assert.equal(refresh,source.bookSourceUrl);
  delete runtime.host.toast;delete runtime.host.refreshExplore;
  const menuSource={...native,url:'https://native-menu.test',actions:[],
    explore:{list:'$.data[*]',fields:{name:'$.name',bookUrl:'$.bookUrl'},
      menus:Array.from({length:363},(_,i)=>({title:'Category '+i,url:'https://native-menu.test/books?page={{page}}'})),
      dynamicMenus:{url:'https://native-menu.test/categories',list:'$.data[*]',title:'$.title',
        target:"= $.url ? replaceText(absUrl($.url, baseUrl), '{{page}}', str(page)) : ''"}}};
  fixtures.set(menuSource.url+'/categories',JSON.stringify({data:Array.from({length:400},(_,i)=>({title:'Dynamic '+i,url:'/books/'+i+'?page={{page}}'}))}));
  const menuReport=parser.parse(JSON.stringify(menuSource));const menuLocal=menuReport.sources[0];
  assert.ok(menuLocal,JSON.stringify(menuReport));menuLocal.definition=codec.stringify(menuLocal);
  nativeCalls=0;
  const menus=JSON.parse(await engine.panel(JSON.stringify(menuLocal),false,'Save','Login'));
  assert.equal(menus.entries.length,763);assert.equal(nativeCalls,0,'plain static/dynamic menus with a JS library must not start QuickJS');
  // A real discovery page combines JS functions with many $.field reads. Crossing
  // the host for JSONPath would replay a batch hundreds of times even after batching.
  const batchSource={...native,url:'https://native-batch.test',actions:[],
    js:'function jsUpper(s){return s.toUpperCase()} function address(id){return "/book/"+id} '+
      'function jsNumber(n){return native.sum([n,1])}',
    explore:{list:'$.data[*]',fields:{name:'=jsUpper($.name)',author:'$.author',
      intro:'=jsUpper(item.intro)',kind:'=str(jsNumber(index))',wordCount:'=str(jsNumber($.count))',
      bookUrl:'=address($.id)'},menus:[{title:'All',url:'/books'}]},
    detail:{fields:{name:'=jsUpper($.name)',intro:'=jsUpper($.intro)',tocUrl:'$.tocUrl'}}};
  fixtures.set(batchSource.url+'/books',JSON.stringify({data:Array.from({length:30},(_,i)=>({
    name:'book '+i,author:'author '+i,intro:'intro '+i,id:i,count:i*10}))}));
  fixtures.set(batchSource.url+'/detail',JSON.stringify({name:'book 0',intro:'detail',tocUrl:'/toc'}));
  const batchLocal=parser.parse(JSON.stringify(batchSource)).sources[0];assert.ok(batchLocal);
  batchLocal.definition=codec.stringify(batchLocal);
  const previousGetSource=runtime.host.getSource;
  runtime.host.getSource=async url=>url===batchSource.url?JSON.stringify(batchLocal):'';
  const batchMenu=JSON.parse(await engine.panel(JSON.stringify(batchLocal),false,'Save','Login')).entries[0];
  nativeCalls=0;
  const batchBooks=JSON.parse(await engine.explore(JSON.stringify(batchLocal),batchMenu.url,1,30)).books;
  assert.equal(batchBooks.length,30);assert.equal(nativeCalls,2,'30 books with JS/JSONPath fields use two bounded tasks');
  for(let i=0;i<30;i++) {
    assert.equal(batchBooks[i].name,'BOOK '+i);assert.equal(batchBooks[i].author,'author '+i);
    assert.equal(batchBooks[i].intro,'INTRO '+i);assert.equal(batchBooks[i].kind,String(i+1));
    assert.equal(batchBooks[i].wordCount,String(i*10+1));assert.equal(batchBooks[i].bookUrl,batchSource.url+'/book/'+i);
  }
  nativeCalls=0;
  const batchDetail=JSON.parse(await engine.detail(JSON.stringify(batchLocal),batchSource.url+'/detail','{}'));
  assert.equal(batchDetail.name,'BOOK 0');assert.equal(batchDetail.intro,'DETAIL');
  assert.equal(nativeCalls,1,'all JS detail fields share one bounded task');
  runtime.host.getSource=previousGetSource;
  const {NativeSourceInteraction}=load(prefix+'upstream/core/nativesource/NativeSourceInteraction');
  const handler=NativeSourceInteraction.handler();
  await runtime.run(source,local,async()=>{
  runtime.host.browse=async()=>'<html>verified</html>';
  assert.equal((await handler.openBrowser({sourceUrl:source.bookSourceUrl,sourceName:'JS Host',url:source.bookSourceUrl},true)).body,'<html>verified</html>');
  assert.match((await handler.openBrowser({sourceUrl:source.bookSourceUrl,url:'http://native-js.test'},true)).error,/HTTPS/);
  runtime.host.browse=async()=>{throw Error('cancelled')};
  assert.match((await handler.openBrowser({sourceUrl:source.bookSourceUrl,url:source.bookSourceUrl},true)).error,/cancelled/);
  delete runtime.host.browse;
  });
  console.log('PASS: native JS expression/template/crypto, async stages, exactly-once host effects, isolation, cancellation, timeout and search persistence');
};
