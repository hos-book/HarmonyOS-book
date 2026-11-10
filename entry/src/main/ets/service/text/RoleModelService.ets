import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo, picker, statfs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { run, cancel } from 'librole_inference.so';
import { RoleModelInfo, RoleModelState } from '../../model/RoleSpeech';
import { RoleSpeechPlanner } from './RoleSpeechPlanner';

class RoleNativeMetadata {
  architecture: string = '';
  parameters: number = 0;
  bytes: number = 0;
}

/** 权重只来自系统文件选择器；分块复制、原子替换，不随 HAP 分发。 */
export class RoleModelService {
  private static instance: RoleModelService | null = null;
  readonly state: RoleModelState = new RoleModelState();
  private store: preferences.Preferences | null = null;
  private initTask: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private epoch: number = 0;
  private idleTimer: number = -1;
  private directory: string = '';

  static getInstance(): RoleModelService {
    if (RoleModelService.instance === null) RoleModelService.instance = new RoleModelService();
    return RoleModelService.instance;
  }

  initialize(context: common.Context): Promise<void> {
    if (this.store !== null) return Promise.resolve();
    if (this.initTask !== null) return this.initTask;
    this.initTask = this.load(context).finally((): void => { this.initTask = null; });
    return this.initTask;
  }

  private async load(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'role_speech_model' });
    this.directory = `${context.filesDir}/role_models`;
    if (!await fileIo.access(this.directory)) await fileIo.mkdir(this.directory, true);
    const saved = store.getSync('model', 'null');
    let model: RoleModelInfo | null = null;
    try {
      const item: RoleModelInfo | null = JSON.parse(typeof saved === 'string' ? saved : 'null');
      if (item !== null && typeof item.path === 'string' && typeof item.name === 'string' &&
        typeof item.fingerprint === 'string' && new RegExp('^[a-f0-9]{64}$').test(item.fingerprint) &&
        item.path === `${this.directory}/${item.fingerprint}.gguf` && await fileIo.access(item.path) &&
        (await fileIo.stat(item.path)).size === item.bytes) {
        model = new RoleModelInfo();
        model.path = item.path; model.name = item.name.substring(0, 160);
        model.fingerprint = item.fingerprint; model.architecture = item.architecture; model.bytes = item.bytes;
      }
    } catch (_error) { /* 丢失或损坏的目录项不能启用推理。 */ }
    this.state.model = model;
    this.state.enabled = model !== null && store.getSync('enabled', false) === true;
    // 上次强退留下的部分文件和已完成替换的旧模型均不继续占空间。
    for (const name of await fileIo.listFile(this.directory)) {
      if (new RegExp('^(import-[0-9]+\\.partial|[a-f0-9]{64}\\.gguf)$').test(name) &&
        `${this.directory}/${name}` !== model?.path) {
        await fileIo.unlink(`${this.directory}/${name}`).catch((): void => {});
      }
    }
    this.store = store;
  }

  private enqueue(operation: string, path: string = '', prompt: string = ''): Promise<string> {
    const ticket = this.epoch;
    const task = this.queue.catch((): void => {}).then((): Promise<string> => {
      if (operation !== 'unload' && ticket !== this.epoch) throw new Error('role_cancelled');
      return run(operation, path, prompt);
    });
    this.queue = task.then((): void => {}, (): void => {});
    return task;
  }

  private scheduleRelease(): void {
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = -1;
      this.enqueue('unload').catch((): void => {});
    }, 30000);
  }

  cancelAnalysis(): void {
    if (this.state.busy) return;
    this.epoch++; cancel(); this.scheduleRelease();
  }

  cancelImport(): void {
    if (!this.state.busy) return;
    this.epoch++; cancel();
  }

  async infer(prompt: string): Promise<string> {
    const model = this.state.model;
    if (!this.state.enabled || model === null || this.state.busy) throw new Error('role_model_unavailable');
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = -1;
    try { return await this.enqueue('infer', model.path, prompt); }
    finally { this.scheduleRelease(); }
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (this.state.busy || this.store === null || (enabled && this.state.model === null)) return;
    await this.persist(this.state.model, enabled);
    this.state.enabled = enabled;
    if (!enabled) this.cancelAnalysis();
  }

  private async persist(model: RoleModelInfo | null, enabled: boolean): Promise<void> {
    const store = this.store;
    if (store === null) throw new Error('role_save');
    const previous = store.getSync('model', 'null');
    const previousEnabled = store.getSync('enabled', false);
    store.putSync('model', JSON.stringify(model)); store.putSync('enabled', enabled);
    try { await store.flush(); }
    catch (_error) {
      store.putSync('model', previous); store.putSync('enabled', previousEnabled);
      throw new Error('role_save');
    }
  }

  async remove(): Promise<void> {
    if (this.state.busy) return;
    const model = this.state.model;
    if (model === null) return;
    this.cancelAnalysis();
    await this.enqueue('unload');
    await this.persist(null, false);
    this.state.model = null; this.state.enabled = false;
    await fileIo.unlink(model.path);
  }

  async pick(context: common.UIAbilityContext, beforeImport: () => void = (): void => {}): Promise<boolean> {
    await this.initialize(context);
    if (this.state.busy) return false;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1; options.fileSuffixFilters = ['GGUF|.gguf'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return false;
    beforeImport();
    return this.importFile(uris[0]);
  }

  private async importFile(uri: string): Promise<boolean> {
    if (this.state.busy) return false;
    this.cancelAnalysis();
    this.state.busy = true; this.state.error = ''; this.state.progress = 0; this.state.verifying = false;
    const ticket = this.epoch;
    let partial = `${this.directory}/import-${Date.now()}.partial`;
    let promoted = '';
    const previous = this.state.model;
    try {
      const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      let digest = '';
      let size = 0;
      try {
        size = (await fileIo.stat(source.fd)).size;
        if (size < 24 || size > 1792 * 1024 * 1024) throw new Error('role_model_size');
        if (await statfs.getFreeSize(this.directory) < size + 64 * 1024 * 1024) throw new Error('role_space');
        const target = await fileIo.open(partial, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          const md = cryptoFramework.createMd('SHA256');
          for (let offset = 0; offset < size;) {
            if (ticket !== this.epoch) throw new Error('role_cancelled');
            const buffer = new ArrayBuffer(Math.min(1024 * 1024, size - offset));
            const count = await fileIo.read(source.fd, buffer, { offset: offset });
            if (count !== buffer.byteLength || await fileIo.write(target.fd, buffer) !== count) throw new Error('role_file');
            await md.update({ data: new Uint8Array(buffer) });
            offset += count; this.state.progress = Math.floor(offset / size * 100);
          }
          await fileIo.fsync(target.fd);
          for (const byte of (await md.digest()).data) digest += byte.toString(16).padStart(2, '0');
        } finally { await fileIo.close(target); }
      } finally { await fileIo.close(source); }
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      this.state.verifying = true;
      const metadata: RoleNativeMetadata = JSON.parse(await this.enqueue('inspect', partial));
      const sample = '{"known":["小明"],"context":"小明说：你好。","lines":[{"id":0,"text":"你好。"}]}';
      const answer = await this.enqueue('infer', partial, sample);
      RoleSpeechPlanner.answers(answer, 1, '小明说：你好。', ['小明']);
      await this.enqueue('unload');
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      const model = new RoleModelInfo();
      model.path = `${this.directory}/${digest}.gguf`; model.fingerprint = digest;
      model.bytes = size; model.architecture = metadata.architecture;
      try { model.name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1)).substring(0, 160); }
      catch (_error) { model.name = 'Qwen GGUF'; }
      if (!model.name.toLowerCase().endsWith('.gguf')) model.name = 'Qwen GGUF';
      if (previous?.path !== model.path) {
        await fileIo.rename(partial, model.path); partial = ''; promoted = model.path;
      }
      await this.persist(model, true);
      this.state.model = model; this.state.enabled = true; promoted = '';
      if (previous !== null && previous.path !== model.path) await fileIo.unlink(previous.path).catch((): void => {});
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes('role_cancelled')) return false;
      this.state.error = RoleModelService.errorMessage(message);
      throw new Error(message);
    } finally {
      if (partial) await fileIo.unlink(partial).catch((): void => {});
      if (promoted) await fileIo.unlink(promoted).catch((): void => {});
      await this.enqueue('unload').catch((): void => {});
      this.state.busy = false; this.state.verifying = false;
    }
  }

  static errorMessage(message: string): ResourceStr {
    if (message.includes('role_model_size')) return $r('app.string.role_model_size_error');
    if (message.includes('role_space')) return $r('app.string.role_model_space_error');
    if (message.includes('role_memory')) return $r('app.string.role_model_memory_error');
    if (message.includes('role_timeout')) return $r('app.string.role_model_timeout_error');
    if (message.includes('role_model_unsupported')) return $r('app.string.role_model_unsupported_error');
    if (message.includes('role_model_invalid')) return $r('app.string.role_model_invalid_error');
    if (message.includes('role_save')) return $r('app.string.role_save_error');
    return $r('app.string.role_model_load_error');
  }
}
