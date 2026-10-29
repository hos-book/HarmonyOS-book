/**
 * ReaderTheme - 阅读页主题与背景模型
 *
 * 预设与自定义主题互斥生效；每个自定义主题独立保存名称、配色和图片。
 * Paper/Cloth 图案值仅供旧偏好迁移。
 */

/** 背景图案类型 */
export enum ReaderPattern {
  None = 'none',
  Paper = 'paper',
  Cloth = 'cloth',
  Image = 'image'
}

/** 自定义背景图显示方式；裁剪为兼容旧版本的默认值。 */
export enum ReaderImageMode {
  Contain = 'contain',
  Tile = 'tile',
  Stretch = 'stretch',
  Cover = 'cover'
}

/** 预设、自定义配色与图片主题 id。 */
export enum ReaderThemeId {
  Parchment = 'parchment',
  EyeCare = 'eyecare',
  Paper = 'paper',
  Night = 'night',
  Black = 'black',
  Image = 'image',
  Custom = 'custom'
}

/** 一套完整的阅读配色，供页面直接取用 */
export class ReaderPalette {
  /** 页面底色 */
  background: string = '#F5F2EA';
  /** 正文色 */
  primary: string = '#2D2925';
  /** 页眉页脚 / 次要信息 */
  secondary: string = '#6F675E';
  /** 分割线 */
  divider: string = '#1A6F675E';
  /** 加载遮罩（底色 + 80% 透明度前缀） */
  scrim: string = '#CCF5F2EA';
  /** 当前章节高亮底 */
  highlight: string = '#14FFC15C';
  /** 该配色是否为深色底（决定状态栏字色等） */
  isDark: boolean = false;

  static of(background: string, primary: string, secondary: string, isDark: boolean): ReaderPalette {
    const value = new ReaderPalette();
    value.background = background;
    value.primary = primary;
    value.secondary = secondary;
    value.divider = ReaderPalette.withAlpha(secondary, 0x1a);
    value.scrim = ReaderPalette.withAlpha(background, 0xcc);
    value.highlight = isDark ? '#26FFC15C' : '#14FFC15C';
    value.isDark = isDark;
    return value;
  }

  /** 给 #RRGGBB 套上 alpha 前缀，得到 #AARRGGBB */
  static withAlpha(hex: string, alpha: number): string {
    const rgb = normalizeHex(hex);
    const a = Math.max(0, Math.min(255, Math.round(alpha)));
    return `#${a.toString(16).padStart(2, '0').toUpperCase()}${rgb.substring(1)}`;
  }
}

/** 预设主题定义 */
export class ReaderThemePreset {
  id: string = ReaderThemeId.Parchment;
  label: string = '';
  background: string = '';
  primary: string = '';
  secondary: string = '';
  isDark: boolean = false;

  static of(id: string, label: string, background: string,
    primary: string, secondary: string, isDark: boolean): ReaderThemePreset {
    const value = new ReaderThemePreset();
    value.id = id;
    value.label = label;
    value.background = background;
    value.primary = primary;
    value.secondary = secondary;
    value.isDark = isDark;
    return value;
  }
}

/** 最多五个主题；第一个免费，其余需要有效会员，权益变化不删除数据。 */
export class ReaderCustomTheme {
  id: string = '';
  slot: number = 0;
  background: string = '#F5F2EA';
  fontColor: string = '#2D2925';
  name: string = '';
  backgroundImage: string = '';
  imageMode: ReaderImageMode = ReaderImageMode.Cover;
  overlayAlpha: number = 0.35;

  static of(slot: number, background: string, fontColor: string): ReaderCustomTheme {
    const theme = new ReaderCustomTheme();
    theme.slot = slot;
    theme.id = `custom-${slot + 1}`;
    theme.background = normalizeHex(background);
    theme.fontColor = fontColor.length > 0 ? normalizeHex(fontColor) : paletteFromCustomColor(background).primary;
    return theme;
  }

  static defaults(): ReaderCustomTheme[] {
    return [ReaderCustomTheme.of(0, '#F5F2EA', '#2D2925'), ReaderCustomTheme.of(1, '#E3EDDF', '#28322A'),
      ReaderCustomTheme.of(2, '#EFE4D0', '#453321'), ReaderCustomTheme.of(3, '#E4EBF2', '#283645'),
      ReaderCustomTheme.of(4, '#242424', '#D6D3CD')];
  }

  static normalizeSlot(slot: number): number {
    return Number.isInteger(slot) && slot >= 0 && slot < 5 ? slot : 0;
  }

