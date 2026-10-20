// Exercise the imported engine and its real stage replay/JSON boundary with deterministic HTTP.
// Node VM replaces native QuickJS here; native timeout and device behavior require device checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const prefix = 'service/rulesource/light/';
const cache = new Map();
const states = new Map();
const fixtures = new Map();
const requests = [];
const storage = new Map();
const comicDisk = new Map();
const comicFiles = new Set();
let liveOrigin = '';
class FakeHttpClient {
  cancelAll() {}
  setHeaders() {}
  async execute(request) {
    requests.push(request);
    if (liveOrigin && new URL(request.url).origin === liveOrigin) {
      const method = request.method || 'GET';
      const response = await fetch(request.url, {method,body:['GET','HEAD'].includes(method) ? undefined : request.body,
        headers:request.headers,signal:AbortSignal.timeout(20000)});
      const body = await response.text();
      if (body.length > 2 * 1024 * 1024) throw Error('Live menu response too large');
      return {url:response.url,statusCode:response.status,headers:{},body,success:response.ok};
    }
    const fixture = fixtures.get(request.url);
    const body = typeof fixture === 'function' ? await fixture(request) : fixture;
    if (body === undefined) throw new Error(`Unexpected HTTP request: ${request.url}`);
    return { url: request.url, statusCode: 200, headers: {}, body, success: true };
  }
}
const repository = { isInitialized: () => false, get: async () => undefined,
  readScriptState: async url => states.get(url) || '', writeScriptState: async (url, value) => states.set(url, value) };
