import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { ComicImagePlugin, ComicImagePluginPackage, ComicImagePluginState } from '../model/ComicImagePlugin';
import { ReaderCacheService } from './ReaderCacheService';

/** 两个独立 WASM 插件共用正文图片处理宿主。 */
export class ComicImagePluginService {
  static readonly instance: ComicImagePluginService = new ComicImagePluginService();
  static readonly ORIGIN: string = 'https://comic-plugins.invalid/';
  readonly state: ComicImagePluginState = new ComicImagePluginState();
  private store: preferences.Preferences | null = null;
  private initialization: Promise<void> | null = null;
  private controller: webview.WebviewController | null = null;
  private queue: Promise<void> = Promise.resolve();
  private results: Map<string, string> = new Map<string, string>();
  private inputPath: string = '';
  private root: string = '';
  private serial: number = 0;

  initialize(context: common.Context): Promise<void> {
    if (this.initialization === null) this.initialization = this.load(context);
    return this.initialization;
  }

  private async load(context: common.Context): Promise<void> {
    this.root = `${context.filesDir}/comic_image_plugins`;
    this.store = await preferences.getPreferences(context, { name: 'comic_image_plugins' });
    for (const plugin of this.state.plugins) {
      const path = `${this.root}/${plugin.id}`;
      plugin.installed = await fileIo.access(`${path}/processor.wasm`) && await fileIo.access(`${path}/parameters.json`);
      plugin.version = Number(this.store.getSync(`${plugin.id}.version`, 0));
      plugin.bytes = plugin.installed ? (await fileIo.stat(`${path}/processor.wasm`)).size : 0;
      plugin.active = plugin.installed && this.store.getSync(`${plugin.id}.active`, false) === true;
    }
    this.state.ready = true;
    this.changed();
  }

  private plugin(id: string): ComicImagePlugin {
    const plugin = this.state.plugins.find((item: ComicImagePlugin): boolean => item.id === id);
    if (!plugin) throw new Error('comic_plugin_package');
    return plugin;
  }

  private changed(): void {
    this.results.clear();
    this.state.hasActive = this.state.plugins.some((plugin: ComicImagePlugin): boolean => plugin.installed && plugin.active);
    this.state.revision++;
  }

  async setActive(id: string, active: boolean): Promise<void> {
    const plugin = this.plugin(id);
    if (this.store === null || !plugin.installed) return;
    await this.store.put(`${id}.active`, active);
    await this.store.flush();
    plugin.active = active;
    this.changed();
  }

