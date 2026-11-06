// Run the paginator's pure Hypium cases with the installed SDK transpiler.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src');
let localImages;
let apiVersion = 20;
function load(relative, mocks = {}) {
  const filename = path.join(root, relative);
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (name === './LocalTextImage') return localImages ??= load('main/ets/service/text/LocalTextImage.ets');
    if (name === './ReaderDialogueHighlighter') return load('main/ets/service/text/ReaderDialogueHighlighter.ets');
    if (name === '../../utils/PlatformCompat') return { PlatformCompat: { supports: version => apiVersion >= version } };
    if (!(name in mocks)) throw new Error(`Unexpected dependency: ${name}`);
    return mocks[name];
  } }, { filename });
  return exports;
}
const paginator = load('main/ets/service/text/OnlineTextPaginator.ets', { '@kit.ArkGraphics2D': {} });
let passed = 0;
load('test/OnlineTextPaginator.test.ets', {
  '../main/ets/service/text/OnlineTextPaginator': paginator,
  '@ohos/hypium': {
    describe: (_name, fn) => fn(),
    it: (name, _level, fn) => { fn(); passed++; console.log(`PASS ${name}`); },
    expect: value => ({
      assertEqual: expected => assert.equal(value, expected),
      assertContain: expected => assert.ok(value.includes(expected)),
      assertTrue: () => assert.equal(value, true),
      assertFalse: () => assert.equal(value, false)
    })
  }
}).default();
const { SpeechTextHighlighter } = load('main/ets/service/text/SpeechTextHighlighter.ets');
const source = '甲乙\n\n\u3000\u00A0\n丙丁';
const displayed = paginator.OnlineTextIndentedContent.fromNormalized(source);
const range = SpeechTextHighlighter.displayRange(displayed.text, source, source.indexOf('丙'), source.length);
assert.equal(displayed.text.substring(range.start, range.end), '丙丁');
console.log(`PASS ${passed} paginator cases and speech highlighting across collapsed blank paragraphs`);

// The graphics engine owns wrapping/justification. Rendering must keep its complete paragraph,
// even when a page ends in the middle of a paragraph or continuous mode shows a single line.
const built = [];
const graphicsText = {
  TextAlign: { LEFT: 0, RIGHT: 1, CENTER: 2, JUSTIFY: 3 },
  WordBreak: { BREAK_WORD: 0 }, BreakStrategy: { GREEDY: 0 },
  FontCollection: { getGlobalInstance: () => ({}) },
  ParagraphBuilder: class {
    constructor(style) { this.style = style; this.text = ''; this.indents = []; this.styles = []; }
    pushStyle(style) { this.styles.push(style); }
    addText(text) {
      if (text === '  ' && this.styles.length > 1) {
        this.indents.push({ ...this.styles.at(-1), offset: this.text.length });
      }
      this.text += text;
    }
    popStyle() { this.styles.pop(); }
    build() {
      const starts = this.style.headIndents === undefined ? [0, 4, 8] :
        this.text.includes('\n') ? [0, 2, 4] : [0, 2, 6];
      const paragraph = { text: this.text, indents: this.indents, style: this.style, layoutSync(width) { this.width = width; },
        getMaxIntrinsicWidth: () => this.style.textStyle.fontSize * 0.6,
        getLineMetrics: () => [
          { startIndex: starts[0], height: 20, baseline: 15, ascent: 15, descent: 5 },
          { startIndex: starts[1], height: 20, baseline: 35, ascent: 15, descent: 5 },
          { startIndex: starts[2], height: 20, baseline: 55, ascent: 15, descent: 5 }
        ] };
      if (this.text !== '  ') built.push(paragraph);
      return paragraph;
    }
  }
};
const native = load('main/ets/service/text/OnlineTextPaginator.ets', { '@kit.ArkGraphics2D': { text: graphicsText } });
const replacedContent = '\n\n甲乙\n\n\n丙丁&nbsp;';
const replacedPages = native.OnlineTextPaginator.paginate(replacedContent, 300, 40, 18, 1.9);
assert.equal(replacedPages.at(-1).endOffset, replacedContent.length,
  'replacement text retains its complete coordinate space, including newly blank paragraphs');
