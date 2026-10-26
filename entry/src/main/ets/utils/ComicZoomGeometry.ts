/** 原图就地缩放；边界按图片在阅读窗口中实际可见的区域计算。 */
export class ComicZoomTransform {
  imageWidth: number = 1;
  imageHeight: number = 1;
  visibleTop: number = 0;
  visibleBottom: number = 1;
  scale: number = 1;
  x: number = 0;
  y: number = 0;

  static fit(width: number, height: number, top: number, bottom: number): ComicZoomTransform {
    const value = new ComicZoomTransform();
    value.imageWidth = Math.max(1, width);
    value.imageHeight = Math.max(1, height);
    return value.viewport(top, bottom);
  }

  width(): number { return this.imageWidth * this.scale; }
  height(): number { return this.imageHeight * this.scale; }

  viewport(top: number, bottom: number): ComicZoomTransform {
    const value = this.copy();
    value.visibleTop = Math.max(0, Math.min(this.imageHeight - 1, top));
    value.visibleBottom = Math.max(value.visibleTop + 1, Math.min(this.imageHeight, bottom));
    return value.bounded();
  }

  zoom(scale: number, anchorX: number, anchorY: number): ComicZoomTransform {
    const value = this.copy();
    value.scale = Math.max(1, Math.min(4, Number.isFinite(scale) ? scale : this.scale));
    const factor = value.scale / this.scale;
    value.x = anchorX - (anchorX - this.x) * factor;
    value.y = anchorY - (anchorY - this.y) * factor;
    return value.bounded();
  }

  pan(x: number, y: number): ComicZoomTransform {
    const value = this.copy();
    value.x += x;
    value.y += y;
    return value.bounded();
  }

  private bounded(): ComicZoomTransform {
    if (this.scale <= 1) {
      this.x = 0;
      this.y = 0;
      return this;
    }
    this.x = Math.max(this.imageWidth - this.width(), Math.min(0, this.x));
    // 长图可能只有中间一段在屏幕内；仍允许将图片顶部和底部拖到这一段。
    this.y = Math.max(this.visibleBottom - this.height(), Math.min(this.visibleTop, this.y));
    return this;
  }

  private copy(): ComicZoomTransform {
    const value = new ComicZoomTransform();
    value.imageWidth = this.imageWidth;
    value.imageHeight = this.imageHeight;
    value.visibleTop = this.visibleTop;
    value.visibleBottom = this.visibleBottom;
    value.scale = this.scale;
    value.x = this.x;
    value.y = this.y;
    return value;
  }
}
