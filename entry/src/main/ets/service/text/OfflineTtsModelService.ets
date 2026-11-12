import { common } from '@kit.AbilityKit';
import { fileIo, picker, statfs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { extract as extractOriginalArchive, cancel as cancelOriginalArchive,
  progress as originalArchiveProgress } from 'liboffline_tts_archive.so';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { OfflineTtsManifest, OfflineTtsModelState,
  OFFLINE_TTS_MODEL_ID, OFFLINE_TTS_CHUNK_BYTES, OFFLINE_TTS_MAX_BYTES } from '../../model/OfflineTts';
import { OfflineTtsPinnedAsset, OFFLINE_TTS_PINNED_SPEAKERS } from '../../model/OfflineTtsAssets';
import { OfflineTtsModelDefinition, OFFLINE_TTS_MODELS, getOfflineTtsModel } from '../../model/OfflineTtsCatalog';
import { EpubArchive } from './EpubArchive';
import { OfflineTtsService } from './OfflineTtsService';

/** 模型仅由系统文件选择器导入；逐块校验固定版本，完成真实短句合成后才交换目录。 */
export class OfflineTtsModelService {
  static readonly instance: OfflineTtsModelService = new OfflineTtsModelService();
  /** 保留旧调用的 Kokoro 状态；其余型号通过 stateFor 取得同一稳定实例。 */
  readonly state: OfflineTtsModelState = new OfflineTtsModelState();
  private states: Map<string, OfflineTtsModelState> = new Map<string, OfflineTtsModelState>();
  private root: string = '';
  private context: common.Context | null = null;
  private recovery: Promise<void> | null = null;
  private epoch: number = 0;
  private extracting: boolean = false;

  private definition(modelId: string): OfflineTtsModelDefinition {
    const definition = getOfflineTtsModel(modelId);
    if (!definition) throw new Error('offline_tts_pack_invalid');
    return definition;
  }

  stateFor(modelId: string): OfflineTtsModelState {
    this.definition(modelId);
    if (modelId === OFFLINE_TTS_MODEL_ID) return this.state;
    let state = this.states.get(modelId);
    if (!state) {
      state = new OfflineTtsModelState();
      this.states.set(modelId, state);
    }
    return state;
  }

  isBusy(): boolean {
    for (const definition of OFFLINE_TTS_MODELS) {
      if (this.stateFor(definition.id).busy) return true;
    }
    return false;
  }

  directory(modelId: string = OFFLINE_TTS_MODEL_ID): string {
    this.definition(modelId);
    return this.root.length > 0 ? `${this.root}/${modelId}` : '';
  }
  cancel(): void {
    this.epoch++;
    if (this.extracting) cancelOriginalArchive();
  }
  isVoiceId(id: string): boolean {
    for (const definition of OFFLINE_TTS_MODELS) {
      const prefix = `${definition.voicePrefix}:`;
      if (!id.startsWith(prefix)) continue;
      const sid = Number(id.substring(prefix.length));
      return Number.isInteger(sid) && sid >= definition.minSpeaker && sid <= definition.maxSpeaker &&
        id === `${prefix}${sid}`;
    }
    return false;
  }

  voices(): CustomTtsConfig[] {
    const voices: CustomTtsConfig[] = [];
    for (const definition of OFFLINE_TTS_MODELS) {
      if (!this.stateFor(definition.id).installed) continue;
      if (definition.id === OFFLINE_TTS_MODEL_ID) {
        this.appendKokoroVoices(voices, definition);
      } else {
        const voice = new CustomTtsConfig();
        voice.id = `${definition.voicePrefix}:0`; voice.provider = definition.provider;
        voice.modelId = definition.id; voice.speakerId = 0;
        voice.group = this.context?.resourceManager.getStringSync($r('app.string.offline_tts_piper_voice_group').id) ?? 'Piper';
        voice.name = this.context?.resourceManager.getStringSync((definition.id === 'piper-chaowen-int8-v1' ?
          $r('app.string.offline_tts_piper_chaowen_voice') : $r('app.string.offline_tts_piper_xiaoya_voice')).id) ?? definition.name;
        voices.push(voice);
      }
    }
    return voices;
  }

  private appendKokoroVoices(voices: CustomTtsConfig[], definition: OfflineTtsModelDefinition): void {
    for (const speaker of OFFLINE_TTS_PINNED_SPEAKERS) {
      const sid = speaker.id;
      if (speaker.language !== 'zh-CN' || sid < definition.minSpeaker || sid > definition.maxSpeaker) continue;
      const voice = new CustomTtsConfig();
      voice.id = `${definition.voicePrefix}:${sid}`; voice.provider = definition.provider;
      voice.modelId = definition.id; voice.speakerId = sid;
      voice.group = this.context?.resourceManager.getStringSync($r('app.string.offline_tts_voice_group').id) ?? 'Kokoro';
      voice.name = this.context?.resourceManager.getStringSync((sid <= 57 ?
        $r('app.string.offline_tts_voice_female') : $r('app.string.offline_tts_voice_male')).id,
        speaker.name.substring(3)) ?? `Kokoro ${speaker.name}`;
      voices.push(voice);
    }
  }

  ensure(context: common.Context): Promise<void> {
    if (this.recovery === null) {
      this.context = context;
      this.root = `${context.filesDir}/offline_tts`;
      this.recovery = this.restore().catch((error: Error): void => { this.recovery = null; throw error; });
    }
    return this.recovery;
  }

  private totalBytes(definition: OfflineTtsModelDefinition): number {
    return definition.assets.reduce((sum: number, asset: OfflineTtsPinnedAsset): number => sum + asset.bytes, 0);
  }

  private async removeDirectory(path: string): Promise<void> {
    if (await fileIo.access(path)) await fileIo.rmdir(path);
  }

  private async installed(directory: string, definition: OfflineTtsModelDefinition): Promise<boolean> {
    try {
      const manifestPath = `${directory}/offline-tts.json`;
      if ((await fileIo.stat(manifestPath)).size > 128 * 1024) return false;
      const manifest: OfflineTtsManifest = JSON.parse(await fileIo.readText(manifestPath));
      this.checkManifest(manifest, definition);
      for (const asset of definition.assets) {
        if ((await fileIo.stat(`${directory}/${asset.name}`)).size !== asset.bytes) return false;
      }
      return true;
    } catch (_error) { return false; }
  }

  private async restore(): Promise<void> {
    for (const definition of OFFLINE_TTS_MODELS) {
      const directory = this.directory(definition.id);
      const previous = `${directory}.previous`;
      if (await fileIo.access(previous)) {
        if (!await this.installed(directory, definition)) {
          await this.removeDirectory(directory);
          await fileIo.rename(previous, directory);
        } else await this.removeDirectory(previous);
      }
      await this.removeDirectory(`${directory}.importing`);
      const state = this.stateFor(definition.id);
      state.installed = await this.installed(directory, definition);
      state.bytes = state.installed ? this.totalBytes(definition) : 0;
      state.name = state.installed ? this.modelName(definition) : '';
    }
  }

  private modelName(definition: OfflineTtsModelDefinition): string {
    if (definition.id !== OFFLINE_TTS_MODEL_ID) return definition.name;
    return this.context?.resourceManager.getStringSync($r('app.string.offline_tts_model_name').id) ?? definition.name;
  }

  private checkManifest(manifest: OfflineTtsManifest, definition: OfflineTtsModelDefinition): void {
    if (!manifest || manifest.format !== 1 || manifest.id !== definition.id ||
      manifest.chunkBytes !== OFFLINE_TTS_CHUNK_BYTES || !Array.isArray(manifest.assets) ||
      manifest.assets.length !== definition.assets.length || manifest.assets.length > 512 ||
      this.totalBytes(definition) > OFFLINE_TTS_MAX_BYTES) throw new Error('offline_tts_pack_invalid');
    const seen = new Set<string>();
    for (const item of manifest.assets) {
      if (!item || typeof item.name !== 'string' || seen.has(item.name)) throw new Error('offline_tts_pack_invalid');
      const expected = definition.assets.find((asset: OfflineTtsPinnedAsset): boolean => asset.name === item.name);
      if (!expected || item.bytes !== expected.bytes || item.sha256 !== expected.sha256) {
        throw new Error('offline_tts_pack_invalid');
      }
      seen.add(item.name);
    }
  }

  async pick(context: common.UIAbilityContext, active: () => boolean,
    beforeMutation: () => Promise<void>, modelId: string = OFFLINE_TTS_MODEL_ID): Promise<boolean> {
    await this.ensure(context);
    this.definition(modelId);
    if (this.isBusy()) return false;
    if (!canIUse('SystemCapability.FileManagement.UserFileService')) throw new Error('offline_tts_unavailable');
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = [modelId === OFFLINE_TTS_MODEL_ID ? 'TTS|.bz2,.zip' : 'TTS|.bz2'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0 || !active()) return false;
    return this.importFile(context, uris[0], active, beforeMutation, modelId);
  }

  private async importOriginal(uri: string, staging: string, check: () => void,
    definition: OfflineTtsModelDefinition, state: OfflineTtsModelState): Promise<ArrayBuffer> {
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const total = this.totalBytes(definition);
    this.extracting = true;
    const timer = setInterval((): void => {
      try {
        check();
        state.progress = Math.min(70, Math.floor(originalArchiveProgress() / total * 70));
      } catch (_cancelled) { cancelOriginalArchive(); }
    }, 200);
    try {
      const count = await extractOriginalArchive(source.fd, staging, definition.id);
      check();
      if (count !== definition.assets.length) throw new Error('offline_tts_pack_invalid');
    } finally {
      clearInterval(timer); this.extracting = false;
      await fileIo.close(source);
    }
    // 原始发布包没有应用清单；解包只落固定资源，随后逐块验证同一份固定 SHA256。
    let complete = 0;
    for (const asset of definition.assets) {
      check();
      const input = await fileIo.open(`${staging}/${asset.name}`, fileIo.OpenMode.READ_ONLY);
      try {
        if ((await fileIo.stat(input.fd)).size !== asset.bytes) throw new Error('offline_tts_pack_invalid');
        const md = cryptoFramework.createMd('SHA256');
        for (let offset = 0; offset < asset.bytes;) {
          check();
          const chunk = new ArrayBuffer(Math.min(OFFLINE_TTS_CHUNK_BYTES, asset.bytes - offset));
          const count = await fileIo.read(input.fd, chunk, { offset, length: chunk.byteLength });
          if (count <= 0 || count > chunk.byteLength) throw new Error('offline_tts_pack_invalid');
          await md.update({ data: new Uint8Array(chunk, 0, count) });
          offset += count;
          state.progress = 70 + Math.floor((complete + offset) / total * 30);
        }
        let digest = '';
        for (const byte of (await md.digest()).data) digest += byte.toString(16).padStart(2, '0');
        if (digest !== asset.sha256) throw new Error('offline_tts_pack_invalid');
        complete += asset.bytes;
      } finally { await fileIo.close(input); }
    }
    const manifest = new OfflineTtsManifest();
    manifest.id = definition.id; manifest.assets = definition.assets;
    return new util.TextEncoder().encodeInto(JSON.stringify(manifest)).buffer;
  }

  async importFile(context: common.Context, uri: string, active: () => boolean,
    beforeMutation: () => Promise<void>, modelId: string = OFFLINE_TTS_MODEL_ID): Promise<boolean> {
    await this.ensure(context);
    const definition = this.definition(modelId);
    const state = this.stateFor(modelId);
    if (this.isBusy()) throw new Error('offline_tts_busy');
    state.busy = true; state.progress = 0; state.verifying = false; state.error = '';
    const ticket = ++this.epoch;
    const directory = this.directory(modelId);
    const staging = `${directory}.importing`;
    const previous = `${directory}.previous`;
    const check = (): void => { if (ticket !== this.epoch || !active()) throw new Error('offline_tts_cancelled'); };
    let archive: EpubArchive | null = null;
    try {
      check(); await beforeMutation(); await OfflineTtsService.instance.pauseForModelChange(); check();
      const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      let size = 0;
      let original = false;
      try {
        size = (await fileIo.stat(source.fd)).size;
        const header = new ArrayBuffer(4);
        if (await fileIo.read(source.fd, header, { offset: 0, length: 4 }) !== 4) {
          throw new Error('offline_tts_pack_invalid');
        }
        const bytes = new Uint8Array(header);
        original = bytes[0] === 0x42 && bytes[1] === 0x5a && bytes[2] === 0x68 && bytes[3] >= 0x31 && bytes[3] <= 0x39;
        if (!original && (bytes[0] !== 0x50 || bytes[1] !== 0x4b)) throw new Error('offline_tts_pack_invalid');
        if (!original && modelId !== OFFLINE_TTS_MODEL_ID) throw new Error('offline_tts_pack_invalid');
      }
      finally { await fileIo.close(source); }
      const total = this.totalBytes(definition);
      if (size <= 0 || size > total + 2 * 1024 * 1024) throw new Error('offline_tts_pack_invalid');
      if (await statfs.getFreeSize(context.filesDir) < total + 64 * 1024 * 1024) throw new Error('offline_tts_space');
      await this.removeDirectory(staging); await fileIo.mkdir(staging, true);
      let rawManifest = new ArrayBuffer(0);
      if (original) {
        rawManifest = await this.importOriginal(uri, staging, check, definition, state);
      } else {
        archive = await EpubArchive.open(uri); check();
        if (archive.expandedSize > total + 128 * 1024 || archive.resourceSize('offline-tts.json') <= 0 ||
          archive.resourceSize('offline-tts.json') > 128 * 1024) throw new Error('offline_tts_pack_invalid');
        rawManifest = await archive.read('offline-tts.json', 128 * 1024);
        const manifest: OfflineTtsManifest = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true })
          .decodeToString(new Uint8Array(rawManifest)));
        this.checkManifest(manifest, definition);
        let complete = 0;
        for (const asset of definition.assets) {
          check();
          // 输出名称只取自编译进应用的白名单，清单字段不参与路径拼接。
          const slash = asset.name.lastIndexOf('/');
          if (slash >= 0) {
            const parent = `${staging}/${asset.name.substring(0, slash)}`;
            if (!await fileIo.access(parent)) await fileIo.mkdir(parent, true);
          }
          const output = await fileIo.open(`${staging}/${asset.name}`,
            fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          try {
            const md = cryptoFramework.createMd('SHA256');
            for (let offset = 0; offset < asset.bytes;) {
              check();
              const name = `${asset.name}/${Math.floor(offset / OFFLINE_TTS_CHUNK_BYTES)}.bin`;
              const length = Math.min(OFFLINE_TTS_CHUNK_BYTES, asset.bytes - offset);
              if (archive.resourceSize(name) !== length) throw new Error('offline_tts_pack_invalid');
              const chunk = await archive.read(name, OFFLINE_TTS_CHUNK_BYTES); check();
              if (chunk.byteLength !== length) throw new Error('offline_tts_pack_invalid');
              let written = 0;
              while (written < length) {
                check();
                const count = await fileIo.write(output.fd, chunk.slice(written));
                if (count <= 0 || count > length - written) throw new Error('offline_tts_write');
                written += count;
              }
              await md.update({ data: new Uint8Array(chunk) });
              offset += length; state.progress = Math.floor((complete + offset) / total * 100);
            }
            let digest = '';
            for (const byte of (await md.digest()).data) digest += byte.toString(16).padStart(2, '0');
            if (digest !== asset.sha256) throw new Error('offline_tts_pack_invalid');
            await fileIo.fsync(output.fd); complete += asset.bytes;
          } finally { await fileIo.close(output); }
        }
      }
      check(); state.verifying = true;
      await OfflineTtsService.instance.validate(staging, modelId); check();
      const receipt = await fileIo.open(`${staging}/offline-tts.json`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let written = 0;
        while (written < rawManifest.byteLength) {
          const count = await fileIo.write(receipt.fd, rawManifest.slice(written));
          if (count <= 0 || count > rawManifest.byteLength - written) throw new Error('offline_tts_write');
          written += count;
        }
        await fileIo.fsync(receipt.fd);
      } finally { await fileIo.close(receipt); }
      check();
      await this.removeDirectory(previous);
      if (await fileIo.access(directory)) await fileIo.rename(directory, previous);
      try { await fileIo.rename(staging, directory); }
      catch (_error) {
        if (await fileIo.access(previous)) await fileIo.rename(previous, directory);
        throw new Error('offline_tts_write');
      }
      state.installed = true; state.bytes = total;
      state.name = this.modelName(definition);
      await this.removeDirectory(previous).catch((): void => {});
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      if (message === 'offline_tts_cancelled' || ticket !== this.epoch || !active()) return false;
      state.error = message.startsWith('offline_tts_') ? message : 'offline_tts_pack_invalid';
      throw new Error(state.error);
    } finally {
      if (archive) await archive.close().catch((): void => {});
      await OfflineTtsService.instance.pauseForModelChange().catch((): void => {});
      await this.removeDirectory(staging).catch((): void => {});
      state.busy = false; state.verifying = false;
    }
  }

  async remove(context: common.Context, beforeMutation: () => Promise<void>,
    modelId: string = OFFLINE_TTS_MODEL_ID): Promise<void> {
    await this.ensure(context);
    const state = this.stateFor(modelId);
    const directory = this.directory(modelId);
    if (this.isBusy()) throw new Error('offline_tts_busy');
    state.busy = true; state.error = '';
    try {
      await beforeMutation(); await OfflineTtsService.instance.pauseForModelChange();
      await this.removeDirectory(`${directory}.previous`); await this.removeDirectory(`${directory}.importing`);
      await this.removeDirectory(directory);
      state.installed = false; state.bytes = 0; state.name = '';
    } finally { state.busy = false; }
  }
}