  static limit(hasMembership: boolean): number {
    return hasMembership ? 5 : 1;
  }

  static canUse(slot: number, hasMembership: boolean): boolean {
    return Number.isInteger(slot) && slot >= 0 && slot < ReaderCustomTheme.limit(hasMembership);
  }

  static normalizeName(name: string): string {
    return typeof name === 'string' ? name.trim().substring(0, 20) : '';
  }

  static copy(source: ReaderCustomTheme): ReaderCustomTheme {
    const theme = ReaderCustomTheme.of(ReaderCustomTheme.normalizeSlot(source.slot), source.background, source.fontColor);
    theme.name = ReaderCustomTheme.normalizeName(source.name);
    theme.backgroundImage = typeof source.backgroundImage === 'string' ? source.backgroundImage : '';
    theme.imageMode = source.imageMode === ReaderImageMode.Contain || source.imageMode === ReaderImageMode.Tile ||
      source.imageMode === ReaderImageMode.Stretch ? source.imageMode : ReaderImageMode.Cover;
    theme.overlayAlpha = Number.isFinite(source.overlayAlpha) ? Math.round(Math.max(0, Math.min(0.85, source.overlayAlpha)) * 100) / 100 : 0.35;
    return theme;
  }
}

/** 手动输入只接受 RGB 六位或三位色值，不把非法输入悄悄转换为默认色。 */
export function isReaderHexColor(input: string): boolean {
  return /^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(input.trim());
}

/** 预设主题表；顺序即设置页展示顺序 */
export const READER_THEME_PRESETS: ReaderThemePreset[] = [
  ReaderThemePreset.of(ReaderThemeId.Parchment, '羊皮纸', '#F5F2EA', '#2D2925', '#6F675E', false),
  ReaderThemePreset.of(ReaderThemeId.EyeCare, '护眼绿', '#E3EDDF', '#28322A', '#5C6B5B', false),
  ReaderThemePreset.of(ReaderThemeId.Black, '', '#000000', '#D6D3CD', '#8F8B84', true),
  ReaderThemePreset.of(ReaderThemeId.Night, '夜间', '#1C1F22', '#D6D3CD', '#8F8B84', true)
];

/** 把任意输入规整为 #RRGGBB；非法值回落到羊皮纸底色 */
export function normalizeHex(input: string): string {
  const fallback: string = '#F5F2EA';
  if (typeof input !== 'string') return fallback;
  let hex = input.trim();
  if (hex.length === 0) return fallback;
  if (!hex.startsWith('#')) hex = `#${hex}`;
  // #AARRGGBB → 丢掉 alpha 段
  if (hex.length === 9) hex = `#${hex.substring(3)}`;
  // #RGB → #RRGGBB
  if (hex.length === 4) {
    const r = hex.charAt(1);
    const g = hex.charAt(2);
    const b = hex.charAt(3);
    hex = `#${r}${r}${g}${g}${b}${b}`;
  }
  if (hex.length !== 7) return fallback;
  const body = hex.substring(1).toUpperCase();
  for (let i = 0; i < body.length; i++) {
    const c = body.charAt(i);
    const isDigit = c >= '0' && c <= '9';
    const isHex = c >= 'A' && c <= 'F';
    if (!isDigit && !isHex) return fallback;
  }
  return `#${body}`;
}

