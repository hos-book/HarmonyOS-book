// Platform boundary for real role services. This fixture never executes a model.
const crypto = require('node:crypto');
module.exports = function createRoleFixture(load) {
  const files = new Map(), dirs = new Set(['/files']), handles = new Map(), stores = new Map(), timers = new Map();
  let sequence = 0, failFlush = false, freeBytes = 8 * 1024 ** 3;
  const io = {
    OpenMode: { READ_ONLY: 1, READ_WRITE: 2, CREATE: 4, TRUNC: 8 },
    async access(path) { return files.has(path) || dirs.has(path); },
    async mkdir(path) { dirs.add(path); },
    async listFile(path) { return [...files.keys()].filter(p => p.startsWith(path + '/') && !p.slice(path.length + 1).includes('/')).map(p => p.slice(path.length + 1)); },
    async stat(value) { const path = typeof value === 'number' ? handles.get(value).path : value;
      if (!files.has(path)) throw Error('missing'); return { size: files.get(path).length, mtime: 1 }; },
    async open(path, mode) {
      if (mode & 4) { if (!files.has(path) || mode & 8) files.set(path, Buffer.alloc(0)); }
      if (!files.has(path)) throw Error('missing');
      const fd = ++sequence; handles.set(fd, { path, position: 0 }); return { fd };
    },
    async close(file) { handles.delete(typeof file === 'number' ? file : file.fd); },
    async read(fd, target, options = {}) {
      const handle = handles.get(fd), bytes = files.get(handle.path);
      const offset = options.offset ?? handle.position;
      const count = Math.min(target.byteLength, bytes.length - offset);
      new Uint8Array(target).set(bytes.subarray(offset, offset + count)); handle.position = offset + count; return count;
    },
    async write(fd, value) {
      const handle = handles.get(fd), bytes = Buffer.from(value);
      files.set(handle.path, Buffer.concat([files.get(handle.path).subarray(0, handle.position), bytes]));
      handle.position += bytes.length; return bytes.length;
    },
    async fsync() {},
    async readText(path) { return files.get(path).toString('utf8'); },
    async rename(from, to) { if (!files.has(from)) throw Error('missing'); files.set(to, files.get(from)); files.delete(from); },
    async unlink(path) { files.delete(path); }
  };
  const preferenceKit = { preferences: { async getPreferences(_context, { name }) {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    return { getSync: (key, fallback) => store.get(key) ?? fallback, putSync: (key, value) => store.set(key, value),
      async flush() { if (failFlush) throw Error('disk full'); } };
  } } };
  const roleModel = load('model/RoleSpeech.ets');
  const offlineAssets = load('model/OfflineTtsAssets.ets');
  const offlinePiperAssets = load('model/OfflineTtsPiperAssets.ets', { './OfflineTtsAssets': offlineAssets });
  const offlineCatalog = load('model/OfflineTtsCatalog.ets', {
    './OfflineTtsAssets': offlineAssets, './OfflineTtsPiperAssets': offlinePiperAssets
  });
  const quoteModel = load('model/ReaderDialogueRules.ets');
  const highlighter = load('service/text/ReaderDialogueHighlighter.ets', { '../../model/ReaderDialogueRules': quoteModel });
  const planner = load('service/text/RoleSpeechPlanner.ets', { '../../model/RoleSpeech': roleModel, './ReaderDialogueHighlighter': highlighter });
  const native = { calls: [], answer: prompt => JSON.parse(prompt).lines.map(item => ({ id: item.id, speaker: '?' })),
    inspectFailure: '', cancelCount: 0,
    cancel() { native.cancelCount++; },
    async run(operation, path, prompt) {
      native.calls.push({ operation, path, prompt });
      if (operation === 'unload') return '{}';
      if (operation === 'inspect') {
        if (native.inspectFailure) throw Error(native.inspectFailure);
        return JSON.stringify({ architecture: 'qwen35', bytes: files.get(path)?.length, parameters: 800000000 });
      }
      return JSON.stringify(await native.answer(prompt));
    }
  };
  const modelExports = load('service/text/RoleModelService.ets', {
    '@kit.ArkData': preferenceKit,
    '@kit.CoreFileKit': { fileIo: io, statfs: { getFreeSize: async () => freeBytes }, picker: {} },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() {
      const md = crypto.createHash('sha256'); return { async update({ data }) { md.update(data); }, async digest() { return { data: md.digest() }; } };
    } } },
    'librole_inference.so': native, '../../model/RoleSpeech': roleModel, './RoleSpeechPlanner': planner
  }, { setTimeout: fn => { const id = ++sequence; timers.set(id, fn); return id; }, clearTimeout: id => timers.delete(id) });
  const modelService = modelExports.RoleModelService.getInstance();
  const roleExports = load('service/text/RoleSpeechService.ets', {
    '@kit.CoreFileKit': { fileIo: io }, '../../model/RoleSpeech': roleModel, './RoleSpeechPlanner': planner,
    './RoleModelService': modelExports,
    '../../model/OfflineTtsCatalog': offlineCatalog,
    '../subtitle/SubtitleFiles': { SubtitleFiles: { key: async text => crypto.createHash('sha256').update(text).digest('hex') } }
  });
  const roles = roleExports.RoleSpeechService.getInstance();
  return { roleExports, roles, modelService, modelExports, roleModel, planner, files, handles, native, timers,
    failFlush: value => { failFlush = value; }, freeSpace: value => { freeBytes = value; },
    async enable(context = { filesDir: '/files' }) {
      await modelService.initialize(context);
      const info = new roleModel.RoleModelInfo(); info.fingerprint = 'a'.repeat(64); info.path = '/files/role_models/' + info.fingerprint + '.gguf';
      modelService.state.model = info; modelService.state.enabled = true;
    }
  };
};