  private async write(path: string, bytes: Uint8Array): Promise<void> {
    const buffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buffer).set(bytes);
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < buffer.byteLength) offset += await fileIo.write(file.fd, buffer.slice(offset));
    } finally { await fileIo.close(file); }
  }

  async pick(context: common.UIAbilityContext, id: string): Promise<boolean> {
    await this.initialize(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['漫画图片插件|.jtplugin'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return false;
    this.state.busyId = id;
    try {
      const source = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
      let bytes: ArrayBuffer;
      try {
        bytes = new ArrayBuffer((await fileIo.stat(source.fd)).size);
        let offset = 0;
        while (offset < bytes.byteLength) {
          const part = new ArrayBuffer(bytes.byteLength - offset);
          const read = await fileIo.read(source.fd, part);
          if (read === 0) throw new Error('comic_plugin_package');
          new Uint8Array(bytes).set(new Uint8Array(part, 0, read), offset);
          offset += read;
        }
      } finally { await fileIo.close(source); }
      const pack: ComicImagePluginPackage = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true })
        .decodeToString(new Uint8Array(bytes)));
      if (pack.format !== 1 || pack.id !== id || pack.abi !== 'koma-image-v1' || pack.version < 1 ||
        typeof pack.parameters !== 'string' || typeof pack.wasm !== 'string') throw new Error('comic_plugin_package');
      const wasm = new util.Base64Helper().decodeSync(pack.wasm);
      await this.queue;
      const directory = `${this.root}/${id}`;
      if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
      await this.write(`${directory}/processor.wasm`, wasm);
      await this.write(`${directory}/parameters.json`, new util.TextEncoder().encodeInto(pack.parameters));
      const plugin = this.plugin(id);
      if (this.store !== null) {
        await this.store.put(`${id}.version`, pack.version);
        await this.store.flush();
      }
      plugin.installed = true; plugin.version = pack.version; plugin.bytes = wasm.byteLength;
      this.changed();
      return true;
    } finally { this.state.busyId = ''; }
  }

  async remove(id: string): Promise<void> {
    this.state.busyId = id;
    try {
      await this.setActive(id, false);
      await this.queue;
      await fileIo.rmdir(`${this.root}/${id}`);
      const plugin = this.plugin(id);
      plugin.installed = false; plugin.version = 0; plugin.bytes = 0;
      if (this.store !== null) {
        await this.store.delete(`${id}.version`);
        await this.store.flush();
      }
      this.changed();
    } finally { this.state.busyId = ''; }
  }

  attach(controller: webview.WebviewController): void { this.controller = controller; }
  detach(controller: webview.WebviewController): void {
    if (this.controller === controller) { this.controller = null; this.inputPath = ''; }
  }

  resource(path: string): string {
    if (path === 'input') return this.inputPath;
    for (const plugin of this.state.plugins) {
      if (plugin.installed && plugin.active &&
        (path === `${plugin.id}/processor.wasm` || path === `${plugin.id}/parameters.json`)) return `${this.root}/${path}`;
    }
    return '';
  }

  transform(context: common.Context, uri: string, active: () => boolean): Promise<string> {
    const revision = this.state.revision;
    const task = this.queue.then(async (): Promise<string> => {
      const current = (): boolean => active() && revision === this.state.revision;
      if (!current() || !this.state.hasActive || this.state.busyId) return uri;
      const cached = this.results.get(uri);
      if (cached && await fileIo.access(new fileUri.FileUri(cached).path)) return cached;
      const readyUntil = Date.now() + 10000;
      while (current() && this.controller === null && Date.now() < readyUntil) {
        await new Promise<void>((resolve): void => { setTimeout(resolve, 50); });
      }
      const controller = this.controller;
      if (!current() || controller === null) return uri;
      const ticket = ++this.serial;
      const ids = this.state.plugins.filter((plugin: ComicImagePlugin): boolean => plugin.installed && plugin.active)
        .map((plugin: ComicImagePlugin): string => plugin.id);
      this.inputPath = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
      ReaderCacheService.hold(uri);
      ReaderCacheService.beginComicWrite();
      try {
        await controller.runJavaScript(`window.comicPlugins.start(${ticket},${JSON.stringify(ids)})`);
        let result: string = '';
        while (current() && this.controller === controller) {
          result = await controller.runJavaScript(`window.comicPlugins.status(${ticket})`);
          if (result.startsWith('"')) result = JSON.parse(result);
          if (result !== 'pending') break;
          await new Promise<void>((resolve): void => { setTimeout(resolve, 50); });
        }
        if (!current() || result === 'original') return uri;
        if (result !== 'ready') throw new Error('comic_plugin_process');
        const directory = `${context.cacheDir}/comic_images`;
        if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
        const path = `${directory}/${util.generateRandomUUID().replace(/-/g, '')}.png`;
        const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (current()) {
            const raw = await controller.runJavaScript(`window.comicPlugins.take(${ticket},${offset},65536)`);
            const chunk: string = raw.startsWith('"') ? JSON.parse(raw) : raw;
            if (!chunk) break;
            const decoded = new util.Base64Helper().decodeSync(chunk);
            let written = 0;
            while (written < decoded.byteLength) written += await fileIo.write(file.fd, decoded.buffer.slice(written));
            offset += chunk.length;
          }
        } finally { await fileIo.close(file); }
        if (!current()) { await fileIo.unlink(path); return uri; }
        const output = fileUri.getUriFromPath(path);
        await ReaderCacheService.record([output]);
        this.results.set(uri, output);
        return output;
      } finally {
        this.inputPath = '';
        try {
          if (this.controller === controller) await controller.runJavaScript(`window.comicPlugins.cancel(${ticket})`);
        } finally {
          ReaderCacheService.unhold(uri);
          ReaderCacheService.endComicWrite();
        }
      }
    });
    this.queue = task.then((): void => {}, (): void => {});
    return task;
  }
}
