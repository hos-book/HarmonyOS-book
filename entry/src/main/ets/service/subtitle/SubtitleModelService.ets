import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { SubtitleFiles } from './SubtitleFiles';

class SubtitleModelAsset {
  name: string;
  bytes: number;
  sha256: string;
  constructor(name: string, bytes: number, sha256: string) {
    this.name = name; this.bytes = bytes; this.sha256 = sha256;
  }
}

const REVISION = '824c678e9b80f301110e3ea8cee9819a7994c049';
// Publisher's ModelScope copy has exactly the same model/token SHA256 as the HF revision above.
const DOWNLOAD_REVISION = 'ec0ba42ddef79fe0bd20c3563f14368f48e69a2c';
const ASSETS: SubtitleModelAsset[] = [
  new SubtitleModelAsset('model.int8.onnx', 367074356, 'e291b9c468b651e2697caa09bc684326c3addc6a019e78eb537cfd1a8248ca07'),
  new SubtitleModelAsset('tokens.txt', 13366, '6fed8c6c248516f38e7faa19404b57413e8ce259f1cbc1fa4aebc86eac32fdfd')
];

export class SubtitleModelService {
  private static verified: Map<string, string> = new Map();
  static directory(context: common.Context): string { return `${context.filesDir}/subtitle_models/${REVISION}`; }

  /** Bundled int8 punctuation model; copy in bounded buffers without another network download. */
  static async preparePunctuation(context: common.Context, active: () => boolean): Promise<void> {
    const asset = new SubtitleModelAsset('punctuation.int8.onnx', 75519198,
      '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1');
    const dir = SubtitleModelService.directory(context);
    const path = `${dir}/${asset.name}`;
    if (await SubtitleModelService.valid(path, asset, active)) return;
    if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir, true);
    const resource = `audio_subtitles/${asset.name}`;
    const descriptor = await context.resourceManager.getRawFd(resource);
    const temporary = `${path}.part`;
    try {
      if (descriptor.length !== asset.bytes) throw new Error('subtitle_model_invalid');
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < asset.bytes) {
          if (!active()) throw new Error('subtitle_cancelled');
          const buffer = new ArrayBuffer(Math.min(1024 * 1024, asset.bytes - offset));
          const read = await fileIo.read(descriptor.fd, buffer, { offset: descriptor.offset + offset });
          if (read !== buffer.byteLength || fileIo.writeSync(file.fd, buffer) !== read) throw new Error('subtitle_file_write');
          offset += read;
        }
      } finally { fileIo.closeSync(file); }
      if (!await SubtitleModelService.valid(temporary, asset, active)) throw new Error('subtitle_model_invalid');
      if (!active()) throw new Error('subtitle_cancelled');
      SubtitleFiles.remove(path); fileIo.renameSync(temporary, path);
      SubtitleModelService.remember(path, asset);
    } finally {
      await context.resourceManager.closeRawFd(resource);
      SubtitleFiles.remove(temporary); SubtitleModelService.verified.delete(temporary);
    }
  }

  static async ready(context: common.Context, active: () => boolean): Promise<boolean> {
    for (const asset of ASSETS) {
      if (!await SubtitleModelService.valid(`${SubtitleModelService.directory(context)}/${asset.name}`, asset, active)) return false;
    }
    return active();
  }

  private static async valid(path: string, asset: SubtitleModelAsset, active: () => boolean): Promise<boolean> {
    try {
      if (!active() || fileIo.statSync(path).size !== asset.bytes) return false;
      const identity = SubtitleModelService.identity(path, asset);
      if (SubtitleModelService.verified.get(path) === identity) return true;
      // These files are app-private and only atomically replaced after SHA256 verification.
      // Rehash when the pinned model, size or filesystem timestamps change.
      const receipt = `${path}.verified`;
      if (!path.endsWith('.part') && fileIo.accessSync(receipt) && fileIo.statSync(receipt).size < 512 &&
        fileIo.readTextSync(receipt) === identity) {
        SubtitleModelService.verified.set(path, identity); return true;
      }
      if (await SubtitleFiles.digest(path, active) !== asset.sha256 || !active()) return false;
      SubtitleModelService.remember(path, asset);
      return true;
    } catch (_error) { return false; }
  }

  private static identity(path: string, asset: SubtitleModelAsset): string {
    const stat = fileIo.statSync(path);
    return `${asset.sha256}:${stat.size}:${stat.mtime}:${stat.ctime}`;
  }

  private static remember(path: string, asset: SubtitleModelAsset): void {
    const identity = SubtitleModelService.identity(path, asset);
    SubtitleModelService.verified.set(path, identity);
    if (path.endsWith('.part')) return;
    try {
      const receipt = fileIo.openSync(`${path}.verified`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(receipt.fd, identity); } finally { fileIo.closeSync(receipt); }
    } catch (_error) { /* A missing receipt only costs another verification on the next launch. */ }
  }

  static async ensure(context: common.Context, active: () => boolean, progress: (percent: number) => void): Promise<void> {
    const dir = SubtitleModelService.directory(context);
    if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir, true);
    let done = 0;
    const total = ASSETS.reduce((sum: number, asset: SubtitleModelAsset): number => sum + asset.bytes, 0);
    for (const asset of ASSETS) {
      if (!active()) throw new Error('subtitle_cancelled');
      const path = `${dir}/${asset.name}`;
      if (!await SubtitleModelService.valid(path, asset, active)) {
        const temporary = `${path}.part`;
        try {
          const url = `https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03/resolve/${DOWNLOAD_REVISION}/${asset.name}`;
          await SubtitleFiles.download(url, {}, temporary, asset.bytes, active,
            (bytes: number): void => progress(Math.floor((done + bytes) * 100 / total)));
          if (!await SubtitleModelService.valid(temporary, asset, active)) throw new Error('subtitle_model_invalid');
          if (!active()) throw new Error('subtitle_cancelled');
          SubtitleFiles.remove(path);
          fileIo.renameSync(temporary, path);
          SubtitleModelService.remember(path, asset);
        } finally {
          SubtitleFiles.remove(temporary);
          SubtitleModelService.verified.delete(temporary);
        }
      }
      done += asset.bytes;
      progress(Math.floor(done * 100 / total));
    }
  }
}
