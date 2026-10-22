// Real imported pipeline, script wrapper and crypto adapter; Node substitutes platform APIs.
// Native interrupts/taskpool/NAPI still require a connected HarmonyOS device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/rulesource/light/upstream');
const files = new Map(), handles = new Map(), modules = new Map();
let nextHandle = 0, cancelled = false, downloaded = 0, executions = 0, partialWrite = false;
const cryptoFramework = {
  CryptoMode: { DECRYPT_MODE: 0, ENCRYPT_MODE: 1 },
  createMd(algorithm) {
    const value = crypto.createHash(algorithm.toLowerCase());
    const updateSync = blob => value.update(blob.data), digestSync = () => ({ data: new Uint8Array(value.digest()) });
    return { updateSync, digestSync, update: async blob => updateSync(blob), digest: async () => digestSync() };
  },
  createSymKeyGenerator() {
    const convertKeySync = blob => ({ data: Buffer.from(blob.data), clearMem() { this.data.fill(0); } });
    return { convertKeySync, convertKey: async blob => convertKeySync(blob) };
  },
  createCipher(transformation) {
    let cipher;
    const initSync = (mode, key, params) => {
      const [family, modeName, padding] = transformation.split('|');
      const algorithm = family.startsWith('AES') ? `aes-${family.slice(3)}-${modeName.toLowerCase()}` : 'des-ede3-cbc';
      cipher = (mode ? crypto.createCipheriv : crypto.createDecipheriv)(algorithm, key.data, params?.iv.data || null);
      cipher.setAutoPadding(padding !== 'NoPadding');
    };
    const doFinalSync = blob => ({ data: new Uint8Array(Buffer.concat([cipher.update(blob.data), cipher.final()])) });
    return { initSync, doFinalSync, init: async (...args) => initSync(...args), doFinal: async blob => doFinalSync(blob) };
  },
  createMac(algorithm) {
    let mac;
    const initSync = key => { mac = crypto.createHmac(algorithm.toLowerCase(), key.data); };
    const updateSync = blob => mac.update(blob.data), doFinalSync = () => ({ data: new Uint8Array(mac.digest()) });
    return { initSync, updateSync, doFinalSync, init: async key => initSync(key),
      update: async blob => updateSync(blob), doFinal: async () => doFinalSync() };
  }
};
const fileIo = { OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, mkdirSync() {},
  accessSync: filename => files.has(filename), unlinkSync: filename => files.delete(filename),
  openSync(filename) { handles.set(++nextHandle, filename); files.set(filename, Buffer.alloc(0)); return { fd: nextHandle }; },
  writeSync(fd, bytes) {
    const filename = handles.get(fd), data = Buffer.from(bytes);
    const count = partialWrite ? Math.min(7, data.length) : data.length;
    files.set(filename, Buffer.concat([files.get(filename), data.subarray(0, count)])); return count;
  }, closeSync(file) { handles.delete(file.fd); } };
