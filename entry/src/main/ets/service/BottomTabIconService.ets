import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ThemeIconRole } from '../theme/ThemeIcons';

/** 只保存本目录生成的文件名，避免图库授权 URI 失效或设备路径变化。 */
class BottomTabIconSelection {
  schemaVersion: number = 1;
  home: string = '';
  shelf: string = '';
  record: string = '';
  profile: string = '';

  get(role: ThemeIconRole): string {
    switch (role) {
      case ThemeIconRole.Home: return this.home;
      case ThemeIconRole.Shelf: return this.shelf;
      case ThemeIconRole.Record: return this.record;
      case ThemeIconRole.Profile: return this.profile;
      default: return '';
    }
  }

  set(role: ThemeIconRole, name: string): void {
    switch (role) {
      case ThemeIconRole.Home: this.home = name; break;
      case ThemeIconRole.Shelf: this.shelf = name; break;
      case ThemeIconRole.Record: this.record = name; break;
      case ThemeIconRole.Profile: this.profile = name; break;
      default: throw new Error('Invalid bottom tab role');
    }
  }

  copy(): BottomTabIconSelection {
    const value = new BottomTabIconSelection();
    value.home = this.home;
    value.shelf = this.shelf;
    value.record = this.record;
    value.profile = this.profile;
    return value;
  }

  static validName(name: string): boolean {
    return typeof name === 'string' && /^tab_[0-9]+_[0-9]+\.png$/.test(name);
  }

  static decode(raw: string): BottomTabIconSelection {
    const value = new BottomTabIconSelection();
    if (raw.length === 0 || raw.length > 1024) return value;
    try {
      const saved: BottomTabIconSelection = JSON.parse(raw);
      if (!saved || saved.schemaVersion !== 1) return value;
      value.home = BottomTabIconSelection.validName(saved.home) ? saved.home : '';
      value.shelf = BottomTabIconSelection.validName(saved.shelf) ? saved.shelf : '';
      value.record = BottomTabIconSelection.validName(saved.record) ? saved.record : '';
      value.profile = BottomTabIconSelection.validName(saved.profile) ? saved.profile : '';
    } catch (_error) { /* 损坏配置回退套装图标，不阻止进入主界面。 */ }
    return value;
  }
}

/** 主应用底栏的本地图片偏好，独立于桌面应用图标、主题套装和书源模块。 */
@ObservedV2
export class BottomTabIconService {
  private static singleton: BottomTabIconService | null = null;

  static get instance(): BottomTabIconService {
    // 必须在 @ObservedV2 完成类装饰后实例化，静态字段内 new 会绕过 V2 观测。
    if (BottomTabIconService.singleton === null) {
      BottomTabIconService.singleton = new BottomTabIconService();
    }
    return BottomTabIconService.singleton;
  }
  private static readonly roles: ThemeIconRole[] = [ThemeIconRole.Home, ThemeIconRole.Shelf,
    ThemeIconRole.Record, ThemeIconRole.Profile];
  @Trace ready: boolean = false;
  @Trace busy: boolean = false;
  @Trace private selection: BottomTabIconSelection = new BottomTabIconSelection();
  private directory: string = '';
  private store: preferences.Preferences | undefined = undefined;
  private initializing: Promise<void> | undefined = undefined;

  async init(context: common.Context): Promise<void> {
    if (this.ready) return;
    if (!this.initializing) {
      this.initializing = this.load(context).finally((): void => { this.initializing = undefined; });
    }
    await this.initializing;
  }

  private async load(context: common.Context): Promise<void> {
    const directory: string = `${context.filesDir}/bottom_tab_icons`;
    const store = await preferences.getPreferences(context, { name: 'bottom_tab_icons' });
    const raw = await store.get('selection_v1', '');
    const selection = BottomTabIconSelection.decode(typeof raw === 'string' ? raw : '');
    for (const role of BottomTabIconService.roles) {
      const name = selection.get(role);
      if (name && !await fileIo.access(`${directory}/${name}`).catch((): boolean => false)) {
        selection.set(role, '');
      }
    }
    this.directory = directory;
    this.store = store;
    this.selection = selection;
    this.ready = true;
  }

