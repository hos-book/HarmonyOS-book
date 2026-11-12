import { OfflineTtsPinnedAsset, OFFLINE_TTS_PINNED_ASSETS } from './OfflineTtsAssets';
import { OFFLINE_TTS_PIPER_CHAOWEN_ASSETS, OFFLINE_TTS_PIPER_XIAOYA_ASSETS } from './OfflineTtsPiperAssets';

/** 仅列出应用已适配并固定校验的本地模型；导入文件不能扩展执行配置。 */
export class OfflineTtsModelDefinition {
  id: string;
  provider: string;
  voicePrefix: string;
  archivePrefix: string;
  assets: OfflineTtsPinnedAsset[];
  minSpeaker: number;
  maxSpeaker: number;
  numSpeakers: number;
  sampleRate: number;
  downloadUrl: string;
  name: string;

  constructor(id: string, provider: string, voicePrefix: string,
    archivePrefix: string, assets: OfflineTtsPinnedAsset[],
    minSpeaker: number, maxSpeaker: number, numSpeakers: number,
    sampleRate: number, downloadUrl: string, name: string) {
    this.id = id; this.provider = provider; this.voicePrefix = voicePrefix;
    this.archivePrefix = archivePrefix; this.assets = assets;
    this.minSpeaker = minSpeaker; this.maxSpeaker = maxSpeaker; this.numSpeakers = numSpeakers;
    this.sampleRate = sampleRate; this.downloadUrl = downloadUrl; this.name = name;
  }
}

const RELEASE: string = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/';

export const OFFLINE_TTS_MODELS: OfflineTtsModelDefinition[] = [
  new OfflineTtsModelDefinition('kokoro-int8-v1_1', 'local-kokoro', 'local-kokoro-v1_1',
    'kokoro-int8-multi-lang-v1_1', OFFLINE_TTS_PINNED_ASSETS, 3, 102, 103, 24000,
    `${RELEASE}kokoro-int8-multi-lang-v1_1.tar.bz2`, 'Kokoro v1.1 中文 · int8'),
  new OfflineTtsModelDefinition('piper-chaowen-int8-v1', 'local-piper', 'local-piper-chaowen-v1',
    'vits-piper-zh_CN-chaowen-medium-int8', OFFLINE_TTS_PIPER_CHAOWEN_ASSETS, 0, 0, 1, 22050,
    `${RELEASE}vits-piper-zh_CN-chaowen-medium-int8.tar.bz2`, 'Piper 超文 · int8'),
  new OfflineTtsModelDefinition('piper-xiaoya-int8-v1', 'local-piper', 'local-piper-xiaoya-v1',
    'vits-piper-zh_CN-xiao_ya-medium-int8', OFFLINE_TTS_PIPER_XIAOYA_ASSETS, 0, 0, 1, 22050,
    `${RELEASE}vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2`, 'Piper 小雅 · int8')
];

export function getOfflineTtsModel(id: string): OfflineTtsModelDefinition | undefined {
  return OFFLINE_TTS_MODELS.find((item: OfflineTtsModelDefinition): boolean => item.id === id);
}

export function isOfflineTtsProvider(provider: string): boolean {
  return provider === 'local-kokoro' || provider === 'local-piper';
}

export function getOfflineTtsVoiceModel(id: string): OfflineTtsModelDefinition | undefined {
  return OFFLINE_TTS_MODELS.find((item: OfflineTtsModelDefinition): boolean => {
    if (!id.startsWith(`${item.voicePrefix}:`)) return false;
    const sid = Number(id.substring(item.voicePrefix.length + 1));
    return Number.isInteger(sid) && sid >= item.minSpeaker && sid <= item.maxSpeaker && id === `${item.voicePrefix}:${sid}`;
  });
}
