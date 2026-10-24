import { webview } from '@kit.ArkWeb';
import { ComicTranslationText } from '../model/ComicTranslation';

class ComicOfflineResult {
  id: number = 0;
  status: string = '';
  translations: ComicTranslationText[] = [];
}

/** 仅使用打包的翻译模型。无网络回退，也不持有用户的 API 配置。 */
export class ComicOfflineTranslationService {
  static readonly MODEL: string = 'opus-four-directions-q8-v2';
  static readonly ORIGIN: string = 'https://comic-offline.invalid/';
  private static controller: webview.WebviewController | null = null;
  private static serial: number = 0;
  private static busy: boolean = false;

  static supported(): boolean { return canIUse('SystemCapability.Web.Webview.Core'); }

  static attach(controller: webview.WebviewController): void {
    // 新挂载的阅读窗口不能抢走正在执行的翻译任务。
    if (ComicOfflineTranslationService.busy && ComicOfflineTranslationService.controller !== null &&
      ComicOfflineTranslationService.controller !== controller) return;
    ComicOfflineTranslationService.controller = controller;
  }
  static detach(controller: webview.WebviewController): void {
    if (ComicOfflineTranslationService.controller === controller) ComicOfflineTranslationService.controller = null;
  }

  static validateDirection(direction: string): void {
    if (!['ja-zh', 'ko-zh', 'en-zh', 'zh-en'].includes(direction)) throw new Error('comic_offline_language');
  }

  static async translate(items: ComicTranslationText[], direction: string, active: () => boolean): Promise<ComicTranslationText[]> {
    ComicOfflineTranslationService.validateDirection(direction);
    if (!active()) throw new Error('comic_ai_cancelled');
    if (ComicOfflineTranslationService.busy) throw new Error('comic_offline_busy');
    if (items.length > 128 || items.some((item: ComicTranslationText): boolean => item.text.length > 2000) ||
      items.reduce((sum: number, item: ComicTranslationText): number => sum + item.text.length, 0) > 16000) {
      throw new Error('comic_ai_translate_too_large');
    }
    ComicOfflineTranslationService.busy = true;
    const id = ++ComicOfflineTranslationService.serial;
    let controller: webview.WebviewController | null = null;
    let completed = false;
    try {
      const readyDeadline = Date.now() + 10000;
      while (Date.now() < readyDeadline && active()) {
        controller = ComicOfflineTranslationService.controller;
        if (controller !== null) {
          const ready = await controller.runJavaScript('typeof window.comicOffline === "object"');
          if (ready === 'true') break;
        }
        await new Promise<void>((resolve): void => { setTimeout(resolve, 100); });
      }
      if (!active()) throw new Error('comic_ai_cancelled');
      if (controller === null) throw new Error('comic_offline_unavailable');
      const accepted = await controller.runJavaScript(`window.comicOffline.start(${id},${JSON.stringify(items)},${JSON.stringify(direction)})`);
      if (accepted !== 'true') throw new Error('comic_offline_unavailable');
      const deadline = Date.now() + 180000;
      while (Date.now() < deadline && active() && ComicOfflineTranslationService.controller === controller) {
        const raw = await controller.runJavaScript('window.comicOffline.snapshot()');
        if (raw.length > 256 * 1024) throw new Error('comic_ai_translate_invalid_response');
        // ArkWeb 返回 JS 字符串的 JSON 表示；部分系统直接返回字符串内容。
        const payload: string = raw.startsWith('"') ? JSON.parse(raw) : raw;
        const result: ComicOfflineResult = JSON.parse(payload);
        if (result.id !== id) throw new Error('comic_ai_cancelled');
        if (result.status === 'error') throw new Error('comic_offline_failed');
        if (result.status === 'done') {
          if (!Array.isArray(result.translations) || result.translations.length !== items.length ||
            result.translations.some((item: ComicTranslationText, index: number): boolean =>
              item.id !== items[index].id || typeof item.text !== 'string' || !item.text.trim() || item.text.length > 2000)) {
            throw new Error('comic_ai_translate_invalid_response');
          }
          if (!active()) throw new Error('comic_ai_cancelled');
          completed = true;
          return result.translations;
        }
        await new Promise<void>((resolve): void => { setTimeout(resolve, 100); });
      }
      throw new Error(active() && ComicOfflineTranslationService.controller === controller ?
        'comic_offline_timeout' : 'comic_ai_cancelled');
    } finally {
      if (!completed && controller !== null) {
        try { await controller.runJavaScript(`window.comicOffline?.cancel(${id})`); } catch (_error) { }
      }
      ComicOfflineTranslationService.busy = false;
    }
  }
}
