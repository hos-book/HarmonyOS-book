const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/text/ReadingExcerptShareService.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
const directory = '/private/cache/reading_excerpt_cards';

function fixture(options = {}) {
  const state = { files: new Map(), descriptors: new Map(), removed: [], canvases: [], pages: [],
    livePixels: 0, livePackers: 0, maxPixels: 0, maxPackers: 0, packs: 0, creates: 0, opens: 0,
    liveIconSources: 0, liveIcons: 0, iconDecodes: 0,
    cancelled: false };
  const pixelWidth = text => Array.from(text).reduce((width, char) =>
    width + (char === ' ' ? 13 : char.codePointAt(0) > 0xffff ? 42 : /[a-z0-9]/i.test(char) ? 20 : 38), 0);
  class Canvas {
    constructor(width, height, _settings, unit) {
      assert.equal(unit, 'px');
      assert.ok(width <= 960 && height <= 2200, 'canvas allocation stays below 8.1 MiB RGBA');
      this.width = width; this.height = height; this.draws = []; this.resets = 0;
      this.activeClip = null; this.savedClips = [];
      state.canvases.push(this);
    }
    reset() { this.draws = []; this.font = '10px sans-serif'; this.resets++; this.activeClip = null; this.savedClips = []; }
    measureText(text) { return { width: pixelWidth(text) }; }
    fillRect(x, y, width, height) { this.draws.push({ kind: 'rect', x, y, width, height, color: this.fillStyle }); }
    fillText(text, x, y, maxWidth) {
      assert.equal(this.activeClip, null, 'icon clipping must not clip later text or branding');
      this.draws.push({ kind: 'text', text, x, y, font: this.font, maxWidth, color: this.fillStyle });
    }
    save() { this.savedClips.push(this.activeClip); }
    restore() { assert.ok(this.savedClips.length > 0); this.activeClip = this.savedClips.pop(); }
    beginPath() { this.currentPath = []; }
    moveTo(x, y) { this.currentPath.push({ op: 'move', points: [x, y] }); }
    lineTo(x, y) { this.currentPath.push({ op: 'line', points: [x, y] }); }
    arcTo(x1, y1, x2, y2, radius) { this.currentPath.push({ op: 'arcTo', points: [x1, y1, x2, y2], radius }); }
    closePath() { this.currentPath.push({ op: 'close', points: [] }); }
    clip() { this.activeClip = this.currentPath.slice(); }
    bezierCurveTo(...points) { this.currentPath.push({ op: 'curve', points }); }
    arc(x, y, radius, start, end) { this.currentPath.push({ op: 'arc', points: [x, y], radius, start, end }); }
    stroke() { this.draws.push({ kind: 'stroke', path: this.currentPath.slice(), color: this.strokeStyle, width: this.lineWidth }); }
    fill() { this.draws.push({ kind: 'fill', path: this.currentPath.slice(), color: this.fillStyle }); }
    drawImage(icon, x, y, width, height) {
      assert.equal(icon.kind, 'app-icon'); assert.equal(state.liveIcons, 1, 'draw only a live application icon');
      this.draws.push({ kind: 'icon', x, y, width, height, clip: this.activeClip });
    }
    getPixelMap(x, y, width, height) {
      assert.equal(x, 0); assert.equal(y, 0);
      assert.ok(width > 0 && width <= this.width && height > 0 && height <= this.height);
      const page = { width, height, draws: this.draws.slice() };
      state.livePixels++; state.maxPixels = Math.max(state.maxPixels, state.livePixels);
      let released = false;
      return { page, async release() {
        assert.equal(released, false, 'pixel map released once'); released = true; state.livePixels--;
      } };
    }
  }
  const io = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    accessSync: () => true, mkdirSync() {},
    async listFile() { return options.oldFiles || []; },
    async open(file) {
      state.opens++;
      if (state.opens === options.failOpenAt) throw new Error('open failure');
      const descriptor = { fd: state.opens };
      state.files.set(file, null); state.descriptors.set(descriptor.fd, file);
      return descriptor;
    },
    async close(file) { assert.ok(state.descriptors.delete(file.fd), 'close the matching open descriptor'); },
    async unlink(file) { state.removed.push(file); state.files.delete(file); }
  };
  class SharedData {
    constructor(record) { this.records = [record]; }
    addRecord(record) { this.records.push(record); }
  }
  class ShareController { constructor(data) { this.data = data; } }
  const imports = {
    '@kit.ArkUI': { LengthMetricsUnit: { PX: 'px' } },
    '@kit.ImageKit': { image: { createImageSource(bytes) {
      assert.equal(bytes.byteLength, 4);
      if (options.failIconSource) throw new Error('icon source failure');
      state.liveIconSources++;
      let released = false;
      return {
        async createPixelMap(config) {
          assert.equal(config.desiredSize.width, 64); assert.equal(config.desiredSize.height, 64);
          state.iconDecodes++;
          if (options.failIconDecode) throw new Error('icon decode failure');
          state.liveIcons++;
          if (options.cancelAfterDecode) state.cancelled = true;
          let iconReleased = false;
          return { kind: 'app-icon', async release() {
            assert.equal(iconReleased, false); iconReleased = true; state.liveIcons--;
          } };
        },
        async release() { assert.equal(released, false); released = true; state.liveIconSources--; }
      };
    }, createImagePacker() {
      state.creates++;
      if (state.creates === options.failCreateAt) throw new Error('packer creation failure');
      state.livePackers++; state.maxPackers = Math.max(state.maxPackers, state.livePackers);
      let released = false;
      return {
        async packToFile(pixels, fd, encoding) {
          state.packs++;
          assert.equal(encoding.format, 'image/png');
          assert.equal(encoding.quality, 100);
          assert.ok(state.descriptors.has(fd), 'encode only into an open file');
          const file = state.descriptors.get(fd);
          state.files.set(file, pixels.page); state.pages.push(pixels.page);
          if (state.packs === options.cancelAfterPack) state.cancelled = true;
          if (state.packs === options.failPackAt) throw new Error('encoding failure');
        },
        async release() {
          assert.equal(released, false, 'packer released once'); released = true; state.livePackers--;
        }
      };
    } } },
    '@kit.CoreFileKit': { fileIo: io, fileUri: { getUriFromPath: file => 'file://app/' + path.basename(file) } },
    '@kit.ShareKit': { systemShare: { SharedData, ShareController } },
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { PNG: 'image/png' } } }
  };
  const exports = {};
  vm.runInNewContext(compiled, { exports, Error, Date,
    require: name => { assert.ok(name in imports, name); return imports[name]; },
    OffscreenCanvasRenderingContext2D: Canvas, RenderingContextSettings: class {},
    $r: id => ({ id })
  });
  return { Service: exports.ReadingExcerptShareService, state,
    context: { cacheDir: '/private/cache', resourceManager: {
      getStringSync: (id, date) => date || (id === 'app.string.reader_excerpt_brand' ? '简听阅读' : id),
      async getMediaContent(id) {
        assert.equal(id, 'app.media.app_icon_legacy', 'use the packaged default application icon');
        if (options.failIconResource) throw new Error('icon resource failure');
        return new Uint8Array([1, 2, 3, 4]);
      }
    } } };
}

