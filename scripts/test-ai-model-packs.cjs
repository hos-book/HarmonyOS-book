// Exercise the real importer and ZIP parser with small pinned fixtures and platform file adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const { zip, platformZlib } = require('./epub-fixture.cjs');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-model-packs-'));
let available = 1024 ** 3, failPromotion = false, hashHook, largestRead = 0;
const fileIo = {
  OpenMode: { READ_ONLY: 1, CREATE: 2, WRITE_ONLY: 4, TRUNC: 8 },
  async access(p) { return fs.existsSync(p); },
  accessSync: fs.existsSync, statSync: fs.statSync,
  async stat(p) { return typeof p === 'number' ? fs.fstatSync(p) : fs.statSync(p); },
  async mkdir(p) { fs.mkdirSync(p, { recursive: true }); },
  async rmdir(p) {
    assert.ok(path.resolve(p).startsWith(path.resolve(temporary) + path.sep));
    fs.rmSync(p, { recursive: true });
  },
  async rename(a, b) {
    if (failPromotion && a.endsWith('.importing')) { failPromotion = false; throw Error('simulated rename failure'); }
    fs.renameSync(a, b);
  },
  async open(p, mode) { return { fd: fs.openSync(p, mode & 2 ? 'w' : 'r') }; },
  async close(f) { fs.closeSync(f.fd); },
  async read(fd, output, options = {}) {
    largestRead = Math.max(largestRead, output.byteLength);
    return fs.readSync(fd, Buffer.from(output), 0, options.length ?? output.byteLength, options.offset ?? null);
  },
  async write(fd, data) { return fs.writeSync(fd, Buffer.from(data)); },
  async fsync(fd) { fs.fsyncSync(fd); },
  async unlink(p) { fs.unlinkSync(p); }
};
function load(name, imports) {
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name + '.ets'), 'utf8')
    .replace(/@ObservedV2\s*|@Trace\s*/g, '');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, Error, $r: id => ({ id }), require: name => {
    if (!(name in imports)) throw Error('Missing adapter: ' + name);
    return imports[name];
  } });
  return exports;
}
const util = { TextDecoder: { create: encoding => ({ decodeToString: data => new TextDecoder(encoding).decode(data) }) } };
const catalog = load('model/AiModelPack', {});
const productionComic = catalog.AI_MODEL_PACKS.find(pack => pack.id === 'comic-color-v1');
const archive = load('service/text/EpubArchive', {
  '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': { util }, '@kit.BasicServicesKit': { zlib: platformZlib }
});
const releaseKey = process.argv.includes('--release-pack')
  ? fs.readFileSync(path.join(__dirname, '../signing/model-pack.key')) : crypto.randomBytes(32);
const keyId = crypto.createHash('sha256').update(releaseKey).digest('hex').slice(0, 16);
let cleared = 0;
const framework = {
  CryptoMode: { DECRYPT_MODE: 0 },
  createSymKeyGenerator: () => ({ convertKey: async blob => {
    const key = Buffer.from(blob.data);
    return { bytes: key, clearMem() { key.fill(0); cleared++; } };
  } }),
  createCipher: algorithm => {
    assert.equal(algorithm, 'AES256|GCM|NoPadding');
    let key, params;
    return { async init(_mode, k, p) { key = k; params = p; }, async doFinal(blob) {
      const cipher = crypto.createDecipheriv('aes-256-gcm', key.bytes, params.iv.data);
      cipher.setAAD(params.aad.data); cipher.setAuthTag(params.authTag.data);
      return { data: Buffer.concat([cipher.update(blob.data), cipher.final()]) };
    } };
  },
  createMd: () => {
    const md = crypto.createHash('sha256');
    return { update: async blob => { md.update(blob.data); hashHook?.(); }, digest: async () => ({ data: md.digest() }) };
  }
};
util.TextEncoder = class { encodeInto(value) { return new TextEncoder().encode(value); } };
const packCrypto = load('service/AiModelPackCrypto', {
  '@kit.CryptoArchitectureKit': { cryptoFramework: framework }, '@kit.ArkTS': { util },
  'libmodel_pack_crypto.so': { getKeyId: () => keyId, getKey: () => Uint8Array.from(releaseKey).buffer }
});
const { AiModelPackService } = load('service/AiModelPackService', {
  '@kit.CoreFileKit': { fileIo, picker: {}, statfs: { getFreeSize: async () => available } },
  '@kit.ArkTS': { util }, '../model/AiModelPack': catalog, './text/EpubArchive': archive,
  './AiModelPackCrypto': packCrypto,
  '@kit.CryptoArchitectureKit': { cryptoFramework: framework }
});
const payloads = [Buffer.alloc(catalog.AI_MODEL_CHUNK_BYTES + 13, 7), Buffer.from('pinned tokens')];
const assets = payloads.map((data, i) => new catalog.AiModelAsset('model-' + i, 'weight-' + i,
  data.length, crypto.createHash('sha256').update(data).digest('hex')));
