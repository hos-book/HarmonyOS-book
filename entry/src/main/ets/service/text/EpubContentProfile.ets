import { LocalBookHtmlText } from './LocalBookHtmlText';

export type EpubImportMode = 'auto' | 'text' | 'comic';

/** 全书正文统计；封面或少量插图不足以把小说识别成漫画。 */
export class EpubContentProfile {
  private sections: number = 0;
  private imageSections: number = 0;
  private images: number = 0;
  private characters: number = 0;
  private proseSections: number = 0;

  static body(html: string): string {
    return html.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(head|script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '');
  }

  observe(html: string): void {
    if (this.proseSections > 0) return;
    const body = EpubContentProfile.body(html);
    const images = (body.match(/<(?:img|image)\b[^>]*>/gi) ?? []).length;
    const characters = LocalBookHtmlText.clean(body).replace(/\s/g, '').length;
    if (images === 0 && characters === 0) return;
    this.sections++;
    this.images += images;
    this.characters += characters;
    if (images > 0) this.imageSections++;
    if (characters > Math.max(800, images * 160)) this.proseSections++;
  }

  isComic(): boolean {
    return this.images >= 3 && this.imageSections >= Math.ceil(this.sections * 0.7) &&
      this.characters <= this.images * 120 && this.proseSections === 0;
  }
}