const excerpt = text => ({ text, bookTitle: '这么多年', author: '八月长安', createdAt: 1775606400000 });
const body = page => page.draws.filter(draw => draw.font === '38px sans-serif');
function released(state) {
  assert.equal(state.livePixels, 0, 'all acquired pixel maps are released');
  assert.equal(state.livePackers, 0, 'all acquired image packers are released');
  assert.equal(state.liveIcons, 0, 'application icon pixel map is released');
  assert.equal(state.liveIconSources, 0, 'application icon image source is released');
  assert.equal(state.descriptors.size, 0, 'all opened output files are closed');
  assert.ok(state.maxPixels <= 1 && state.maxPackers <= 1, 'pages encode serially');
  assert.equal(state.canvases.length, 1, 'reuse a bounded canvas for all pages');
  assert.ok(state.canvases[0].resets > 0, 'canvas is cleared on exit');
}

async function main() {
  const short = fixture();
  await short.Service.cards(short.context, excerpt('第一段。\r\n\r\n第二段 😀。\r末段。'), () => false);
  assert.deepEqual(body(short.state.pages[0]).map(draw => draw.text), ['第一段。', '', '第二段 😀。', '末段。'],
    'CRLF, paragraph breaks, empty lines and emoji survive rendering');
  released(short.state);

  const long = fixture();
  const text = '多段长文 😀📚，每个句子都要完整保存。\n\n'.repeat(300);
  assert.ok(text.length < 20000);
  const files = await long.Service.cards(long.context, excerpt(text), () => false);
  assert.ok(files.length > 1 && files.length <= 60);
  assert.equal(new Set(files).size, files.length);
  const rendered = long.state.pages.flatMap(page => body(page));
  assert.equal(rendered.map(draw => draw.text).join(''), text.replace(/\n/g, ''), 'all selected characters reach the images in order');
  for (const page of long.state.pages) {
    assert.ok(page.height >= 640 && page.height <= 2200);
    const decoration = page.draws.filter(draw => draw.kind === 'stroke' || draw.kind === 'fill');
    assert.equal(decoration.filter(draw => draw.kind === 'stroke').length, 1);
    assert.equal(decoration.flatMap(draw => draw.path).filter(command => command.op === 'curve').length, 4,
      'every card includes four background curves');
    assert.equal(decoration.flatMap(draw => draw.path).filter(command => command.op === 'arc').length, 3,
      'every card includes three subtle dots');
    for (const draw of decoration) {
      assert.equal(draw.color, '#E9E5E0');
      assert.ok(page.draws.indexOf(draw) > 0 && page.draws.indexOf(draw) < page.draws.findIndex(item => item.kind === 'text'),
        'decoration is painted above the white background and below text');
      for (const command of draw.path) {
        for (let i = 0; i < command.points.length; i += 2) {
          assert.ok(command.points[i] >= page.width - 360 && command.points[i] <= page.width);
          assert.ok(command.points[i + 1] >= page.height - 272 && command.points[i + 1] <= page.height,
            'decoration stays inside the bottom-right bounded area');
        }
      }
    }
    const icons = page.draws.filter(draw => draw.kind === 'icon');
    assert.equal(icons.length, 1, 'each image includes the application icon');
    const icon = icons[0], brand = page.draws.find(draw => draw.text === '简听阅读');
    assert.equal(icon.width, 64); assert.equal(icon.height, 64);
    assert.ok(icon.clip && icon.clip.at(-1).op === 'close', 'icon uses a closed rounded clipping path');
    const corners = icon.clip.filter(command => command.op === 'arcTo');
    assert.equal(corners.length, 4);
    assert.ok(corners.every(command => command.radius === 16), 'all icon corners have a 16px radius');
    for (const command of icon.clip) {
      for (let i = 0; i < command.points.length; i += 2) {
        assert.ok(command.points[i] >= icon.x && command.points[i] <= icon.x + icon.width);
        assert.ok(command.points[i + 1] >= icon.y && command.points[i + 1] <= icon.y + icon.height);
      }
    }
    assert.equal(brand.x, icon.x + icon.width + 16);
    assert.equal((icon.x + brand.x + long.state.canvases[0].measureText(brand.text).width) / 2, page.width / 2,
      'icon and application name form one centered group');
    assert.equal(brand.color, '#3C4247');
    assert.equal(page.draws.filter(draw => draw.kind === 'rect').length, 1, 'only the page background remains, without the old accent bar');
    for (const draw of body(page)) {
      assert.equal(draw.maxWidth, undefined, 'body text is wrapped rather than squeezed or truncated');
      assert.ok(draw.x >= 0 && draw.x + long.state.canvases[0].measureText(draw.text).width <= page.width);
      assert.ok(draw.y >= 0 && draw.y + 60 < page.height, 'body remains inside image bounds');
      assert.ok(!/[\uD800-\uDBFF]$/.test(draw.text) && !/^[\uDC00-\uDFFF]/.test(draw.text), 'line wraps preserve UTF-16 surrogate pairs');
    }
  }
  const controller = long.Service.imageController(files, '这么多年');
  assert.equal(controller.data.records.length, files.length, 'every generated page is attached to sharing');
  assert.ok(controller.data.records.every(record => record.uri.startsWith('file://app/') && record.utd === 'image/png'));
  assert.equal(long.Service.text(excerpt(text)), text + '\n\n《这么多年》 / 八月长安');
  assert.equal(long.state.iconDecodes, 1, 'decode one bounded icon and reuse it across every page');
  released(long.state);

  for (const options of [{ cancelAfterPack: 1 }, { cancelAfterPack: 2 }, { failPackAt: 2 },
    { failOpenAt: 2 }, { failCreateAt: 2 }]) {
    const test = fixture(options);
    await assert.rejects(test.Service.cards(test.context, excerpt('正文\n'.repeat(35)), () => test.state.cancelled),
      /reading_excerpt_cancelled|encoding failure|open failure|packer creation failure/);
    assert.equal(test.state.files.size, 0, 'cancelled or failed exports leave no partial files');
    assert.ok(test.state.removed.length > 0);
    released(test.state);
  }
  const cancelled = fixture();
  await assert.rejects(cancelled.Service.cards(cancelled.context, excerpt('句子'), () => true), /reading_excerpt_cancelled/);
  assert.equal(cancelled.state.packs, 0); assert.equal(cancelled.state.files.size, 0); released(cancelled.state);

  for (const options of [{ failIconResource: true }, { failIconSource: true }, { failIconDecode: true },
    { cancelAfterDecode: true }]) {
    const test = fixture(options);
    await assert.rejects(test.Service.cards(test.context, excerpt('必须有完整应用标识'), () => test.state.cancelled),
      /icon resource failure|icon source failure|icon decode failure|reading_excerpt_cancelled/);
    assert.equal(test.state.packs, 0, 'never encode a card with a missing application icon');
    assert.equal(test.state.files.size, 0); released(test.state);
  }

  const oversized = fixture();
  await assert.rejects(oversized.Service.cards(oversized.context, excerpt('\n'.repeat(1680)), () => false),
    /reading_excerpt_card_limit/);
  assert.equal(oversized.state.packs, 0); assert.equal(oversized.state.files.size, 0); released(oversized.state);
  const expired = `excerpt_${Date.now() - 2 * 86400000}_00.png`;
  const recent = `excerpt_${Date.now()}_00.png`;
  const prune = fixture({ oldFiles: [expired, recent, 'keep.png'] });
  await prune.Service.cards(prune.context, excerpt('清理过期临时图'), () => false);
  assert.ok(prune.state.removed.includes(directory + '/' + expired));
  assert.ok(!prune.state.removed.includes(directory + '/' + recent));
  assert.ok(!prune.state.removed.includes(directory + '/keep.png'));
  released(prune.state);
  console.log('reading excerpt share passed: complete text, centered application icon/name, bounded decoding, pagination, cancellation and resource cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
