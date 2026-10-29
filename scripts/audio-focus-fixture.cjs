// Real focus policy and watcher with deterministic platform events/time; shared by playback regressions.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

module.exports = function createFocusFixture(preference, baseAudio = {}, compat = { supports: () => true }) {
  const events = new Map(), timers = new Map(), active = new Set(), calls = [];
  let now = 100000, timerId = 0, streamCallback = null;
  const names = ['MUSIC', 'MOVIE', 'AUDIOBOOK', 'GAME', 'VOICE_COMMUNICATION', 'VIDEO_COMMUNICATION',
    'VOICE_MESSAGE', 'VOICE_ASSISTANT', 'ALARM', 'RINGTONE', 'NAVIGATION', 'ACCESSIBILITY', 'NOTIFICATION'];
  const usages = Object.fromEntries(names.map((name, i) => [`STREAM_USAGE_${name}`, i + 1]));
  const audio = { ...baseAudio,
    StreamUsage: { ...usages, ...baseAudio.StreamUsage },
    InterruptHint: { INTERRUPT_HINT_RESUME: 1, INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_STOP: 3,
      INTERRUPT_HINT_DUCK: 4, INTERRUPT_HINT_UNDUCK: 5 },
    AudioSessionScene: { AUDIO_SESSION_SCENE_MEDIA: 0 },
    AudioConcurrencyMode: { CONCURRENCY_MIX_WITH_OTHERS: 1, CONCURRENCY_PAUSE_OTHERS: 3 },
    AudioSessionBehaviorFlags: { DEFAULT_BEHAVIOR: 0, PAUSE_WHEN_INTERRUPTED: 4 },
    AudioSessionStateChangeHint: { AUDIO_SESSION_STATE_CHANGE_HINT_RESUME: 0,
      AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE: 1, AUDIO_SESSION_STATE_CHANGE_HINT_STOP: 2,
      AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP: 3, AUDIO_SESSION_STATE_CHANGE_HINT_DUCK: 4,
      AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK: 5 }
  };
  const session = { activated: false,
    on: (event, callback) => events.set(event, callback), off: event => events.delete(event),
    setAudioSessionScene: value => calls.push(['scene', value]),
    setAudioSessionBehavior: value => calls.push(['behavior', value]),
    async activateAudioSession(strategy) { calls.push(['activate', strategy.concurrencyMode]); this.activated = true; },
    async deactivateAudioSession() { calls.push(['deactivate']); this.activated = false; },
    isAudioSessionActivated() { return this.activated; }
  };
  const stream = { on: (_event, cb) => { streamCallback = cb; }, off: () => { streamCallback = null; },
    isStreamActive: usage => active.has(usage) };
  audio.getAudioManager = () => ({ getSessionManager: () => session, getStreamManager: () => stream });
  const diagnostics = { DiagnosticLogService: { info() {}, failure() {} } };
  function load(file, dependencies) {
    const filename = path.join(__dirname, '../entry/src/main/ets/service', file);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const mod = { exports: {} };
    vm.runInNewContext(code, { module: mod, exports: mod.exports, Promise, Error,
      Date: class extends Date { static now() { return now; } },
      setInterval: (callback, delay) => { const id = ++timerId; timers.set(id, { callback, delay, next: now + delay }); return id; },
      clearInterval: id => timers.delete(id), require(name) {
        if (!dependencies[name]) throw new Error(`Unexpected focus dependency ${name}`);
        return dependencies[name];
      } }, { filename });
    return mod.exports;
  }
  const watcher = load('ExternalMediaWatcher.ets', { '@kit.AudioKit': { audio }, './DiagnosticLogService': diagnostics });
  const exports = load('AudioFocusService.ets', { '@kit.AudioKit': { audio },
    '../utils/PlatformCompat': { PlatformCompat: compat }, './PreferenceService': { PreferenceService: preference },
    './DiagnosticLogService': diagnostics, './ExternalMediaWatcher': watcher });
  return { exports, focus: exports.AudioFocusService.getInstance(), audio, session, stream, calls, active, timers,
    emit(hint) { if (hint === 1 || hint === 2 || hint === 3) session.activated = false;
      events.get('audioSessionStateChanged')?.({ stateChangeHint: hint }); },
    change() { streamCallback?.([]); },
    advance(ms) { const end = now + ms;
      while (now < end) { now = Math.min(end, now + 1000);
        for (const timer of [...timers.values()]) if (timer.next <= now) {
          timer.next = now + timer.delay; timer.callback();
        }
      }
    }
  };
};
