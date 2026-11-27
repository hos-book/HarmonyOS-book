import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ThemeDocument, ThemeDraft, ThemeToken } from '../model/ThemeDocument';
import { AppAppearance } from '../model/AppAppearance';
import { AppThemeBundle } from '../model/AppThemeBundle';
import { AppThemeVisual, ThemeIconRole, ThemeBackgroundKind } from '../model/AppThemeVisual';
import { ThemeBundles } from '../theme/ThemeBundles';
import { MembershipService } from './MembershipService';
import { AppBackgroundService } from './AppBackgroundService';
import { AppBackgroundScene } from '../model/AppBackground';
import { BottomTabIconService } from './BottomTabIconService';

export class ThemeFieldChoice {
  value: string = '';
  label: string = '';
}

export class ThemeEditorField {
  key: string = '';
  label: string = '';
  section: string = '';
  type: string = '';
  light: string = '';
  dark: string = '';
  min: number = 0;
  max: number = 100;
  choices: ThemeFieldChoice[] = [];
}

class ThemeEditorSchema {
  fields: ThemeEditorField[] = [];
}

class ThemePackageManifest {
  format: string = 'jianting.theme';
  schemaVersion: number = 1;
  theme: string = 'theme.json';
}

export class ThemePackageService {
  private static loading: Promise<void> | undefined = undefined;
  private static root: string = '';

  static async initialize(context: common.Context): Promise<void> {
    if (ThemePackageService.loading) return ThemePackageService.loading;
    ThemePackageService.loading = ThemePackageService.load(context);
    return ThemePackageService.loading;
  }

  static async ready(): Promise<void> { await ThemePackageService.loading; }

  private static async load(context: common.Context): Promise<void> {
    ThemePackageService.root = context.filesDir + '/themes';
    if (!await fileIo.access(ThemePackageService.root)) await fileIo.mkdir(ThemePackageService.root, true);
    for (const name of await fileIo.listFile(ThemePackageService.root)) {
      const directory: string = ThemePackageService.root + '/' + name;
      const document: ThemeDocument = JSON.parse(await fileIo.readText(directory + '/theme.json'));
      ThemeBundles.register(document, directory);
    }
  }