assert.ok(built.at(-1).text.includes('&nbsp;'), 'replacement output is literal text, not decoded a second time');
native.OnlineTextPaginator.invalidateLayouts();
localImages.LocalTextImage.setRoot('/files');
const token = localImages.LocalTextImage.token('/files/ebooks/import_fixture/image_0_0.img');
localImages.LocalTextImage.rememberSize('/files/ebooks/import_fixture/image_0_0.img', 80, 40);
const mixedBody = '图前正文有很多文字\n' + token + '\n图后正文有很多文字';
const mixedPages = native.OnlineTextPaginator.paginate(mixedBody, 300, 200, 18, 1.9);
assert.equal(mixedPages.length, 1, 'short text before and after a small image shares one page');
const imagePage = mixedPages[0].parts.find(page => page.imageUrl);
assert.ok(imagePage);
assert.equal(imagePage.startOffset, mixedBody.indexOf(token));
assert.equal(imagePage.endOffset, mixedBody.indexOf(token) + token.length);
assert.equal(imagePage.layoutHeight, 40);
assert.equal(imagePage.imageWidth, 80, 'small images are never enlarged');
assert.equal(mixedPages[0].parts.length, 3, 'adjacent text lines remain one selectable paragraph fragment');
assert.equal(mixedPages[0].parts[0].lineMetrics.length, 3);
assert.equal(mixedPages[0].parts[2].lineMetrics.length, 3);
assert.equal(mixedPages[0].layoutHeight, 160);
assert.equal(mixedPages.at(-1).endOffset, mixedBody.length);
assert.equal(localImages.LocalTextImage.speechContent(mixedBody).length, mixedBody.length);
const badToken = localImages.LocalTextImage.token('/files/secret');
assert.equal(native.OnlineTextPaginator.paginate(badToken, 300, 200, 18, 1.9).length, 0, 'invalid markers cannot create blank page loops');
const splitMixed = native.OnlineTextPaginator.paginate(mixedBody, 300, 90, 18, 1.9);
assert.ok(splitMixed.length > 1);
splitMixed.forEach(page => assert.ok(page.layoutHeight <= 90));
assert.equal(splitMixed[0].endOffset, splitMixed[1].startOffset);
assert.ok(splitMixed[1].parts.some(part => part.imageUrl));
assert.ok(splitMixed[1].parts.some(part => part.paragraph));
assert.equal(native.OnlineTextPaginator.pageIndexForOffset(splitMixed, mixedBody.indexOf(token)), 1);
localImages.LocalTextImage.rememberSize('/files/ebooks/import_fixture/image_0_0.img', 1200, 600);
const scaled = native.OnlineTextPaginator.paginate(token, 300, 200, 18, 1.9)[0].parts[0];
assert.equal(scaled.imageWidth, 300); assert.equal(scaled.layoutHeight, 150);
localImages.LocalTextImage.rememberSize('/files/ebooks/import_fixture/image_0_0.img', 100, 1000);
const tall = native.OnlineTextPaginator.paginate(token, 300, 200, 18, 1.9)[0].parts[0];
assert.equal(tall.imageWidth, 20); assert.equal(tall.layoutHeight, 200);
const scrollImage = native.OnlineTextPaginator.paginate(token, 300, 1, 18, 1.9)[0];
assert.equal(scrollImage.layoutHeight, 1000, 'continuous mode does not impose a full-page box');
const pair = native.OnlineTextPage.spreads(mixedBody, splitMixed);
assert.equal(pair[0].columns[1], splitMixed[1]);
console.log('PASS EPUB mixed text/images, intrinsic size, aspect ratio, overflow, scrolling, columns and stable source offsets');
for (const [alignment, expected] of [['justify', 3], ['start', 0], ['center', 2], ['end', 1]]) {
  const pages = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9, '', 400, alignment);
  assert.equal(pages.length, 3);
  const paragraph = built.at(-1);
  assert.equal(paragraph.style.align, expected);
  assert.equal(paragraph.text, '  甲乙丙丁戊己庚辛壬癸');
  assert.equal(paragraph.indents[0].letterSpacing, (36 - 18 * 0.6) / 2);
  pages.forEach((page, index) => {
    assert.equal(page.paragraph, paragraph, 'all slices retain original paragraph geometry');
    assert.equal(page.layoutTop, index * 20);
    assert.equal(page.layoutHeight, 20);
    assert.equal(page.displayStart, index * 4);
  });
  assert.equal(pages[1].startOffset, 2, 'saved positions exclude display indentation');
  assert.equal(pages[2].endOffset, 10);
}
console.log('PASS four alignments retain complete paragraph layout for page and scroll slices');

