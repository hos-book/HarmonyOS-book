// Verify real audio catalog orchestration when a source uses different edition/novel metadata.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(file, dependencies = {}) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: {target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}
  }).outputText;
  vm.runInNewContext(code, {exports,console,Map,Set,Promise,Date,
    require:name => dependencies[name] || {}});
  return exports;
}
const {BookCoverPolicy} = compile('utils/BookCoverPolicy.ets', {
  '../model/BookPresentation': {BookPresentation: {get() {}}},
  '../service/rulesource/light/upstream/core/nativesource/SourceCoverUrl':
    compile('service/rulesource/light/upstream/core/nativesource/SourceCoverUrl.ts')
});
const {ChapterTitleFormatter} = compile('utils/ChapterTitleFormatter.ets');
const source = {rawSourceJson:'fixture',variable:'{}'};
const saved = [];
let resolvedVariables;
const {BookSourceService: service} = compile('service/BookSourceService.ets', {
  '../utils/BookCoverPolicy':{BookCoverPolicy},
  '../utils/ChapterTitleFormatter':{ChapterTitleFormatter},
  './rulesource/LocalRuleSourceRepository':{LocalRuleSourceRepository:{getByUrl:async () => source}},
  '../utils/SearchCache':{SearchCache:{put() {}}},
  './DataService':{DataService:{upsertCachedBook:async book => saved.push(book)}},
  './DownloadPolicy':{DownloadPolicy:{isHttpUrl:url=>url.startsWith('https://')}},
  './rulesource/LocalRuleDispatcher':{LocalRuleDispatcher:{resolveContent:async (_source,_url,variables)=>{
    resolvedVariables=variables;
    return {audioUrl:'https://fixture/audio.mp3',requestHeaders:{Referer:'https://fixture'}};
  }}}
});
const preview = {id:'audio-fixture',title:'有声版名称',author:'作者',cover:'https://fixture/audio.jpg',
  category:'有声书',intro:'',contentType:'audio',bookUrl:'https://fixture/detail?id=123',
  sourceUrl:'https://fixture',variables:{__lightBook:'{}'},tags:[],chapters:[],chapterCount:0};
