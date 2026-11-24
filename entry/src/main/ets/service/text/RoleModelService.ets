import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo, picker, statfs } from '@kit.CoreFileKit';
import { loadRoleNnrtModel, predictRoleNnrtModel, releaseRoleNnrtModel } from 'librole_nnrt.so';
import { RoleInferenceRequest, RoleModelAnswer, RoleModelInfo, RoleModelState } from '../../model/RoleSpeech';
import { RoleBertEncoding, RoleBertTokenizer } from './RoleBertTokenizer';
import { RoleSpeechPlanner } from './RoleSpeechPlanner';

/** Runs CSI speaker extraction with NPU preference and CPU execution. */
export class RoleModelService {
  private static instance: RoleModelService | null = null;
  readonly state: RoleModelState = new RoleModelState();
  private store: preferences.Preferences | null = null;
  private initTask: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private epoch: number = 0;
  private idleTimer: number = -1;
  private directory: string = '';
  private runtimePath: string = '';
  private tokenizer: RoleBertTokenizer | null = null;

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
    this.tokenizer = await RoleBertTokenizer.fromResource(context);
    const saved = store.getSync('model', 'null');
    let model: RoleModelInfo | null = null;
    try {
      const item: RoleModelInfo | null = JSON.parse(typeof saved === 'string' ? saved : 'null');
      if (item !== null && await this.installedFile(item.path, item.name, item.bytes, '.ms')) {
        model = new RoleModelInfo();
        model.architecture = 'RoBERTa CSI';
        model.path = item.path; model.name = item.name.substring(0, 160); model.bytes = item.bytes;
      }
    } catch (_error) {}
    this.state.model = model;
    this.state.enabled = model !== null && store.getSync('enabled', false) === true;
    for (const name of await fileIo.listFile(this.directory)) {
      if (/^import-[0-9]+\.partial$/.test(name)) {
        await fileIo.unlink(`${this.directory}/${name}`).catch((): void => {});
      }
    }
    this.store = store;
  }

  private async installedFile(path: string, name: string, bytes: number, suffix: string): Promise<boolean> {
    return typeof path === 'string' && typeof name === 'string' && typeof bytes === 'number' &&
      path.startsWith(`${this.directory}/role-`) && path.endsWith(suffix) && !path.includes('..') &&
      await fileIo.access(path) && (await fileIo.stat(path)).size === bytes;
  }

  private enqueue<T>(operation: () => Promise<T>, ticket: number, allowStale: boolean = false): Promise<T> {
    const task = this.queue.catch((): void => {}).then((): Promise<T> => {
      if (!allowStale && ticket !== this.epoch) throw new Error('role_cancelled');
      return operation();
    });
    this.queue = task.then((): void => {}, (): void => {});
    return task;
  }

  private scheduleRelease(): void {
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = -1;
      const ticket = this.epoch;
      this.enqueue<void>(async (): Promise<void> => {
        await releaseRoleNnrtModel(); this.runtimePath = '';
      }, ticket, true).catch((): void => {});
    }, 30000);
  }

  cancelAnalysis(): void {
    if (this.state.busy) return;
    this.epoch++;
    this.scheduleRelease();
  }

  cancelImport(): void {
    if (!this.state.busy) return;
    this.epoch++;
  }

  async infer(request: RoleInferenceRequest): Promise<RoleModelAnswer[]> {
    const model = this.state.model;
    if (!this.state.enabled || model === null || this.state.busy) throw new Error('role_model_unavailable');
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = -1;
    const ticket = this.epoch;
    try {
      return await this.enqueue<RoleModelAnswer[]>((): Promise<RoleModelAnswer[]> =>
        this.inferRequest(model, request, ticket), ticket);
    } catch (error) {
      this.runtimePath = '';
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally { this.scheduleRelease(); }
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
    await this.enqueue<void>(async (): Promise<void> => {
      await releaseRoleNnrtModel(); this.runtimePath = '';
    }, this.epoch, true);
    await this.persist(null, false);
    this.state.model = null; this.state.enabled = false; this.state.backend = '';
    if (model.path.length > 0) await fileIo.unlink(model.path);
  }

  async pick(context: common.UIAbilityContext, beforeImport: () => void = (): void => {}): Promise<boolean> {
    await this.initialize(context);
    if (this.state.busy) return false;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1; options.fileSuffixFilters = ['CSI|.ms'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return false;
    beforeImport();
    return this.importFile(context, uris[0]);
  }

  private async importFile(context: common.Context, uri: string): Promise<boolean> {
    if (this.state.busy) return false;
    this.cancelAnalysis();
    this.state.busy = true; this.state.error = ''; this.state.progress = 0; this.state.verifying = false;
    const ticket = this.epoch;
    let partial = `${this.directory}/import-${Date.now()}.partial`;
    let promoted = '';
    const previous = this.state.model;
    const previousBackend = this.state.backend;
    try {
      const selectedName = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1)).substring(0, 160);
      const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      let size = 0;
      try {
        size = (await fileIo.stat(source.fd)).size;
        if (size <= 0 || size > 1792 * 1024 * 1024) throw new Error('role_model_size');
        if (await statfs.getFreeSize(this.directory) < size + 64 * 1024 * 1024) throw new Error('role_space');
        const target = await fileIo.open(partial, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          for (let offset = 0; offset < size;) {
            if (ticket !== this.epoch) throw new Error('role_cancelled');
            const buffer = new ArrayBuffer(Math.min(1024 * 1024, size - offset));
            const count = await fileIo.read(source.fd, buffer, { offset: offset });
            if (count !== buffer.byteLength || await fileIo.write(target.fd, buffer) !== count) {
              throw new Error('role_file');
            }
            offset += count; this.state.progress = Math.floor(offset / size * 100);
          }
          await fileIo.fsync(target.fd);
        } finally { await fileIo.close(target); }
      } finally { await fileIo.close(source); }
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      this.state.verifying = true;
      this.tokenizer = await RoleBertTokenizer.fromResource(context);
      const fileName = `role-${Date.now()}.ms`;
      const finalPath = `${this.directory}/${fileName}`;
      await fileIo.rename(partial, finalPath); partial = ''; promoted = finalPath;
      const model = new RoleModelInfo();
      model.architecture = 'RoBERTa CSI';
      model.path = finalPath; model.bytes = size;
      model.name = selectedName.toLowerCase().endsWith('.ms') ? selectedName : fileName;
      await this.enqueue<void>(async (): Promise<void> => {
        if (ticket !== this.epoch) throw new Error('role_cancelled');
        await this.ensureRuntime(model.path);
        await this.validateRuntime();
      }, ticket);
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      await this.persist(model, true);
      this.state.model = model; this.state.enabled = true; promoted = '';
      if (previous !== null) {
        if (previous.path.length > 0 && previous.path !== model.path) {
          await fileIo.unlink(previous.path).catch((): void => {});
        }
      }
      return true;
    } catch (error) {
      this.state.backend = previousBackend;
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes('role_cancelled')) return false;
      this.state.error = RoleModelService.errorMessage(message);
      throw new Error(message);
    } finally {
      if (partial) await fileIo.unlink(partial).catch((): void => {});
      if (promoted) await fileIo.unlink(promoted).catch((): void => {});
      await this.enqueue<void>(async (): Promise<void> => {
        await releaseRoleNnrtModel(); this.runtimePath = '';
      }, this.epoch, true).catch((): void => {});
      this.state.busy = false; this.state.verifying = false;
    }
  }

  private async ensureRuntime(path: string): Promise<void> {
    if (this.runtimePath === path) return;
    this.state.backend = await loadRoleNnrtModel(path);
    this.runtimePath = path;
  }

  private async validateRuntime(): Promise<void> {
    const tokenizer = this.tokenizer;
    if (tokenizer === null) throw new Error('role_model_invalid');
    const encoding = tokenizer.encode('你好。', '小明说：你好。');
    await this.predict(encoding);
  }

  private async inferRequest(model: RoleModelInfo, request: RoleInferenceRequest, ticket: number): Promise<RoleModelAnswer[]> {
    const tokenizer = this.tokenizer;
    if (tokenizer === null) throw new Error('role_model_invalid');
    await this.ensureRuntime(model.path);
    const pieces = tokenizer.tokenize(request.context);
    const answers: RoleModelAnswer[] = [];
    for (const line of request.lines) {
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      const encoding = tokenizer.encodeDialogue(pieces, line.start, line.end);
      const outputs = await this.predict(encoding);
      if (ticket !== this.epoch) throw new Error('role_cancelled');
      const start = outputs.subarray(0, RoleBertTokenizer.SEQUENCE_LENGTH);
      const end = outputs.subarray(RoleBertTokenizer.SEQUENCE_LENGTH,
        RoleBertTokenizer.SEQUENCE_LENGTH * 2);
      const speaker = this.bestSpan(start, end, encoding, request.context);
      const answer = new RoleModelAnswer(); answer.id = line.id; answer.speaker = speaker;
      answers.push(answer);
    }
    return answers;
  }

  private async predict(encoding: RoleBertEncoding): Promise<Float32Array> {
    const output = await predictRoleNnrtModel(RoleModelService.intBuffer(encoding.inputIds),
      RoleModelService.intBuffer(encoding.tokenTypes), RoleModelService.intBuffer(encoding.attentionMask));
    this.state.backend = output.backend;
    const scores = new Float32Array(output.output);
    if (scores.length !== RoleBertTokenizer.SEQUENCE_LENGTH * 2) throw new Error('role_model_unsupported');
    return scores;
  }

  private static intBuffer(values: number[]): ArrayBuffer {
    const buffer = new ArrayBuffer(values.length * 4);
    const view = new DataView(buffer);
    for (let index = 0; index < values.length; index++) view.setInt32(index * 4, values[index], true);
    return buffer;
  }

  private bestSpan(start: Float32Array, end: Float32Array, encoding: RoleBertEncoding, context: string): string {
    let bestScore = Number.NEGATIVE_INFINITY;
    let bestName = '?';
    for (let first = 0; first < encoding.contextModelPositions.length; first++) {
      const firstPosition = encoding.contextModelPositions[first];
      const lastLimit = Math.min(encoding.contextModelPositions.length, first + 25);
      for (let last = first; last < lastLimit; last++) {
        if (last > first && context.substring(encoding.contextEnds[last - 1], encoding.contextStarts[last]).trim()) break;
        const name = context.substring(encoding.contextStarts[first], encoding.contextEnds[last]).trim();
        if (name.length > 24) break;
        if (!RoleSpeechPlanner.isSpeaker(name)) continue;
        const lastPosition = encoding.contextModelPositions[last];
        const score = start[firstPosition] + end[lastPosition];
        if (score > bestScore) { bestScore = score; bestName = name; }
      }
    }
    return bestName;
  }

  static errorMessage(message: string): ResourceStr {
    if (message.includes('role_model_size')) return $r('app.string.role_model_size_error');
    if (message.includes('role_space')) return $r('app.string.role_model_space_error');
    if (message.includes('role_memory')) return $r('app.string.role_model_memory_error');
    if (message.includes('role_model_unsupported')) return $r('app.string.role_model_unsupported_error');
    if (message.includes('role_tokenizer_invalid')) return $r('app.string.role_model_tokenizer_error');
    if (message.includes('role_save')) return $r('app.string.role_save_error');
    return $r('app.string.role_model_load_error');
  }
}