// Native fixed indentation must retain display offsets across source whitespace, blank lines,
// supplementary characters and font/viewport changes. Font space widths are compensated.
const mixedSource = '甲乙\n\u2002\u2003\u2009\u202F第二段\n\n\u3000第三段😀';
const mixedDisplay = paginator.OnlineTextIndentedContent.fromNormalized(mixedSource);
for (const size of [14, 18, 30]) {
  native.OnlineTextPaginator.paginate(mixedSource, 320, 600, size, 1.9, 'ImportedFont');
  const paragraph = built.at(-1);
  assert.equal(paragraph.text, '  甲乙\n  第二段\n  第三段😀');
  assert.equal(paragraph.text.length, mixedDisplay.text.length);
  assert.deepEqual(paragraph.indents.map(span => span.offset), [0, 5, 11]);
  assert.ok(paragraph.indents.every(span => Math.abs(size * 0.6 + span.letterSpacing * 2 - size * 2) < 0.001));
  assert.ok(paragraph.indents.every(span => span.fontFamilies[0] === 'ImportedFont'));
  for (const body of ['甲乙', '第二段', '第三段😀']) {
    assert.equal(mixedDisplay.sourceOffsetForDisplay(paragraph.text.indexOf(body)), mixedSource.indexOf(body));
  }
}
console.log('PASS fixed two-em indentation, mixed Unicode whitespace, font sizes and source offsets');

const paletteModule = load('main/ets/model/ReaderTheme.ets');
const { resolveReaderAccent } = load('main/ets/theme/ReaderAccentColor.ets', {
  '../model/AppAppearance': { AppAppearance: {
    normalizeAccent: value => /^#[\dA-F]{6}$/i.test(value) ? value.toUpperCase() : '',
    defaultAccent: '#C4475B'
  } },
  './Theme': { AppTheme: { resolve: () => ({ accent: '#2468AC' }) } }
});
let resourceColor = 0xFF2678AB;
const resourceContext = { resourceManager: { getColorSync: id => {
  assert.equal(id, 101, 'resolve the selected brand resource by its SDK-compatible numeric ID');
  return resourceColor;
} } };
assert.equal(resolveReaderAccent(resourceContext, '#12ab34'), '#12AB34');
assert.equal(resolveReaderAccent(resourceContext, { id: 101 }), '#2678AB');
resourceColor = 0xFF90CAEF;
assert.equal(resolveReaderAccent(resourceContext, { id: 101 }), '#90CAEF',
  'the same resource ID resolves again after dark/light configuration changes');