  static async fields(context: common.Context): Promise<ThemeEditorField[]> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent('theme_editor_schema.json');
    const schema: ThemeEditorSchema = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes));
    return schema.fields;
  }

  static async draft(context: common.Context, themeId: string): Promise<ThemeDraft> {
    await ThemePackageService.initialize(context);
    const saved: ThemeDraft | undefined = ThemeBundles.document(themeId);
    const document: ThemeDocument = saved ? ThemeDocument.copy(saved.document) : new ThemeDocument();
    const directory: string = context.cacheDir + '/theme-editor-' + util.generateRandomUUID(true);
    await fileIo.mkdir(directory + '/assets', true);
    if (saved) {
      await ThemePackageService.copyAssets(saved.directory, directory, document);
    } else {
      const bundle: AppThemeBundle = ThemeBundles.fresh(themeId);
      const fields: ThemeEditorField[] = await ThemePackageService.fields(context);
      document.id = 'custom-' + util.generateRandomUUID(true);
      document.name = typeof bundle.name === 'string' ? bundle.name : context.resourceManager.getStringSync(bundle.name.id);
      document.description = '';
      document.materialStyle = AppAppearance.current.material;
      document.verticalBottomTabs = AppAppearance.current.verticalBottomTabs;
      for (const dark of [false, true]) {
        const configuration = context.resourceManager.getConfigurationSync();
        configuration.colorMode = dark ? resourceManager.ColorMode.DARK : resourceManager.ColorMode.LIGHT;
        const manager = context.resourceManager.getOverrideResourceManager(configuration);
        const tokens: ThemeToken[] = await ThemePackageService.capture(bundle.visual, manager, directory);
        if (themeId === AppAppearance.current.themeBundleId && AppAppearance.current.useLegacyThemeOverrides) {
          await ThemePackageService.capturePersonal(tokens, directory, manager);
        }
        for (const field of fields) {
          const fallback: string = dark ? field.dark : field.light;
          if (fallback && !tokens.some((token: ThemeToken): boolean => token.key === field.key)) {
            tokens.push(new ThemeToken(field.key, fallback));
          }
        }
        ThemePackageService.replace(tokens, 'tab.normalColor', ThemeDocument.value(tokens, 'color.textSecondary'));
        ThemePackageService.replace(tokens, 'tab.selectedColor', ThemeDocument.value(tokens, 'color.brand'));
        if (dark) document.dark = tokens; else document.light = tokens;
      }
    }
    return new ThemeDraft(document, directory);
  }

  private static color(manager: resourceManager.ResourceManager, color: ResourceColor): string {
    if (typeof color === 'string') return color;
    const number: number = typeof color === 'number' ? color : manager.getColorSync(color.id);
    return '#' + (number >>> 0).toString(16).padStart(8, '0').toUpperCase();
  }

  private static async capture(visual: AppThemeVisual, manager: resourceManager.ResourceManager,
    directory: string): Promise<ThemeToken[]> {
    const tokens: ThemeToken[] = [];
    if (visual.colors.background !== undefined) tokens.push(new ThemeToken('color.background', ThemePackageService.color(manager, visual.colors.background)));
    if (visual.colors.surface !== undefined) tokens.push(new ThemeToken('color.surface', ThemePackageService.color(manager, visual.colors.surface)));
    if (visual.colors.settingsBackground !== undefined) tokens.push(new ThemeToken('color.settingsBackground', ThemePackageService.color(manager, visual.colors.settingsBackground)));
    if (visual.colors.profileMenuSurface !== undefined) tokens.push(new ThemeToken('color.profileMenuSurface', ThemePackageService.color(manager, visual.colors.profileMenuSurface)));
    if (visual.colors.textPrimary !== undefined) tokens.push(new ThemeToken('color.textPrimary', ThemePackageService.color(manager, visual.colors.textPrimary)));
    if (visual.colors.textSecondary !== undefined) tokens.push(new ThemeToken('color.textSecondary', ThemePackageService.color(manager, visual.colors.textSecondary)));
    if (visual.colors.textTertiary !== undefined) tokens.push(new ThemeToken('color.textTertiary', ThemePackageService.color(manager, visual.colors.textTertiary)));
    if (visual.colors.iconPrimary !== undefined) tokens.push(new ThemeToken('color.iconPrimary', ThemePackageService.color(manager, visual.colors.iconPrimary)));
    if (visual.colors.iconSecondary !== undefined) tokens.push(new ThemeToken('color.iconSecondary', ThemePackageService.color(manager, visual.colors.iconSecondary)));
    if (visual.colors.divider !== undefined) tokens.push(new ThemeToken('color.divider', ThemePackageService.color(manager, visual.colors.divider)));
    if (visual.colors.appDivider !== undefined) tokens.push(new ThemeToken('color.appDivider', ThemePackageService.color(manager, visual.colors.appDivider)));
    if (visual.colors.brand !== undefined) tokens.push(new ThemeToken('color.brand', ThemePackageService.color(manager, visual.colors.brand)));
    if (visual.colors.brandHover !== undefined) tokens.push(new ThemeToken('color.brandHover', ThemePackageService.color(manager, visual.colors.brandHover)));
    if (visual.colors.brandPressed !== undefined) tokens.push(new ThemeToken('color.brandPressed', ThemePackageService.color(manager, visual.colors.brandPressed)));
    if (visual.colors.brandDisabled !== undefined) tokens.push(new ThemeToken('color.brandDisabled', ThemePackageService.color(manager, visual.colors.brandDisabled)));
    if (visual.colors.brandSoft !== undefined) tokens.push(new ThemeToken('color.brandSoft', ThemePackageService.color(manager, visual.colors.brandSoft)));
    if (visual.colors.brandDark !== undefined) tokens.push(new ThemeToken('color.brandDark', ThemePackageService.color(manager, visual.colors.brandDark)));
    if (visual.colors.onBrand !== undefined) tokens.push(new ThemeToken('color.onBrand', ThemePackageService.color(manager, visual.colors.onBrand)));
    if (visual.colors.controlFallback !== undefined) tokens.push(new ThemeToken('color.controlFallback', ThemePackageService.color(manager, visual.colors.controlFallback)));
    if (visual.colors.controlTint !== undefined) tokens.push(new ThemeToken('color.controlTint', ThemePackageService.color(manager, visual.colors.controlTint)));
    if (visual.colors.stroke !== undefined) tokens.push(new ThemeToken('color.stroke', ThemePackageService.color(manager, visual.colors.stroke)));
    if (visual.colors.shadow !== undefined) tokens.push(new ThemeToken('color.shadow', ThemePackageService.color(manager, visual.colors.shadow)));
    if (visual.colors.homeTop !== undefined) tokens.push(new ThemeToken('color.homeTop', ThemePackageService.color(manager, visual.colors.homeTop)));
    if (visual.colors.homeMid !== undefined) tokens.push(new ThemeToken('color.homeMid', ThemePackageService.color(manager, visual.colors.homeMid)));
    if (visual.colors.homeBottom !== undefined) tokens.push(new ThemeToken('color.homeBottom', ThemePackageService.color(manager, visual.colors.homeBottom)));
    if (visual.colors.statusScrim !== undefined) tokens.push(new ThemeToken('color.statusScrim', ThemePackageService.color(manager, visual.colors.statusScrim)));
    if (visual.colors.floatingMask !== undefined) tokens.push(new ThemeToken('color.floatingMask', ThemePackageService.color(manager, visual.colors.floatingMask)));
    if (visual.colors.homeAccent !== undefined) tokens.push(new ThemeToken('color.homeAccent', ThemePackageService.color(manager, visual.colors.homeAccent)));
    if (visual.colors.homeAccentSoft !== undefined) tokens.push(new ThemeToken('color.homeAccentSoft', ThemePackageService.color(manager, visual.colors.homeAccentSoft)));
    if (visual.colors.homeControl !== undefined) tokens.push(new ThemeToken('color.homeControl', ThemePackageService.color(manager, visual.colors.homeControl)));
    if (visual.colors.homeSurface !== undefined) tokens.push(new ThemeToken('color.homeSurface', ThemePackageService.color(manager, visual.colors.homeSurface)));
    if (visual.colors.homeShadow !== undefined) tokens.push(new ThemeToken('color.homeShadow', ThemePackageService.color(manager, visual.colors.homeShadow)));
    if (visual.colors.progressTrack !== undefined) tokens.push(new ThemeToken('color.progressTrack', ThemePackageService.color(manager, visual.colors.progressTrack)));
    if (visual.colors.detailTop !== undefined) tokens.push(new ThemeToken('color.detailTop', ThemePackageService.color(manager, visual.colors.detailTop)));
    if (visual.colors.detailMid !== undefined) tokens.push(new ThemeToken('color.detailMid', ThemePackageService.color(manager, visual.colors.detailMid)));
    if (visual.colors.detailBottom !== undefined) tokens.push(new ThemeToken('color.detailBottom', ThemePackageService.color(manager, visual.colors.detailBottom)));
    tokens.push(new ThemeToken('background.coverBackdrop', visual.background.showCoverBackdrop.toString()));
    tokens.push(new ThemeToken('cover.decoration', visual.cover.decoration.toString()));
    tokens.push(new ThemeToken('cover.illustratedPlaceholder', visual.cover.illustratedPlaceholder.toString()));
    tokens.push(new ThemeToken('cover.title', ThemePackageService.color(manager, visual.cover.title)));
    tokens.push(new ThemeToken('cover.localTitle', ThemePackageService.color(manager, visual.cover.localTitle)));
    tokens.push(new ThemeToken('cover.author', ThemePackageService.color(manager, visual.cover.author)));
    tokens.push(new ThemeToken('cover.authorBackground', ThemePackageService.color(manager, visual.cover.authorBackground)));
    tokens.push(new ThemeToken('cover.label', ThemePackageService.color(manager, visual.cover.label)));
    tokens.push(new ThemeToken('cover.edge', ThemePackageService.color(manager, visual.cover.edge)));
    await ThemePackageService.captureAsset(tokens, 'background.common.image', visual.background.image, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'background.shelf.image', visual.background.shelfImage, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'background.record.image', visual.background.recordImage, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'background.profileCard', visual.background.profileCardImage, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'cover.placeholder', visual.cover.placeholder, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'cover.localPlaceholder', visual.cover.localPlaceholder, manager, directory);
    await ThemePackageService.captureAsset(tokens, 'cover.playerPlaceholder', visual.cover.playerPlaceholder, manager, directory);
    for (const scene of ['common', 'shelf', 'record']) {
      if (ThemeDocument.value(tokens, 'background.' + scene + '.image')) tokens.push(new ThemeToken('background.' + scene + '.mode', 'image'));
    }
    if (visual.background.kind === ThemeBackgroundKind.Solid) {
      ThemePackageService.replace(tokens, 'background.common.mode', 'solid');
      ThemePackageService.replace(tokens, 'background.common.color', ThemePackageService.color(manager, visual.colors.background));
    }
    await ThemePackageService.captureAsset(tokens, 'icon.Search', visual.icons.get(ThemeIconRole.Search), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'icon.Filter', visual.icons.get(ThemeIconRole.Filter), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'icon.Grid', visual.icons.get(ThemeIconRole.Grid), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'icon.List', visual.icons.get(ThemeIconRole.List), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'icon.ChevronRight', visual.icons.get(ThemeIconRole.ChevronRight), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'tab.home.normal', visual.icons.get(ThemeIconRole.Home), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'tab.shelf.normal', visual.icons.get(ThemeIconRole.Shelf), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'tab.record.normal', visual.icons.get(ThemeIconRole.Record), manager, directory);
    await ThemePackageService.captureAsset(tokens, 'tab.profile.normal', visual.icons.get(ThemeIconRole.Profile), manager, directory);
    return tokens;
  }

  private static async captureAsset(tokens: ThemeToken[], key: string, source: ResourceStr | undefined,
    manager: resourceManager.ResourceManager, directory: string): Promise<void> {
    if (source === undefined) return;
    const bytes: Uint8Array = typeof source === 'string' ? await ThemePackageService.readBytes(source) :
      await manager.getMediaContent(source.id);
    const name: string = 'assets/' + util.generateRandomUUID(true) + ThemePackageService.extension(bytes);
    await ThemePackageService.write(directory + '/' + name, ThemePackageService.buffer(bytes));
    tokens.push(new ThemeToken(key, name));
  }

  private static extension(bytes: Uint8Array): string {
    if (bytes[0] === 137 && bytes[1] === 80) return '.png';
    if (bytes[0] === 255 && bytes[1] === 216) return '.jpg';
    if (bytes[0] === 82 && bytes[1] === 73) return '.webp';
    return '.svg';
  }

  private static async capturePersonal(tokens: ThemeToken[], directory: string,
    manager: resourceManager.ResourceManager): Promise<void> {
    const scenes: AppBackgroundScene[] = [AppBackgroundScene.Common, AppBackgroundScene.Home,
      AppBackgroundScene.Shelf, AppBackgroundScene.Record, AppBackgroundScene.Profile];
    const names: string[] = ['common', 'home', 'shelf', 'record', 'profile'];
    for (let index: number = 0; index < scenes.length; index++) {
      const config = AppBackgroundService.instance.resolve(scenes[index]);
      const source = AppBackgroundService.instance.resolveImage(config);
      const prefix: string = 'background.' + names[index] + '.';
      if (config.preset === 'image' && source) {
        const bytes = await ThemePackageService.readBytes(source);
        const path: string = 'assets/' + util.generateRandomUUID(true) + ThemePackageService.extension(bytes);
        await ThemePackageService.write(directory + '/' + path, ThemePackageService.buffer(bytes));
        ThemePackageService.replace(tokens, prefix + 'mode', 'image');
        ThemePackageService.replace(tokens, prefix + 'image', path);
        ThemePackageService.replace(tokens, prefix + 'veil', config.veil.toString());
        ThemePackageService.replace(tokens, prefix + 'blur', config.blur.toString());
        ThemePackageService.replace(tokens, prefix + 'positionX', config.positionX.toString());
        ThemePackageService.replace(tokens, prefix + 'positionY', config.positionY.toString());
        ThemePackageService.replace(tokens, prefix + 'scale', config.scale.toString());
      } else if (config.preset === 'paper' || config.preset === 'mist') {
        const path: string = await ThemePackageService.captureGradient(config.preset, config.veil, manager, directory);
        ThemePackageService.replace(tokens, prefix + 'mode', 'image');
        ThemePackageService.replace(tokens, prefix + 'image', path);
        ThemePackageService.replace(tokens, prefix + 'veil', '0');
      }
    }
    const roles: ThemeIconRole[] = [ThemeIconRole.Home, ThemeIconRole.Shelf, ThemeIconRole.Record, ThemeIconRole.Profile];
    const tabs: string[] = ['home', 'shelf', 'record', 'profile'];
    for (let index: number = 0; index < roles.length; index++) {
      const source: string | undefined = BottomTabIconService.instance.resolve(roles[index]);
      if (source) {
        const path: string = 'assets/' + util.generateRandomUUID(true) + '.png';
        await ThemePackageService.write(directory + '/' + path, ThemePackageService.buffer(await ThemePackageService.readBytes(source)));
        ThemePackageService.replace(tokens, 'tab.' + tabs[index] + '.normal', path);
      }
    }
    if (AppAppearance.current.accent) ThemePackageService.replace(tokens, 'color.brand', AppAppearance.current.accent);
  }

  private static async captureGradient(preset: string, veil: number, manager: resourceManager.ResourceManager,
    directory: string): Promise<string> {
    const paper: boolean = preset === 'paper';
    const top: string = ThemePackageService.color(manager, paper ? $r('app.color.app_background_paper_top') :
      $r('app.color.app_background_mist_top'));
    const middle: string = ThemePackageService.color(manager, paper ? $r('app.color.app_background_paper_mid') :
      $r('app.color.app_background_mist_mid'));
    const bottom: string = ThemePackageService.color(manager, paper ? $r('app.color.app_background_paper_bottom') :
      $r('app.color.app_background_mist_bottom'));
    const scrim: string = ThemePackageService.color(manager, $r('app.color.app_background_night_scrim'));
    const overlay: string = ThemePackageService.color(manager, $r('app.color.app_background_veil'));
    const angle: number = (paper ? 150 : 160) * Math.PI / 180;
    const x: number = Math.sin(angle) / 2;
    const y: number = -Math.cos(angle) / 2;
    const svg: string = '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="1000" viewBox="0 0 600 1000">' +
      '<defs><linearGradient id="background" x1="' + (0.5 - x) + '" y1="' + (0.5 - y) +
      '" x2="' + (0.5 + x) + '" y2="' + (0.5 + y) + '">' +
      '<stop stop-color="#' + top.slice(-6) + '"/><stop offset="' + (paper ? '0.6' : '0.58') +
      '" stop-color="#' + middle.slice(-6) + '"/><stop offset="1" stop-color="#' + bottom.slice(-6) +
      '"/></linearGradient></defs><rect width="600" height="1000" fill="url(#background)"/>' +
      '<rect width="600" height="1000" fill="#' + scrim.slice(-6) + '" opacity="' +
      (parseInt(scrim.substring(1, 3), 16) / 255) + '"/>' +
      '<rect width="600" height="1000" fill="#' + overlay.slice(-6) + '" opacity="' + (veil / 100) + '"/></svg>';
    const path: string = 'assets/' + util.generateRandomUUID(true) + '.svg';
    await ThemePackageService.writeText(directory + '/' + path, svg);
    return path;
  }

  private static replace(tokens: ThemeToken[], key: string, value: string): void {
    const token: ThemeToken | undefined = tokens.find((item: ThemeToken): boolean => item.key === key);
    if (token) token.value = value; else tokens.push(new ThemeToken(key, value));
  }

  static async pickImage(draft: ThemeDraft): Promise<string> {
    if (!await fileIo.access(draft.directory + '/assets')) await fileIo.mkdir(draft.directory + '/assets', true);
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (result.photoUris.length === 0) return '';
    const bytes: Uint8Array = await ThemePackageService.readBytes(result.photoUris[0]);
    const source = image.createImageSource(ThemePackageService.buffer(bytes));
    const packer = image.createImagePacker();
    try {
      const buffer = await packer.packToData(source, { format: 'image/png', quality: 100 });
      const path: string = 'assets/' + util.generateRandomUUID(true) + '.png';
      await ThemePackageService.write(draft.directory + '/' + path, buffer);
      return path;
    } finally {
      await packer.release();
      await source.release();
    }
  }

  static async importPackage(context: common.Context): Promise<ThemeDraft | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = [context.resourceManager.getStringSync($r('app.string.theme_editor_file_filter').id)];
    const uris: string[] = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return undefined;
    const directory: string = context.cacheDir + '/theme-editor-' + util.generateRandomUUID(true);
    await fileIo.mkdir(directory, true);
    const archive: string = directory + '.zip';
    await ThemePackageService.write(archive, ThemePackageService.buffer(await ThemePackageService.readBytes(uris[0])));
    try {
      await zlib.decompressFile(archive, directory);
      const manifest: ThemePackageManifest = JSON.parse(await fileIo.readText(directory + '/manifest.json'));
      if (manifest.format !== 'jianting.theme' || manifest.schemaVersion !== 1) throw new Error('THEME_FORMAT');
      const document: ThemeDocument = JSON.parse(await fileIo.readText(directory + '/theme.json'));
      document.id = 'custom-' + util.generateRandomUUID(true);
      return new ThemeDraft(document, directory);
    } finally { await fileIo.unlink(archive); }
  }

  static async save(draft: ThemeDraft): Promise<void> {
    if (!await MembershipService.instance.hasCurrentEntitlement()) throw new Error('MEMBERSHIP_REQUIRED');
    const directory: string = ThemePackageService.root + '/' + draft.document.id;
    if (!await fileIo.access(directory + '/assets')) await fileIo.mkdir(directory + '/assets', true);
    await ThemePackageService.copyAssets(draft.directory, directory, draft.document);
    await ThemePackageService.writeText(directory + '/theme.json', JSON.stringify(draft.document));
    await ThemePackageService.writeText(directory + '/manifest.json', JSON.stringify(new ThemePackageManifest()));
    ThemeBundles.register(ThemeDocument.copy(draft.document), directory);
  }

  static async exportPackage(context: common.Context, draft: ThemeDraft): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [draft.document.name + '.jttheme'];
    const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) return false;
    const directory: string = draft.directory + '-export';
    await fileIo.mkdir(directory + '/assets', true);
    const archive: string = draft.directory + '.zip';
    try {
      await ThemePackageService.copyAssets(draft.directory, directory, draft.document);
      await ThemePackageService.writeText(directory + '/theme.json', JSON.stringify(draft.document));
      await ThemePackageService.writeText(directory + '/manifest.json', JSON.stringify(new ThemePackageManifest()));
      await zlib.compressFile(directory, archive, {});
      const target = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { await fileIo.copyFile(archive, target.fd); } finally { await fileIo.close(target); }
      return true;
    } finally {
      if (await fileIo.access(archive)) await fileIo.unlink(archive);
      await fileIo.rmdir(directory);
    }
  }

  static async discard(draft: ThemeDraft): Promise<void> {
    if (draft.directory) await fileIo.rmdir(draft.directory);
  }

  private static async copyAssets(source: string, target: string, document: ThemeDocument): Promise<void> {
    const paths: Set<string> = new Set<string>();
    for (const token of document.light.concat(document.dark)) {
      if (token.value.startsWith('assets/')) paths.add(token.value);
    }
    for (const path of paths) await fileIo.copyFile(source + '/' + path, target + '/' + path);
  }

  private static async readBytes(uri: string): Promise<Uint8Array> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const bytes: Uint8Array = new Uint8Array((await fileIo.stat(file.fd)).size);
      let offset: number = 0;
      while (offset < bytes.byteLength) {
        const part: ArrayBuffer = new ArrayBuffer(bytes.byteLength - offset);
        const count: number = await fileIo.read(file.fd, part);
        if (count === 0) break;
        bytes.set(new Uint8Array(part, 0, count), offset);
        offset += count;
      }
      return bytes;
    } finally { await fileIo.close(file); }
  }

  private static async writeText(path: string, text: string): Promise<void> {
    await ThemePackageService.write(path, ThemePackageService.buffer(new util.TextEncoder().encodeInto(text)));
  }

  private static async write(path: string, bytes: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let offset: number = 0;
      while (offset < bytes.byteLength) offset += await fileIo.write(file.fd, bytes.slice(offset));
    } finally { await fileIo.close(file); }
  }

  private static buffer(bytes: Uint8Array): ArrayBuffer {
    const result: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(result).set(bytes);
    return result;
  }
}
