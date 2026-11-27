import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { SHENGQIAO_PROVIDER, ShengqiaoPackage, ShengqiaoState, ShengqiaoVoice } from '../../model/ShengqiaoPlugin';

/** 插件目录与账号凭据供登录、调试及朗读共用。 */
export class ShengqiaoPluginService {
  static readonly instance: ShengqiaoPluginService = new ShengqiaoPluginService();
  readonly state: ShengqiaoState = new ShengqiaoState();
  private pack: ShengqiaoPackage = new ShengqiaoPackage();
  private store: preferences.Preferences | null = null;
  private initialization: Promise<void> | null = null;
  private credential: string = '';
  private huaweiGroup: string = '';
  private edgeGroup: string = '';
  private celiaGroup: string = '';
  private pickerLabel: string = '';

  initialize(context: common.Context): Promise<void> {
    if (this.initialization === null) this.initialization = this.load(context);
    return this.initialization;
  }

  private async load(context: common.Context): Promise<void> {
    this.huaweiGroup = context.resourceManager.getStringSync($r('app.string.shengqiao_group_huawei').id);
    this.edgeGroup = context.resourceManager.getStringSync($r('app.string.shengqiao_group_edge').id);
    this.celiaGroup = context.resourceManager.getStringSync($r('app.string.shengqiao_group_celia').id);
    this.pickerLabel = context.resourceManager.getStringSync($r('app.string.shengqiao_title').id);
    this.store = await preferences.getPreferences(context, { name: 'shengqiao_plugin' });
    const raw = this.store.getSync('package', '');
    if (typeof raw === 'string' && raw) this.publish(JSON.parse(raw));
    this.state.active = this.state.installed && this.store.getSync('active', false) === true;
    const query = this.assetQuery();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const records = await asset.query(query);
      const secret = records[0]?.get(asset.Tag.SECRET);
      if (secret instanceof Uint8Array) this.credential = util.TextDecoder.create('utf-8').decodeToString(secret);
    } catch (error) {
      const failure: BusinessError = error;
      if (failure.code !== 24000002) throw new Error('shengqiao_credential');
    }
    this.state.loggedIn = this.credential.length > 0;
    this.state.ready = true;
  }

  private assetQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('jianting.shengqiao.refresh'));
    return query;
  }

  async saveCredential(refresh: string): Promise<void> {
    const attributes = this.assetQuery();
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(refresh));
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attributes);
    this.credential = refresh;
    this.state.loggedIn = true;
  }

  refreshCredential(): string { return this.credential; }

  async logout(): Promise<void> {
    if (this.state.loggedIn) await asset.remove(this.assetQuery());
    this.credential = '';
    this.state.loggedIn = false;
  }

  secret(index: number): string {
    const key: number[] = [0x5A, 0x3C, 0x91, 0xE7, 0x2B, 0x6D, 0xF4, 0x18];
    const data = new util.Base64Helper().decodeSync(this.pack.secrets[index]);
    for (let offset = 0; offset < data.length; offset++) data[offset] ^= key[offset % 8] ^ ((offset * 31 + 7) & 255);
    return util.TextDecoder.create('utf-8').decodeToString(data);
  }

  voice(key: string): ShengqiaoVoice | undefined { return this.pack.voices.find((item: ShengqiaoVoice): boolean => item.key === key); }

  voices(includeInactive: boolean = false): CustomTtsConfig[] {
    if (!this.state.installed || (!includeInactive && !this.state.active)) return [];
    return this.pack.voices.map((voice: ShengqiaoVoice): CustomTtsConfig => {
      const config = new CustomTtsConfig();
      config.provider = SHENGQIAO_PROVIDER;
      config.modelId = voice.key;
      config.id = `shengqiao:${voice.key}`;
      config.name = voice.name;
      config.group = voice.channel === 'celia' ? this.celiaGroup :
        (voice.channel === 'huawei' ? this.huaweiGroup : this.edgeGroup);
      config.tier = voice.vip ? 'vip' : '';
      return config;
    });
  }

  private publish(pack: ShengqiaoPackage): void {
    this.pack = pack;
    this.state.installed = true;
    this.state.version = pack.version;
    this.state.voiceCount = pack.voices.length;
  }

  async pick(context: common.UIAbilityContext): Promise<boolean> {
    await this.initialize(context);
    this.state.busy = true;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = [`${this.pickerLabel}|.jtplugin`];
      const uris = await new picker.DocumentViewPicker(context).select(options);
      if (uris.length === 0) return false;
      const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
      let raw = '';
      try {
        const bytes = new ArrayBuffer((await fileIo.stat(file.fd)).size);
        let offset = 0;
        while (offset < bytes.byteLength) {
          const part = new ArrayBuffer(bytes.byteLength - offset);
          const count = await fileIo.read(file.fd, part);
          if (count === 0) throw new Error('shengqiao_package');
          new Uint8Array(bytes).set(new Uint8Array(part, 0, count), offset);
          offset += count;
        }
        raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(bytes));
      }
      finally { await fileIo.close(file); }
      const pack: ShengqiaoPackage = JSON.parse(raw);
      if (pack.format !== 1 || pack.id !== 'shengqiao' || pack.abi !== 'shengqiao-tts-v1' ||
        !pack.version || !Array.isArray(pack.voices) || !Array.isArray(pack.secrets) ||
        (pack.secrets.length !== 5 && pack.secrets.length !== 7) ||
        pack.voices.length === 0 || pack.voices.some((voice: ShengqiaoVoice): boolean =>
          !voice.key || !voice.name || !voice.sid ||
          (voice.channel !== 'huawei' && voice.channel !== 'edge' && voice.channel !== 'celia') ||
          (voice.channel === 'celia' && pack.secrets.length !== 7))) {
        throw new Error('shengqiao_package');
      }
      await this.store?.put('package', JSON.stringify(pack));
      await this.store?.flush();
      this.publish(pack);
      return true;
    } finally { this.state.busy = false; }
  }

  async setActive(active: boolean): Promise<void> {
    await this.store?.put('active', active);
    await this.store?.flush();
    this.state.active = active;
  }

  async remove(): Promise<void> {
    await this.setActive(false);
    await this.logout();
    await this.store?.delete('package');
    await this.store?.flush();
    this.pack = new ShengqiaoPackage();
    this.state.installed = false;
    this.state.version = '';
    this.state.voiceCount = 0;
    this.state.result = '';
  }
}
