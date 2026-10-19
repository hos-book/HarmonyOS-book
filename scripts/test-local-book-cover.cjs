const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/LocalBookCoverService.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
async function main() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'local-book-cover-'));
  let created = 0, released = 0, failPack = false;
  const painted = [];
  const resource = () => { created++; return { async release() { released++; } }; };
  const image = {
    PixelMapFormat: { RGBA_8888: 3 },
    createImageSource: () => ({ ...resource(), async createPixelMap() { return resource(); } }),
    async createPixelMap() { return resource(); },
    createImagePacker: () => ({ ...resource(), async packToData() {
      if (failPack) throw new Error('encode failed');
      return new Uint8Array([1, 2, 3]).buffer;
    } })
  };
  const fileIo = {
    accessSync: fs.existsSync,
    mkdirSync(p) { fs.mkdirSync(p); }, // 目录已存在时抛错，验证重复渲染不会再次创建目录。
    statSync(p) { const s = fs.statSync(p); return { size: s.size, mtime: s.mtimeMs }; },
    OpenMode: { CREATE: 1, WRITE_ONLY: 2 },
    openSync(p) { return { fd: fs.openSync(p, 'w') }; },
    writeSync(fd, data) { fs.writeSync(fd, Buffer.from(data)); },
    closeSync(file) { fs.closeSync(file.fd); },
    renameSync: fs.renameSync, unlinkSync: fs.unlinkSync, listFileSync: fs.readdirSync
  };
  const modules = {
    '@kit.ImageKit': { image }, '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(s) { return Buffer.from(s); } }, generateRandomUUID: crypto.randomUUID } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => {
      const hash = crypto.createHash('sha256');
      return { async update({ data }) { hash.update(data); }, async digest() { return { data: hash.digest() }; } };
    } } },
    '@kit.ArkGraphics2D': { drawing: { Canvas: class { drawImageRect() {} } }, text: {
      FontWeight: { W700: 6, W400: 3 }, TextAlign: { CENTER: 2 }, WordBreak: { BREAK_WORD: 1 }, BreakStrategy: { GREEDY: 0 },
      FontCollection: { getGlobalInstance() { return {}; } },
      ParagraphBuilder: class {
        pushStyle() {} popStyle() {} addText(s) { this.content = s; }
        build() { const content = this.content; return { layoutSync() {}, getHeight: () => 30, paint() { painted.push(content); } }; }
      }
    } }, '@kit.PerformanceAnalysisKit': { hilog: { warn(...args) { if (!failPack) console.error(...args); } } }
  };
  const exports = {};
  vm.runInNewContext(code, { exports, require: key => modules[key] || {}, $r: () => ({ id: 1 }), ArrayBuffer, Uint8Array });
  const service = exports.LocalBookCoverService;
  const context = { cacheDir: directory, resourceManager: { async getMediaContent() { return new Uint8Array([1]); } } };
  try {
    const args = [context, 'import_a', '', '不科学恋爱', '照腰镜'];
    const paths = await Promise.all([service.resolve(...args), service.resolve(...args)]);
    assert.ok(paths[0]); assert.equal(paths[0], paths[1]);
    assert.deepEqual(painted, ['不科学恋爱', '照腰镜']);
    assert.equal(await service.resolve(...args), paths[0]);
    assert.equal(painted.length, 2, 'cache hit avoids redrawing');
    const changed = await service.resolve(context, 'import_a', '', '新书名', '新作者');
    assert.notEqual(changed, paths[0]);
    assert.equal(await service.resolve(context, 'import_a', '/custom.jpg', 'title', 'author'), '/custom.jpg');
    assert.equal(await service.resolve(context, 'online_a', '', 'title', 'author'), '');
    failPack = true;
    assert.equal(await service.resolve(context, 'import_failure', '', 'failure', ''), '');
    assert.equal(created, released, 'success, cache hits and failure release every native image resource');
    assert.equal(fs.readdirSync(path.join(directory, 'local_book_covers_v1')).length, 2);
    console.log('PASS local cover caching, concurrent requests, title/author updates, real-cover priority and native cleanup');
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