catalog.AI_MODEL_PACKS.splice(0, catalog.AI_MODEL_PACKS.length,
  new catalog.AiModelPack('fixture-v1', 'fixture_models', assets));
let pack = catalog.AI_MODEL_PACKS[0];
function sealed(data, name, index, key = releaseKey) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(`JiantingModelPack/v2/${pack.id}/${name}/${index}`));
  return Buffer.concat([nonce, cipher.update(data), cipher.final(), cipher.getAuthTag()]);
}
function fixture(name, transform = entries => entries, key = releaseKey) {
  const manifest = { format: pack.encrypted ? 2 : 1, id: pack.id, chunkBytes: catalog.AI_MODEL_CHUNK_BYTES };
  if (pack.encrypted) Object.assign(manifest, { cipher: 'AES-256-GCM', keyId });
  const entries = [['model-pack.json', JSON.stringify(manifest)]];
  payloads.forEach((data, index) => {
    for (let offset = 0; offset < data.length; offset += catalog.AI_MODEL_CHUNK_BYTES) {
      let chunk = data.subarray(offset, offset + catalog.AI_MODEL_CHUNK_BYTES);
      if (pack.encrypted) chunk = sealed(chunk, assets[index].name, offset / catalog.AI_MODEL_CHUNK_BYTES, key);
      entries.push([`${assets[index].name}/${offset / catalog.AI_MODEL_CHUNK_BYTES}.bin`, chunk]);
    }
  });
  const output = path.join(temporary, name + '.zip');
  fs.writeFileSync(output, zip(transform(entries), { stored: true }));
  return output;
}
const context = { filesDir: temporary };
const service = new AiModelPackService();
const directory = path.join(temporary, 'fixture_models');
let stopped = 0, checks = 0;
const before = async () => { assert.equal(service.isBusy(pack.id), true); stopped++; };
const check = (name, fn) => { fn(); checks++; console.log('PASS ' + name); };
const install = file => service.importFile(context, pack.id, file, () => true, before);
(async () => {
  fs.mkdirSync(directory + '.previous');
  fs.writeFileSync(path.join(directory + '.previous', 'old'), 'old usable model');
  fs.mkdirSync(directory + '.importing');
  fs.writeFileSync(path.join(directory + '.importing', 'partial'), 'unfinished');
  await service.recover(context);
  check('interrupted directory swap restores previous model and removes staging', () => {
    assert.equal(fs.readFileSync(path.join(directory, 'old'), 'utf8'), 'old usable model');
    assert.equal(fs.existsSync(directory + '.importing'), false);
  });
  const valid = fixture('valid');
  assert.equal(await install(valid), true);
  check('bounded ZIP import verifies weights and commits the complete pack', () => {
    assert.equal(stopped, 1);
    assert.equal(service.usage(context, pack.id).installed, true);
    assert.deepEqual(fs.readFileSync(path.join(directory, assets[0].local)), payloads[0]);
    assert.ok(largestRead <= catalog.AI_MODEL_CHUNK_BYTES + 28);
    assert.equal(fs.existsSync(directory + '.previous'), false);
  });
  const corrupt = fixture('corrupt', entries => entries.map(([name, data]) =>
    name === 'model-0/0.bin' ? [name, Buffer.alloc(data.length, 9)] : [name, data]));
  await assert.rejects(install(corrupt), /model_pack_invalid/);
  check('SHA256 mismatch preserves the working model and cleans staging', () => {
    assert.deepEqual(fs.readFileSync(path.join(directory, assets[0].local)), payloads[0]);
    assert.equal(fs.existsSync(directory + '.importing'), false);
  });
  const wrong = fixture('wrong-id', entries => entries.map(([name, data]) => name === 'model-pack.json'
    ? [name, JSON.stringify({ format: 1, id: 'other-v1', chunkBytes: catalog.AI_MODEL_CHUNK_BYTES })] : [name, data]));
  await assert.rejects(install(wrong), /model_pack_invalid/);
  const traversal = fixture('traversal', entries => [...entries, ['../../escape', 'blocked']]);
  await assert.rejects(install(traversal), /model_pack_invalid/);
  check('wrong pack and traversal paths are rejected', () => assert.equal(service.usage(context, pack.id).installed, true));
  available = 1;
  await assert.rejects(install(valid), /model_pack_space/);
  available = 1024 ** 3;
  hashHook = () => service.cancel();
  assert.equal(await install(valid), false);
  hashHook = undefined;
  check('space failure and cancellation preserve existing models', () => {
    assert.equal(service.usage(context, pack.id).installed, true);
    assert.equal(fs.existsSync(directory + '.importing'), false);
    assert.equal(service.state.busyId, '');
  });
  failPromotion = true;
  await assert.rejects(install(valid), /model_pack_write/);
  check('promotion failure rolls the old directory back', () => assert.equal(service.usage(context, pack.id).installed, true));
  const unrelated = path.join(temporary, 'user-book.txt');
  fs.writeFileSync(unrelated, 'book');
  fs.mkdirSync(directory + '.previous');
  fs.writeFileSync(path.join(directory + '.previous', 'old'), 'cleanup residue');
  await service.remove(context, pack.id, before);
  check('delete frees only the selected model directory', () => {
    assert.equal(service.usage(context, pack.id).bytes, 0);
    assert.equal(fs.existsSync(directory + '.previous'), false, 'deletion cannot restore an obsolete backup on restart');
    assert.equal(fs.readFileSync(unrelated, 'utf8'), 'book');
  });
  pack = new catalog.AiModelPack('comic-color-v1', 'fixture_models', assets);
  catalog.AI_MODEL_PACKS.splice(0, catalog.AI_MODEL_PACKS.length, pack);
  assert.equal(service.usage(context, pack.id).installed, false, 'no bundled availability');
  const encrypted = fixture('encrypted');
  const originalWrite = fileIo.write;
  fileIo.write = async (fd, data) => fs.writeSync(fd, Buffer.from(data).subarray(0, 65536));
  assert.equal(await install(encrypted), true);
  fileIo.write = originalWrite;
  check('AES-GCM import authenticates every chunk and handles short writes', () => {
    assert.deepEqual(fs.readFileSync(path.join(directory, assets[0].local)), payloads[0]);
    assert.ok(largestRead <= catalog.AI_MODEL_CHUNK_BYTES + 28);
    assert.equal(cleared, 1);
  });
  const tampered = fixture('tampered', entries => entries.map(([name, data]) => {
    if (name === 'model-0/0.bin') { data = Buffer.from(data); data[12] ^= 1; }
    return [name, data];
  }));
  await assert.rejects(install(tampered), /model_pack_invalid/);
  const wrongKey = fixture('wrong-key', entries => entries, crypto.randomBytes(32));
  await assert.rejects(install(wrongKey), /model_pack_invalid/);
  check('tampered ciphertext and wrong release key reject while retaining old models', () => {
    assert.deepEqual(fs.readFileSync(path.join(directory, assets[0].local)), payloads[0]);
    assert.equal(cleared, 3);
  });
  const swapped = fixture('swapped-context', entries => entries.map(([name, data]) =>
    name === 'model-0/0.bin' ? [name, sealed(payloads[0].subarray(0, catalog.AI_MODEL_CHUNK_BYTES), 'model-1', 0)] : [name, data]));
  await assert.rejects(install(swapped), /model_pack_invalid/);
  const plain = fixture('plaintext', entries => entries.map(([name, data]) => name === 'model-pack.json'
    ? [name, JSON.stringify({ format: 1, id: pack.id, chunkBytes: catalog.AI_MODEL_CHUNK_BYTES })] : [name, data]));
  await assert.rejects(install(plain), /model_pack_invalid/);
  check('ciphertext cannot move between assets and legacy unencrypted comic packs are refused', () => {
    assert.equal(service.usage(context, pack.id).installed, true);
    assert.equal(fs.existsSync(directory + '.importing'), false);
  });
  hashHook = () => service.cancel();
  assert.equal(await install(encrypted), false);
  hashHook = undefined;
  check('encrypted import cancellation clears the key and preserves the working model', () => {
    assert.equal(cleared, 5);
    assert.equal(service.usage(context, pack.id).installed, true);
  });
  await service.remove(context, pack.id, before);
  const restarted = new AiModelPackService();
  await restarted.recover(context);
  check('removed external comic model remains missing after restart', () => {
    assert.equal(restarted.usage(context, pack.id).installed, false);
    assert.equal(fs.existsSync(directory), false);
  });
  if (process.argv.includes('--release-pack')) {
    catalog.AI_MODEL_PACKS.splice(0, catalog.AI_MODEL_PACKS.length, productionComic);
    assert.equal(await service.importFile(context, productionComic.id,
      path.join(__dirname, '../artifacts/model-packs/v1/Jianting-comic-color-v1.jtmodel'), () => true, async () => {}), true);
    check('Python release pack interoperates with actual ArkTS importer for all three pinned weights', () => {
      assert.equal(service.usage(context, productionComic.id).installed, true);
      for (const asset of productionComic.assets) {
        assert.equal(fs.statSync(path.join(temporary, productionComic.directory, asset.local)).size, asset.bytes);
      }
      assert.ok(largestRead <= catalog.AI_MODEL_CHUNK_BYTES + 28);
    });
  }
  console.log(`${checks} model pack checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  assert.ok(path.resolve(temporary).startsWith(path.resolve(os.tmpdir()) + path.sep));
  fs.rmSync(temporary, { recursive: true, force: true });
});
