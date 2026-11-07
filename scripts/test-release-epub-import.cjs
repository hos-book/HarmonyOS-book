// Verify the compiled EPUB dependency chain and names used across the Web/ArkTS boundary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const product = process.argv[2] || 'release';
const mode = process.argv[3] || 'release';
const cache = mode === 'release' ? JSON.parse(fs.readFileSync(path.join(root, 'build/outputs', product, 'symbol/release/entry/entry-nameCache.json'))) : { FileNameCache: {} };
const compiledRoot = path.join(root, 'entry/build', product, 'cache/default/default@CompileArkTS/esmodule', mode);
function mapped(relative) { return ('entry/src/main/ets/' + relative).split('/').map(part => cache.FileNameCache[part] || part).join('/'); }
function compiled(relative) { return fs.readFileSync(path.join(compiledRoot, mapped(relative) + '.ts'), 'utf8'); }
const parser = compiled('service/text/EpubParserService');
const caller = compiled('service/LocalBookImportService');
const reader = compiled('pages/ReaderPage');
const viewport = compiled('components/EpubOriginalReader');
for (const source of [parser, caller, reader, viewport]) assert.ok(!/readerservice|ReaderKit|createEpubReaderController/.test(source), 'compiled EPUB code must use only the self-developed implementation');
assert.ok(parser.includes(mapped('service/text/EpubArchive')));
assert.ok(parser.includes(mapped('service/text/EpubXml')));
assert.ok(caller.includes(mapped('service/text/EpubParserService')));
assert.ok(reader.includes(mapped('components/EpubOriginalReader')));
assert.ok(reader.includes(mapped('components/ReaderPageTurnComponent')));
for (const field of ['token', 'paged', 'spot', 'restorePage', 'paint', 'selected', 'report']) {
  assert.ok(new RegExp('\\b' + field + '\\b').test(viewport), 'Web bridge property must survive compilation: ' + field);
}
console.log('PASS compiled EPUB ZIP/XML dependencies, shared page turn and Web bridge contract (' + product + '/' + mode + ')');
