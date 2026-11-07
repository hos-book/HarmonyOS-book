/** EPUB 背景与正文分开存储，不占用字符位置或朗读内容。 */
export class EpubPageStyle {
  image: string = '';
  color: string = '';
  foreground: string = '';
  size: string = 'auto';
  repeat: string = 'repeat';
  position: string = 'top left';
  headingColor: string = '';
  headingForeground: string = '';

  visible(): boolean { return !!(this.image || this.color || this.headingColor); }

  static color(value: string): string {
    const text = (value || '').trim().toLowerCase();
    if (/^#[0-9a-f]{6}$/.test(text)) return text;
    if (/^#[0-9a-f]{3}$/.test(text)) return '#' + text.substring(1).split('').map((c: string): string => c + c).join('');
    if (text === 'white') return '#ffffff';
    if (text === 'black') return '#000000';
    const rgb = /^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/.exec(text);
    if (rgb && [rgb[1], rgb[2], rgb[3]].every((v: string): boolean => Number(v) <= 255)) {
      return '#' + [rgb[1], rgb[2], rgb[3]].map((v: string): string => Number(v).toString(16).padStart(2, '0')).join('');
    }
    return '';
  }

  static position(value: string): string {
    const tokens = value.trim().toLowerCase().split(/\s+/);
    if (tokens.length > 2 || tokens.some((v: string): boolean => !/^(?:left|right|top|bottom|center|0%|50%|100%)$/.test(v))) {
      return 'top left';
    }
    let x = 'center'; let y = 'center';
    for (let index = 0; index < tokens.length; index++) {
      const value = tokens[index];
      if (value === 'left' || value === 'right') x = value;
      else if (value === 'top' || value === 'bottom') y = value;
      else if (value.endsWith('%')) {
        if (index === 0) x = value === '0%' ? 'left' : value === '100%' ? 'right' : 'center';
        else y = value === '0%' ? 'top' : value === '100%' ? 'bottom' : 'center';
      }
    }
    return `${y} ${x}`;
  }
}

export class EpubStyleRun {
  start: number = 0;
  style: EpubPageStyle = new EpubPageStyle();

  constructor(start: number = 0, style: EpubPageStyle = new EpubPageStyle()) {
    this.start = start;
    this.style = style;
  }
}
