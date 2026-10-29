// Execute the real feed framer/parser and streaming worker. Python's XML DOM substitutes only the native XML codec.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
let streamChunks = () => [];
const sources = new Map();
const subscriptions = new Map();
const stubs = {
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: {
    getAll: async () => [...sources.values()], getByUrl: async url => sources.get(url),
    upsertImportedBatch: async values => {
      for (const source of values) sources.set(source.bookSourceUrl, source);
      return values.length;
    }
  } },
  'service/rulesource/podcast/PodcastRepository': { PodcastRepository: {
    save: async feed => subscriptions.set(feed.feedUrl, feed), list: async () => [...subscriptions.values()]
  } },
  'service/DataService': { DataService: { upsertCachedBook: async () => {} } },
  'service/SourceDataService': { SourceDataService: { invalidateLocalSources() {} } },
  'service/BookSourceService': { BookSourceService: {} },
  'service/ChapterCacheService': { ChapterCacheService: {} },
  'utils/SearchCache': { SearchCache: { put() {} } }
};
const xmlCodec = `import json,sys
from xml.dom import minidom
def node(n):
 if n.nodeType == n.ELEMENT_NODE:
  return {'name':n.tagName,'attributes':dict(n.attributes.items()),'elements':[node(c) for c in n.childNodes]}
 if n.nodeType == n.TEXT_NODE: return {'text':n.data}
 if n.nodeType == n.CDATA_SECTION_NODE: return {'cdata':n.data}
 return {}
print(json.dumps({'elements':[node(c) for c in minidom.parseString(sys.stdin.buffer.read()).childNodes]}))`;
const nativeXml = { ConvertXML: class {
  fastConvertToJSObject(xml) {
    const run = spawnSync('python', ['-c', xmlCodec], { input: xml, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    if (run.status !== 0) throw Error(run.stderr);
    return JSON.parse(run.stdout);
  }
} };
const http = { RequestMethod: { GET: 'GET' }, createHttp() {
  let receive, destroyed = false;
  return {
    on(event, callback) { assert.equal(event, 'dataReceive'); receive = callback; },
    async requestInStream() {
      for (const bytes of streamChunks()) {
        receive(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
        if (destroyed) throw { code: 2300023, message: 'stopped' };
      }
      return 200;
    },
    destroy() { destroyed = true; }
  };
} };
function load(relative) {
  const stem = relative.replace(/\.(ets|ts)$/, '').split(path.sep).join('/');
  if (stubs[stem]) return stubs[stem];
  const filename = ['.ets', '.ts'].map(ext => path.resolve(root, stem + ext)).find(fs.existsSync);
  if (!filename) throw Error('Missing module: ' + relative);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const source = fs.readFileSync(filename, 'utf8').replace(/^@Concurrent\s*$/gm, '');
  const localRequire = name => {
    if (name === '@ohos.convertxml') return { default: nativeXml };
    if (name === '@ohos.net.http') return { default: http };
    if (name === '@kit.ArkTS') return { url: { URL: { parseURL: (value, base) => new URL(value, base) } },
      util: { TextDecoder: { create: encoding => { const decoder = new TextDecoder(encoding); return {
        decodeToString: (bytes, options) => decoder.decode(bytes, options) }; } } } };
    if (name.startsWith('@')) return {};
    return load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')));
  };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true
  } }).outputText, { exports, require: localRequire, console, URL, TextDecoder, Uint8Array, ArrayBuffer, setTimeout,
    ObservedV2: value => value, Trace: () => {} }, { filename });
  return exports;
}
const { PodcastFeedParser } = load('service/rulesource/podcast/PodcastFeedParser.ets');
const { PodcastXmlStream } = load('service/rulesource/podcast/PodcastXmlStream.ets');
const { downloadPodcastFeed } = load('service/rulesource/podcast/PodcastFeedWorker.ets');
const { PodcastIdentity } = load('model/Podcast.ets');
const { PodcastDirectoryService } = load('service/rulesource/podcast/PodcastDirectoryService.ets');
const { PodcastService } = load('service/rulesource/podcast/PodcastService.ets');
const { PodcastSourceAdapter } = load('service/rulesource/podcast/PodcastSourceAdapter.ets');
const feedUrl = 'https://example.test/feed.xml';
const head = '<rss xmlns:itunes="https://example.test/itunes"><channel><title><![CDATA[中文节目]]></title><itunes:author>作者</itunes:author>';
const episode = (id, title, date) => `<item><guid>${id}</guid><title><![CDATA[${title}]]></title><description><![CDATA[literal </item> and <item>, 中文]]></description><enclosure type="audio/mpeg" url="https://example.test/${id}.mp3?a=1&amp;b=2"/><pubDate>${date}</pubDate><itunes:duration>01:02:03</itunes:duration></item>`;
const first = episode('one', '第一集', '2026-10-28');
const second = episode('two', '第二集', '2026-10-29');
const end = '</channel></rss>';
(async () => {
  const stream = new PodcastXmlStream(feedUrl);
  const xml = head + '<!-- <item> is not an entry -->' + first + second + end;
  for (const char of xml) stream.append(char);
  const parsed = stream.finish();
  assert.equal(parsed.title, '中文节目');
  assert.equal(parsed.episodes.length, 2);
  assert.equal(parsed.episodes[0].title, '第二集');
  assert.equal(parsed.episodes[1].audioUrl, 'https://example.test/one.mp3?a=1&b=2');
  assert.equal(parsed.episodes[1].durationSeconds, 3723);
  const before = PodcastFeedParser.parse(head + first + end, feedUrl);
  assert.equal(before.episodes[0].id, parsed.episodes[1].id, 'inserting a newer episode preserves saved progress identity');
  assert.equal(PodcastIdentity.chapterId('show', PodcastIdentity.episodeUrl(feedUrl, before.episodes[0].id)),
    PodcastIdentity.chapterId('show', PodcastIdentity.episodeUrl(feedUrl, parsed.episodes[1].id)));
  await PodcastService.subscribe(parsed);
  const imported = sources.get(feedUrl);
  assert.ok(PodcastSourceAdapter.matches(imported), 'real import validation preserves the RSS adapter marker');
  assert.equal(imported.nativeSearch, false, 'single-programme feeds do not advertise keyword search');
  assert.equal(imported.enabledExplore, false, 'subscribing does not replace the selected home source');
  const book = await PodcastService.playbackBook(parsed);
  assert.equal(book.chapters.length, 2);
  const media = await PodcastSourceAdapter.content(imported, book.chapters[0].source.value);
  assert.equal(media.audioUrl, parsed.episodes[0].audioUrl, 'saved episode identifiers resolve to the actual enclosure');
  await PodcastService.subscribe(parsed);
  assert.equal(sources.size, 1, 'resubscribing retains the same source definition');
  sources.delete(feedUrl);
  assert.equal((await PodcastService.subscriptions()).length, 0);
  await assert.rejects(PodcastService.playbackBook(parsed), /podcast_source_missing/);
  const atom = new PodcastXmlStream(feedUrl);
  atom.append('<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><id>a</id><title>episode</title><link rel="enclosure" type="audio/mpeg" href="/a.mp3"/></entry></feed>');
  assert.equal(atom.finish().episodes[0].audioUrl, 'https://example.test/a.mp3');
  assert.throws(() => { const value = new PodcastXmlStream(feedUrl); value.append('<!DOCTYPE rss><rss/>'); }, /podcast_invalid_feed/);
  assert.throws(() => { const value = new PodcastXmlStream(feedUrl); value.append(head + first); value.finish(); }, /podcast_invalid_feed/);
  const entry = { title: '节目', rssUrl: feedUrl, tags: ['科技'], latestEpisode: { title: '单集' } };
  const directory = PodcastDirectoryService.parse('<script>window.__INITIAL_DATA__ = ' + JSON.stringify({ featured: [entry, entry], rightNow: [], promoted: [] }) + ';</script>');
  assert.equal(directory.featured.length, 1);
  assert.throws(() => PodcastDirectoryService.parse('<script>window.__INITIAL_DATA__ = doSomething();</script>'));
  // Exercise 500 MiB through the real worker without allocating a 500 MiB string or returning synthetic success.
  const prefix = Buffer.from(head + first);
  const suffix = Buffer.from(end);
  const filler = Buffer.alloc(1024 * 1024, 32);
  streamChunks = function* () {
    yield prefix;
    let remaining = 500 * 1024 * 1024 - prefix.length - suffix.length;
    while (remaining > 0) { const count = Math.min(filler.length, remaining); yield filler.subarray(0, count); remaining -= count; }
    yield suffix;
  };
  const large = JSON.parse(await downloadPodcastFeed(feedUrl));
  assert.equal(large.episodes.length, 1);
  const allowed = streamChunks;
  streamChunks = function* () { yield* allowed(); yield Buffer.from(' '); };
  await assert.rejects(downloadPodcastFeed(feedUrl), /podcast_feed_too_large/);
  console.log('PASS: RSS/Atom, arbitrary chunk boundaries, real source import and subscription, playback URL mapping, stable progress IDs, directory parsing, 500 MiB acceptance and over-limit rejection');
})().catch(error => { console.error(error); process.exitCode = 1; });
