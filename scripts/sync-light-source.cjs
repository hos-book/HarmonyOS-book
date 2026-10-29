// Import the source engine only. UI, account, database and app configuration stay local.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const readerCacheBoundary = require('./light-reader-cache-boundary.cjs');
const project = path.resolve(__dirname, '..');
const args = process.argv.slice(2).filter(arg => arg !== '--check');
if (args.length !== 2) throw new Error('Usage: node scripts/sync-light-source.cjs <engine-repository> <application-repository> [--check]');
const checkOnly = process.argv.includes('--check');
const engineSource = path.resolve(args[0]);
const source = path.resolve(args[1]);
const sourceRoot = path.join(source, 'entry/src/main/ets');
const engineRoot = path.join(engineSource, 'sourceengine/src/main/ets');
// Never fall back to the application's old sourceengine copy.
const sourceRoots = [engineRoot, sourceRoot];
const readText = filename => fs.readFileSync(filename, 'utf8').replaceAll('\r\n', '\n');
function revision(root, paths) {
  const status = cp.execFileSync('git', ['-C', root, 'status', '--porcelain', '--', ...paths], { encoding: 'utf8' }).trim();
  if (status) throw new Error(`The upstream source working tree must be clean: ${root}`);
  // GitHub API archives are usable when Git transport is unavailable. The importer must
  // verify their complete Git tree against the pinned upstream commit before recording it.
  const archivePath = path.join(root, '.git/upstream-archive.json');
  if (fs.existsSync(archivePath)) {
    const archive = JSON.parse(fs.readFileSync(archivePath, 'utf8'));
    const tree = cp.execFileSync('git', ['-C', root, 'rev-parse', 'HEAD^{tree}'], { encoding: 'utf8' }).trim();
    if (!/^[a-f0-9]{40}$/.test(archive.commit) || tree !== archive.tree) throw new Error('Unverified upstream archive');
    return archive.commit;
  }
  return cp.execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
}
const sources = {
  engine: { repository: 'https://github.com/wip3l/harmony-book-source-engine',
    commit: revision(engineSource, ['sourceengine', 'LICENSE', 'NOTICE']) },
  application: { repository: 'https://github.com/wip3l/qingye-reader',
    commit: revision(source, ['entry/src/main/ets', 'LICENSE']) }
};
const exportOwners = new Map();
const packageIndex = path.join(engineSource, 'sourceengine/Index.ts');
if (!fs.existsSync(packageIndex)) throw new Error(`Missing independent engine entry: ${packageIndex}`);
if (fs.existsSync(packageIndex)) {
  const index = fs.readFileSync(packageIndex, 'utf8');
  for (const match of index.matchAll(/export\s*\{([^}]+)\}\s*from\s*['"]\.\/src\/main\/ets\/([^'"]+)['"]/g)) {
    for (const name of match[1].split(',').map(value => value.trim()).filter(Boolean)) {
      if (exportOwners.has(name)) throw new Error(`Duplicate sourceengine export: ${name}`);
      exportOwners.set(name, match[2]);
    }
  }
}
const locate = name => sourceRoots.map(root => path.join(root, name)).find(fs.existsSync);
function provenance(filename) {
  const owner = filename.startsWith(engineRoot + path.sep) ? 'engine' : 'application';
  return { source: owner, upstreamPath: path.relative(owner === 'engine' ? engineSource : source, filename).replaceAll('\\', '/') };
}
function rewritePackageImports(name, text) {
  return text.replace(/\b(import|export)\s*\{([^}]+)\}\s*from\s*['"]@legado\/sourceengine['"];?/g,
    (all, keyword, members) => {
      const groups = new Map();
      for (const member of members.split(',').map(value => value.trim()).filter(Boolean)) {
        const symbol = member.split(/\s+as\s+/)[0];
        const owner = exportOwners.get(symbol);
        if (!owner) throw new Error(`Unknown sourceengine export ${symbol} in ${name}`);
        if (!groups.has(owner)) groups.set(owner, []);
        groups.get(owner).push(member);
      }
      return [...groups].map(([owner, symbols]) => {
        let relative = path.posix.relative(path.posix.dirname(name), owner);
        if (!relative.startsWith('.')) relative = './' + relative;
        return `${keyword} { ${symbols.join(', ')} } from '${relative}';`;
      }).join('\n');
    });
}
const target = path.join(project, 'entry/src/main/ets/service/rulesource/light/upstream');
const manifestPath = path.join(project, 'third_party/light-source/upstream.json');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const excluded = new Set(['model/data/AppDatabase.ts']);
const seeds = ['core/book/WebBookService.ts', 'core/book/SearchCoordinator.ts',
  'core/book/AudioUrlResolver.ts',
  'core/nativesource/SourceCoverLoader.ts',
  'core/book/ExploreCoordinator.ts', 'core/nativesource/NativeSourceService.ts',
  'core/book/ReaderInteractionProvider.ts', 'core/book/BookSourceScriptRunner.ts',
  'core/book/BookSourceLoginWebRuntime.ts', 'core/http/RawHttpTextClient.ts'];
