// Load the real, platform-free EPUB viewport and its pinned helper modules.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/text');
function loadEpubScript() {
  const cache = new Map();
  function load(name) {
    const file = ['.ets', '.ts'].map(ext => name + ext).find(fs.existsSync);
    if (!file || !file.startsWith(root + path.sep)) throw Error('Unexpected EPUB dependency: ' + name);
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} };
    cache.set(file, module);
    const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
    } }).outputText;
    vm.runInNewContext(code, { module, exports: module.exports, require: dependency => {
      if (!dependency.startsWith('.')) throw Error('Unexpected EPUB package: ' + dependency);
      return load(path.resolve(path.dirname(file), dependency));
    } }, { filename: file });
    return module.exports;
  }
  return load(path.join(root, 'light/EpubOriginalScript'));
}
module.exports = { loadEpubScript };
