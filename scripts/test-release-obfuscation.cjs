// Check actual compiled module boundaries; a successful Debug build cannot detect these failures.
// Usage: DEVECO_HOME=<Release IDE> node scripts/test-release-obfuscation.cjs [product] [mode]
const fs = require('node:fs');
const path = require('node:path');

function main() {
  const root = path.resolve(__dirname, '..');
  const product = process.argv[2] || 'release';
  const mode = process.argv[3] || 'release';
  if (!process.env.DEVECO_HOME) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio directory.');
  const ts = require(path.join(process.env.DEVECO_HOME,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
  const cache = mode === 'release' ? JSON.parse(fs.readFileSync(path.join(root,
    'build/outputs', product, 'symbol/release/entry/entry-nameCache.json'), 'utf8')) : { FileNameCache: {} };
  const compiledRoot = path.join(root, 'entry/build', product,
    'cache/default/default@CompileArkTS/esmodule', mode);
  const sourceRoot = path.join(root, 'entry/src/main/ets');
  const errors = [];
  const stats = { sourceFiles: 0, compiledFiles: 0, dynamicImports: 0, dynamicTargets: 0,
    runtimeExports: 0, namespaceMembers: 0, nativeModules: 0, nativeDeclarations: 0,
    nativeImports: 0, nativeDefaultImports: 0 };
  const relative = filename => path.relative(root, filename).replace(/\\/g, '/');
  const mapped = filename => relative(filename).replace(/\.(ets|ts)$/, '').split('/')
    .map(part => cache.FileNameCache[part] || part).join('/');
  const compiledPath = filename => path.join(compiledRoot, mapped(filename) + '.ts');
  const location = (sf, node) => relative(sf.fileName) + ':' + (sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1);
  function files(directory, accept) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
      const filename = path.join(directory, entry.name);
      return entry.isDirectory() ? files(filename, accept) : accept(filename) ? [filename] : [];
    }).sort();
  }
  const sourceFiles = files(sourceRoot, filename => /\.(ets|ts)$/.test(filename) && !/\.d\.(ets|ts)$/.test(filename));
  const compiledFiles = files(compiledRoot, filename => /\.ts$/.test(filename) && !/\.d\.ts$/.test(filename));
  const options = { target: ts.ScriptTarget.ESNext, noResolve: true, noLib: true, allowNonTsExtensions: true };
  const sourceProgram = ts.createProgram(sourceFiles, options);
  const compiledProgram = ts.createProgram(compiledFiles, options);
  const sourceChecker = sourceProgram.getTypeChecker();
  const compiledChecker = compiledProgram.getTypeChecker();
  const sourceOf = (program, filename) => {
    const sf = program.getSourceFile(filename);
    if (!sf) throw new Error('SDK TypeScript did not load ' + relative(filename));
    return sf;
  };
  const visit = (node, action) => { action(node); ts.forEachChild(node, child => visit(child, action)); };
  const dynamicCalls = sf => {
    const calls = [];
    visit(sf, node => { if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) calls.push(node); });
    return calls;
  };
  const exported = node => node.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.ExportKeyword);
  function runtimeExports(sf, nativeDeclaration = false) {
    const names = new Set();
    for (const statement of sf.statements) {
      if (ts.isExportDeclaration(statement)) {
        if (!statement.isTypeOnly) errors.push(location(sf, statement) + ': unsupported runtime re-export; add an explicit contract check.');
      } else if (ts.isExportAssignment(statement)) {
        names.add('default');
      } else if (exported(statement)) {
        // Native return-shape classes in .d.ts are types, not N-API export properties.
        if (nativeDeclaration && !ts.isVariableStatement(statement) && !ts.isFunctionDeclaration(statement)) continue;
        if (ts.isInterfaceDeclaration(statement) || ts.isTypeAliasDeclaration(statement)) continue;
        if (statement.modifiers.some(modifier => modifier.kind === ts.SyntaxKind.DefaultKeyword)) names.add('default');
        else if (ts.isVariableStatement(statement)) {
          for (const declaration of statement.declarationList.declarations) {
            if (ts.isIdentifier(declaration.name)) names.add(declaration.name.text);
            else errors.push(location(sf, declaration) + ': unsupported exported binding pattern.');
          }
        } else if ((ts.isClassDeclaration(statement) || ts.isFunctionDeclaration(statement) || ts.isEnumDeclaration(statement)) && statement.name) {
          names.add(statement.name.text);
        } else errors.push(location(sf, statement) + ': unsupported runtime export.');
      }
    }
    return names;
  }
  function namespaceMembers(sf, call, checker) {
    const awaited = call.parent;
    const declaration = ts.isAwaitExpression(awaited) ? awaited.parent : null;
    if (!declaration || !ts.isVariableDeclaration(declaration) || !ts.isIdentifier(declaration.name)) {
      errors.push(location(sf, call) + ': unsupported dynamic-import binding; expected const namespace = await import(...).');
      return [];
    }
    const symbol = checker.getSymbolAtLocation(declaration.name);
    if (!symbol) { errors.push(location(sf, declaration) + ': cannot resolve dynamic-import namespace binding.'); return []; }
    const members = new Set();
    visit(sf, node => {
      if (!ts.isIdentifier(node) || node === declaration.name || checker.getSymbolAtLocation(node) !== symbol) return;
      const parent = node.parent;
      if (ts.isPropertyAccessExpression(parent) && parent.expression === node) members.add(parent.name.text);
      else if (ts.isElementAccessExpression(parent) && parent.expression === node && ts.isStringLiteral(parent.argumentExpression)) members.add(parent.argumentExpression.text);
      else errors.push(location(sf, node) + ': unsupported dynamic namespace use; cannot prove the export name.');
    });
    if (members.size === 0) errors.push(location(sf, call) + ': dynamic import has no verifiable namespace member access.');
    return [...members].sort();
  }
  function targetOf(sf, call) {
    const argument = call.arguments[0];
    if (call.arguments.length !== 1 || !argument || !ts.isStringLiteral(argument) || !argument.text.startsWith('.')) {
      errors.push(location(sf, call) + ': unsupported dynamic import; expected one literal relative module path.');
      return null;
    }
    const base = path.resolve(path.dirname(sf.fileName), argument.text);
    const target = [base, base + '.ets', base + '.ts', path.join(base, 'Index.ets'), path.join(base, 'index.ts')]
      .find(filename => fs.existsSync(filename) && fs.statSync(filename).isFile());
    if (!target || !sourceFiles.includes(target)) {
      errors.push(location(sf, call) + ': dynamic target is outside the scanned sources or missing: ' + argument.text);
      return null;
    }
    return target;
  }
  const checkedTargets = new Map();
  for (const filename of sourceFiles) {
    stats.sourceFiles++;
    const sf = sourceOf(sourceProgram, filename);
    const calls = dynamicCalls(sf);
    if (!calls.length) continue;
    const builtFilename = compiledPath(filename);
    if (!fs.existsSync(builtFilename)) { errors.push(relative(filename) + ': compiled caller missing: ' + relative(builtFilename)); continue; }
    const built = sourceOf(compiledProgram, builtFilename);
    const builtCalls = dynamicCalls(built);
    if (calls.length !== builtCalls.length) errors.push(relative(filename) + ': dynamic-import count changed during compilation (' + calls.length + ' -> ' + builtCalls.length + ').');
    for (let index = 0; index < calls.length; index++) {
      stats.dynamicImports++;
      const call = calls[index];
      const target = targetOf(sf, call);
      if (!target) continue;
      const builtCall = builtCalls[index];
      const expectedPath = mapped(target);
      const argument = builtCall?.arguments[0];
      const actualPath = argument && ts.isStringLiteral(argument) ? argument.text.split('&')[3] : undefined;
      if (actualPath !== expectedPath) errors.push(location(sf, call) + ': dynamic path does not resolve to ' + relative(target) + '; expected ' + expectedPath + ', got ' + String(actualPath) + '.');
      if (!checkedTargets.has(target)) {
        const targetFile = compiledPath(target);
        if (!fs.existsSync(targetFile)) { errors.push(relative(target) + ': compiled dynamic target missing: ' + relative(targetFile)); checkedTargets.set(target, null); }
        else {
          const originalNames = runtimeExports(sourceOf(sourceProgram, target));
          const actualNames = runtimeExports(sourceOf(compiledProgram, targetFile));
          const identifiers = cache[relative(target)]?.IdentifierCache || {};
          for (const name of originalNames) {
            const emittedName = identifiers['#' + name] || cache.PropertyCache?.[name] || name;
            if (!actualNames.has(emittedName)) errors.push(relative(target) + ': runtime export ' + name + ' is missing from compiled target (expected ' + emittedName + ').');
          }
          checkedTargets.set(target, { originalNames, actualNames });
          stats.runtimeExports += originalNames.size;
        }
      }
      const exports = checkedTargets.get(target);
      const members = namespaceMembers(sf, call, sourceChecker);
      const builtMembers = builtCall ? namespaceMembers(built, builtCall, compiledChecker) : [];
      stats.namespaceMembers += members.length;
      for (const member of members) {
        if (!exports?.originalNames.has(member)) errors.push(location(sf, call) + ': namespace access is not a runtime export: ' + relative(target) + '#' + member + '.');
        else if (!exports.actualNames.has(member) || !builtMembers.includes(member)) errors.push(location(sf, call) + ': dynamic export broken: ' + relative(target) + '#' + member + '; compiled exports [' + [...exports.actualNames].join(', ') + '], namespace reads [' + builtMembers.join(', ') + '].');
      }
    }
  }
  stats.dynamicTargets = checkedTargets.size;

  const nativeModules = new Map();
  const nativeRoots = [path.join(root, 'entry/src/main/cpp/types')];
  const dependencies = path.join(root, 'entry/oh_modules');
  for (const dependency of fs.readdirSync(dependencies).filter(name => !name.startsWith('.'))) {
    const dependencyPath = path.join(dependencies, dependency);
    const packages = dependency.startsWith('@') ? fs.readdirSync(dependencyPath).map(name => path.join(dependencyPath, name)) : [dependencyPath];
    for (const packagePath of packages) {
      const candidate = path.join(packagePath, 'src/main/cpp/types');
      if (fs.existsSync(candidate)) nativeRoots.push(candidate);
    }
  }
  for (const nativeRoot of nativeRoots) {
    for (const directory of fs.readdirSync(nativeRoot, { withFileTypes: true }).filter(entry => entry.isDirectory())) {
      const directoryPath = path.join(nativeRoot, directory.name);
      const packageFile = path.join(directoryPath, 'oh-package.json5');
      const parsed = ts.parseConfigFileTextToJson(packageFile, fs.readFileSync(packageFile, 'utf8'));
      if (parsed.error || !parsed.config?.name?.endsWith('.so')) throw new Error('Cannot read native module name from ' + relative(packageFile));
      const names = new Set();
      for (const declaration of files(directoryPath, filename => /\.d\.ts$/.test(filename))) {
        stats.nativeDeclarations++;
        const sf = ts.createSourceFile(declaration, fs.readFileSync(declaration, 'utf8'), ts.ScriptTarget.Latest, true);
        for (const name of runtimeExports(sf, true)) names.add(name);
      }
      // Some native packages expose only a default object (for example QuickJS).
      // An empty named-export set is valid; a real named import is rejected below.
      nativeModules.set(parsed.config.name, names);
    }
  }
  stats.nativeModules = nativeModules.size;
  for (const filename of compiledFiles) {
    stats.compiledFiles++;
    const sf = sourceOf(compiledProgram, filename);
    for (const statement of sf.statements) {
      if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)) continue;
      const moduleName = statement.moduleSpecifier.text.match(/(?:^|[&/])([^&/]+\.so)(?:&|$)/)?.[1];
      if (!moduleName) continue;
      const clause = statement.importClause;
      if (!clause || clause.isTypeOnly) continue;
      // A default native object has no named ESM import to rename.
      // Count it separately; the named-export check below must cover every named native import.
      if (clause.name) stats.nativeDefaultImports++;
      if (clause.name && !clause.namedBindings) continue;
      const names = nativeModules.get(moduleName);
      if (!names) { errors.push(location(sf, statement) + ': named native module has no scanned declaration: ' + moduleName); continue; }
      if (!clause.namedBindings || !ts.isNamedImports(clause.namedBindings)) {
        errors.push(location(sf, statement) + ': unsupported native import shape: ' + moduleName); continue;
      }
      for (const element of clause.namedBindings.elements) {
        if (element.isTypeOnly) continue;
        stats.nativeImports++;
        const importedName = (element.propertyName || element.name).text;
        if (!names.has(importedName)) {
          const originals = [...names].filter(name => cache.PropertyCache?.[name] === importedName);
          errors.push(location(sf, element) + ': native export broken: ' + moduleName + '#' + importedName +
            (originals.length ? ' (renamed from ' + originals.join(', ') + ')' : '') + '; declared exports [' + [...names].join(', ') + '].');
        }
      }
    }
  }
  console.log('Obfuscation contract coverage (' + product + '/' + mode + '): ' + JSON.stringify(stats));
  if (errors.length) {
    for (const error of errors) console.error('FAIL ' + error);
    process.exitCode = 1;
  } else console.log('PASS compiled dynamic-module paths/exports and native named imports');
}

try { main(); } catch (error) { console.error('FAIL ' + error.message); process.exitCode = 1; }