  resolve(role: ThemeIconRole): string | undefined {
    const name = this.selection.get(role);
    return name && this.directory ? `file://${this.directory}/${name}` : undefined;
  }

  get hasCustomIcons(): boolean {
    return BottomTabIconService.roles.some((role: ThemeIconRole): boolean => this.selection.get(role).length > 0);
  }

  async importIcon(role: ThemeIconRole, uri: string, isCurrent: () => boolean): Promise<boolean> {
    if (!this.ready || this.busy || !BottomTabIconService.roles.includes(role)) return false;
    this.busy = true;
    const name: string = `tab_${Date.now()}_${Math.floor(Math.random() * 1000000000)}.png`;
    let committed: boolean = false;
    try {
      await this.writeIcon(uri, `${this.directory}/${name}`);
      if (!isCurrent()) return false;
      const next = this.selection.copy();
      next.set(role, name);
      await this.save(next);
      committed = true;
      return true;
    } finally {
      if (!committed) await this.removeFile(name);
      this.busy = false;
    }
  }

  async reset(role: ThemeIconRole = ThemeIconRole.None): Promise<void> {
    if (!this.ready || this.busy) return;
    this.busy = true;
    try {
      const next = role === ThemeIconRole.None ? new BottomTabIconSelection() : this.selection.copy();
      if (role !== ThemeIconRole.None) next.set(role, '');
      await this.save(next);
    } finally { this.busy = false; }
  }

  private async save(next: BottomTabIconSelection): Promise<void> {
    const store = this.store;
    if (!store) throw new Error('Bottom tab preferences unavailable');
    const previous = this.selection;
    const raw = await store.get('selection_v1', '');
    try {
      await store.put('selection_v1', JSON.stringify(next));
      await store.flush();
    } catch (error) {
      // flush 失败也要还原 Preferences 内存缓存，防止后续保存误写失败记录。
      await store.put('selection_v1', raw);
      const failure: Error = error;
      throw new Error(failure.message);
    }
    this.selection = next;
    for (const role of BottomTabIconService.roles) {
      const oldName = previous.get(role);
      if (oldName && !BottomTabIconService.roles.some((item: ThemeIconRole): boolean => next.get(item) === oldName)) {
        await this.removeFile(oldName);
      }
    }
  }

  private async removeFile(name: string): Promise<void> {
    if (BottomTabIconSelection.validName(name)) {
      await fileIo.unlink(`${this.directory}/${name}`).catch((): void => {});
    }
  }

  private async writeIcon(uri: string, target: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0 || stat.size > 20 * 1024 * 1024) throw new Error('Icon input exceeds budget');
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0 || info.size.width * info.size.height > 100000000) {
        throw new Error('Invalid icon dimensions');
      }
      const scale = Math.min(1, 256 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({ editable: true, desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      const decoded = await pixels.getImageInfo();
      const edge = Math.min(decoded.size.width, decoded.size.height);
      await pixels.crop({ x: Math.floor((decoded.size.width - edge) / 2),
        y: Math.floor((decoded.size.height - edge) / 2), size: { width: edge, height: edge } });
      packer = image.createImagePacker();
      const bytes = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      if (bytes.byteLength === 0 || bytes.byteLength > 512 * 1024) throw new Error('Icon output exceeds budget');
      if (!await fileIo.access(this.directory)) await fileIo.mkdir(this.directory, true);
      const output = await fileIo.open(target, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < bytes.byteLength) {
          const written = await fileIo.write(output.fd, bytes.slice(offset));
          if (written <= 0) throw new Error('Incomplete icon file');
          offset += written;
        }
      } finally { await fileIo.close(output); }
    } finally {
      // 每项单独释放，某项释放异常也不能跳过文件描述符和其他图像对象。
      if (pixels) await pixels.release().catch((): void => {});
      if (source) await source.release().catch((): void => {});
      if (packer) await packer.release().catch((): void => {});
      await fileIo.close(file);
    }
  }
}