/** 取 #RRGGBB 的相对亮度（0~1），用于决定正文用深色还是浅色 */
export function hexLuminance(hex: string): number {
  const body = normalizeHex(hex).substring(1);
  const r = parseInt(body.substring(0, 2), 16) / 255;
  const g = parseInt(body.substring(2, 4), 16) / 255;
  const b = parseInt(body.substring(4, 6), 16) / 255;
  // ITU-R BT.601 感知亮度，够用且比线性化便宜
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/** 按 id 找预设；找不到返回 null（表示自定义色） */
export function findThemePreset(themeId: string): ReaderThemePreset | null {
  for (let i = 0; i < READER_THEME_PRESETS.length; i++) {
    if (READER_THEME_PRESETS[i].id === themeId) return READER_THEME_PRESETS[i];
  }
  return null;
}

/**
 * 自定义底色 → 完整配色。
 * 亮度 > 0.55 视为浅底（用深灰字），否则深底（用浅灰字）。
 * 正文不用纯黑/纯白，避免高对比刺眼。
 */
export function paletteFromCustomColor(background: string): ReaderPalette {
  const bg = normalizeHex(background);
  const lum = hexLuminance(bg);
  const isDark = lum <= 0.55;
  const primary = isDark ? '#D9D6D0' : '#2A2724';
  const secondary = isDark ? '#8E8A84' : '#6B645C';
  return ReaderPalette.of(bg, primary, secondary, isDark);
}

/**
 * 解析出当前应生效的配色。
 * 自定义字色仅作用于自定义主题，图片只使用自己的蒙层与字色。
 * 两参数调用保留旧模型迁移所需的背景解析语义。
 */
export function resolvePalette(themeId: string, customBackground: string, customFontColor: string = '',
  imageBackground: string = customBackground, imageFontColor: string = ''): ReaderPalette {
  if (themeId === ReaderThemeId.Custom || themeId === ReaderThemeId.Image) {
    const palette = paletteFromCustomColor(themeId === ReaderThemeId.Image ? imageBackground : customBackground);
    const color = themeId === ReaderThemeId.Image ? imageFontColor : customFontColor;
    if (color.length > 0) palette.primary = normalizeHex(color);
    return palette;
  }
  const preset = findThemePreset(themeId);
  const resolved = preset !== null ? preset : READER_THEME_PRESETS[0];
  return ReaderPalette.of(resolved.background, resolved.primary, resolved.secondary, resolved.isDark);
}

/** 系统主题只影响显示，不覆写已保存的主题。 */
export function resolveEffectiveThemeId(themeId: string, followSystem: boolean, systemDark: boolean): string {
  if (!followSystem) return themeId;
  if (systemDark) return ReaderThemeId.Night;
  return themeId === ReaderThemeId.Night || themeId === ReaderThemeId.Black ? ReaderThemeId.Parchment : themeId;
}

function linearColorChannel(value: number): number {
  return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

function relativeColorLuminance(hex: string): number {
  const rgb = normalizeHex(hex).substring(1);
  return 0.2126 * linearColorChannel(parseInt(rgb.substring(0, 2), 16) / 255) +
    0.7152 * linearColorChannel(parseInt(rgb.substring(2, 4), 16) / 255) +
    0.0722 * linearColorChannel(parseInt(rgb.substring(4, 6), 16) / 255);
}

/** WCAG 对比度仅用于提示，不自动更改用户颜色。 */
export function readerColorContrast(background: string, foreground: string): number {
  const first = relativeColorLuminance(background);
  const second = relativeColorLuminance(foreground);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

export function recommendedReaderFontColor(background: string): string {
  return readerColorContrast(background, '#2D2925') >= readerColorContrast(background, '#F5F2EA') ?
    '#2D2925' : '#F5F2EA';
}

/**
 * HSV → #RRGGBB，保留用于颜色数据兼容。
 * h: 0~360, s: 0~1, v: 0~1
 */
export function hsvToHex(h: number, s: number, v: number): string {
  const hue = ((h % 360) + 360) % 360;
  const sat = Math.max(0, Math.min(1, s));
  const val = Math.max(0, Math.min(1, v));
  const c = val * sat;
  const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = val - c;
  let r = 0;
  let g = 0;
  let b = 0;
  if (hue < 60) {
    r = c; g = x; b = 0;
  } else if (hue < 120) {
    r = x; g = c; b = 0;
  } else if (hue < 180) {
    r = 0; g = c; b = x;
  } else if (hue < 240) {
    r = 0; g = x; b = c;
  } else if (hue < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  const toHex = (channel: number): string => {
    const v255 = Math.round((channel + m) * 255);
    return Math.max(0, Math.min(255, v255)).toString(16).padStart(2, '0').toUpperCase();
  };
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

/** #RRGGBB → HSV，用于打开设置页时把已存色值还原到滑杆位置 */
export class HsvColor {
  h: number = 0;
  s: number = 0;
  v: number = 1;

  static of(h: number, s: number, v: number): HsvColor {
    const value = new HsvColor();
    value.h = h;
    value.s = s;
    value.v = v;
    return value;
  }
}

export function hexToHsv(hex: string): HsvColor {
  const body = normalizeHex(hex).substring(1);
  const r = parseInt(body.substring(0, 2), 16) / 255;
  const g = parseInt(body.substring(2, 4), 16) / 255;
  const b = parseInt(body.substring(4, 6), 16) / 255;
  const max = Math.max(r, Math.max(g, b));
  const min = Math.min(r, Math.min(g, b));
  const delta = max - min;
  let h = 0;
  if (delta > 0.00001) {
    if (max === r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max === g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
  }
  if (h < 0) h += 360;
  const s = max <= 0.00001 ? 0 : delta / max;
  return HsvColor.of(Math.round(h), s, max);
}
