/** 放大模式的视口坐标；图片按视口宽度适配，再围绕手指位置缩放。 */
export class ComicZoomTransform {
  viewportWidth: number = 1;
  viewportHeight: number = 1;
  ratio: number = 1;
  scale: number = 1;
  x: number = 0;
  y: number = 0;

  static open(width: number, height: number, ratio: number, focusY: number): ComicZoomTransform {
    const value = new ComicZoomTransform();
    value.viewportWidth = Math.max(1, width);
    value.viewportHeight = Math.max(1, height);
    value.ratio = Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
    value.scale = 2;
    value.x = (value.viewportWidth - value.width()) / 2;
    value.y = value.viewportHeight / 2 - value.height() * Math.max(0, Math.min(1, focusY));
    return value.bounded();
  }

  width(): number { return this.viewportWidth * this.scale; }
  height(): number { return this.width() * this.ratio; }

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

  resize(width: number, height: number): ComicZoomTransform {
    const focusX = (this.viewportWidth / 2 - this.x) / this.width();
    const focusY = (this.viewportHeight / 2 - this.y) / this.height();
    const value = this.copy();
    value.viewportWidth = Math.max(1, width);
    value.viewportHeight = Math.max(1, height);
    value.x = value.viewportWidth / 2 - value.width() * focusX;
    value.y = value.viewportHeight / 2 - value.height() * focusY;
    return value.bounded();
  }

  private bounded(): ComicZoomTransform {
    this.x = this.width() <= this.viewportWidth ? (this.viewportWidth - this.width()) / 2 :
      Math.max(this.viewportWidth - this.width(), Math.min(0, this.x));
    this.y = this.height() <= this.viewportHeight ? (this.viewportHeight - this.height()) / 2 :
      Math.max(this.viewportHeight - this.height(), Math.min(0, this.y));
    return this;
  }

  private copy(): ComicZoomTransform {
    const value = new ComicZoomTransform();
    value.viewportWidth = this.viewportWidth;
    value.viewportHeight = this.viewportHeight;
    value.ratio = this.ratio;
    value.scale = this.scale;
    value.x = this.x;
    value.y = this.y;
    return value;
  }
}
