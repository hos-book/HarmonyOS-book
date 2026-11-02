// Actual subtitle service and timeline with simulated platform/Worker; no model download.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(name, imports) {
  const mod = { exports: {} };
  const source = fs.readFileSync(path.join(root, name), 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  vm.runInNewContext(code, { module: mod, exports: mod.exports, require: n => {
    if (!(n in imports)) throw new Error(`Missing mock ${n}`);
    return imports[n];
  }, setTimeout, clearTimeout, console });
  return mod.exports;
}
const model = load('model/AudioSubtitle.ets', {});
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'audio-subtitle-test-'));
const hosts = [];
let ready = async () => true;
let modelDownloads = 0;
let preloadEnabled = false;
let cachedDuration = 180;
class Worker {
  requests = []; stopped = false;
  constructor() { hosts.push(this); }
  terminate() { this.stopped = true; }
  postMessage(value) { this.requests.push(value); }
  respond(text = '测试字幕') {
    const request = this.requests.at(-1);
    this.onmessage({ data: { requestId: request.requestId, error: '', chunk: {
      index: request.chunk, endMs: (request.chunk + 1) * 12000,
      cues: text ? [{ id: `chunk-${request.chunk}`, startMs: request.chunk * 12000,
        endMs: (request.chunk + 1) * 12000, text }] : []
    } } });
  }
}
const fileIo = {
  OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
  accessSync: fs.existsSync, mkdirSync: p => fs.mkdirSync(p, { recursive: true }),
  statSync: p => { const s = fs.statSync(p); return { size: s.size, mtime: s.mtimeMs, ctime: s.ctimeMs }; },
  listFileSync: fs.readdirSync, readTextSync: p => fs.readFileSync(p, 'utf8'),
  openSync: p => ({ fd: fs.openSync(p, 'w') }), writeSync: fs.writeSync,
  closeSync: f => fs.closeSync(f.fd), renameSync: fs.renameSync
};
const { AudioSubtitleService } = load('service/subtitle/AudioSubtitleService.ets', {
  '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': { worker: { ThreadWorker: Worker },
    util: { TextDecoder: { create: () => ({ decodeToString: b => Buffer.from(b).toString('utf8') }) } } },
  '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
  '../../model/AudioSubtitle': model,
  '../AudioService': { AudioService: { getInstance: () => ({ subtitleHeaders: () => ({}) }) } },
  '../ChapterCacheService': { ChapterCacheService: { getInstance: () => ({ getAudioFilePath: () => null,
    isPreloadEnabled: () => preloadEnabled, getChapterDuration: () => cachedDuration }) } },
  '../DownloadService': { DownloadService: { getInstance: () => ({ getDownloadedFilePath: () => null }) } },
  '../DownloadPolicy': { DownloadPolicy: { isHls: u => u.includes('.m3u8') } },
  './SubtitleFiles': { SubtitleFiles: {
    digest: async p => `fingerprint:${p}`, key: async s => crypto.createHash('sha256').update(s).digest('hex'),
    remove: p => { try { fs.unlinkSync(p); } catch {} }
  } },
  './SubtitleModelService': { SubtitleModelService: {
    preparePunctuation: async () => {}, ready: (...a) => ready(...a), directory: () => dir, ensure: async () => { modelDownloads++; }
  } }
});
const service = AudioSubtitleService.instance;
const context = { filesDir: dir, cacheDir: dir, resourceManager: {
  getRawFileContent: async name => fs.readFileSync(path.join(root, '../resources/rawfile', name))
} };
const chapter = { id: 'chapter-a', source: { type: 'file', value: '/fixture/audio.mp3' } };
const nextChapter = { id: 'chapter-next', duration: 180, source: { type: 'file', value: '/fixture/next.mp3' } };
const book = { id: 'a', sourceUrl: 'source:a', chapters: [chapter, nextChapter] };
let passed = 0;
function check(name, fn) { fn(); passed++; console.log(`PASS ${name}`); }
(async () => {
  const cues = [new model.SubtitleCue('a', 1000, 2000, 'a'), new model.SubtitleCue('b', 3000, 4000, 'b')];
  check('timeline: start/end and silence', () => {
    for (const [t, expected] of [[0,-1],[1000,0],[1999,0],[2000,-1],[2999,-1],[3000,1],[4000,-1]])
      assert.equal(model.SubtitleTimeline.activeIndex(cues, t), expected);
  });
  check('timeline: seek backwards uses media time', () => {
    assert.equal(model.SubtitleTimeline.activeIndex(cues, 3500), 1);
    assert.equal(model.SubtitleTimeline.activeIndex(cues, 1500), 0);
  });
  let digestCalls = 0;
  const { SubtitleModelService } = load('service/subtitle/SubtitleModelService.ets', {
    '@kit.CoreFileKit': { fileIo }, './SubtitleFiles': { SubtitleFiles: {
      digest: async p => { digestCalls++; return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'); }
    } }
  });
  const modelPath = path.join(dir, 'model-check'); fs.writeFileSync(modelPath, 'abcd');
  const asset = { name: 'model-check', bytes: 4, sha256: crypto.createHash('sha256').update('abcd').digest('hex') };
  assert.equal(await SubtitleModelService.valid(modelPath, asset, () => true), true);
  SubtitleModelService.verified.clear();
  assert.equal(await SubtitleModelService.valid(modelPath, asset, () => true), true);
  check('verified unchanged model survives cold start without hashing again', () => assert.equal(digestCalls, 1));
  fs.writeFileSync(modelPath, 'wxyz'); fs.utimesSync(modelPath, new Date(), new Date(Date.now() + 3000));
  assert.equal(await SubtitleModelService.valid(modelPath, asset, () => true), false);
  check('changed model is rehashed and corruption is rejected', () => assert.equal(digestCalls, 2));

  service.begin(context, { ...book, id: 'first-preview' }, chapter, 180000, 27000); await service.setup;
  const previewHost = hosts.at(-1);
  const previewRequest = previewHost.requests.at(-1);
  check('first recognition requests short provisional audio at the playhead', () => {
    assert.equal(previewRequest.preview, true); assert.equal(previewRequest.positionMs, 27000);
  });
  previewHost.onmessage({ data: { requestId: previewRequest.requestId, preview: true, error: '',
    chunk: { index: 2, endMs: 30500, units: [], annotated: [], cues: [
      { id: 'preview', text: '先显示的字幕', startMs: 26500, endMs: 30500, continues: true }
    ] } } });
  check('preview appears before full recognition and is never cached', () => {
    assert.equal(service.state.cues[0].text, '先显示的字幕');
    assert.equal(fs.existsSync(service.cachePath), false);
    assert.equal(previewHost.requests.at(-1).preview, false);
    assert.equal(previewHost.requests.at(-1).chunk, 2);
  });
  previewHost.respond('完整上下文字幕');
  check('full context replaces provisional text without duplication', () => {
    assert.equal(service.state.cues[0].text, '完整上下文字幕');
    assert.ok(!fs.readFileSync(service.cachePath, 'utf8').includes('先显示的字幕'));
  });
  service.release();
  service.begin(context, book, chapter, 180000, 25000); await service.setup;
  const first = hosts.at(-1);
  check('resume prioritizes current chunk', () => assert.equal(first.requests[0].chunk, 2));
  service.tick(110000); first.respond();
  check('seek reprioritizes after in-flight result', () => assert.equal(first.requests.at(-1).chunk, 9));
  for (let i = 0; i < 6; i++) first.respond();
  check('lookahead stops at chapter end', () => assert.equal(first.requests.length, 7));
  check('completed chunks saved', () => assert.ok(fs.readdirSync(path.join(dir, 'audio_subtitles')).some(n => n.endsWith('.json'))));
  service.begin(context, { ...book, id: 'b' }, { ...chapter, id: 'chapter-b' }, 180000, 0);
  await service.setup;
  first.respond('迟到的旧章');
  check('old chapter response discarded', () => assert.equal(service.state.cues.length, 0));
  const second = hosts.at(-1);
  service.release(); second.respond('关闭后的结果');
  check('close terminates worker and ignores results', () => {
    assert.equal(second.stopped, true); assert.equal(service.state.cues.length, 0);
  });
  service.begin(context, book, chapter, 180000, 25000); await service.setup;
  check('reopening restores cached text', () => assert.ok(service.state.cues.some(c => c.startMs === 24000)));
  service.release();
  const segmenter = model.SubtitleSegmenter;
  function chunk(index, text, output, final = false) {
    const value = new model.SubtitleChunk(); value.index = index; value.endMs = (index + 1) * 12000;
    value.units = segmenter.units(index, value.endMs, text, [], []);
    value.annotated = segmenter.punctuate(value.units, output, final);
    value.cues = segmenter.cues(index, value.annotated, final);
    return value;
  }
  check('sentence boundaries come from punctuation, not character count or commas', () => {
    const text = '因为外面突然下起了很大的雨所以他决定先在屋里等一会儿';
    const value = chunk(0, text, '因为外面突然下起了很大的雨，所以他决定先在屋里等一会儿。', true);
    assert.equal(value.cues.length, 1); assert.ok(value.cues[0].text.length > 18);
  });
  check('period and question mark separate complete sentences', () => {
    const value = chunk(0, '他拿起信你看过吗', '他拿起信。你看过吗？', true);
    assert.equal(value.cues.length, 2); assert.equal(value.cues[1].text, '你看过吗？');
  });
  check('context completes a sentence across audio windows without losing words', () => {
    const first = chunk(0, '他推开门走进屋里发现桌上', '他推开门走进屋里，发现桌上。');
    assert.equal(first.cues[0].continues, true);
    assert.ok(!first.cues[0].text.endsWith('。'));
    const second = chunk(1, '放着一封信他拿起信仔细看了起来', '放着一封信。他拿起信仔细看了起来。', true);
    const annotated = segmenter.punctuate([...first.units, ...second.units],
      '他推开门走进屋里，发现桌上放着一封信。他拿起信仔细看了起来。', true);
    first.cues = segmenter.cues(0, annotated, false);
    second.cues = segmenter.cues(1, annotated, true);
    first.annotated = annotated.filter(u => u.startMs < 12000);
    second.annotated = annotated.filter(u => u.startMs >= 12000);
    const result = segmenter.timeline([first, second]);
    assert.equal(result.length, 2);
    assert.equal(result[0].text, '他推开门走进屋里，发现桌上放着一封信。');
    assert.equal(result[1].text, '他拿起信仔细看了起来。');
    assert.equal(result[0].startMs, 0); assert.ok(result[0].endMs <= result[1].startMs);
    assert.deepEqual(JSON.parse(JSON.stringify(segmenter.timeline(JSON.parse(JSON.stringify([first, second]))))),
      JSON.parse(JSON.stringify(result)));
  });
  check('seek gaps never join unrelated sentences', () => {
    assert.equal(segmenter.timeline([chunk(0, '前句', '前句。'), chunk(2, '后句', '后句。')]).length, 2);
  });
  check('punctuation model cannot rewrite recognized words', () => {
    const value = chunk(0, '他拿起信', '他放下信。', true);
    assert.equal(value.cues.map(c => c.text).join(''), '他拿起信');
  });
  check('unaligned tokens preserve text with approximate timing', () => {
    const units = segmenter.units(1, 24000, '原文', ['<0xA0>'], [0.2]);
    assert.equal(segmenter.text(units), '原文'); assert.equal(units[0].startMs, 12000);
  });
  check('decimal point is not a sentence boundary', () => {
    const value = chunk(0, '数值是3.14没错', '数值是3.14，没错。', true);
    assert.equal(value.cues.length, 1); assert.equal(value.cues[0].text, '数值是3.14，没错。');
  });
  check('idioms remain whole across every possible audio-window split, despite wrong punctuation', () => {
    for (const word of ['喜出望外', '天造地设', '千钧一发', '不知所措', '恍然大悟', '迫不及待']) {
      for (let split = 1; split < word.length; split++) {
        const before = chunk(0, '他' + word.slice(0, split), '他' + word.slice(0, split) + '。', true);
        const after = chunk(1, word.slice(split) + '地走了出来', word.slice(split) + '，地走了出来。', true);
        const result = segmenter.timeline([before, after]);
        assert.ok(result.some(c => c.text.includes(word)), word + ':' + split + ' ' + JSON.stringify(result) +
          ' dictionary=' + segmenter.protectedWords.size);
        assert.equal(result.map(c => c.text).join('').replace(/[，。]/g, ''), '他' + word + '地走了出来');
        assert.equal(before.annotated.at(-1).sentenceEnd, true, 'display repair must not mutate cache');
      }
    }
  });
  check('long screenshot sentence splits at clauses with no lost text or invented timestamps', () => {
    const text = '水帘连呼没水没水，里面是一座铁板桥，那是一副天造地设的家当，而且地方非常宽敞，我们都进去住，也省的受老天的气。';
    const value = chunk(0, text.replace(/[，。]/g, ''), text, true);
    const result = segmenter.timeline([value]);
    assert.ok(result.length >= 2); assert.ok(result.every(c => c.text.length <= 42));
    assert.equal(result.map(c => c.text).join(''), text);
    assert.ok(result.slice(0,-1).every(c => /[，；]$/.test(c.text)));
    assert.ok(result.every((c,i) => c.startMs < c.endMs && (!i || c.startMs >= result[i-1].endMs)));
  });
  check('unpunctuated speech is not cut by length and seek gaps do not heal idioms', () => {
    const text = '他站在那里看着远方的山川久久没有说话'.repeat(4);
    assert.equal(segmenter.timeline([chunk(0,text,text,true)]).length, 1);
    assert.equal(segmenter.timeline([chunk(0,'喜出','喜出。',true),chunk(2,'望外','望外。',true)]).length, 2);
  });
  check('timing gap within adjacent windows cannot break a protected idiom', () => {
    const first = chunk(0, '小石猴喜出', '小石猴喜出。', true);
    first.annotated.at(-1).endMs = 10000;
    const second = chunk(1, '望外急忙闭目', '望外，急忙闭目。', true);
    const result = segmenter.timeline([first,second]);
    assert.equal(result.length, 1); assert.equal(result[0].text, '小石猴喜出望外，急忙闭目。');
  });
  const cacheBook = { ...book, id: 'annotated-cache' };
  service.begin(context, cacheBook, chapter, 24000, 0); await service.setup;
  const cacheHost = hosts.at(-1);
  const cachedFirst = chunk(0, '小石猴喜出', '小石猴喜出。', true);
  const cachedSecond = chunk(1, '望外急忙闭目', '望外，急忙闭目。', true);
  cacheHost.onmessage({ data: { requestId: cacheHost.requests.at(-1).requestId,
    error: '', chunk: cachedFirst } });
  cacheHost.onmessage({ data: { requestId: cacheHost.requests.at(-1).requestId,
    error: '', chunk: cachedSecond } });
  const cachedCues = JSON.stringify(service.state.cues);
  service.release(); service.begin(context, cacheBook, chapter, 24000, 0); await service.setup;
  check('annotated cache restore preserves cross-window idioms and sentence timing', () => {
    assert.equal(JSON.stringify(service.state.cues), cachedCues);
    assert.equal(service.state.cues[0].text, '小石猴喜出望外，急忙闭目。');
  });
  service.release();
  preloadEnabled = true;
  cachedDuration = 0;
  const earlyNext = { ...nextChapter, duration: 0 };
  service.begin(context, { ...book, id: 'early', chapters: [chapter, earlyNext], skipIntro: 36 }, chapter, 180000, 0);
  await service.setup; await new Promise(resolve => setImmediate(resolve));
  const earlyHost = hosts.at(-1);
  earlyHost.respond();
  check('filling future subtitles does not claim current subtitle is missing', () => assert.equal(service.state.phase, 'ready'));
  earlyHost.respond();
  check('next chapter gets opening buffer after 24 seconds even without duration metadata', () => {
    assert.equal(earlyHost.requests.at(-1).audioPath, earlyNext.source.value);
    assert.equal(earlyHost.requests.at(-1).chunk, 3);
    assert.equal(earlyHost.requests.length, 3);
  });
  earlyHost.respond(); earlyHost.respond();
  check('after next opening buffer scheduler returns to current chapter', () => {
    assert.equal(earlyHost.requests.at(-1).audioPath, chapter.source.value);
    assert.equal(earlyHost.requests.at(-1).chunk, 2);
  });
  service.release(); cachedDuration = 180;
  const preBook = { ...book, id: 'preload' };
  service.begin(context, preBook, chapter, 180000, 0); await service.setup;
  const preHost = hosts.at(-1);
  for (let i = 0; i < 10; i++) preHost.respond();
  await new Promise(resolve => setImmediate(resolve));
  check('next chapter starts when async preparation completes', () => {
    assert.equal(preHost.requests.length, 11);
    assert.equal(preHost.requests.at(-1).audioPath, nextChapter.source.value);
    assert.equal(service.state.cues.length, 10);
  });
  service.tick(150000); preHost.respond('下一章缓存');
  check('seek preempts speculative work after one in-flight job', () => {
    assert.equal(preHost.requests.at(-1).audioPath, chapter.source.value);
    assert.equal(preHost.requests.at(-1).chunk, 12);
    assert.ok(!service.state.cues.some(c => c.text === '下一章缓存'));
  });
  service.begin(context, preBook, nextChapter, 180000, 0); await service.setup;
  check('switching chapter restores prefetched subtitle', () => {
    assert.equal(service.state.cues[0].text, '下一章缓存');
    assert.equal(hosts.at(-1).requests[0].chunk, 1);
  });
  service.begin(context, { ...book, id: 'failure' }, chapter, 12000, 0); await service.setup;
  const failureHost = hosts.at(-1); failureHost.respond();
  await new Promise(resolve => setImmediate(resolve));
  failureHost.onmessage({ data: { requestId: failureHost.requests.at(-1).requestId,
    error: 'subtitle_decode_failed', chunk: { index: 0, cues: [] } } });
  check('next chapter decode failure preserves current subtitles', () => {
    assert.equal(service.state.phase, 'ready'); assert.equal(service.state.cues.length, 1);
    assert.equal(failureHost.stopped, false);
  });
  service.begin(context, { ...book, id: 'cancel-next' }, chapter, 12000, 0); await service.setup;
  const cancelHost = hosts.at(-1); cancelHost.respond();
  await new Promise(resolve => setImmediate(resolve));
  service.release(); cancelHost.respond('已取消');
  check('close cancels pre-recognition and discards late response', () => {
    assert.equal(cancelHost.stopped, true); assert.equal(service.state.cues.length, 0);
  });
  service.release(); preloadEnabled = false;
  service.begin(context, { ...book, id: 'disabled' }, chapter, 12000, 0); await service.setup;
  const disabledHost = hosts.at(-1); disabledHost.respond();
  await new Promise(resolve => setImmediate(resolve));
  check('preload disabled never schedules next chapter', () => assert.equal(disabledHost.requests.length, 1));
  service.release(); ready = async () => false;
  service.begin(context, book, chapter, 180000, 0); await service.setup;
  check('model download requires explicit UI action', () => {
    assert.equal(service.state.phase, 'needsModel'); assert.equal(modelDownloads, 0);
  });
  let finish;
  ready = () => new Promise(resolve => { finish = resolve; });
  service.begin(context, book, chapter, 180000, 0);
  await new Promise(resolve => setImmediate(resolve));
  const count = hosts.length; service.release(); finish(true); await service.setup;
  check('cancel during preparation does not create worker', () => assert.equal(hosts.length, count));
  ready = async () => true;
  service.begin(context, book, { ...chapter, source: { type: 'url', value: 'https://example.invalid/live.m3u8' } }, 180000, 0);
  await service.setup;
  check('unsupported streaming source fails without worker', () => {
    assert.equal(service.state.error, 'subtitle_unsupported'); assert.equal(hosts.length, count);
  });
  console.log(`${passed} audio subtitle checks passed`);
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => {
  service.release(); fs.rmSync(dir, { recursive: true, force: true });
});
