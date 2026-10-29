// Real import/template code; optional arguments verify user-provided JSON files.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const cache = new Map();
const http = { RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { ARRAY_BUFFER: 2 } };
function load(relative) {
  const file = path.resolve(root, relative);
  if (cache.has(file)) return cache.get(file);
  const source = fs.readFileSync(file, 'utf8').replace(/@ObservedV2\s*|@Trace\s*/g, '');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, console, require(name) {
    if (name === '@kit.NetworkKit') return { http };
    if (name.endsWith('/LocalRuleQuickJsRuntime')) return {
      LocalRuleQuickJsRequest: class {},
      LocalRuleQuickJsRuntime: { async execute(request) {
        assert.ok(request.timeoutMs <= 100);
        assert.equal(request.maxPendingJobs, 0);
        try { return { success: true, value: String(vm.runInNewContext(request.script, {}, { timeout: 100 })) }; }
        catch { return { success: false, value: '' }; }
      } }
    };
    if (name.startsWith('.')) return load(path.relative(root, path.resolve(path.dirname(file), name + '.ets')));
    throw new Error(`Unexpected dependency: ${name}`);
  } }, { filename: file });
  cache.set(file, module.exports);
  return module.exports;
}
const { CustomTtsConfigParser: Parser } = load('service/text/CustomTtsConfigParser.ets');
const parse = entry => Parser.parse(JSON.stringify(entry));
(async () => {
  const baidu = parse({ name: '百度测试', url: '@http://tts.example/text2audio?tex={{java.encodeURI(speakText)}}&spd={{~~((speakSpeed - 10) / 2 + 5)}}&per=3', header: '' })[0];
  assert.equal(baidu.method, 'POST');
  assert.equal(baidu.url, 'http://tts.example/text2audio');
  const sentence = '她说："你好"。\\下一行\n&测试=$1 {{text}}';
  for (const speed of [0.5, 1, 1.5, 2]) {
    const options = await Parser.requestOptions(baidu, sentence, speed);
    const params = new URLSearchParams(options.extraData);
    assert.equal(params.get('tex'), sentence);
    assert.equal(Number(params.get('spd')), Math.trunc(Math.round(speed * 10) / 2));
    assert.match(options.header['Content-Type'], /form-urlencoded/);
  }
  assert.equal(Parser.usesSpeed(baidu), true);
  const qd = parse({ name: '起点测试', url: 'http://voice.example/ifly,' + JSON.stringify({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: { text: '{{speakText}}', voice: 4001, speed: 50, volume: 50 } }) })[0];
  const payload = JSON.parse((await Parser.requestOptions(qd, sentence, 1.5)).extraData);
  assert.equal(payload.text, sentence);
  assert.equal(payload.voice, 4001);
  assert.equal(Parser.usesSpeed(qd), false); // player applies the requested rate once
  const kokoro = parse({ name: 'Kokoro-GPU·晓晓', url: 'http://192.168.50.17:8880/v1/audio/speech',
    method: 'POST', header: 'Content-Type: application/json',
    body: '{"model":"kokoro","input":"{{speakText}}","voice":"zf_xiaoxiao","response_format":"wav"}',
    contentType: 'audio/wav' })[0];
  const kokoroOptions = await Parser.requestOptions(kokoro, sentence, 1);
  assert.equal(kokoroOptions.method, 'POST');
  assert.equal(kokoroOptions.header['Content-Type'], 'application/json');
  assert.deepEqual(JSON.parse(kokoroOptions.extraData), {
    model: 'kokoro', input: sentence, voice: 'zf_xiaoxiao', response_format: 'wav'
  });
  const nested = parse({ name: '嵌套正文', url: 'http://tts.example/speech', method: 'post',
    header: 'Content-Type: application/json\r\nReferer: https://tts.example:8880/path\r\nX-Label: "test"',
    body: { request: { input: '{{speakText}}', voices: ['zh', 'en'] } } })[0];
  const nestedOptions = await Parser.requestOptions(nested, sentence, 1);
  assert.equal(JSON.parse(nestedOptions.extraData).request.input, sentence);
  assert.equal(nestedOptions.header.Referer, 'https://tts.example:8880/path');
  assert.equal(nestedOptions.header['X-Label'], '"test"');
  const get = parse({ name: 'GET 桥接', url: 'http://tts.example/tts?text={{java.encodeURI(speakText)}}&voice=zf_xiaoxiao' })[0];
  const getOptions = await Parser.requestOptions(get, sentence, 1);
  assert.equal(getOptions.method, 'GET');
  assert.equal(getOptions.extraData, undefined);
  assert.equal(new URL(await Parser.expand(get.url, sentence, 1, false)).searchParams.get('text'), sentence);
  assert.equal(Parser.parse(JSON.stringify([kokoro]))[0].id, kokoro.id);
  assert.equal(Parser.parse(JSON.stringify([nested]))[0].id, nested.id);
  assert.throws(() => parse({ name: 'bad', url: get.url, header: 'Content-Type application/json' }));
  assert.equal(Parser.parse(JSON.stringify([baidu]))[0].id, baidu.id);
  assert.equal(Parser.parse(JSON.stringify([qd]))[0].id, qd.id);
  assert.equal(parse({ name: '起点测试', url: 'http://voice.example/ifly,' + JSON.stringify({ method: 'POST', body: { text: '{{speakText}}', voice: 4001, speed: 50, volume: 50 }, headers: { 'Content-Type': 'application/json' } }) })[0].id, qd.id);
  assert.throws(() => parse({ name: 'bad', url: 'file:///tmp/{{text}}' }));
  assert.throws(() => parse({ name: 'bad', url: 'https://voice.example/{{text}}', loginCheckJs: 'doLogin()' }));
  assert.throws(() => parse({ name: 'bad', url: 'https://voice.example/{{text' }));
  assert.throws(() => Parser.parse('[]'));
  await assert.rejects(() => Parser.expand('{{(()=>{while(true){}})()}}', 'x', 1, false));
  await assert.rejects(() => Parser.expand('{{fetch("https://example.com")}}', 'x', 1, false));
  const imported = new Map();
  for (const file of process.argv.slice(2).filter(arg => arg !== '--probe')) {
    const configs = Parser.parse(fs.readFileSync(file, 'utf8'));
    for (const config of configs) {
      imported.set(config.id, config);
      const options = await Parser.requestOptions(config, '你好，这是语音测试。', 1);
      assert.equal(options.method, 'POST');
      assert.ok(options.extraData.length > 0);
      if (config.name.startsWith('度')) {
        assert.equal(new URLSearchParams(options.extraData).get('spd'), '5');
      } else {
        const payload = JSON.parse(options.extraData);
        assert.equal(payload.input ?? payload.text, '你好，这是语音测试。');
      }
    }
    console.log(`PASS ${path.basename(file)}: ${configs.length} 个音色`);
  }
  console.log(`PASS 模板兼容、JSON 转义、语速、持久化重读和脚本隔离；样本去重后 ${imported.size} 个音色`);
  if (process.argv.includes('--probe')) {
    const configs = [...imported.values()];
    const probes = [configs.find(config => config.name === '度博文'), ...configs.filter(config => config.name.startsWith('起点'))].filter(Boolean);
    for (const config of probes) {
      try {
        const text = '你好，这是语音测试。';
        const url = await Parser.expand(config.url, text, 1, false);
        const options = await Parser.requestOptions(config, text, 1);
        const response = await fetch(url, { method: options.method, headers: options.header,
          body: options.extraData, signal: AbortSignal.timeout(25000) });
        const bytes = Buffer.from(await response.arrayBuffer());
        console.log(`PROBE ${config.name}: HTTP ${response.status}, ${response.headers.get('content-type')}, ${bytes.length} bytes, magic=${bytes.subarray(0, 12).toString('hex')}`);
      } catch (error) { console.log(`PROBE ${config.name}: ${error.name}: ${error.message}`); }
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
