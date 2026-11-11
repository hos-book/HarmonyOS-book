import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { SubtitleFiles } from './SubtitleFiles';
import { AiModelPackService } from '../AiModelPackService';

class SubtitleModelAsset {
  name: string;
  bytes: number;
  sha256: string;
  constructor(name: string, bytes: number, sha256: string) {
    this.name = name; this.bytes = bytes; this.sha256 = sha256;
  }
}

const REVISION = '824c678e9b80f301110e3ea8cee9819a7994c049';
const ASSETS: SubtitleModelAsset[] = [
  new SubtitleModelAsset('model.int8.onnx', 367074356, 'e291b9c468b651e2697caa09bc684326c3addc6a019e78eb537cfd1a8248ca07'),
  new SubtitleModelAsset('tokens.txt', 13366, '6fed8c6c248516f38e7faa19404b57413e8ce259f1cbc1fa4aebc86eac32fdfd')
];

export class SubtitleModelService {
  private static verified: Map<string, string> = new Map();
  static directory(context: common.Context): string { return `${context.filesDir}/subtitle_models/${REVISION}`; }

  /** 标点权重来自用户导入的固定版本资源包；旧版本已提取文件继续复用。 */
  static async preparePunctuation(context: common.Context, active: () => boolean): Promise<void> {
    const asset = new SubtitleModelAsset('punctuation.int8.onnx', 75519198,
      '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1');
    if (!await SubtitleModelService.valid(`${SubtitleModelService.directory(context)}/${asset.name}`, asset, active)) {
      throw new Error('model_pack_missing');
    }
  }

  static async ready(context: common.Context, active: () => boolean): Promise<boolean> {
    await AiModelPackService.instance.recover(context);
    if (AiModelPackService.instance.isBusy('audio-subtitle-v1')) return false;
    for (const asset of ASSETS) {
      if (!await SubtitleModelService.valid(`${SubtitleModelService.directory(context)}/${asset.name}`, asset, active)) return false;
    }
    try { await SubtitleModelService.preparePunctuation(context, active); } catch (_error) { return false; }
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

}
