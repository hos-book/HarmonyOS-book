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
    const next: ThemeDocument = new ThemeDocument();
    next.format = document.format;
    next.schemaVersion = document.schemaVersion;
    next.id = document.id;
    next.name = document.name;
    next.description = document.description;
    next.baseThemeId = document.baseThemeId;
    next.light = document.light.filter((token: ThemeToken): boolean => token.key !== 'icon.ChevronRight')
      .map((token: ThemeToken): ThemeToken => new ThemeToken(token.key, token.value));
    next.dark = document.dark.filter((token: ThemeToken): boolean => token.key !== 'icon.ChevronRight')
      .map((token: ThemeToken): ThemeToken => new ThemeToken(token.key, token.value));
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
  draft: ThemeDraft | undefined;

  constructor(themeId: string = 'default', draft: ThemeDraft | undefined = undefined) {
    this.themeId = themeId;
    this.draft = draft;
  }
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
