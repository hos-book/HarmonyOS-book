/** 页眉、页脚和正文标题独立样式；空字色跟随当前阅读主题。 */
export class ReaderRegionStyle {
  top: number = 0;
  bottom: number = 0;
  left: number = 0;
  right: number = 0;
  color: string = '';

  static normalize(value: ReaderRegionStyle): ReaderRegionStyle {
    const result = new ReaderRegionStyle();
    result.top = ReaderRegionStyle.margin(value.top);
    result.bottom = ReaderRegionStyle.margin(value.bottom);
    result.left = ReaderRegionStyle.margin(value.left);
    result.right = ReaderRegionStyle.margin(value.right);
    result.color = typeof value.color === 'string' && /^#[0-9a-fA-F]{6}$/.test(value.color) ? value.color : '';
    return result;
  }

  private static margin(value: number): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(64, value))) : 0;
  }

  static decode(value: string): ReaderRegionStyle {
    try {
      const parsed: ReaderRegionStyle = JSON.parse(value);
      return parsed ? ReaderRegionStyle.normalize(parsed) : new ReaderRegionStyle();
    } catch (_error) { return new ReaderRegionStyle(); }
  }

  pixels(density: number): ReaderRegionStyle {
    const result = ReaderRegionStyle.normalize(this);
    result.top *= density;
    result.bottom *= density;
    result.left *= density;
    result.right *= density;
    return result;
  }
}
