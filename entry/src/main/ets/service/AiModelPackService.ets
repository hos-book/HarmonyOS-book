import { common } from '@kit.AbilityKit';
import { fileIo, picker, statfs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AiModelAsset, AiModelPack, AiModelPackManifest, AiModelPackState, AiModelPackUsage,
  AI_MODEL_CHUNK_BYTES, AI_MODEL_PACKS } from '../model/AiModelPack';
import { EpubArchive } from './text/EpubArchive';
import { AiModelPackCrypto } from './AiModelPackCrypto';

/** 只安装应用固定版本的权重；ZIP 路径永不作为文件系统输出路径。 */
export class AiModelPackService {
  static readonly instance: AiModelPackService = new AiModelPackService();
  readonly state: AiModelPackState = new AiModelPackState();
  private epoch: number = 0;
  private recovery: Promise<void> | null = null;

  static pack(id: string): AiModelPack {
    const pack = AI_MODEL_PACKS.find((item: AiModelPack): boolean => item.id === id);
    if (!pack) throw new Error('model_pack_invalid');
    return pack;
  }

  isBusy(id: string): boolean { return this.state.busyId === id; }
  cancel(): void { this.epoch++; }

  private directory(context: common.Context, pack: AiModelPack): string { return `${context.filesDir}/${pack.directory}`; }

  private async removeDirectory(path: string): Promise<void> {
    if (await fileIo.access(path)) await fileIo.rmdir(path);
  }

  /** 恢复目录交换期间的进程中断；模型从不放入可淘汰的 cacheDir。 */
  recover(context: common.Context): Promise<void> {
    if (this.state.busyId) return Promise.resolve();
    if (this.recovery === null) this.recovery = this.restore(context).catch((error: Error): void => {
      this.recovery = null; throw error;
    });
    return this.recovery;
  }

  private async restore(context: common.Context): Promise<void> {
    for (const pack of AI_MODEL_PACKS) {
      const directory = this.directory(context, pack);
      const previous = `${directory}.previous`;
      if (await fileIo.access(previous)) {
        if (!await fileIo.access(directory)) await fileIo.rename(previous, directory);
        else await this.removeDirectory(previous);
      }
      await this.removeDirectory(`${directory}.importing`);
    }
  }

  usage(context: common.Context, id: string): AiModelPackUsage {
    const pack = AiModelPackService.pack(id);
    const usage = new AiModelPackUsage();
    usage.installed = true;
    for (const asset of pack.assets) {
      try {
        const size = fileIo.statSync(`${this.directory(context, pack)}/${asset.local}`).size;
        usage.bytes += size;
        if (size !== asset.bytes) usage.installed = false;
      } catch (_error) { usage.installed = false; }
    }
    return usage;
  }