assert.equal(resolveReaderAccent(undefined, { id: 101 }), '#2468AC', 'unavailable resources retain the current bundle accent');
console.log('PASS theme accent resources, custom accent and dark/light re-resolution');
const highlighter = load('main/ets/service/text/SpeechTextHighlighter.ets');
let paintedColor;
const paints = [];
const ranges = [];
const page = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9)[1];
page.paragraph.updateColor = color => { paintedColor = color; };
page.paragraph.getTextLines = () => [0, 1, 2].map(index => ({
  paint: (_canvas, x, y) => paints.push({ index, x, y, color: paintedColor })
}));
page.paragraph.getRectsForRange = range => {
  ranges.push(range);
  return [{ rect: { left: 0, right: 100, top: 20, bottom: 40 } }];
};
graphicsText.RectWidthStyle = { TIGHT: 0 };
graphicsText.RectHeightStyle = { TIGHT: 0 };
let frameInvalidations = 0;
let highlightColor;
const nodeModule = load('main/ets/service/text/ReaderParagraphNode.ets', {
  '@kit.ArkGraphics2D': { text: graphicsText, drawing: {
    ClipOp: { INTERSECT: 0 }, Brush: class { setColor(value) { highlightColor = value; } }
  } },
  '@ohos.arkui.node': { FrameNode: class { invalidate() { frameInvalidations++; } getRenderNode() { return { invalidate() {} }; } }, NodeController: class {} },
  './OnlineTextPaginator': native,
  './SpeechTextHighlighter': highlighter,
  '../../model/ReaderTheme': paletteModule
});
const controller = new nodeModule.ReaderParagraphNodeController();
const nativeRange = new highlighter.SpeechHighlightRange();
nativeRange.start = 0; nativeRange.end = 2;
const palette = paletteModule.ReaderPalette.of('#FFFFFF', '#112233', '#555555', false);
palette.accent = '#2678AB';
controller.update(page, nativeRange, palette, 'highlight');
const node = controller.makeNode({});
const clips = [];
node.onDraw({ canvas: {
  save() {}, restore() {}, clipRect(rect) { clips.push(rect); },
  attachBrush() {}, detachBrush() {}, drawRect() {}
} });
assert.equal(paints.length, 2, 'base paragraph and translucent speech highlight are painted');
assert.equal(paints[0].index, 1, 'scroll row paints only its own line, not the complete chapter');
assert.equal(paints[1].index, 1, 'highlight redraws only that same line');
assert.equal(paints[0].x, 0, 'native lines already retain horizontal alignment');
assert.equal(paints[0].y, -page.layoutTop, 'native line coordinates remain relative to the original paragraph');
assert.equal(clips[0].bottom, 20, 'only the current row is visible');
assert.equal(ranges[0].start, page.displayStart, 'highlight uses full paragraph display coordinates');
assert.equal(paints[1].color.red, 17, 'highlight keeps readable original text instead of inverted white blocks');
assert.equal(highlightColor.alpha, 51, 'speech highlight is 80 percent transparent');
assert.equal(paintedColor.red, 17, 'shared paragraph color is restored before another row paints');
const nextPage = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9)[2];
const invalidationsBeforeTurn = frameInvalidations;
controller.update(nextPage, new highlighter.SpeechHighlightRange(), palette);
assert.equal(frameInvalidations, invalidationsBeforeTurn + 1, 'page turn schedules FrameNode.onDraw on the mounted node');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[0].index, 2, 'the same mounted node now paints the next page');
controller.update(page, new highlighter.SpeechHighlightRange(), palette);
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[0].index, 1, 'previous page / canceled preview redraws the original page');
console.log('PASS native paragraph clipping and speech highlight preserve measured geometry');

page.dialogueRanges = [{ start: 0, end: 2 }];
const dialogueRange = new highlighter.SpeechHighlightRange();
controller.update(page, dialogueRange, palette, 'color', true, '#3478AB');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.red, 0x34);
assert.equal(paints[1].color.green, 0x78);
assert.equal(paints[1].color.blue, 0xAB, 'dialogue paint uses the selected color');
const beforeColorChange = frameInvalidations;
controller.update(page, dialogueRange, palette, 'color', true, '#AB7834');
assert.equal(frameInvalidations, beforeColorChange + 1, 'color-only changes redraw an existing native paragraph');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.red, 0xAB);
assert.equal(paintedColor.red, 17, 'dialogue painting restores the shared text color');
controller.update(page, dialogueRange, palette, 'color', true, '');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.red, 0x26, 'automatic dialogue color uses the actual theme accent');
assert.equal(paints[1].color.blue, 0xAB);
const changedPalette = paletteModule.ReaderPalette.of('#FFFFFF', '#112233', '#555555', false);
changedPalette.accent = '#32965A';
const beforeThemeChange = frameInvalidations;
controller.update(page, dialogueRange, changedPalette, 'color', true, '');
assert.equal(frameInvalidations, beforeThemeChange + 1, 'theme-only changes invalidate the mounted paragraph');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.green, 0x96, 'existing dialogue repaints with the new accent');
controller.update(page, dialogueRange, changedPalette, 'color', true, '#AB7834');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.red, 0xAB, 'an explicit dialogue color overrides any theme accent');
page.dialogueRanges = [];
console.log('PASS custom dialogue colors, live theme repaint and custom-color isolation');

controller.update(page, nativeRange, palette, 'color', false, '', '#2678AB');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.red, 0x26, 'speech marks use their own custom color');
assert.equal(paints[1].color.blue, 0xAB);
const beforeSpeechColorChange = frameInvalidations;
controller.update(page, nativeRange, palette, 'color', false, '', '#AB7826');
assert.equal(frameInvalidations, beforeSpeechColorChange + 1, 'speech color changes redraw without pagination');
controller.update(page, nativeRange, palette, 'highlight', false, '', '#AB7826');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {}, attachBrush() {}, detachBrush() {}, drawRect() {} } });
assert.equal(paints[1].color.red, 17, 'background highlighting retains the original text color');
console.log('PASS custom speech mark colors, repaint and independent highlight mode');
controller.update(page, nativeRange, changedPalette, 'color', false, '', '');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[1].color.green, 0x96, 'automatic speech marks share the same theme accent');