const stubs = {
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
  '@kit.CoreFileKit': { fileUri: { getUriFromPath: value => 'file://' + value,
    FileUri: class { constructor(uri) { this.path = uri.slice(7); } } },
    fileIo: { stat: async p => { if (!comicFiles.has(p)) throw Error('missing'); return {size:128}; },
      unlink: async p => comicFiles.delete(p) } },
  '@kit.BasicServicesKit': { emitter: { emit() {} } },
  'service/text/OnlineTextContentCache': { OnlineTextContentCache: {
    key: (...parts) => JSON.stringify(parts), read: async (_ctx,key) => comicDisk.get(key),
    write: async (_ctx,key,value) => comicDisk.set(key,value), removeChapter: async (_ctx,key) => comicDisk.delete(key)
  } },
  '@kit.ArkTS': { url: {URL:{parseURL:(value,base)=>new URL(value,base)}}, util: { TextEncoder: class { encodeInto(s) { return new TextEncoder().encode(s); } },
    TextDecoder: { create: (encoding='utf-8',options={}) => {
      const decoder = new TextDecoder(encoding,options);
      return {decodeWithStream:(a,o) => decoder.decode(a,o),decodeToString:(a,o) => decoder.decode(a,o)};
    } },
    Base64Helper: class { encodeToStringSync(a) { return Buffer.from(a).toString('base64'); }
      decodeSync(s) { return Uint8Array.from(Buffer.from(s, 'base64')); } },
    generateRandomUUID: () => 'fixture-id' } },
  '@kit.ArkWeb': { webview: {WebCookieManager: {
    jar: new Map(),
    clearAllCookiesSync() { this.jar.clear(); },saveCookieAsync() {},saveCookieSync() {},
    fetchCookieSync(url) { return this.jar.get(new URL(url).origin) || ''; },
    configCookieSync(url, value) {
      const origin = new URL(url).origin;
      const jar = new Map((this.jar.get(origin) || '').split(';').filter(v => v.includes('=')).map(v => v.trim().split(/=(.*)/s).slice(0,2)));
      const [name, content] = value.split(';')[0].split(/=(.*)/s);
      if (/max-age=0/i.test(value)) jar.delete(name); else jar.set(name,content);
      this.jar.set(origin,[...jar].map(([k,v]) => `${k}=${v}`).join('; '));
    }
  }} }, '@kit.AbilityKit': {}, '@ohos.data.preferences': {},
  '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: algorithm => {
    const hash = require('node:crypto').createHash(algorithm.toLowerCase());
    return { updateSync: value => hash.update(value.data), digestSync: () => ({data:hash.digest()}) };
  } } }, '@ohos.file.fs': {},
  '@devzeng/quickjs': {},
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: repository },
  [prefix + 'LightSourceCookies']: { LightSourceCookies: {
    hydrateCookies: async () => {}, getCookieSnapshot: async () => ({}), clearCookies: async () => {}, saveWebCookies: async () => {}
  } },
  [prefix + 'LightSourceSandbox']: { LightSourceSandbox: { evaluate: async script =>
    vm.runInNewContext(script, {}, { timeout: 5000 }) } },
  [prefix + 'upstream/core/http/HttpClient']: { HttpClient: FakeHttpClient }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (cache.has(name)) return cache.get(name).exports;
  const filename = ['.ts', '.ets'].map(ext => path.join(root, name + ext)).find(fs.existsSync);
  if (!filename) throw new Error(`Module not found: ${name}`);
  const module = { exports: {} };
  cache.set(name, module);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(output, { module, exports: module.exports, console, setTimeout, clearTimeout, setInterval, clearInterval,
    ObservedV2: value => value, Trace: () => {},
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value),
      set: (key, value) => storage.set(key, value), delete: key => storage.delete(key) },
    require: dependency => load(dependency.startsWith('.') ?
      path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
async function run() {
  // Application startup installs the shared engine host before any source work.
  load(prefix + 'LightSourceRuntime');
  const { BookSource } = load(prefix + 'upstream/model/data/Book');
  const { BookSourceRateLimiter: limiter, RateLimitAcquireResult: rateResult } = load(prefix + 'upstream/core/http/BookSourceRateLimiter');
  const { LightSourceRequest, LightSourceRequestPolicy: policy } = load(prefix + 'LightSourceRequestPolicy');
  const order = [];
  const admittedAt = [];
  const rateSource = key => Object.assign(new BookSource(), {bookSourceUrl:key, concurrentRate:'60'});
  const claim = async (key, label, request, maxWait = 0) => {
    const scoped = rateSource(key);
    policy.bind(scoped, request);
    const result = await limiter.acquire(scoped, undefined, maxWait);
    if (result === rateResult.Acquired) { order.push(label); admittedAt.push(Date.now()); }
    return result;
  };
  await limiter.acquire(rateSource('priority-fixture'));
  const background = claim('priority-fixture', 'background', new LightSourceRequest(0));
  const backgroundSecond = claim('priority-fixture', 'background-second', new LightSourceRequest(0));
  const normal = claim('priority-fixture', 'normal', new LightSourceRequest(1));
  const foreground = claim('priority-fixture', 'foreground', new LightSourceRequest(2));
  await Promise.all([background, backgroundSecond, normal, foreground]);
  assert.deepEqual(order, ['foreground','normal','background','background-second']);
  assert.ok(admittedAt.slice(1).every((at, index) => at - admittedAt[index] >= 59),
    'priority must preserve the source frequency window');
  await limiter.acquire(rateSource('promotion-fixture'));
  const promoted = new LightSourceRequest(0);
  order.length = 0;
  const alreadyPending = claim('promotion-fixture', 'promoted', promoted);
  const competing = claim('promotion-fixture', 'normal', new LightSourceRequest(1));
  promoted.promote();
  await Promise.all([alreadyPending, competing]);
  assert.deepEqual(order, ['promoted','normal'], 'take over the same pending preload without another request');
  await limiter.acquire(rateSource('cancel-priority-fixture'));
  const cancelledRequest = new LightSourceRequest(0);
  const cancelledClaim = claim('cancel-priority-fixture', 'cancelled', cancelledRequest);
  cancelledRequest.cancel();
  assert.equal(await cancelledClaim, rateResult.Cancelled);
  const waitingForeground = claim('cancel-priority-fixture', 'after-cancel', new LightSourceRequest(2));
  assert.equal(await claim('unrelated-priority-fixture', 'independent', new LightSourceRequest(0)), rateResult.Acquired);
  assert.equal(await waitingForeground, rateResult.Acquired);
  assert.ok(!order.includes('cancelled'), 'cancelled wait must not consume a quota');
  await limiter.acquire(rateSource('deadline-priority-fixture'));
  assert.equal(await claim('deadline-priority-fixture', 'expired', new LightSourceRequest(1), 5), rateResult.RateLimited);
  console.log('PASS: foreground priority, FIFO within a priority, source frequency, pending promotion, cancellation and source isolation');
  const { AnalyzeRule } = load(prefix + 'upstream/core/rule/AnalyzeRule');
  const { LightSourceImport } = load(prefix + 'upstream/LightSourceImport');
  const { LightSourceCore: engine } = load(prefix + 'LightSourceCore');
  const { LightSourceRuntime } = load(prefix + 'LightSourceRuntime');
  LightSourceRuntime.host = {
    hydrate: async () => '{}', readState: async url => states.get(url) || '',
    getSource: async () => '', listSources: async () => '[]', writeState: async (url, state) => states.set(url, state),
    saveCookies: async () => {}, fetch: async () => { throw Error('Unexpected web fetch'); },
    evaluate: async script => vm.runInNewContext(script, {}, {timeout:5000})
  };
  const source = { bookSourceUrl: 'https://engine.test', bookSourceName: 'Engine', bookSourceType: 0,
    searchUrl: '/search', ruleSearch: { bookList: '$.books', name: '$.name', bookUrl: '$.url' },
    ruleBookInfo: { name: '$.name', author: '$.author', tocUrl: '$.toc' },
    ruleToc: { chapterList: '$.chapters', chapterName: '$.name', chapterUrl: '$.url' },
    ruleContent: { content: '$.text' } };
  const { LocalRuleSourceImportParser: parser } = load('service/rulesource/LocalRuleSourceImportParser');
  const { LocalRuleSourceCodec: codec } = load('service/rulesource/LocalRuleSourceCodec');
  await require('./test-native-js-host.cjs')({load,prefix,runtime:LightSourceRuntime,parser,codec,engine,fixtures,states});
  assert.equal(parser.parse(JSON.stringify({format:'jianting.source',version:1})).sources.length,0, 'removed format is rejected');
  const local = parser.parse(JSON.stringify(source)).sources[0];
  assert.equal(local.bookSourceUrl, source.bookSourceUrl);
  local.definition = codec.stringify(local);
  assert.equal(new AnalyzeRule('<div id="x"><b>Hi</b></div>').getString('#x@html'), '<div id="x"><b>Hi</b></div>');
  assert.equal(new AnalyzeRule('{"items":[{"n":"a"},{"n":"b"}]}').getString('$.items[*].n'), 'a\nb');
  assert.equal(new LightSourceImport().parseBookSource({ ...source, ruleContent: { ...source.ruleContent, images: '$.images' } }).contentRule.images, '$.images');
  fixtures.set('https://engine.test/search', '{"books":[{"name":"Book","url":"/book"}]}');
  fixtures.set('https://engine.test/book', '{"name":"Book","author":"Author","toc":"/toc"}');
  fixtures.set('https://engine.test/toc', '{"chapters":[{"name":"One","url":"/chapter"}]}');
  fixtures.set('https://engine.test/chapter', '{"text":"chapter text"}');
  const search = JSON.parse(await engine.search(JSON.stringify(local), 'Book', 1));
  assert.equal(search[0].bookUrl, 'https://engine.test/book');
  const detail = JSON.parse(await engine.detail(JSON.stringify(local), search[0].bookUrl, '{}'));
  assert.equal(detail.author, 'Author');
  const toc = JSON.parse(await engine.toc(JSON.stringify(local), detail.tocUrl, JSON.stringify({ bookUrl: search[0].bookUrl })));
  assert.equal(toc[0].url, 'https://engine.test/chapter');
  assert.equal(toc[0].variables.chapterName, 'One');
  assert.equal(toc[0].variables.chapterIndex, '0');
  const largeRevision = JSON.stringify(['light-source-toc-v1', 'source-definition'.repeat(8192)]);
  const compactToc = await engine.toc(JSON.stringify(local), detail.tocUrl,
    JSON.stringify({bookUrl:search[0].bookUrl, session:'preserve-rule-variable', __audioTocDefinition:largeRevision}));
  assert.ok(compactToc.length < 4096, 'application revision must not be duplicated into chapter variables');
  assert.equal(JSON.parse(compactToc)[0].variables.session, 'preserve-rule-variable');
  assert.equal(JSON.parse(compactToc)[0].variables.__audioTocDefinition, undefined);
  assert.equal(JSON.parse(await engine.content(JSON.stringify(local), toc[0].url, '{}')).content, 'chapter text');
  const { BookSourceStageWebRuntime, StageWebRuntimeRequest } = load(prefix + 'upstream/core/book/BookSourceStageWebRuntime');
  const canonical = new LightSourceImport().parseBookSource(source);
  await LightSourceRuntime.run(canonical, local, async () => {
    const request = new StageWebRuntimeRequest();
    request.source = canonical; request.baseUrl = source.bookSourceUrl;
    request.code = 'const xs=[1,2,3]; xs.map(x=>x*2).join(",")';
    assert.equal((await BookSourceStageWebRuntime.get().execute(request)).value, '2,4,6');
    request.code = 'JSON.parse(java.ajax("https://engine.test/search")).books[0].name';
    assert.equal((await BookSourceStageWebRuntime.get().execute(request)).value, 'Book');
  });
  const { NativeSourceSpec } = load(prefix + 'upstream/core/nativesource/NativeSourceSpec');
  const native = NativeSourceSpec.fromObject({ sourceFormat: 'native', version: 1,
    name: 'Native', url: 'https://engine.test', search: { url: '/search', list: '$.books',
      fields: { name: '$.name', bookUrl: '$.url' } } });
  assert.equal(native.name, 'Native');
  const importedNative = parser.parse(JSON.stringify({sourceFormat:'native',version:1,...native})).sources[0];
  assert.equal(importedNative.engine, 'light-native');
  assert.equal(importedNative.canExecute(), true);
  assert.equal(JSON.parse(codec.stringify(importedNative)).search.fields.bookUrl, '$.url');
  importedNative.definition = codec.stringify(importedNative);
  assert.equal(JSON.parse(await engine.search(JSON.stringify(importedNative), 'Book', 1))[0].name, 'Book');
  // The shared sourceengine added a debug argument before our application page argument.
  const pagedNative = {...importedNative,definition:JSON.stringify({...native,sourceFormat:'native',version:1,
    search:{...native.search,url:'/search?page={{page}}'}})};
  fixtures.set('https://engine.test/search?page=3','{"books":[{"name":"NativeThird","url":"/third"}]}');
  assert.equal(JSON.parse(await engine.search(JSON.stringify(pagedNative),'NativeThird',3))[0].name,'NativeThird');
  const upgradedDefinition = {sourceFormat:'native',version:1,name:'Shared engine',url:'https://upgrade.test',
    voices:[{id:'0',name:'真人原声'},{id:'74',name:'成熟升级'}],
    type:'audio',search:{url:'/search',list:'$.books',fields:{name:'$.name',bookUrl:'$.url'}},
    content:{url:'{{chapter.url}}',audio:'$.audio',mediaHeaders:{Referer:'https://upgrade.test/listen','X-Media':'native'}},
    login:{form:[{key:'account',label:'Account'},{key:'password',label:'Password',secret:true}],
      submit:{url:'/login',method:'POST',body:{account:'=form.account',password:'=form.password'},
        ok:'=data.ok',token:'=data.token',user:'=data.user',message:'=data.message'},
      sendCode:{label:'Send code',url:'/code',method:'POST',body:{account:'=form.account'},message:'=data.message'}},
    actions:[{label:'Check in',url:'/check-in',headers:{Authorization:'Bearer {{login.token}}'},message:'=data.message'},
      {label:'Account',open:'/account'}]};
  const upgraded = parser.parse(JSON.stringify(upgradedDefinition)).sources[0];
  assert.ok(upgraded,'shared sourceengine native schema imports');
  upgraded.definition = codec.stringify(upgraded);
  assert.deepEqual(JSON.parse(await engine.voices(JSON.stringify(upgraded))),
    [{id:'0',name:'真人原声'},{id:'74',name:'成熟升级'}], 'voice names and ids survive the imported-source boundary');
  fixtures.set('https://upgrade.test/chapter','{"audio":"https://media.test/native.mp3"}');
  const upgradedAudio = JSON.parse(await engine.content(JSON.stringify(upgraded),'https://upgrade.test/chapter','{}'));
  assert.equal(upgradedAudio.audioUrl,'https://media.test/native.mp3');
  assert.equal(upgradedAudio.requestHeaders.Referer,'https://upgrade.test/listen');
  assert.equal(upgradedAudio.requestHeaders['X-Media'],'native');
  const { ChapterRuleContext } = load('service/rulesource/ChapterRuleContext');
  const titleSource = {...upgraded, definition: JSON.stringify({...upgradedDefinition,
    content:{url:'{{chapter.url}}',audio:'=chapter.title == "One" && chapter.index == 0 ? "https://media.test/real.mp3" : "https://media.test/tts.mp3"'}})};
  const resolveTitle = async variables => JSON.parse(await engine.content(JSON.stringify(titleSource),
    'https://upgrade.test/chapter',JSON.stringify(variables))).audioUrl;
  assert.equal(await resolveTitle({}), 'https://media.test/tts.mp3', 'missing title reproduces synthesized fallback');
  assert.equal(await resolveTitle({...toc[0].variables,__lightBookType:'32'}), 'https://media.test/real.mp3', 'fresh catalog preserves rule chapter metadata');
  const oldVariables = {session:'keep'};
  const restoredContext = ChapterRuleContext.create('One',0,oldVariables);
  assert.equal(await resolveTitle(restoredContext), 'https://media.test/real.mp3', 'old catalog title reaches native content');
  assert.equal(restoredContext.session,'keep');
  assert.equal(oldVariables.chapterName,undefined,'input variables remain unchanged');
  assert.equal(ChapterRuleContext.create('UI title',1,{chapterName:'Original title'}).chapterName,'Original title');
  assert.equal(ChapterRuleContext.create('Second',1).chapterIndex,'1');
  const formPanel = JSON.parse(await engine.panel(JSON.stringify(upgraded),true,'save','login'));
  const submitControl = formPanel.controls.find(item => item.action === 'light-native-submit');
  const codeControl = formPanel.controls.find(item => item.action === 'light-native-send-code');
  assert.ok(submitControl && codeControl,'native form actions reach the existing panel');
  const passwordControl = formPanel.controls.find(item => item.id === 'light-native-form:password');
  assert.equal(passwordControl.type,'password');
  passwordControl.value = 'transient-secret';
  formPanel.controls.find(item => item.id === 'light-native-form:account').value = 'fixture-user';
  fixtures.set('https://upgrade.test/code',request => {
    assert.equal(JSON.parse(request.body).account,'fixture-user');
    return '{"message":"code sent"}';
  });
  assert.equal(JSON.parse(await engine.panelAction(JSON.stringify(upgraded),JSON.stringify(codeControl),
    JSON.stringify(formPanel.controls))).message,'code sent');
  fixtures.set('https://upgrade.test/login',request => {
    assert.equal(JSON.parse(request.body).password,'transient-secret');
    return '{"ok":true,"token":"fixture-token","user":"fixture-user","message":"logged in"}';
  });
  const loggedIn = JSON.parse(await engine.panelAction(JSON.stringify(upgraded),JSON.stringify(submitControl),
    JSON.stringify(formPanel.controls)));
  assert.equal(loggedIn.refreshLogin,true);
  assert.equal(JSON.parse(JSON.parse(states.get(upgraded.bookSourceUrl)).loginInfo).nativeToken,'fixture-token');
  assert.ok(!states.get(upgraded.bookSourceUrl).includes('transient-secret'),'password never persists');
  assert.equal(await engine.checkNativeLogin(JSON.stringify(upgraded)),true);
  fixtures.set('https://upgrade.test/check-in',request => {
    assert.equal(request.headers.Authorization,'Bearer fixture-token');
    return '{"message":"checked in"}';
  });
  const checkIn = formPanel.controls.find(item => item.action === 'light-native-action:0');
  assert.equal(JSON.parse(await engine.panelAction(JSON.stringify(upgraded),JSON.stringify(checkIn),'[]')).message,'checked in');
  const account = formPanel.controls.find(item => item.action === 'light-native-action:1');
  assert.equal(JSON.parse(await engine.panelAction(JSON.stringify(upgraded),JSON.stringify(account),'[]')).browserUrl,
    'https://upgrade.test/account');
  fixtures.set('https://upgrade.test/login','{"ok":false,"message":"denied"}');
  assert.equal(JSON.parse(await engine.panelAction(JSON.stringify(upgraded),JSON.stringify(submitControl),
    JSON.stringify(formPanel.controls))).refreshLogin,false);
  assert.equal(JSON.parse(JSON.parse(states.get(upgraded.bookSourceUrl)).loginInfo).nativeToken,'fixture-token');
  const readerAction = 'legado-native-action:'+encodeURIComponent(JSON.stringify({
    r:{url:'https://upgrade.test/check-in',method:'GET',headers:{Authorization:'Bearer fixture-token'},body:'',retry:0},
    m:'=data.message'}));
  assert.equal(JSON.parse(await engine.readerAction(JSON.stringify(upgraded),readerAction,'{}')).message,'checked in');
  await engine.clearLogin(JSON.stringify(upgraded));
  assert.equal(await engine.checkNativeLogin(JSON.stringify(upgraded)),false);
  const {NativeSourceService} = load(prefix+'upstream/core/nativesource/NativeSourceService');
  const waitingDefinition = {sourceFormat:'native',version:1,name:'Wait for',url:'https://wait.test',rate:'60',
    search:{url:'/search',webView:{waitFor:'#ready',timeout:3},list:'$.books',fields:{name:'$.name',bookUrl:'$.url'}}};
  const waitingLocal = parser.parse(JSON.stringify(waitingDefinition)).sources[0];
  waitingLocal.definition = codec.stringify(waitingLocal);
  const waitingSource = NativeSourceService.importObject(waitingDefinition);
  const waitTimes = [];
  fixtures.set('https://wait.test/search',request => {
    waitTimes.push(Date.now());
    assert.equal(request.cookieSource,waitingSource.bookSourceUrl);
    assert.equal(request.maxResponseBytes,2048);
    assert.match(request.webJs,/#ready/);
    return '{"books":[{"name":"Ready","url":"/book"}]}';
  });
  await LightSourceRuntime.run(waitingSource,waitingLocal,async () => {
    for(let i=0;i<2;i++) assert.equal((await NativeSourceService.search(waitingSource,new FakeHttpClient(),
      'Ready',()=>false,2048))[0].name,'Ready');
    assert.ok(waitTimes[1]-waitTimes[0]>=59,'waitFor respects the source frequency window');
    const pending = new LightSourceRequest(0);
    policy.bind(waitingSource,pending);
    const stopped = NativeSourceService.search(waitingSource,new FakeHttpClient(),'Ready',()=>false,2048);
    pending.cancel();
    await assert.rejects(stopped,/取消/);
    assert.equal(waitTimes.length,2,'cancelled waitFor must not send HTTP');
  });
  console.log('PASS: shared engine native pagination, media headers, form login/code, transient secrets, actions and logout');
  source.searchUrl = '/search?page={{page}}';
  fixtures.set('https://engine.test/search?page=2', '{"books":[{"name":"Second","url":"/second"}]}');
  const paged = {...local, definition:JSON.stringify(source)};
  assert.equal(JSON.parse(await engine.search(JSON.stringify(paged), 'Second', 2))[0].name, 'Second');
  fixtures.set('https://engine.test/media', '{"images":["https://engine.test/1.jpg","https://engine.test/2.jpg"],"url":"https://engine.test/audio.mp3"}');
  const comic = {...local,definition:JSON.stringify({...source,bookSourceType:2,ruleContent:{images:'$.images[*]'}})};
  const comicContent = JSON.parse(await engine.content(JSON.stringify(comic), 'https://engine.test/media', '{}'));
  assert.equal(comicContent.mediaType, 'comic');
  assert.equal(comicContent.imageUrls.length, 2);
  const comicSearch = JSON.parse(await engine.search(JSON.stringify(comic), 'Second', 2));
  assert.equal(comicSearch[0].contentType, 'comic', 'comic source results must not enter the text reader');
  let requestedChapter;
  stubs['service/BookSourceService'] = { BookSourceService: {
    getSourceChapterContent: async (_book, url, variables) => {
      requestedChapter = { url, variables };
      return comicContent;
    }
  } };
  const { ComicReaderService } = load('service/ComicReaderService');
  const comicChapter = { id: 'comic-c0', originSourceValue: 'https://engine.test/media',
    source: { value: 'stale-url' }, variables: { chapterName: 'First', chapterIndex: '0' } };
  let comicPages = await ComicReaderService.load({ contentType: 'comic' }, comicChapter);
  assert.equal(comicPages.length, 2);
  assert.equal(requestedChapter.url, comicChapter.originSourceValue);
  assert.equal(requestedChapter.variables, comicChapter.variables, 'chapter context reaches the shared dispatcher');
  assert.equal(comicPages[0].url, 'https://engine.test/1.jpg');
  comicContent.imageUrls.push(comicContent.imageUrls[0]);
  comicPages = await ComicReaderService.load({}, comicChapter);
  assert.equal(new Set(comicPages.map(page => page.key)).size, 3, 'repeated images retain order and unique stable keys');
  comicContent.imageUrls = ['/data/storage/el2/base/haps/entry/cache/comic_images/page.webp',
    'file:///data/storage/el2/base/haps/entry/cache/comic_images/ready.webp'];
  comicPages = await ComicReaderService.load({}, comicChapter);
  assert.equal(comicPages[0].url, 'file:///data/storage/el2/base/haps/entry/cache/comic_images/page.webp',
    'materialized engine files must be passed to ArkUI as file URIs, not application assets');
  assert.equal(comicPages[1].url, comicContent.imageUrls[1]);
  const comicContext = {cacheDir:'/data/storage/el2/base/haps/entry/cache'};
  const localImage = comicContext.cacheDir + '/comic_images/page.webp';
  comicContent.imageUrls = [localImage];
  comicFiles.add(localImage);
  await ComicReaderService.load({}, comicChapter, comicContext);
  comicContent.imageUrls = [];
  assert.equal((await ComicReaderService.load({}, comicChapter, comicContext)).length, 1, 'reopen uses valid disk image cache');
  comicFiles.clear();
  assert.equal((await ComicReaderService.load({}, comicChapter, comicContext)).length, 0, 'deleted image must refetch, not claim offline availability');
  comicFiles.add(localImage);
  comicContent.imageUrls = [localImage];
  await ComicReaderService.load({}, comicChapter, comicContext);
  comicContent.imageUrls = [];
  assert.equal((await ComicReaderService.load({}, comicChapter, comicContext, true)).length, 0, 'refresh bypasses chapter cache');
  assert.equal(comicFiles.has(localImage), false, 'refresh invalidates owned image file');
  comicContent.imageUrls = [];
  assert.equal((await ComicReaderService.load({}, comicChapter)).length, 0, 'empty image chapters remain empty');
  console.log('PASS: comic search typing, real image reader bridge, chapter context, duplicate pages and empty content');
  const audio = {...local,definition:JSON.stringify({...source,bookSourceType:1,ruleContent:{audioUrl:'$.url'}})};
  assert.equal(JSON.parse(await engine.content(JSON.stringify(audio), 'https://engine.test/media', '{}')).audioUrl, 'https://engine.test/audio.mp3');
  // AudioBook resolves JSON results after WebBookService and preserves anti-hotlink headers.
  const audioJson = {...local,definition:JSON.stringify({...source,bookSourceType:1,
    header:JSON.stringify({'Referer':'https://engine.test/','User-Agent':'Audio fixture',
      'Authorization':'source-secret','Cookie':'source-session=private'}),
    ruleContent:{content:"html<js>result.replace(/^\\s+/,'')</js>"}})};
  fixtures.set('https://engine.test/audio-json', '\ufeff'+JSON.stringify({status:1,
    url:'https://cdn.other.test/中文/第1集.mp3?key=a&value=b'}).replace(/中文|第1集/g,
      value=>[...value].map(char=>'\\u'+char.charCodeAt(0).toString(16).padStart(4,'0')).join('')));
  const audioJsonResult = JSON.parse(await engine.content(JSON.stringify(audioJson), 'https://engine.test/audio-json', '{}'));
  assert.equal(audioJsonResult.audioUrl, 'https://cdn.other.test/中文/第1集.mp3?key=a&value=b');
  assert.equal(audioJsonResult.requestHeaders.Referer, 'https://engine.test/');
  assert.equal(audioJsonResult.requestHeaders['User-Agent'], 'Audio fixture');
  assert.equal(audioJsonResult.requestHeaders.Authorization, undefined, 'source credentials stay on their site');
  assert.equal(audioJsonResult.requestHeaders.Cookie, undefined, 'source cookies cannot leak to another media host');
  const explicitAudio = {...audio,definition:JSON.stringify({...source,bookSourceType:1,
    header:JSON.stringify({'Referer':'https://engine.test/'}),ruleContent:{audioUrl:'$.url'}})};
  fixtures.set('https://engine.test/audio-explicit',JSON.stringify({url:'https://cdn.other.test/a.mp3,'+
    JSON.stringify({headers:{Referer:'https://cdn.other.test/player','X-Media':'explicit'}})}));
  const explicitResult = JSON.parse(await engine.content(JSON.stringify(explicitAudio),'https://engine.test/audio-explicit','{}'));
  assert.equal(explicitResult.audioUrl,'https://cdn.other.test/a.mp3');
  assert.equal(explicitResult.requestHeaders.Referer,'https://cdn.other.test/player');
  assert.equal(explicitResult.requestHeaders['X-Media'],'explicit');
  fixtures.set('https://engine.test/audio-denied',JSON.stringify({status:-1,url:'',message:'需要站点授权'}));
  await assert.rejects(engine.content(JSON.stringify(audioJson),'https://engine.test/audio-denied','{}'), /需要站点授权/);
  const {ReaderActionMarker} = load(prefix + 'upstream/core/book/ReaderActionMarker');
  fixtures.set('https://engine.test/comments', JSON.stringify({text:'paragraph'+ReaderActionMarker.create('段评 2','https://engine.test/comments/1')}));
  const commentSource = {...local,definition:JSON.stringify({...source,ruleContent:{content:'$.text'}})};
  const commentContent = JSON.parse(await engine.content(JSON.stringify(commentSource), 'https://engine.test/comments', '{}'));
  assert.equal(commentContent.content, 'paragraph');
  assert.equal(commentContent.interactions[0].label, '段评 2');
  const {LightCookieStore} = load(prefix + 'LightSourceRuntime');
  const cookieWrites = [];
  LightSourceRuntime.host.saveCookies = async (url, origin, cookies) => cookieWrites.push({url,origin,cookies});
  await assert.rejects(LightSourceRuntime.run(canonical, local, async () => {
    LightCookieStore.forSource(source.bookSourceUrl).setCookies(source.bookSourceUrl, 'session=A');
    throw Error('fixture failure');
  }), /fixture failure/);
  assert.equal(cookieWrites[0].url, source.bookSourceUrl);
  await LightSourceRuntime.run(canonical, {...local,bookSourceUrl:'https://other.test'}, async () => {
    assert.equal(LightCookieStore.forSource('https://other.test').getCookie(source.bookSourceUrl), '');
  });
  assert.equal(LightSourceRuntime.execution(canonical), undefined);

  await LightSourceRuntime.run(canonical, local, async () => {
    LightCookieStore.forSource(source.bookSourceUrl).setCookies(source.bookSourceUrl,'a=1; b=2');
    LightCookieStore.forSource(source.bookSourceUrl).removeCookie(source.bookSourceUrl,'a');
    assert.equal(LightCookieStore.forSource(source.bookSourceUrl).getCookieValue(source.bookSourceUrl,'a'),'');
    LightCookieStore.forSource(source.bookSourceUrl).replaceCookies(source.bookSourceUrl,'c=3');
    assert.equal(LightCookieStore.forSource(source.bookSourceUrl).getCookie(source.bookSourceUrl),'c=3');
    LightCookieStore.forSource(source.bookSourceUrl).setCookies(source.bookSourceUrl,'c=; Max-Age=0; Path=/');
    assert.equal(LightCookieStore.forSource(source.bookSourceUrl).getCookie(source.bookSourceUrl),'');
  });
  LightSourceRuntime.host.getSource = async url => url === source.bookSourceUrl ? JSON.stringify(local) : '';
  const loginLocal = {...local,definition:JSON.stringify({...source,loginUrl:'',loginUi:'[]'})};
  const loginAction = {action:"source.setVariable(JSON.stringify({loginFixture:'saved'}));java.toast('login-ok');java.reLoginView();",type:'button'};
  const loginResult = JSON.parse(await engine.panelAction(JSON.stringify(loginLocal),JSON.stringify(loginAction),'[]'));
  assert.equal(loginResult.message,'login-ok');
  assert.equal(loginResult.refreshLogin,true);
  assert.equal(JSON.parse(JSON.parse(states.get(source.bookSourceUrl)).variable).loginFixture,'saved');
  console.log('PASS: browser cookie removal/replacement and upstream login action persistence');

  LightSourceRuntime.host.browse = async (_url,_name,address) => {
    assert.equal(address,'https://engine.test/login');
    return 'authorized-html';
  };
  const waitingAction = {action:"var html=java.startBrowserAwait('https://engine.test/login','login').body();if(html)source.setVariable(JSON.stringify({resumed:html}));",type:'button'};
  await engine.panelAction(JSON.stringify(loginLocal),JSON.stringify(waitingAction),'[]');
  assert.equal(JSON.parse(JSON.parse(states.get(source.bookSourceUrl)).variable).resumed,'authorized-html');
  assert.equal(JSON.parse(states.get(source.bookSourceUrl)).lightLoginPending,undefined);
  let browserVisits = 0;
  LightSourceRuntime.host.browse = async () => 'page-'+(++browserVisits);
  const twice = {action:"var a=java.startBrowserAwait('https://engine.test/login','first').body();var b=java.startBrowserAwait('https://engine.test/login2','second').body();source.setVariable(a+'|'+b);",type:'button'};
  await engine.panelAction(JSON.stringify(loginLocal),JSON.stringify(twice),'[]');
  assert.equal(browserVisits,2);
  assert.equal(JSON.parse(states.get(source.bookSourceUrl)).variable,'page-1|page-2');
  LightSourceRuntime.host.browse = async () => {throw Error('login cancelled');};
  await assert.rejects(engine.panelAction(JSON.stringify(loginLocal),JSON.stringify(waitingAction),'[]'),/login cancelled/);
  assert.equal(LightSourceRuntime.execution(canonical),undefined);
  const savedCookieState = JSON.parse(states.get(source.bookSourceUrl));
  savedCookieState.lightCookieRecords = [
    {url:source.bookSourceUrl+'/secure/page',cookie:'pathToken=deep; Path=/secure; Secure; HttpOnly'},
    {url:source.bookSourceUrl+'/',cookie:'expired=old; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT'}
  ];
  states.set(source.bookSourceUrl,JSON.stringify(savedCookieState));
  const manager = stubs['@kit.ArkWeb'].webview.WebCookieManager;
  const fetchCookies = manager.fetchCookieSync;
  manager.fetchCookieSync = () => ''; // exercise metadata fallback without a browser result
  await LightSourceRuntime.run(canonical,local,async () => {
    assert.equal(LightCookieStore.forSource(source.bookSourceUrl).getCookie(source.bookSourceUrl+'/secure/chapter'),'pathToken=deep');
    assert.equal(LightCookieStore.forSource(source.bookSourceUrl).getCookie(source.bookSourceUrl+'/'),'');
    LightCookieStore.forSource(source.bookSourceUrl).removeCookie(source.bookSourceUrl,'pathToken');
  });
  assert.equal(JSON.parse(states.get(source.bookSourceUrl)).lightCookieRecords.length,0,'deleted/expired cookies cannot resurrect on flush');
  manager.fetchCookieSync = fetchCookies;

  // Ordinary resolutions neither acquire Web sessions nor write unchanged state.
  await LightSourceRuntime.run(canonical,local,async () => {
    const request=new StageWebRuntimeRequest(); request.source=canonical; request.code='1+1';
    await BookSourceStageWebRuntime.get().execute(request);
  }); // one-time removal of the old persisted script-cache field
  const originalWrite = LightSourceRuntime.host.writeState;
  let unchangedWrites = 0;
  LightSourceRuntime.host.writeState = async (...args) => { unchangedWrites++; return originalWrite(...args); };
  let webAcquires = 0;
  LightSourceRuntime.host.acquireWeb = async () => { webAcquires++; return webAcquires; };
  await LightSourceRuntime.run(canonical, local, async () => {
    LightCookieStore.forSource(source.bookSourceUrl).getCookie(source.bookSourceUrl);
    const request=new StageWebRuntimeRequest(); request.source=canonical; request.code='1+1';
    assert.equal((await BookSourceStageWebRuntime.get().execute(request)).value,'2');
  });
  assert.equal(unchangedWrites,0,'read-only resolution must not persist unchanged cookies');
  assert.equal(webAcquires,0,'HTTP-only resolution must not enter ArkWeb');
  LightSourceRuntime.host.writeState = originalWrite;
  delete LightSourceRuntime.host.acquireWeb;

  const within = async promise => {
    let timer;
    try { return await Promise.race([promise,new Promise((_,reject) => {
      timer=setTimeout(() => reject(Error('parallel source task was blocked')),1500);
    })]); } finally { clearTimeout(timer); }
  };
  const scopeA = new LightSourceImport().parseBookSource({...source,bookSourceUrl:'https://shared.test/source-a'});
  const scopeB = new LightSourceImport().parseBookSource({...source,bookSourceUrl:'https://shared.test/source-b'});
  const localA = {...local,bookSourceUrl:scopeA.bookSourceUrl};
  const localB = {...local,bookSourceUrl:scopeB.bookSourceUrl};
  let unblockA;
  const waitA = new Promise(resolve => {unblockA=resolve;});
  await within(Promise.all([
    LightSourceRuntime.run(scopeA,localA,async () => {
      const jar=LightCookieStore.forSource(scopeA.bookSourceUrl);
      jar.setCookies('https://shared.test/','session=A');
      await waitA;
      assert.equal(jar.getCookie('https://shared.test/'),'session=A');
    }),
    LightSourceRuntime.run(scopeB,localB,async () => {
      const jar=LightCookieStore.forSource(scopeB.bookSourceUrl);
      assert.equal(jar.getCookie('https://shared.test/'),'');
      jar.setCookies('https://shared.test/','session=B');
      assert.equal(jar.getCookie('https://shared.test/'),'session=B');
      unblockA();
    })
  ]));
  assert.equal(manager.jar.size,0,'plain HTTP must not touch global browser cookies');

  // An unrelated script's slow HTTP must not hold the global stage queue.
  let releaseSlow, enteredSlow;
  const slowGate=new Promise(resolve => {releaseSlow=resolve;});
  const slowEntered=new Promise(resolve => {enteredSlow=resolve;});
  fixtures.set('https://engine.test/slow-script', async () => {enteredSlow(); await slowGate; return '{"value":"slow"}';});
  const slowSource=new LightSourceImport().parseBookSource(source);
  const fastSource=new LightSourceImport().parseBookSource(source);
  const slowTask=LightSourceRuntime.run(slowSource,local,async () => {
    const request=new StageWebRuntimeRequest(); request.source=slowSource; request.ownerId='slow-fixture';
    request.code='JSON.parse(java.ajax("https://engine.test/slow-script")).value';
    return (await BookSourceStageWebRuntime.get().execute(request)).value;
  });
  await within(slowEntered);
  try {
    const fastValue=await within(LightSourceRuntime.run(fastSource,local,async () => {
      const request=new StageWebRuntimeRequest(); request.source=fastSource;
      request.code='"fast"';
      return (await BookSourceStageWebRuntime.get().execute(request)).value;
    }));
    assert.equal(fastValue,'fast');
  } finally {releaseSlow();}
  assert.equal(await slowTask,'slow');

  let releaseCancelled, enteredCancelled;
  const cancelledGate=new Promise(resolve => {releaseCancelled=resolve;});
  const cancelledEntered=new Promise(resolve => {enteredCancelled=resolve;});
  fixtures.set('https://engine.test/cancel-script',async () => {enteredCancelled();await cancelledGate;return '{}';});
  const cancelledTask=LightSourceRuntime.run(slowSource,local,async () => {
    const request=new StageWebRuntimeRequest();request.source=slowSource;request.ownerId='cancel-fixture';
    request.code='java.ajax("https://engine.test/cancel-script")';
    return BookSourceStageWebRuntime.get().execute(request);
  });
  const cancelledResult=assert.rejects(cancelledTask,/已取消/);
  await within(cancelledEntered);
  BookSourceStageWebRuntime.get().cancelOwner('cancel-fixture');releaseCancelled();
  await within(cancelledResult);
  assert.equal(LightSourceRuntime.execution(slowSource),undefined);
  assert.throws(() => LightCookieStore.forSource(source.bookSourceUrl),/未初始化/);
  BookSourceStageWebRuntime.get().clearOwner('cancel-fixture');

  // Concurrent updates of separate source variables must merge, with task-local errors.
  const {LightSourceDatabase}=load(prefix+'LightSourceRuntime');
  states.set(source.bookSourceUrl,JSON.stringify({variable:'{"tone":"a","channel":"book"}',definitionVariable:local.variable}));
  let firstReady, secondReady;
  const firstGate=new Promise(resolve => {firstReady=resolve;});
  const secondGate=new Promise(resolve => {secondReady=resolve;});
  await within(Promise.all([
    LightSourceRuntime.run(slowSource,local,async () => {
      LightSourceRuntime.setError(slowSource,'only-slow'); firstReady(); await secondGate;
      await LightSourceDatabase.getInstance(slowSource).updateBookSourceVariable(source.bookSourceUrl,'{"tone":"b","channel":"book"}');
    }),
    LightSourceRuntime.run(fastSource,local,async () => {
      await firstGate;
      assert.equal(LightSourceRuntime.getError(fastSource),''); secondReady();
      await LightSourceDatabase.getInstance(fastSource).updateBookSourceVariable(source.bookSourceUrl,'{"tone":"a","channel":"audio"}');
    })
  ]));
  assert.deepEqual(JSON.parse(JSON.parse(states.get(source.bookSourceUrl)).variable),{tone:'b',channel:'audio'});
  console.log('PASS: parallel source/script execution, isolated cookies/errors, unchanged-state writes and concurrent variable merges');

  // Exercise the actual HttpClient adapter, including Web-only leases and failure cleanup.
  const httpName=prefix+'upstream/core/http/HttpClient';
  const httpStub=stubs[httpName];
  const platformRequests=[];
  stubs['@ohos.net.http']={default:{
    RequestMethod:{GET:'GET',POST:'POST',PUT:'PUT',DELETE:'DELETE',HEAD:'HEAD'},
    HttpDataType:{ARRAY_BUFFER:0},HttpProtocol:{HTTP1_1:1},
    createHttp:() => ({destroy(){},async request(url,options){
      platformRequests.push({url,headers:options.header});
      return {responseCode:200,header:{'Set-Cookie':'httpToken=ok; Path=/secure; Secure; HttpOnly'},result:'{}'};
    }})
  }};
  delete stubs[httpName]; cache.delete(httpName);
  const {HttpClient:ActualHttpClient}=load(httpName);
  await LightSourceRuntime.run(scopeA,localA,async () => {
    const jar=LightCookieStore.forSource(scopeA.bookSourceUrl);
    jar.setCookies('https://shared.test/','session=A');
    const result=await new ActualHttpClient().execute({url:'https://shared.test/api',method:'GET',headers:{},cookieSource:scopeA.bookSourceUrl});
    assert.equal(result.success,true,result.error);
    assert.equal(platformRequests.at(-1).headers.Cookie,'session=A');
    assert.equal(jar.getCookieValue('https://shared.test/secure/chapter','httpToken'),'ok');
    assert.equal(jar.getCookieValue('https://shared.test/chapter','httpToken'),'');
  });
  const {LocalRuleWebSession}=load('service/rulesource/LocalRuleWebSession');
  let webReleases=0;
  LightSourceRuntime.host.acquireWeb=async () => {webAcquires++;return LocalRuleWebSession.acquire(1500);};
  LightSourceRuntime.host.releaseWeb=lease => {webReleases++;LocalRuleWebSession.release(lease);};
  const web=load(prefix+'upstream/core/book/WebBookFetchRuntime').WebBookFetchRuntime.get();
  const originalAttached=web.waitUntilAttached, originalFetch=web.fetch;
  web.waitUntilAttached=async () => true;
  web.fetch=async request => {
    const expected=request.cookieSource === scopeA.bookSourceUrl ? 'A' : 'B';
    assert.ok(manager.fetchCookieSync(request.url).includes('session='+expected));
    assert.ok(!manager.fetchCookieSync(request.url).includes('session='+(expected==='A'?'B':'A')));
    await Promise.resolve();
    if(expected==='A') { manager.configCookieSync(request.url,'session=updated; Path=/'); throw Error('fixture Web failure'); }
    return {url:request.url,statusCode:200,headers:{},body:'web-ok',success:true};
  };
  const webResults=await within(Promise.all([[scopeA,localA,'A'],[scopeB,localB,'B']].map(([canonicalSource,localSource,token]) =>
    LightSourceRuntime.run(canonicalSource,localSource,async () => {
      LightCookieStore.forSource(canonicalSource.bookSourceUrl).setCookies('https://shared.test/','session='+token);
      return new ActualHttpClient().execute({url:'https://shared.test/web',method:'GET',headers:{},useWebView:true,cookieSource:canonicalSource.bookSourceUrl});
    }))));
  assert.equal(webResults[0].success,false);
  assert.match(webResults[0].error,/fixture Web failure/);
  assert.ok(JSON.parse(states.get(scopeA.bookSourceUrl)).lightCookieRecords.some(record => record.cookie.split(';')[0] === 'session=updated'));
  assert.equal(webResults[1].body,'web-ok');
  assert.equal(webAcquires,2); assert.equal(webReleases,2);
  assert.equal(manager.jar.size,0,'failed/successful Web requests must both clear their session');
  web.waitUntilAttached=originalAttached;web.fetch=originalFetch;
  delete LightSourceRuntime.host.acquireWeb;delete LightSourceRuntime.host.releaseWeb;
  stubs[httpName]=httpStub;cache.delete(httpName);
  console.log('PASS: actual HTTP headers/Set-Cookie scope, exclusive Web sessions and failure cleanup');
  const nativeWithLogin = parser.parse(JSON.stringify({sourceFormat:'native',version:1,name:'Login',url:source.bookSourceUrl,
    search:{url:'/search',list:'$.books',fields:{name:'$.name',bookUrl:'$.url'}},
    login:{url:source.bookSourceUrl+'/login',check:{url:'/login-check',ok:'=data.ok'}}})).sources[0];
  nativeWithLogin.definition = codec.stringify(nativeWithLogin);
  fixtures.set(source.bookSourceUrl+'/login-check','{"ok":true}');
  assert.equal(await engine.checkLogin(JSON.stringify(nativeWithLogin),'',''),true);
  fixtures.set(source.bookSourceUrl+'/login-check','{"ok":false}');
  assert.equal(await engine.checkLogin(JSON.stringify(nativeWithLogin),'',''),false);
  const cookieOnly = {...nativeWithLogin,definition:JSON.stringify({...JSON.parse(nativeWithLogin.definition),login:{url:source.bookSourceUrl+'/login',cookies:['session']}})};
  LightSourceRuntime.host.hydrate = async () => JSON.stringify({[source.bookSourceUrl]:'session=ok'});
  assert.equal(await engine.checkLogin(JSON.stringify(cookieOnly),'',''),true);
  LightSourceRuntime.host.hydrate = async () => '{}';
  states.delete(source.bookSourceUrl);
  assert.equal(await engine.checkLogin(JSON.stringify(cookieOnly),'',''),false);
  const savedHydrate = LightSourceRuntime.host.hydrate;
  let accountCookie = 'account-a';
  let cacheFetches = 0;
  const cacheOrigin = 'https://cache-login.test';
  const cachedLogin = parser.parse(JSON.stringify({sourceFormat:'native',version:1,name:'Cached login',url:cacheOrigin,
    login:{url:cacheOrigin+'/login',cookies:['session']},
    cache:{sessionToken:{url:'/token',value:'=data.token',ttl:600}},
    search:{url:'/search',headers:{'X-Cached':'{{sessionToken}}'},list:'$.books',fields:{name:'$.name',bookUrl:'$.url'}}})).sources[0];
  cachedLogin.definition = codec.stringify(cachedLogin);
  const cachedLoginJson = JSON.stringify(cachedLogin);
  LightSourceRuntime.host.hydrate = async () => JSON.stringify({[cacheOrigin]:'session='+accountCookie});
  fixtures.set(cacheOrigin+'/token',() => { cacheFetches++; return JSON.stringify({token:accountCookie}); });
  fixtures.set(cacheOrigin+'/search','{"books":[{"name":"Cached","url":"/book"}]}');
  await engine.search(cachedLoginJson,'Cached',1);
  accountCookie = 'refreshed-a';
  await engine.search(cachedLoginJson,'Cached',1);
  assert.equal(cacheFetches,1,'ordinary Cookie refresh must not invalidate native declared caches');
  accountCookie = 'account-b';
  assert.equal(await engine.checkLogin(cachedLoginJson,'',''),true);
  await engine.search(cachedLoginJson,'Cached',1);
  assert.equal(cacheFetches,2,'cookie-only browser login must invalidate the previous account cache');
  assert.equal(requests.filter(request => request.url === cacheOrigin+'/search').at(-1).headers['X-Cached'],'account-b');
  await engine.clearLogin(cachedLoginJson);
  accountCookie = 'account-c';
  await engine.search(cachedLoginJson,'Cached',1);
  assert.equal(cacheFetches,3,'logout must invalidate native declared caches');
  LightSourceRuntime.host.hydrate = savedHydrate;
  console.log('PASS: native cache reuse on Cookie refresh, invalidation on browser login and logout');
  delete LightSourceRuntime.host.browse;
  const scriptOnly = {...loginLocal,definition:JSON.stringify({...source,loginUi:'',loginUrl:'function login(){java.startBrowser("https://engine.test/login");}'})};
  const scriptPanel = JSON.parse(await engine.panel(JSON.stringify(scriptOnly),true,'save','login'));
  assert.equal(scriptPanel.controls[0].action,'light-login-run');
  assert.equal(JSON.parse(await engine.panelAction(JSON.stringify(scriptOnly),JSON.stringify(scriptPanel.controls[0]),'[]')).browserUrl,'https://engine.test/login');

  stubs['service/rulesource/LocalRuleQuickJsRuntime'] = {LocalRuleQuickJsRequest:class {},
    LocalRuleQuickJsRuntime:{execute:async request => ({success:true,value:String(vm.runInNewContext(request.script,{}, {timeout:5000}))})}};
  delete stubs[prefix+'LightSourceSandbox'];
  const sandbox = load(prefix+'LightSourceSandbox').LightSourceSandbox;
  const evaluateCodec = script => sandbox.evaluate(LightSourceRuntime.polyfills()+'\n'+script,'https://engine.test');
  assert.equal(await evaluateCodec("new TextDecoder('gbk').decode(new Uint8Array([214,208,206,196]))"),'中文');
  assert.equal(await evaluateCodec("var d=new TextDecoder();d.decode(new Uint8Array([228,184]),{stream:true})+d.decode(new Uint8Array([173]))"),'中');
  assert.equal(await evaluateCodec("try{new TextDecoder('gbk').decode(new Uint8Array([214,208]))}catch(e){'fallback'}"),'中');
  console.log('PASS: script-only login entry, browser wait continuation, GBK and streaming codec replay');

  if (process.argv.includes('--live-imported-audio')) {
    const definition = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const imported = parser.parse(JSON.stringify(definition)).sources[0];
    imported.definition = codec.stringify(imported);
    const bookUrl = process.argv[process.argv.indexOf('--live-imported-audio')+1];
    liveOrigin = new URL(bookUrl).origin;
    const detail = JSON.parse(await engine.detail(JSON.stringify(imported),bookUrl,'{}'));
    const chapters = JSON.parse(await engine.toc(JSON.stringify(imported),detail.tocUrl || bookUrl,JSON.stringify(detail.variables)));
    assert.ok(chapters.length > 0,'live imported audio catalog exists');
    for (const chapter of chapters.slice(0,2)) {
      const content = JSON.parse(await engine.content(JSON.stringify(imported),chapter.url,
        JSON.stringify({...detail.variables,...chapter.variables})));
      assert.ok(/^https?:\/\//.test(content.audioUrl),'audio rule resolves a stream address');
      const probe = await fetch(content.audioUrl,{headers:{...content.requestHeaders,Range:'bytes=0-4095'},
        signal:AbortSignal.timeout(30000)});
      try { assert.ok(probe.ok,'media server accepts the resolved address and source headers'); }
      finally { await probe.body?.cancel(); }
      console.log(JSON.stringify({stage:'live-imported-audio',book:detail.name,chapter:chapter.name,
        chapters:chapters.length,status:probe.status,contentType:probe.headers.get('content-type'),
        hasReferer:!!content.requestHeaders.Referer}));
    }
  }
  if (process.argv[2] && !process.argv.includes('--live-imported-audio')) {
    const definition = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const nativeLocal = parser.parse(JSON.stringify(definition)).sources[0];
    assert.equal(nativeLocal.engine, 'light-native');
    nativeLocal.definition = codec.stringify(nativeLocal);
    const base = definition.url;
    repository.isInitialized = () => true;
    repository.get = async url => url === base ? nativeLocal : undefined;
    repository.list = async () => [nativeLocal];
    storage.set('lightSourceSaveLabel', 'save');
    storage.set('lightSourceLoginLabel', 'login');
    const styleUrl = `${base}/api/discover/style?tab=${encodeURIComponent('小说')}&source_type=${encodeURIComponent('男频')}`;
    fixtures.set(styleUrl, JSON.stringify({data:[{title:'排行榜'},{title:'fixture-category',url:'/api/discover?page={{page}}'}]}));
    LightSourceRuntime.host.getSource = async url => url === base ? JSON.stringify(nativeLocal) : '';
    states.delete(base);
    const panel = JSON.parse(await engine.panel(JSON.stringify(nativeLocal), false, 'save', 'login'));
    assert.equal(panel.entries.length, 2, 'native dynamic menus reach the app panel');
    const {LightSourceBridge} = load(prefix + 'LightSourceBridge');
    const {LocalRuleControl} = load('model/LocalRulePanel');
    LightSourceRuntime.host = new (load(prefix + 'LightSourceAppHost').LightSourceAppHost)();
    const appPanel = await LightSourceBridge.panel(nativeLocal, false);
    assert.equal(appPanel.entries.length, 2);
    assert.ok(appPanel.controls[0] instanceof LocalRuleControl, 'native controls use the app observed model');
    const mode = appPanel.controls.find(item => item.id === 'light-native-var:mode');
    // ArkUI serializes @Trace value as __ob_value, while value remains an accessor.
    for (const control of appPanel.controls) {
      control.__ob_value = control.value;
      delete control.value;
      Object.defineProperty(control, 'value', {enumerable:false,
        get() { return this.__ob_value; }, set(value) { this.__ob_value = value; }});
    }
    assert.equal(mode.options.length, 6);
    assert.equal(mode.value, '小说');
    assert.ok(panel.controls.some(item => item.id === 'light-native-var:channel'));
    mode.value = '听书';
    appPanel.controls.find(item => item.id === 'light-native-var:dp').value = 'stale-invalid-value';
    assert.equal(JSON.parse(JSON.stringify(mode)).value,undefined,'raw observed model JSON omits its value');
    await LightSourceBridge.panelAction(nativeLocal,mode,appPanel.controls);
    assert.equal(JSON.parse(JSON.parse(states.get(base)).variable).mode, '听书');
    assert.notEqual(JSON.parse(JSON.parse(states.get(base)).variable).dp,'stale-invalid-value', 'mode selection updates one key only');
    const audioStyle = `${base}/api/discover/style?tab=${encodeURIComponent('听书')}&source_type=${encodeURIComponent('男频')}`;
    fixtures.set(audioStyle, fixtures.get(styleUrl));
    const audioPanel = JSON.parse(await engine.panel(JSON.stringify(nativeLocal), false, 'save', 'login'));
    assert.equal(audioPanel.controls.find(item => item.id === mode.id).value, '听书', 'persisted source state survives reload');
    fixtures.set(`${base}/api/discover?page=2`, JSON.stringify({data:{books:[{book_id:'123',book_name:'audio edition',cover:'https://fixture/audio.jpg',book_type:'2'}]}}));
    const audioPreview = JSON.parse(await engine.explore(JSON.stringify(nativeLocal), audioPanel.entries[1].url, 2, 10)).books[0];
    assert.equal(audioPreview.contentType, 'audio');
    // Run the text fixture in novel mode; a source may correctly preserve audio intent in listening mode.
    const textFixtureState = JSON.parse(states.get(base));
    textFixtureState.variable = JSON.stringify({...JSON.parse(textFixtureState.variable),mode:'小说'});
    states.set(base,JSON.stringify(textFixtureState));
    fixtures.set(`${base}/api/detail?book_id=123`, JSON.stringify({data:{book_id:'123',name:'original novel',cover:'https://fixture/novel.jpg',book_type:'3',intro:'Intro'}}));
    const nativeDetail = JSON.parse(await engine.detail(JSON.stringify(nativeLocal), audioPreview.bookUrl,
      JSON.stringify({...audioPreview.variables,bookUrl:'https://fixture/stale-book'})));
    assert.equal(nativeDetail.name, 'original novel', 'detail rules still return the original novel title');
    assert.equal(nativeDetail.coverUrl, audioPreview.coverUrl, 'upstream keeps the selected edition cover');
    assert.equal(JSON.parse(nativeDetail.variables.__lightBook).bookUrl,audioPreview.bookUrl);
    assert.equal(nativeDetail.variables.bookUrl,audioPreview.bookUrl,'stale detail variables do not reach toc/content');
    assert.equal(nativeDetail.variables.bookId, '123');
    fixtures.set(`${base}/api/book?book_id=123`, JSON.stringify({data:{book_id:'123',volumes:[{title:'Volume',chapters:[{item_id:'456',title:'One'}]}]}}));
    const nativeToc = JSON.parse(await engine.toc(JSON.stringify(nativeLocal), nativeDetail.tocUrl, JSON.stringify(nativeDetail.variables)));
    assert.equal(nativeToc.length, 1);
    fixtures.set(nativeToc[0].url, JSON.stringify({data:{item_id:'456',book_id:'123',content:'first paragraph',content_type:'text'}}));
    fixtures.set(`${base}/api/para_comment/stats?chapter_id=456&book_id=123`, JSON.stringify({data:{paras:{}}}));
    const nativeContent = JSON.parse(await engine.content(JSON.stringify(nativeLocal), nativeToc[0].url, JSON.stringify(nativeToc[0].variables)));
    assert.equal(nativeContent.content.trim(), 'first paragraph');
    assert.ok(nativeContent.interactions.some(item => item.label === '本章说'));
    if (process.argv.includes('--live-audio') || process.argv.includes('--live-audio-categories')) {
      const liveAudioState = JSON.parse(states.get(base));
      liveAudioState.variable = JSON.stringify({...JSON.parse(liveAudioState.variable),mode:'听书'});
      states.set(base,JSON.stringify(liveAudioState));
      liveOrigin = new URL(base).origin;
      const livePanel = JSON.parse(await engine.panel(JSON.stringify(nativeLocal), false, 'save', 'login'));
      const category = livePanel.entries.find(item => item.url);
      assert.ok(category, 'live audio category exists');
      const liveBooks = JSON.parse(await engine.explore(JSON.stringify(nativeLocal), category.url, 1, 3)).books;
      assert.ok(liveBooks.length, 'live audio discovery returns books');
      for (const item of liveBooks.slice(0, 3)) {
        const detail = JSON.parse(await engine.detail(JSON.stringify(nativeLocal), item.bookUrl, JSON.stringify(item.variables)));
        const requestedId = new URL(item.bookUrl).searchParams.get('book_id');
        assert.equal(detail.variables.bookId, requestedId, 'audio detail identity matches discovery URL');
        assert.equal(detail.coverUrl,item.coverUrl,'live audio cover matches upstream preview preference');
        console.log(JSON.stringify({stage:'live-audio',id:requestedId,preview:item.name,detail:detail.name,
          sameCover:item.coverUrl === detail.coverUrl,type:item.contentType}));
      }
      if (process.argv.includes('--live-audio-categories')) {
        for (const entry of livePanel.entries.filter(item => item.url).slice(0,4)) {
          const item = JSON.parse(await engine.explore(JSON.stringify(nativeLocal),entry.url,1,1)).books[0];
          if (!item) continue;
          const detail = JSON.parse(await engine.detail(JSON.stringify(nativeLocal),item.bookUrl,JSON.stringify(item.variables)));
          const chapters = JSON.parse(await engine.toc(JSON.stringify(nativeLocal),detail.tocUrl,JSON.stringify(detail.variables)));
          const chapter = chapters.find(item => item.url && !item.isVolume);
          if (!chapter) continue;
          const content = JSON.parse(await engine.content(JSON.stringify(nativeLocal),chapter.url,JSON.stringify(chapter.variables)));
          console.log(JSON.stringify({stage:'live-audio-category',category:entry.title,name:item.name,
            previewType:item.variables.tab,detailType:detail.variables.tab,chapterType:chapter.variables.tab,
            mediaType:content.mediaType,hasAudio:!!content.audioUrl,textLength:content.content.length}));
          if (!content.audioUrl) {
            const response = await fetch(chapter.url.replace('tab=novel','tab=audio'),{signal:AbortSignal.timeout(20000)});
            const body = await response.json(); const data = body.data || {};
            console.log(JSON.stringify({stage:'diagnostic-audio-api',category:entry.title,status:response.status,
              responseKeys:Object.keys(body),contentType:data.content_type,hasProxy:!!data.content_proxy,
              contentIsUrl:/^https?:/.test(data.content || ''),contentLength:String(data.content || '').length}));
          }
        }
      }
    }
    if (process.argv.includes('--live-menu')) {
      states.delete(base);
      liveOrigin = new URL(base).origin;
      const livePanel = JSON.parse(await engine.panel(JSON.stringify(nativeLocal), false, 'save', 'login'));
      const categories = livePanel.entries.filter(item => item.url);
      assert.ok(categories.length > 0, 'live source dynamic categories are visible');
      console.log('PASS live native menu: '+categories.length+' categories');
    }
    console.log('PASS supplied native source: dynamic categories, six modes, settings persistence, paged discovery, detail, toc, text and chapter comments');
  }

  console.log('PASS: canonical HTML/JSON, complete source fields, search/detail/toc/content, bounded-stage bridge and native-format import');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