  async pick(context: common.UIAbilityContext, id: string, active: () => boolean,
    beforeMutation: () => Promise<void>): Promise<boolean> {
    if (this.state.busyId) return false;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = AiModelPackService.pack(id).encrypted ? ['JTMODEL|.jtmodel'] : ['ZIP|.zip'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (!active() || uris.length === 0) return false;
    return this.importFile(context, id, uris[0], active, beforeMutation);
  }

  async importFile(context: common.Context, id: string, uri: string, active: () => boolean,
    beforeMutation: () => Promise<void>): Promise<boolean> {
    await this.recover(context);
    if (this.state.busyId) throw new Error('model_pack_busy');
    const pack = AiModelPackService.pack(id);
    this.state.busyId = id; this.state.progress = 0; this.state.verifying = false;
    const ticket = ++this.epoch;
    const check = (): void => { if (ticket !== this.epoch || !active()) throw new Error('model_pack_cancelled'); };
    const directory = this.directory(context, pack);
    const staging = `${directory}.importing`;
    const previous = `${directory}.previous`;
    let archive: EpubArchive | null = null;
    let decryptor: AiModelPackCrypto | null = null;
    try {
      check();
      // 文件选择取消不影响推理；选中文件后才阻止新任务并等待在途 Worker 释放。
      await beforeMutation(); check();
      if (await fileIo.access(previous)) {
        if (!await fileIo.access(directory)) await fileIo.rename(previous, directory);
        else await this.removeDirectory(previous);
      }
      await this.removeDirectory(staging);
      const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const size = (await fileIo.stat(source.fd)).size;
        if (size <= 0 || size > pack.bytes() + 2 * 1024 * 1024) throw new Error('model_pack_invalid');
      } finally { await fileIo.close(source); }
      if (await statfs.getFreeSize(context.filesDir) < pack.bytes() + 64 * 1024 * 1024) throw new Error('model_pack_space');
      archive = await EpubArchive.open(uri); check();
      const overhead = pack.assets.reduce((sum: number, asset: AiModelAsset): number =>
        sum + Math.ceil(asset.bytes / AI_MODEL_CHUNK_BYTES) * 28, 0);
      if (archive.expandedSize > pack.bytes() + overhead + 65536 || archive.resourceSize('model-pack.json') > 4096) {
        throw new Error('model_pack_invalid');
      }
      const manifest: AiModelPackManifest = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true })
        .decodeToString(new Uint8Array(await archive.read('model-pack.json', 4096))));
      if (!manifest || manifest.format !== (pack.encrypted ? 2 : 1) || manifest.id !== id ||
        manifest.chunkBytes !== AI_MODEL_CHUNK_BYTES || (pack.encrypted && manifest.cipher !== 'AES-256-GCM')) {
        throw new Error('model_pack_invalid');
      }
      if (pack.encrypted) decryptor = await AiModelPackCrypto.open(manifest.keyId);
      await fileIo.mkdir(staging, true);
      let completed = 0;
      for (const asset of pack.assets) {
        check();
        const output = await fileIo.open(`${staging}/${asset.local}`,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          const md = cryptoFramework.createMd('SHA256');
          for (let offset = 0; offset < asset.bytes;) {
            check();
            const name = `${asset.name}/${Math.floor(offset / AI_MODEL_CHUNK_BYTES)}.bin`;
            const length = Math.min(AI_MODEL_CHUNK_BYTES, asset.bytes - offset);
            if (archive.resourceSize(name) !== length + (pack.encrypted ? 28 : 0)) throw new Error('model_pack_invalid');
            let chunk = await archive.read(name, AI_MODEL_CHUNK_BYTES + 28); check();
            if (decryptor) chunk = await decryptor.decrypt(chunk, id, asset.name, Math.floor(offset / AI_MODEL_CHUNK_BYTES));
            check();
            if (chunk.byteLength !== length) throw new Error('model_pack_invalid');
            let written = 0;
            while (written < length) {
              check();
              const count = await fileIo.write(output.fd, chunk.slice(written));
              if (count <= 0 || count > length - written) throw new Error('model_pack_write');
              written += count;
            }
            await md.update({ data: new Uint8Array(chunk) });
            offset += length;
            this.state.progress = Math.floor((completed + offset) / pack.bytes() * 100);
          }
          this.state.verifying = true;
          let hex = '';
          for (const byte of (await md.digest()).data) hex += byte.toString(16).padStart(2, '0');
          if (hex !== asset.sha256) throw new Error('model_pack_invalid');
          await fileIo.fsync(output.fd);
          this.state.verifying = false;
          completed += asset.bytes;
        } finally { await fileIo.close(output); }
      }
      check();
      if (await fileIo.access(directory)) await fileIo.rename(directory, previous);
      try { await fileIo.rename(staging, directory); }
      catch (_error) {
        if (await fileIo.access(previous)) await fileIo.rename(previous, directory);
        throw new Error('model_pack_write');
      }
      // 交换成功后不再接受取消，清理失败交给下次 recover，不误报安装失败。
      await this.removeDirectory(previous).catch((): void => {});
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      if (message === 'model_pack_cancelled') return false;
      if (message.startsWith('model_pack_')) throw new Error(message);
      throw new Error('model_pack_invalid');
    } finally {
      if (decryptor) decryptor.close();
      if (archive) await archive.close().catch((): void => {});
      await this.removeDirectory(staging).catch((): void => {});
      this.state.busyId = ''; this.state.verifying = false;
    }
  }

  async remove(context: common.Context, id: string, beforeMutation: () => Promise<void>): Promise<void> {
    await this.recover(context);
    if (this.state.busyId) throw new Error('model_pack_busy');
    const pack = AiModelPackService.pack(id);
    this.state.busyId = id; this.state.removing = true;
    try {
      await beforeMutation();
      await this.removeDirectory(`${this.directory(context, pack)}.previous`);
      await this.removeDirectory(`${this.directory(context, pack)}.importing`);
      await this.removeDirectory(this.directory(context, pack));
      const marker = `${this.directory(context, pack)}.disabled`;
      if (await fileIo.access(marker)) await fileIo.unlink(marker);
    } finally { this.state.busyId = ''; this.state.removing = false; }
  }

  static errorMessage(code: string): Resource {
    if (code === 'model_pack_space') return $r('app.string.model_pack_space');
    if (code === 'model_pack_busy') return $r('app.string.model_pack_busy');
    if (code === 'model_pack_write') return $r('app.string.model_pack_write');
    return $r('app.string.model_pack_invalid');
  }
}