const spreadContent = '甲乙丙丁戊己庚辛壬癸';
const columnPages = native.OnlineTextPaginator.paginate(spreadContent, 100, 20, 18, 1.9);
const spreads = native.OnlineTextPage.spreads(spreadContent, columnPages);
assert.equal(spreads.length, Math.ceil(columnPages.length / 2));
assert.equal(spreads[0].columns[0], columnPages[0], 'spread retains native left-column layout');
assert.equal(spreads[0].columns[1], columnPages[1], 'right column retains its own native offsets');
assert.equal(spreads.at(-1).endOffset, spreadContent.length, 'odd last column is not dropped');
for (let offset = 0; offset < spreadContent.length; offset++) {
  const index = native.OnlineTextPaginator.pageIndexForOffset(spreads, offset);
  assert.ok(spreads[index].startOffset <= offset && spreads[index].endOffset > offset,
    'single/double-column reflow restores every source character');
}
console.log('PASS dual-column spreads preserve native layouts and character-position restore');

const cacheText = '缓存复用验证甲乙丙丁戊己庚辛壬癸';
const beforeBuilds = built.length;
const cachedPages = native.OnlineTextPaginator.paginate(cacheText, 120, 20, 18, 1.9);
for (let height = 1; height <= 40; height++) {
  const resized = native.OnlineTextPaginator.paginate(cacheText, 120, height, 18, 1.9);
  assert.equal(resized[0].paragraph, cachedPages[0].paragraph);
  assert.equal(resized[0].layoutKey, cachedPages[0].layoutKey);
}
assert.equal(built.length, beforeBuilds + 1, 'page/scroll/height changes share one native measurement');
const wider = native.OnlineTextPaginator.paginate(cacheText, 150, 20, 18, 1.9);
assert.notEqual(wider[0].paragraph, cachedPages[0].paragraph);
assert.equal(built.length, beforeBuilds + 2);
native.OnlineTextPaginator.invalidateLayouts();
native.OnlineTextPaginator.paginate(cacheText, 120, 20, 18, 1.9);
assert.equal(built.length, beforeBuilds + 3, 'system font changes discard old native layouts');
const existingNode = controller.node;
controller.update(cachedPages[0], new highlighter.SpeechHighlightRange(), palette);
assert.equal(controller.node, existingNode, 'reflow updates the mounted node without rebuilding it');
console.log('PASS one measurement across 40 viewport changes, cache invalidation and native node reuse');

// Paragraph spacing adds no source characters and no gap at the top of a new page.
const sample = '甲\n乙\n丙丁';
const compact = native.OnlineTextPaginator.paginate(sample, 100, 60, 18, 1.9, '', 400, 'justify', 0);
const spaced = native.OnlineTextPaginator.paginate(sample, 100, 60, 18, 1.9, '', 400, 'justify', 1);
assert.equal(compact.length, 1);
assert.equal(spaced.length, 2);
assert.equal(spaced[0].layoutHeight, 58);
assert.equal(spaced[1].layoutHeight, 20);
assert.equal(spaced[1].lineShifts[0], 0);
assert.equal(spaced[0].endOffset, spaced[1].startOffset);
assert.equal(spaced[1].endOffset, sample.length);
assert.equal(native.OnlineTextPaginator.pageIndexForOffset(spaced, sample.indexOf('丙')), 1);
assert.notEqual(compact[0].layoutKey, spaced[0].layoutKey, 'spacing participates in the layout cache key');
const rows = native.OnlineTextPaginator.paginate(sample, 100, 1, 18, 1.9, '', 400, 'justify', 1);
assert.deepEqual(Array.from(rows, row => row.trailingSpacing), [18, 18, 0]);
assert.deepEqual(Array.from(rows, row => row.layoutHeight), [20, 20, 20]);
const whole = native.OnlineTextPaginator.paginate(sample, 100, 100, 18, 1.9, '', 400, 'justify', 1)[0];
assert.equal(whole.layoutHeight, 96);
assert.deepEqual(Array.from(whole.lineShifts), [0, 18, 36]);
whole.paragraph.updateColor = color => { paintedColor = color; };
whole.paragraph.getTextLines = () => [0, 1, 2].map(index => ({
  paint: (_canvas, x, y) => paints.push({ index, x, y, color: paintedColor })
}));
whole.paragraph.getRectsForRange = () => [0, 1, 2].map(index => ({
  rect: { left: 0, right: 100, top: index * 20, bottom: (index + 1) * 20 }
}));
const allRange = new highlighter.SpeechHighlightRange();
allRange.start = 0; allRange.end = whole.text.length;
controller.update(whole, allRange, palette, 'highlight');
paints.length = 0;
const highlighted = [];
node.onDraw({ canvas: {
  save() {}, restore() {}, clipRect() {}, attachBrush() {}, detachBrush() {},
  drawRect(left, top, right, bottom) { highlighted.push([top, bottom]); }
} });
assert.deepEqual(paints.slice(0, 3).map(p => p.y), [0, 18, 36]);
assert.deepEqual(highlighted, [[0, 20], [38, 58], [76, 96]], 'speech highlight skips the added paragraph gaps');
console.log('PASS paragraph spacing pagination, scroll gaps, source position, cache and speech highlight');

