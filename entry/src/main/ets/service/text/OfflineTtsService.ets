import { worker, MessageEvents, ThreadWorkerPriority } from '@kit.ArkTS';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { OFFLINE_TTS_MODEL_ID } from '../../model/OfflineTts';
import { getOfflineTtsModel } from '../../model/OfflineTtsCatalog';
import { OfflineTtsWorkerRequest, OfflineTtsWorkerResponse, OFFLINE_TTS_MAX_PCM } from '../../model/OfflineTtsWorkerProtocol';
import { OfflineTtsModelService } from './OfflineTtsModelService';

/** 本地合成串行运行于独立 Worker；取消只丢弃结果，模型变更等待 native 安全结束。 */
export class OfflineTtsService {
  static readonly instance: OfflineTtsService = new OfflineTtsService();
  private host: worker.ThreadWorker | null = null;
  private closing: Promise<void> = Promise.resolve();
  private queue: Promise<void> = Promise.resolve();
  private epoch: number = 0;
  private sequence: number = 0;
  private pending: number = -1;
  private complete: ((response: OfflineTtsWorkerResponse) => void) | null = null;
  private failed: ((error: Error) => void) | null = null;
  private idleTimer: number = -1;
  private changing: boolean = false;
  private lastModelId: string = '';

  async synthesize(config: CustomTtsConfig, text: string, speed: number,
    cancelled: () => boolean): Promise<ArrayBuffer> {
    const model = OfflineTtsModelService.instance;
    const definition = getOfflineTtsModel(config.modelId);
    if (this.changing || model.isBusy() || !definition || !model.stateFor(config.modelId).installed ||
      config.provider !== definition.provider ||
      !model.isVoiceId(config.id) || config.id !== `${definition.voicePrefix}:${config.speakerId}` ||
      !text.trim() || text.length > 300) throw new Error('offline_tts_unavailable');
    const ticket = this.epoch;
    const request = new OfflineTtsWorkerRequest();
    request.modelId = definition.id;
    request.directory = model.directory(definition.id); request.text = text; request.speakerId = config.speakerId;
    request.speed = Math.max(0.5, Math.min(3, speed));
    return this.enqueue(request, (): boolean => cancelled() || ticket !== this.epoch || model.isBusy());
  }

  async validate(directory: string, modelId: string = OFFLINE_TTS_MODEL_ID): Promise<void> {
    await this.pauseForModelChange();
    const request = new OfflineTtsWorkerRequest();
    const model = getOfflineTtsModel(modelId);
    if (!model) throw new Error('offline_tts_model');
    request.modelId = modelId;
    request.directory = directory; request.text = '你好，欢迎使用本地朗读。'; request.speakerId = model.minSpeaker;
    try { await this.enqueue(request, (): boolean => false); }
    finally { await this.pauseForModelChange(); }
  }

  private enqueue(request: OfflineTtsWorkerRequest, cancelled: () => boolean): Promise<ArrayBuffer> {
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = -1;
    let abandoned = false;
    const actual = this.queue.catch((): void => {}).then(async (): Promise<ArrayBuffer> => {
      if (abandoned || cancelled()) throw new Error('offline_tts_cancelled');
      await this.closing;
      if (abandoned || cancelled()) throw new Error('offline_tts_cancelled');
      return this.run(request);
    });
    this.queue = actual.then((): void => {}, (): void => {}).finally((): void => this.scheduleRelease());
    return new Promise<ArrayBuffer>((resolve, reject): void => {
      let settled = false;
      const finish = (error: Error | null, buffer: ArrayBuffer | null): void => {
        if (settled) return;
        settled = true; clearInterval(poll); clearTimeout(timeout);
        if (error !== null) reject(error);
        else if (buffer !== null) resolve(buffer);
      };
      const poll = setInterval((): void => {
        if (cancelled()) { abandoned = true; finish(new Error('offline_tts_cancelled'), null); }
      }, 100);
      const timeout = setTimeout((): void => {
        abandoned = true; finish(new Error('offline_tts_timeout'), null);
      }, 120000);
      actual.then((buffer: ArrayBuffer): void => {
        if (cancelled()) finish(new Error('offline_tts_cancelled'), null);
        else finish(null, buffer);
      }, (error: Error): void => finish(error, null));
    });
  }

  private run(request: OfflineTtsWorkerRequest): Promise<ArrayBuffer> {
    const host = this.ensureWorker();
    this.lastModelId = request.modelId;
    request.requestId = ++this.sequence; this.pending = request.requestId;
    return new Promise<ArrayBuffer>((resolve, reject): void => {
      this.complete = (response: OfflineTtsWorkerResponse): void => {
        this.pending = -1; this.complete = null; this.failed = null;
        if (response.error) reject(new Error(response.error));
        else if (response.speakers !== getOfflineTtsModel(request.modelId)?.numSpeakers || response.wave.byteLength <= 44 ||
          response.wave.byteLength > OFFLINE_TTS_MAX_PCM + 44) reject(new Error('offline_tts_audio'));
        else resolve(response.wave);
      };
      this.failed = reject;
      try { host.postMessage(request); }
      catch (_error) { this.pending = -1; this.complete = null; this.failed = null; reject(new Error('offline_tts_worker')); }
    });
  }

  private ensureWorker(): worker.ThreadWorker {
    if (this.host !== null) return this.host;
    // 用户主动朗读的合成任务使用 API18 起支持的 USER_INITIATED 优先级。
    const host = new worker.ThreadWorker('entry/ets/workers/OfflineTtsWorker.ets', {
      name: 'OfflineTts', priority: ThreadWorkerPriority.HIGH
    });
    host.onmessage = (event: MessageEvents): void => {
      const response: OfflineTtsWorkerResponse = event.data;
      if (this.host === host && response.requestId === this.pending) this.complete?.(response);
    };
    host.onerror = (): void => {
      if (this.host !== host) return;
      const reject = this.failed;
      this.pending = -1; this.complete = null; this.failed = null;
      reject?.(new Error('offline_tts_worker'));
      this.closeWorker();
    };
    host.onexit = (): void => {
      if (this.host !== host) return;
      this.host = null;
      const reject = this.failed;
      this.pending = -1; this.complete = null; this.failed = null;
      reject?.(new Error('offline_tts_worker'));
    };
    this.host = host;
    return host;
  }

  private scheduleRelease(): void {
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout((): void => { this.idleTimer = -1; if (this.pending === -1) this.closeWorker(); },
      this.lastModelId.startsWith('piper-') ? 90000 : 30000);
  }

  private closeWorker(): Promise<void> {
    const host = this.host;
    if (host === null || this.pending !== -1) return this.closing;
    this.host = null;
    this.closing = new Promise<void>((resolve): void => {
      host.onexit = (): void => resolve();
      host.onerror = (): void => {};
      const request = new OfflineTtsWorkerRequest(); request.shutdown = true;
      try { host.postMessage(request); }
      catch (_error) {
        try { host.terminate(); } catch (_closed) { resolve(); }
      }
    });
    return this.closing;
  }

  async pauseForModelChange(): Promise<void> {
    this.changing = true; this.epoch++;
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = -1;
    try { await this.queue; await this.closeWorker(); }
    finally { this.changing = false; }
  }
}
