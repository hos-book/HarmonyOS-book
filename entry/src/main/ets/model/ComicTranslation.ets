export class ComicTranslationText {
  id: number = 0;
  text: string = '';
  constructor(id: number = 0, text: string = '') { this.id = id; this.text = text; }
}

export class ComicTranslationResult {
  translations: ComicTranslationText[] = [];
}

export class ComicTextBox {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}

export class ComicTranslationRegion extends ComicTextBox {
  source: string = '';
  masks: ComicTextBox[] = [];
}
