/** 归一化裁剪框；原图坐标保留给缩放、超分和翻译复用。 */
export class ComicCropRect {
  constructor(public x: number = 0, public y: number = 0,
    public width: number = 1, public height: number = 1) {}
}

export class ComicWhiteBorderGeometry {
  static detect(pixels: Uint8Array, width: number, height: number): ComicCropRect {
    if (width < 16 || height < 16 || pixels.length < width * height * 4) return new ComicCropRect();
    let left = width;
    let right = -1;
    let top = height;
    let bottom = -1;
    // 只剔除整行/整列都是白色的外缘。透明、浅色线条和零散文字都算正文。
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const offset = (y * width + x) * 4;
        if (pixels[offset] >= 245 && pixels[offset + 1] >= 245 &&
          pixels[offset + 2] >= 245 && pixels[offset + 3] >= 250) continue;
        left = Math.min(left, x); right = Math.max(right, x);
        top = Math.min(top, y); bottom = Math.max(bottom, y);
      }
    }
    // 空白页不放大；每边最多裁 25%，留下两像素余量保护抗锯齿边缘。
    if (right < left || bottom < top) return new ComicCropRect();
    left = Math.min(Math.floor(width / 4), Math.max(0, left - 2));
    top = Math.min(Math.floor(height / 4), Math.max(0, top - 2));
    const trimRight = Math.min(Math.floor(width / 4), Math.max(0, width - right - 3));
    const trimBottom = Math.min(Math.floor(height / 4), Math.max(0, height - bottom - 3));
    return new ComicCropRect(left / width, top / height,
      (width - left - trimRight) / width, (height - top - trimBottom) / height);
  }
}
