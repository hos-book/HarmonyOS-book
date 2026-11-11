export class AiModelAsset {
  name: string;
  local: string;
  bytes: number;
  sha256: string;
  constructor(name: string, local: string, bytes: number, sha256: string) {
    this.name = name; this.local = local; this.bytes = bytes; this.sha256 = sha256;
  }
}

export class AiModelPack {
  id: string;
  directory: string;
  assets: AiModelAsset[];
  constructor(id: string, directory: string, assets: AiModelAsset[]) {
    this.id = id; this.directory = directory; this.assets = assets;
  }
  bytes(): number { return this.assets.reduce((sum: number, asset: AiModelAsset): number => sum + asset.bytes, 0); }
  get encrypted(): boolean { return this.id === 'comic-color-v1'; }
}

export const AI_MODEL_CHUNK_BYTES: number = 4 * 1024 * 1024;
export const AI_MODEL_PACKS: AiModelPack[] = [
  new AiModelPack('comic-color-v1', 'comic_colorizer', [
    new AiModelAsset('alac.ms', 'alac-fp16-v4.ms', 61596264,
      'c212815a335a006b4bbf336af1c25c6158aaeac077f35f2775af381b83fe9934'),
    new AiModelAsset('alac-npu-portrait.ms', 'alac-npu-v1-portrait.ms', 61608728,
      'db162d1620a560c86fe883484311133e11ba5e4b24790cefe355043f9928e3e0'),
    new AiModelAsset('alac-npu-landscape.ms', 'alac-npu-v1-landscape.ms', 61608728,
      '2abbc0e27cb1dbf859a835072c4c7f06982e70cd0e57ff401008501b33ce40fd')
  ]),
  new AiModelPack('audio-subtitle-v1', 'subtitle_models/824c678e9b80f301110e3ea8cee9819a7994c049', [
    new AiModelAsset('model.int8.onnx', 'model.int8.onnx', 367074356,
      'e291b9c468b651e2697caa09bc684326c3addc6a019e78eb537cfd1a8248ca07'),
    new AiModelAsset('tokens.txt', 'tokens.txt', 13366,
      '6fed8c6c248516f38e7faa19404b57413e8ce259f1cbc1fa4aebc86eac32fdfd'),
    new AiModelAsset('punctuation.int8.onnx', 'punctuation.int8.onnx', 75519198,
      '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1')
  ])
];

export class AiModelPackManifest {
  format: number = 0;
  id: string = '';
  chunkBytes: number = 0;
  cipher: string = '';
  keyId: string = '';
}

export class AiModelPackUsage {
  bytes: number = 0;
  installed: boolean = false;
}

@ObservedV2
export class AiModelPackState {
  @Trace busyId: string = '';
  @Trace progress: number = 0;
  @Trace verifying: boolean = false;
  @Trace removing: boolean = false;
}
