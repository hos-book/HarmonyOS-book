export class ComicReaderAppearance {
  cropTop: number = 0;
  cropBottom: number = 0;
  cropLeft: number = 0;
  cropRight: number = 0;
  split: number = 0;
  lightBackground: number = 0;
  darkBackground: number = 0;

  static normalize(value: ComicReaderAppearance): ComicReaderAppearance {
    const result = new ComicReaderAppearance();
    result.cropTop = ComicReaderAppearance.percent(value.cropTop);
    result.cropBottom = ComicReaderAppearance.percent(value.cropBottom);
    result.cropLeft = ComicReaderAppearance.percent(value.cropLeft);
    result.cropRight = ComicReaderAppearance.percent(value.cropRight);
    result.split = value.split === 1 || value.split === 2 ? value.split : 0;
    result.lightBackground = ComicReaderAppearance.background(value.lightBackground);
    result.darkBackground = ComicReaderAppearance.background(value.darkBackground);
    return result;
  }

  static decode(raw: string): ComicReaderAppearance {
    try {
      const value: ComicReaderAppearance = JSON.parse(raw);
      return value ? ComicReaderAppearance.normalize(value) : new ComicReaderAppearance();
    } catch (_error) { return new ComicReaderAppearance(); }
  }

  private static percent(value: number): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(25, value))) : 0;
  }

  private static background(value: number): number {
    return value === 1 || value === 2 || value === 3 ? value : 0;
  }

  background(dark: boolean): string {
    const option = dark ? this.darkBackground : this.lightBackground;
    if (option === 1) return dark ? '#292929' : '#FFFFFF';
    if (option === 2) return dark ? '#30291F' : '#D8BE91';
    if (option === 3) return dark ? '#1F2924' : '#DCE8D8';
    return '#121212';
  }
}