service.getBookInfo = async (_source, url) => {
  assert.equal(url,preview.bookUrl);
  return {name:'原著名称',author:'作者',coverUrl:preview.cover,intro:'详情简介',kind:'',wordCount:'',
    lastChapter:'',tocUrl:'https://fixture/toc?id=123',variables:{bookId:'123'}};
};
service.getBookToc = async (_source,url,variables,_name,onBatch) => {
  assert.equal(url,'https://fixture/toc?id=123');
  assert.equal(variables.bookId,'123');
  const chapters = [{name:'第一章',url:'https://fixture/chapter?id=456'}];
  onBatch(chapters);
  return chapters;
};
async function run() {
  const {SourceVoiceDataSource} = compile('utils/SourceVoiceDataSource.ets');
  const voiceData = new SourceVoiceDataSource();
  const voices = [{id:'0',name:'真人原声'},{id:'1',name:'默认合成'},
    {id:'28',name:'亲切姐姐'},{id:'74',name:'成熟升级'},{id:'74',name:'重复'}];
  voiceData.setVoices(voices,{tones:'74,1,2,5,4,6,91',real:'7556227913956199449'});
  assert.deepEqual(Array.from({length:voiceData.totalCount()},(_,i)=>voiceData.getData(i).id),['0','1','74'],
    'book tones exclude unsupported voice 28 while retaining the related real edition');
  voiceData.setVoices(voices,{tones:' 74, 1 ',real:''});
  assert.deepEqual(Array.from({length:voiceData.totalCount()},(_,i)=>voiceData.getData(i).id),['1','74']);
  voiceData.setVoices(voices,{tones:''});
  assert.equal(voiceData.totalCount(),0,'explicit empty availability leaves only the separate default choice');
  voiceData.setVoices(voices,{});
  assert.equal(voiceData.totalCount(),4,'sources without per-book availability keep declared choices and deduplicate');
  const cached = {...preview,cover:'https://fixture/novel.jpg',coverFromDetail:true};
  BookCoverPolicy.merge(preview,cached);
  assert.equal(preview.cover,'https://fixture/audio.jpg','old detail cache cannot override fresh audio edition');
  const updates = [];
  const loaded = await service.loadAudioBook(preview,book => updates.push([book.title,book.cover]));
  assert.equal(loaded.title,preview.title);
  assert.equal(loaded.cover,preview.cover);
  assert.equal(loaded.chapters.length,1);
  assert.equal(loaded.tocComplete,true);
  assert.ok(updates.every(([title,cover]) => title === preview.title && cover === preview.cover));
  assert.equal(saved[0].title,preview.title,'persisted book keeps selected audio edition name');
  const unnamed = await service.loadAudioBook({...preview,id:'unnamed',title:''},() => {});
  assert.equal(unnamed.title,'原著名称','detail still fills missing titles');
  const text = {...preview,contentType:'text',cover:'https://fixture/search.jpg'};
  BookCoverPolicy.merge(text,cached);
  assert.equal(text.cover,'https://fixture/search.jpg','text covers also reuse the selected image');
  service.resolveLocalSource = async () => source;
  const chapter = {id:'old-chapter',index:1,title:'第一章',duration:90,
    source:{type:'url',value:'https://fixture/old-page.html'},
    originSourceValue:'https://fixture/old-page.html',variables:{__genericTocFallback:'true'}};
  const legacy = {...preview,chapters:[chapter],variables:{__audioTocDefinition:JSON.stringify([source.rawSourceJson,source.variable])}};
  await service.prepareAudioChapter(source,legacy,chapter);
  assert.equal(chapter.id,'old-chapter','migration preserves chapter identity and progress key');
  assert.equal(chapter.originSourceValue,'https://fixture/chapter?id=456');
  assert.equal(chapter.variables.__genericTocFallback,undefined,'obsolete fallback metadata is removed');
  assert.equal(JSON.parse(legacy.variables.__audioTocDefinition)[0],'light-source-toc-v1');
  const writes = saved.length;
  await service.prepareAudioChapter(source,legacy,chapter);
  assert.equal(saved.length,writes,'current catalogs are reused without another migration');
  const chapterVariables = {custom:'1',chapterName:'第一章'};
  await service.resolveAudioRequest(source,'https://fixture/chapter',{__audioSourceVoice:'74'},chapterVariables);
  assert.equal(resolvedVariables.custom,'74','selected book voice wins over old catalog voice');
  assert.equal(resolvedVariables.chapterName,'第一章');
  await service.resolveAudioRequest(source,'https://fixture/chapter',{__audioSourceVoice:''},chapterVariables);
  assert.equal(resolvedVariables.custom,'','default selection clears old catalog override');
  assert.equal(chapterVariables.custom,'1','switching does not mutate the chapter snapshot');
  service.getBookInfo = async () => { throw new Error('detail endpoint returned an empty response'); };
  let fallbackTocCalls = 0;
  service.getBookToc = async (_source,url,variables,_name,onBatch) => {
    fallbackTocCalls++;
    assert.equal(url,preview.bookUrl);
    assert.equal(variables.__lightBook,'{}');
    const chapters = [{name:'第一章',url:'https://fixture/chapter?id=456'}];
    onBatch(chapters); return chapters;
  };
  const recovered = await service.loadAudioBook({...preview,id:'detail-failed',chapters:[]},() => {});
  assert.equal(fallbackTocCalls,1,'failed detail must not prevent an independent catalog request');
  assert.equal(recovered.chapters.length,1);
  assert.equal(recovered.tocComplete,true);
  assert.equal(recovered.title,preview.title);
  service.getBookToc = async () => { throw new Error('catalog endpoint failed'); };
  await assert.rejects(service.loadAudioBook({...preview,id:'both-failed',chapters:[]},() => {}),/catalog endpoint failed/);
  console.log('PASS: audio edition identity, old cover cache, detail/toc variables, updates and persistence');
}
run().catch(error => {console.error(error);process.exitCode=1;});
