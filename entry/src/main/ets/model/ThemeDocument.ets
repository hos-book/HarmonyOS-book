export class ThemeToken {
  key: string = '';
  value: string = '';

  constructor(key: string = '', value: string = '') {
    this.key = key;
    this.value = value;
  }
}

/** 三端共用的主题配置；图片引用主题包内的 assets 路径。 */
export class ThemeDocument {
  format: string = 'jianting.theme';
  schemaVersion: number = 1;
  id: string = '';
  name: string = '';
  description: string = '';
  baseThemeId: string = 'default';
  materialStyle: number = 6;
  verticalBottomTabs: boolean = false;
  light: ThemeToken[] = [];
  dark: ThemeToken[] = [];

  static value(tokens: ThemeToken[], key: string, fallback: string = ''): string {
    return tokens.find((token: ThemeToken): boolean => token.key === key)?.value ?? fallback;
  }

  static put(tokens: ThemeToken[], key: string, value: string): ThemeToken[] {
    const next: ThemeToken[] = tokens.filter((token: ThemeToken): boolean => token.key !== key);
    if (value.length > 0) next.push(new ThemeToken(key, value));
    return next;
  }

  static copy(document: ThemeDocument): ThemeDocument {
    const next: ThemeDocument = JSON.parse(JSON.stringify(document));
    return next;
  }
}

export class ThemeDraft {
  document: ThemeDocument;
  directory: string;

  constructor(document: ThemeDocument = new ThemeDocument(), directory: string = '') {
    this.document = document;
    this.directory = directory;
  }
}

export class ThemeEditorRoute {
  themeId: string;
  constructor(themeId: string = 'default') { this.themeId = themeId; }
}

export class ThemePageBackdrop {
  mode: string = 'theme';
  image: string = '';
  color: string = '#F7F4EF';
  veil: number = 0;
  blur: number = 0;
  positionX: number = 50;
  positionY: number = 50;
  scale: number = 100;
}
