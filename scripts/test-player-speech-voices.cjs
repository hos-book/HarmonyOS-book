const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compile = code => ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const stateScope = { exports: {}, ObservedV2: value => value, Trace: () => {}, require: () => ({}) };
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'model/TextToSpeechState.ets'), 'utf8')), stateScope);
const source = fs.readFileSync(path.join(root, 'pages/PlayerPage.ets'), 'utf8');
function method(name) {
  const start = new RegExp(`  private (?:async )?${name}\\(`).exec(source).index;
  let end = source.indexOf('{', start) + 1, depth = 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(start, end);
}
const state = new stateScope.exports.TextToSpeechState();
const voice = (person, installed = true) => Object.assign(new stateScope.exports.SpeechVoice(), {
  person, id: `zh-CN:${person}:interaction-broadcast`, label: `voice-${person}`, installed
});
state.voices = [voice(0), voice(21), voice(99, false)];
state.customTtsConfigs = [{ id: 'disabled', name: 'Disabled', enabled: false },
  { id: 'imported', name: 'Imported', enabled: true }];
const calls = [];
const service = {
  async selectVoice(item) { calls.push(['system', item.person]); state.person = item.person; state.customTtsId = ''; },
  async selectCustomTts(id) { calls.push(['imported', id]); state.customTtsId = id; }
};
const scope = { TextToSpeechService: { getInstance: () => service }, $r: value => value };
vm.runInNewContext(compile(`class Player { ${['playbackSpeechVoices', 'selectedPlaybackVoiceId',
  'selectedSourceVoiceIndex', 'saveSpeechVoice'].map(method).join('\n')} }
  globalThis.Player = Player;`), scope);
(async () => {
  const player = new scope.Player();
  Object.assign(player, { speechState: state, isSpeechBook: () => true, savingSourceVoice: false,
    getUIContext() { return { getPromptAction: () => ({ showToast: () => assert.fail('unexpected save error') }) }; } });
  assert.equal(player.playbackSpeechVoices().length, 2, 'both built-in installed voices are listed');
  assert.equal(player.selectedPlaybackVoiceId(), 'system:zh-CN:0:interaction-broadcast');
  assert.equal(player.selectedSourceVoiceIndex(), 0);
  await player.saveSpeechVoice('system:zh-CN:21:interaction-broadcast');
  assert.deepEqual(calls.at(-1), ['system', 21], 'second built-in dispatches to native voice selection');
  assert.equal(player.selectedSourceVoiceIndex(), 1);
  assert.equal(player.selectedPlaybackVoiceId(), 'system:zh-CN:21:interaction-broadcast');
  await player.saveSpeechVoice('imported');
  assert.deepEqual(calls.at(-1), ['imported', 'imported']);
  assert.equal(player.selectedSourceVoiceIndex(), 2, 'imported voices follow all installed system voices');
  await player.saveSpeechVoice('system:zh-CN:0:interaction-broadcast');
  assert.equal(state.customTtsId, '');
  assert.equal(state.person, 0);
  const count = calls.length;
  await player.saveSpeechVoice('system:zh-CN:0:interaction-broadcast');
  assert.equal(calls.length, count, 'selected voice does not restart playback');
  player.isSpeechBook = () => false;
  player.sourceVoiceDraft = 'audio';
  player.sourceVoices = { totalCount: () => 1, getData: () => ({ id: 'audio' }) };
  assert.equal(player.selectedPlaybackVoiceId(), 'audio');
  assert.equal(player.selectedSourceVoiceIndex(), 1, 'audio book default row remains separate');
  console.log('player speech voices: two built-ins, independent selection, imported switch, selected index and audio menu passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
