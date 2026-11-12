import { worker, MessageEvents } from '@kit.ArkTS';
import { OfflineTts, OfflineTtsConfig, TtsInput } from 'sherpa_onnx';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getOfflineTtsModel } from '../model/OfflineTtsCatalog';
import { OfflineTtsWorkerRequest, OfflineTtsWorkerResponse, OFFLINE_TTS_MAX_PCM } from '../model/OfflineTtsWorkerProtocol';

const port = worker.workerPort;
class CachedOfflineTts {
  modelId: string;
  directory: string;
  engine: OfflineTts;
  constructor(modelId: string, directory: string, engine: OfflineTts) {
    this.modelId = modelId; this.directory = directory; this.engine = engine;
  }
}
let engines: CachedOfflineTts[] = [];

function wave(samples: Float32Array, rate: number): ArrayBuffer {
  const bytes = samples.length * 2;
  if (bytes <= 0 || bytes > OFFLINE_TTS_MAX_PCM || !Number.isInteger(rate) || rate < 8000 || rate > 48000) {
    throw new Error('offline_tts_audio');
  }
  const result = new ArrayBuffer(44 + bytes);
  const view = new DataView(result);
  view.setUint32(0, 0x52494646, false); view.setUint32(4, 36 + bytes, true);
  view.setUint32(8, 0x57415645, false); view.setUint32(12, 0x666d7420, false);
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  view.setUint32(36, 0x64617461, false); view.setUint32(40, bytes, true);
  for (let index = 0; index < samples.length; index++) {
    if (!Number.isFinite(samples[index])) throw new Error('offline_tts_audio');
    const value = Math.max(-1, Math.min(1, samples[index]));
    view.setInt16(44 + index * 2, Math.round(value * (value < 0 ? 32768 : 32767)), true);
  }
  return result;
}

port.onmessage = (event: MessageEvents): void => {
  const request: OfflineTtsWorkerRequest = event.data;
  // 消息只会在同步 native generate 返回后处理，不能在推理中途销毁运行环境。
  if (request.shutdown) {
    engines = [];
    try { port.close(); } catch (_closed) { /* 已关闭。 */ }
    return;
  }
  const response = new OfflineTtsWorkerResponse();
  response.requestId = request.requestId;
  try {
    const model = getOfflineTtsModel(request.modelId);
    if (!request.directory || !request.text.trim() || request.text.length > 300 ||
      !model || !Number.isInteger(request.speakerId) || request.speakerId < model.minSpeaker || request.speakerId > model.maxSpeaker ||
      !Number.isFinite(request.speed) || request.speed < 0.5 || request.speed > 3) throw new Error('offline_tts_input');
    let cached = engines.find((item: CachedOfflineTts): boolean => item.modelId === request.modelId && item.directory === request.directory);
    const started = Date.now();
    if (!cached) {
      const config = new OfflineTtsConfig();
      if (model.provider === 'local-piper') {
        config.model.vits.model = `${request.directory}/${request.modelId === 'piper-chaowen-int8-v1' ?
          'zh_CN-chaowen-medium.onnx' : 'zh_CN-xiao_ya-medium.onnx'}`;
        config.model.vits.tokens = `${request.directory}/tokens.txt`;
        config.model.vits.lexicon = `${request.directory}/lexicon.txt`;
        config.model.vits.noiseScale = 0.667; config.model.vits.noiseScaleW = 0.8;
        config.ruleFsts = `${request.directory}/phone.fst,${request.directory}/date.fst,${request.directory}/number.fst`;
      } else {
        config.model.kokoro.model = `${request.directory}/model.int8.onnx`;
        config.model.kokoro.voices = `${request.directory}/voices.bin`;
        config.model.kokoro.tokens = `${request.directory}/tokens.txt`;
        config.model.kokoro.lexicon = `${request.directory}/lexicon-us-en.txt,${request.directory}/lexicon-zh.txt`;
        config.model.kokoro.dataDir = `${request.directory}/espeak-ng-data`;
        // lang 留空才使用多语言词表分流；强设 zh 会绕过中文词表。
        config.model.kokoro.lang = '';
        config.ruleFsts = `${request.directory}/date-zh.fst,${request.directory}/number-zh.fst,${request.directory}/phone-zh.fst`;
      }
      config.model.numThreads = 2; config.model.provider = 'cpu';
      config.maxNumSentences = 1;
      const engine = new OfflineTts(config);
      if (engine.numSpeakers !== model.numSpeakers || engine.sampleRate !== model.sampleRate) throw new Error('offline_tts_model');
      cached = new CachedOfflineTts(request.modelId, request.directory, engine);
    }
    // 两个轻量 Piper 声音共用 Worker 并保留会话，角色切换无需反复加载权重。
    engines = engines.filter((item: CachedOfflineTts): boolean => item.modelId !== request.modelId);
    engines.push(cached);
    if (engines.length > 2) engines.shift();
    const loaded = Date.now();
    const input = new TtsInput();
    input.text = request.text; input.sid = request.speakerId; input.speed = request.speed;
    input.enableExternalBuffer = false;
    const audio = cached.engine.generate(input);
    hilog.info(0x0000, 'OfflineTts', 'model=%{public}s loadMs=%{public}d generateMs=%{public}d audioMs=%{public}d',
      request.modelId, loaded - started, Date.now() - loaded, Math.round(audio.samples.length / audio.sampleRate * 1000));
    response.wave = wave(audio.samples, audio.sampleRate);
    response.speakers = cached.engine.numSpeakers;
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    response.error = message.startsWith('offline_tts_') ? message : 'offline_tts_synthesis';
    engines = [];
  }
  try { port.postMessage(response, [response.wave]); }
  catch (_transfer) {
    response.wave = new ArrayBuffer(0); response.error = 'offline_tts_worker';
    try { port.postMessage(response); }
    catch (_closed) { try { port.close(); } catch (_error) { /* 宿主已退出。 */ } }
  }
};
