import { OfflineTtsPinnedAsset, OFFLINE_TTS_PINNED_ASSETS } from './OfflineTtsAssets';

export const OFFLINE_TTS_MODEL_ID: string = 'kokoro-int8-v1_1';
export const OFFLINE_TTS_CHUNK_BYTES: number = 4 * 1024 * 1024;
export const OFFLINE_TTS_MAX_BYTES: number = 512 * 1024 * 1024;

@ObservedV2
export class OfflineTtsModelState {
  @Trace installed: boolean = false;
  @Trace name: string = '';
  @Trace bytes: number = 0;
  @Trace busy: boolean = false;
  @Trace progress: number = 0;
  @Trace verifying: boolean = false;
  @Trace error: string = '';
}

export class OfflineTtsManifest {
  format: number = 1;
  id: string = OFFLINE_TTS_MODEL_ID;
  chunkBytes: number = OFFLINE_TTS_CHUNK_BYTES;
  assets: OfflineTtsPinnedAsset[] = [];
}

/** 固定官方 int8 权重；不接受使用同一清单名字替换任意 ONNX 的包。 */
export const OFFLINE_TTS_ASSETS: OfflineTtsPinnedAsset[] = OFFLINE_TTS_PINNED_ASSETS;