const files = new Map();
const visit = name => {
  if (files.has(name) || excluded.has(name)) return;
  const filename = locate(name);
  if (!filename) throw new Error(`Missing upstream module: ${name}`);
  const text = readText(filename);
  files.set(name, text);
  const dependencies = name === 'core/nativesource/NativeImageScriptRunner.ts' ?
    text.replace(/^import .* from '@devzeng\/quickjs';\n/m, '')
      .replace(/^import .* from '\.\/NativeImageTransform';\n/m, '') : readerCacheBoundary(name, text);
  for (const match of rewritePackageImports(name, name === 'core/book/ReaderCacheBudget.ts' ? '' : dependencies).matchAll(/(?:from\s*|import\s*)['"]([^'"]+)['"]/g)) {
    if (match[1].startsWith('@legado/sourceengine')) throw new Error(`Unsupported package import: ${match[1]}`);
    if (!match[1].startsWith('.')) continue;
    const base = path.posix.normalize(path.posix.join(path.posix.dirname(name), match[1]));
    const found = ['.ts', '.ets', '/index.ts', '/index.ets'].map(ext => base + ext).find(locate);
    if (!found) throw new Error(`Unresolved dependency ${name}: ${match[1]}`);
    const relative = found;
    if (relative.endsWith('.ets')) throw new Error(`UI dependency must be adapted explicitly: ${relative}`);
    visit(relative);
  }
};
seeds.forEach(visit);
const previous = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : null;
for (const entry of previous?.files || []) {
  const filename = path.join(target, entry.path);
  if (!fs.existsSync(filename) || (hash(fs.readFileSync(filename)) !== entry.sha256 && hash(readText(filename)) !== entry.sha256)) {
    throw new Error(`Local engine change: ${entry.path}. Update the adapter/patch before syncing.`);
  }
}
const replaceMethod = (text, signature, body) => {
  const expression = new RegExp('(^  ' + signature + '[\\s\\S]*?\\n  \\})', 'm');
  if (!expression.test(text)) throw new Error(`Upstream method changed: ${signature}`);
  return text.replace(expression, body);
};
function adapt(name, text) {
  text = readerCacheBoundary(name, text);
  if (name === 'core/book/ComicImagePipeline.ts') text = require('./light-image-protection.cjs')(text);
  if (name === 'core/book/ReaderCacheCoordinator.ts') {
    text = "import { ReaderCacheService } from '../../../../../ReaderCacheService';\n" + text;
    text = replaceMethod(text, 'static retainFile\\(', `  static retainFile(path: string): () => void {
    const normalized = ReaderCacheCoordinator.path(path);
    const release = ReaderCacheCoordinator.retain(ReaderCacheCoordinator.files, normalized);
    ReaderCacheService.hold(normalized);
    let released = false;
    return (): void => {
      if (released) return;
      released = true;
      release();
      ReaderCacheService.unhold(normalized);
    };
  }`);
  }
  if (name === 'core/book/ReaderCacheBudget.ts') return `
import { ReaderCacheService } from '../../../../../ReaderCacheService';
/** Cache lifetime belongs to the app, including active-reader holds and durable text chapters. */
export class ReaderCacheBudget {
  static touchComicFile(path: string): void { ReaderCacheService.record([path]).catch(() => {}); }
  static noteComicWrite(path?: string): void {
    if (path) ReaderCacheService.record([path]).catch(() => {});
    else ReaderCacheService.reconcile();
  }
}
`;
  if (name === 'core/book/WebBookService.ts') {
    const guard = '    if (!content || !content.includes(ReaderImageMarker.PREFIX)) return content;';
    if (text.split(guard).length !== 2) throw new Error('Upstream reader image entry changed');
    text = text.replace(guard, guard + '\n    if (cancelled()) throw new Error(HttpClient.CANCELLED_ERROR);' +
      '\n    // The app owns visible-image scheduling and source-bound decoding.' +
      '\n    if (SourceEngineHost.readerImagesDeferred(source)) return content;');
  }
  if (name === 'core/nativesource/NativeImageScriptRunner.ts') {
    text = text.replace(/^import .* from '@devzeng\/quickjs';\n/m, '')
      .replace(/^import .* from '\.\/NativeSourceCrypto';\n/m, '')
      .replace(/^import .* from '\.\/NativeImageTransform';\n/m, '');
    return replaceMethod(text, 'static async run\\(', `  static async run(js: string, fn: string, input: Uint8Array, context: NativeImageScriptContext,
    cancelled: () => boolean = (): boolean => false): Promise<Uint8Array> {
    const code = this.program(js, fn, context);
    if (!input.length || input.length > this.MAX_BYTES) throw new Error('图片脚本输入须为 1 字节至 20 MiB');
    if (cancelled()) throw new Error('书源请求已取消');
    const executor = SourceEngineHost.imageScripts();
    if (!executor) throw new Error('Image script requires the isolated host');
    const bytes = await executor.run(code, input, cancelled);
    if (cancelled()) throw new Error('书源请求已取消');
    if (!bytes.length || bytes.length > this.MAX_BYTES) throw new Error('图片脚本输出超过限制');
    return bytes;
  }`);
  }
  // Execution policy stays in host ports; upstream owns the web-wait behavior.
  // This host deliberately has no synchronous or pooled QuickJS runtime. Keep the
  // optional upstream defaults out of the dependency graph; nativeScripts supplies both paths.
  if (name === 'core/nativesource/NativeJsLibrary.ts') return `
import type { NativeScriptLibrary } from './NativeExpr';
export class NativeJsLibrary {
  static check(_code: string, _names: string[], _functions: string[] = []): string { return ''; }
  static forCode(_code: string): NativeScriptLibrary {
    return { has: () => true, call: () => { throw new Error('Native JS requires the isolated host'); } };
  }
}
`;
  if (name === 'core/nativesource/NativeScriptSessions.ts') return `
import type { NativeScriptEngine } from './NativeScriptHost';
export class NativeScriptSessions {
  static forCode(_code: string): NativeScriptEngine {
    throw new Error('Native script requires the isolated host');
  }
}
`;
  return rewritePackageImports(name, text).replaceAll('\r\n', '\n');
}

