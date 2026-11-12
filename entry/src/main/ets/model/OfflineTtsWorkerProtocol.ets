// Worker 与 UI 共用的纯数据协议；不得引入 ArkUI 状态装饰器或页面模块。
export const OFFLINE_TTS_MAX_PCM: number = 8 * 1024 * 1024;

export class OfflineTtsWorkerRequest {
  requestId: number = 0;
  modelId: string = 'kokoro-int8-v1_1';
  directory: string = '';
  text: string = '';
  speakerId: number = 3;
  speed: number = 1;
  shutdown: boolean = false;
}

export class OfflineTtsWorkerResponse {
  requestId: number = 0;
  wave: ArrayBuffer = new ArrayBuffer(0);
  speakers: number = 0;
  error: string = '';
}