const stubs = {
  '@ohos.file.fs': { default: fileIo }, '@kit.CryptoArchitectureKit': { cryptoFramework },
  '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } } }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name);
  const exports = {}; modules.set(name, exports);
  const filename = path.join(root, name + '.ts');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, setTimeout, Uint8Array, ArrayBuffer,
    AppStorage: { get: () => '/cache', setOrCreate() {} },
    require: dependency => load(dependency.startsWith('.') ?
      path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return exports;
}
const { SourceEngineHost } = load('core/host/SourceEngineHost');
const { NativeSourceSpec } = load('core/nativesource/NativeSourceSpec');
const { NativeSourceCrypto } = load('core/nativesource/NativeSourceCrypto');
const { NativeImageScriptRunner } = load('core/nativesource/NativeImageScriptRunner');
const { ComicImagePipeline } = load('core/book/ComicImagePipeline');
SourceEngineHost.install({ requests: { isCancelled: () => cancelled }, imageScripts: {
  async run(program, input) {
    executions++;
    const result = await vm.runInNewContext(program, { __imageInput: input.slice().buffer,
      __imageHost: (op, bytes, params) => NativeSourceCrypto.imageOperationSync(op, bytes, params).buffer
    }, { timeout: 2000 });
    if (ArrayBuffer.isView(result)) return new Uint8Array(result.buffer, result.byteOffset, result.byteLength);
    if (Object.prototype.toString.call(result) === '[object ArrayBuffer]') return new Uint8Array(result);
    throw new Error('invalid binary result');
  }
} });
const image = Uint8Array.from([255, 216, 255, ...Array(29).fill(7)]);
let body = image, afterDownload = () => {};
const http = { async executeBinary(request, limit) {
  assert.equal(limit, 20 * 1024 * 1024); assert.equal(request.cookieSource, 'fixture');
  downloaded++; afterDownload(); return { success: true, data: body };
} };
const source = { bookSourceUrl: 'fixture', jsLib: NativeSourceSpec.pack({
  sourceFormat: 'native', js: 'function decode(input,ctx){if(ctx.index!==ctx.params.expected)throw Error("index");return input.subarray(2);}'
}) };
const url = options => 'https://images.test/page,' + JSON.stringify(options);
async function materialize(options) { return ComicImagePipeline.materialize(http, source, url(options)); }
(async () => {
  body = Uint8Array.from([1, 2, ...image]); partialWrite = true;
  const options = { imageIndex: 3, decode: { script: 'decode', params: { expected: 3 } } };
  const first = await materialize(options);
  assert.deepEqual(files.get(first), Buffer.from(image), 'sliced bytes and partial writes preserve exact image');
  assert.equal(await materialize(options), first); assert.equal(downloaded, 1);
  options.headers = { Referer: 'https://reader.test/' };
  assert.notEqual(await materialize(options), first, 'headers participate in cache identity');
  options.imageIndex = 4; options.decode.params.expected = 4;
  assert.notEqual(await materialize(options), first, 'page index and params participate in cache identity');
  const before = executions;
  body = image; options.decode.processPlainImages = false;
  options.headers.Referer += 'plain';
  await materialize(options); assert.equal(executions, before, 'ordinary image bypasses script by default');
  source.jsLib = NativeSourceSpec.pack({ sourceFormat: 'native',
    js: 'async function decode(input,ctx){await Promise.resolve();input[31]=ctx.index;return input.buffer;}' });
  options.decode.processPlainImages = true;
  const plain = await materialize(options);
  assert.equal(files.get(plain)[31], 4); assert.equal(executions, before + 1);
  source.jsLib = NativeSourceSpec.pack({ sourceFormat: 'native', js: 'function decode(){throw Error("decode failed")}' });
  const count = files.size;
  await assert.rejects(materialize(options), /decode failed/); assert.equal(files.size, count);
  source.jsLib = NativeSourceSpec.pack({ sourceFormat: 'native', js: 'function decode(){return new Uint8Array([1,2,3]);}' });
  await assert.rejects(materialize(options), /有效图片/); assert.equal(files.size, count);
  source.jsLib = NativeSourceSpec.pack({ sourceFormat: 'native', js: 'function decode(input){return input;}' });
  afterDownload = () => { cancelled = true; };
  await assert.rejects(materialize(options), /cancelled/); assert.equal(files.size, count);
  cancelled = false; afterDownload = () => {};
  const key = '11'.repeat(16), iv = '22'.repeat(16), algorithm = 'AES/CBC/PKCS7Padding';
  const encrypted = await NativeSourceCrypto.imageOperation('encrypt', image, JSON.stringify({ algorithm, keyHex: key, ivHex: iv }));
  body = Uint8Array.from([...Buffer.from(iv, 'hex'), ...encrypted]);
  const decoded = await materialize({ decode: { algorithm, key, ivPrefixBytes: 16 } });
  assert.deepEqual(files.get(decoded), Buffer.from(image));
  await assert.rejects(materialize({ decode: { algorithm, key, iv, ivPrefixBytes: 16 } }), /前置 IV/);
  const script = `function decode(input){const encrypted=image.encrypt('${algorithm}',input,'${key}','${iv}');
    const decoded=image.decrypt('${algorithm}',encrypted,'${key}','${iv}');
    if(image.hash('SHA256',decoded).length!==32||image.hmac('SHA256',decoded,'${key}').length!==32)throw Error('hash');return decoded;}`;
  const result = await NativeImageScriptRunner.run(script, 'decode', image, { url: 'fixture', index: 0, params: {} });
  assert.deepEqual(Array.from(result), Array.from(image));
  for (const op of ['fetch', 'file', 'eval']) assert.throws(() => NativeSourceCrypto.imageOperationSync(op, image, '{}'), /不支持/);
  assert.throws(() => NativeSourceCrypto.imageOperationSync('decrypt', image,
    JSON.stringify({ algorithm, keyHex: key, ivHex: 'ff' })), /IV/);
  assert.throws(() => NativeImageScriptRunner.program(script, 'decode()', { url: '', index: 0, params: {} }), /函数名/);
  console.log('image scripts: pipeline bytes, async/ArrayBuffer, params/index, cache identity, plain-image opt-in, cancellation, failed decode, prefix IV and four crypto operations passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