apiVersion = 26;
native.OnlineTextPaginator.invalidateLayouts();
const insetPages = native.OnlineTextPaginator.paginate(sample, 100, 100, 18, 1.9);
assert.equal(insetPages[0].paragraph.text, '甲\n乙\n丙丁');
assert.deepEqual(Array.from(insetPages[0].paragraph.style.headIndents), [36, 36, 36]);
assert.equal(insetPages[0].paragraph.indents.length, 0, 'native margins introduce no inline whitespace, markers or placeholders');
assert.equal(insetPages[0].nativeOffsets.nativeOffsetForDisplay(2), 0);
assert.equal(insetPages[0].nativeOffsets.nativeOffsetForDisplay(6), 2);
assert.equal(insetPages[0].nativeOffsets.displayOffsetForNative(4), 8);
const continued = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9);
assert.deepEqual(Array.from(continued[0].paragraph.style.headIndents), [36, 0, 0]);
assert.equal(continued[1].startOffset, 2);
assert.equal(continued[2].endOffset, 10);
insetPages[0].paragraph.updateColor = () => {};
insetPages[0].paragraph.getTextLines = () => [0, 1, 2].map(() => ({ paint() {} }));
let nativeHighlight;
insetPages[0].paragraph.getRectsForRange = range => { nativeHighlight = range; return []; };
const insetHighlight = new highlighter.SpeechHighlightRange();
insetHighlight.start = 6; insetHighlight.end = 7;
controller.update(insetPages[0], insetHighlight, palette);
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(nativeHighlight.start, 2);
assert.equal(nativeHighlight.end, 3);
console.log('PASS API 26 native first-line margins, native/display offset mapping and unindented continuation lines');

(async () => {
  let reads = 0, releases = 0;
  const sizing = load('main/ets/service/text/LocalTextImageSizing.ets', {
    '@kit.ImageKit': { image: { createImageSource: path => ({
      getImageInfo: async () => {
        reads++;
        if (path.includes('image_9_0')) throw new Error('broken image');
        return { size: { width: 240, height: 120 } };
      },
      release: async () => { releases++; }
    }) } }
  }).LocalTextImageSizing;
  const valid = '/files/ebooks/import_fixture/image_8_0.img';
  const broken = '/files/ebooks/import_fixture/image_9_0.img';
  const content = [valid, valid, broken, '/files/secret'].map(localImages.LocalTextImage.token).join('\n');
  await Promise.all([sizing.prepare(content), sizing.prepare(content)]);
  assert.equal(reads, 2, 'concurrent prepares share metadata probes and reject outside paths');
  assert.equal(releases, 2, 'image sources release on both success and failure');
  assert.equal(localImages.LocalTextImage.size(valid).width, 240);
  assert.equal(localImages.LocalTextImage.size(broken).width, 0);
  await sizing.prepare(content);
  assert.equal(reads, 2, 'cached dimensions do not reread images during reflow');
  console.log('PASS image metadata preparation, deduplication, bounded path access and release');
})().catch(error => { console.error(error); process.exitCode = 1; });