// Prepare and validate every transformation before mutating the working tree.
const generated = [...files].map(([name, original]) => ({ name, original, text: adapt(name, original) }));
// Both parsers have no platform imports. JSONPath must stay in the same bounded task
// as NativeExpr so each $.field access does not replay the entire batch across the host.
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const exprOriginal = files.get('core/nativesource/NativeExpr.ts') + '\n' + files.get('core/rule/JsonPathEvaluator.ts');
const exprProgram = ts.transpileModule(exprOriginal, { compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, removeComments: true
}}).outputText;
generated.push({ name: 'NativeExprProgram.ts', original: exprOriginal,
  origin: locate('core/nativesource/NativeExpr.ts'), generated: true,
  text: 'export const nativeExprProgram: string = ' + JSON.stringify(exprProgram) + ';\n' });
// Keep upstream CookieStore semantics reusable, while its persistence/session entry remains local.
const cookieOriginal = files.get('core/http/CookieStore.ts');
let cookieSemantics = cookieOriginal.replaceAll('CookieStore', 'LightCookieSemantics')
    .replace('fetchCookieSync(target)', 'fetchCookieSync(target, true)')
    .replace('fetchCookieSync(target, false, true)', 'fetchCookieSync(target, true, true)')
    .replaceAll('configCookieSync(target, value, false, true)', 'configCookieSync(target, value, true, true)')
    .replaceAll('configCookieSync(target, value)', 'configCookieSync(target, value, true)')
    .replace('clearAllCookiesSync()', 'clearAllCookiesSync(true)')
    .replace('private static withoutExpiredJwtCookies', 'static withoutExpiredJwtCookies');
cookieSemantics = replaceMethod(cookieSemantics, 'static saveAsync\\(',
  '  static saveAsync(): void { /* Encrypted persistence is flushed by the source lease. */ }');
generated.push({name:'core/http/LightCookieSemantics.ts',original:cookieOriginal,text:cookieSemantics,
  origin: locate('core/http/CookieStore.ts'), generated: true});
const page = fs.readFileSync(path.join(sourceRoot, 'pages/BookSource.ets'), 'utf8').replaceAll('\r\n', '\n');
const methods = ['parseBookSource', 'parseCompactRule', 'applyRuleToSearchRule', 'applyRuleToTocRule',
  'applyRuleToContentRule', 'applyRuleToBookInfoRule'].map(name => {
  const match = page.match(new RegExp('^  ' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Source import method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightSourceImport.ts', original: methods.join('\n'),
  origin: path.join(sourceRoot, 'pages/BookSource.ets'), generated: true, text:
  `import { BookSource, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from './model/data/Book';\n` +
  `export class LightSourceImport {\n${methods.join('\n\n')}\n}\n` });
// The package now provides a platform-free import entry; keep the existing application alias.
generated.push({ name: 'LightNativeImport.ts', original: files.get('core/nativesource/NativeSourceImport.ts'),
  origin: locate('core/nativesource/NativeSourceImport.ts'), generated: true,
  text: "export { NativeSourceImport as NativeSourceService } from './core/nativesource/NativeSourceImport';\n" });
// Upstream now shares the same resolver between playback and offline download; preserve the application alias.
generated.push({ name: 'LightAudioSupport.ts', original: files.get('core/book/AudioUrlResolver.ts'),
  origin: locate('core/book/AudioUrlResolver.ts'), generated: true,
  text: "export { AudioUrlResolver as LightAudioSupport } from './core/book/AudioUrlResolver';\n" });
const manifest = { schemaVersion: 2, sources, license: 'GPL-3.0',
  hashNormalization: 'LF',
  patches: ['host-visible-image-scheduling-v1', 'host-reader-cache-budget-v1', 'host-image-protection-v1',
    'host-reader-cache-boundary-v1', 'host-incognito-partitioned-cookies-v1'],
  files: generated.map(entry => ({ path: entry.name,
    ...provenance(entry.origin || locate(entry.name)),
    ...(entry.generated ? { generated: true } : {}),
    upstreamSha256: hash(entry.original), sha256: hash(entry.text) }))
};
const manifestText = JSON.stringify(manifest, null, 2) + '\n';
const license = readText(path.join(engineSource, 'LICENSE'));
const notice = readText(path.join(engineSource, 'NOTICE'));
if (checkOnly) {
  if (!previous || readText(manifestPath) !== manifestText) throw new Error('Upstream manifest differs; synchronize the pinned inputs first.');
  for (const entry of generated) {
    if (readText(path.join(target, entry.name)) !== entry.text) throw new Error(`Generated output differs: ${entry.name}`);
  }
  for (const folder of ['third_party/light-source', 'entry/src/main/resources/rawfile/third_party/light-source']) {
    if (readText(path.join(project, folder, 'LICENSE')) !== license || readText(path.join(project, folder, 'NOTICE')) !== notice) {
      throw new Error(`Upstream license/notice differs: ${folder}`);
    }
  }
  console.log(`Verified ${generated.length} files against both pinned upstream commits.`);
  process.exit(0);
}
for (const entry of previous?.files || []) {
  if (!generated.some(value => value.name === entry.path)) fs.unlinkSync(path.join(target, entry.path));
}
for (const entry of generated) {
  const filename = path.join(target, entry.name);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, entry.text);
}
const licenseDir = path.dirname(manifestPath);
fs.mkdirSync(licenseDir, { recursive: true });
fs.writeFileSync(path.join(licenseDir, 'LICENSE'), license);
fs.writeFileSync(path.join(licenseDir, 'NOTICE'), notice);
const packagedLicense = path.join(project, 'entry/src/main/resources/rawfile/third_party/light-source/LICENSE');
fs.mkdirSync(path.dirname(packagedLicense), {recursive:true});
fs.writeFileSync(packagedLicense, license);
fs.writeFileSync(path.join(path.dirname(packagedLicense), 'NOTICE'), notice);
fs.writeFileSync(manifestPath, manifestText);
console.log(`Imported ${generated.length} files. Engine: ${sources.engine.commit}; application helpers: ${sources.application.commit}. No pages copied.`);
