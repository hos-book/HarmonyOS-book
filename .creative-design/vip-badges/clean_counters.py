"""清理指定的 P 字和无限符号内孔；只移除与内孔种子相连的中性白底/灰影。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

DIRECTORY = Path(__file__).resolve().parent
SEEDS = {
    'month': [(2250, 480)],
    'year': [(1920, 360)],
    'life': [(1990, 490), (450, 400), (1050, 230)],
}

def clean(image: Image.Image, seeds: list[tuple[int, int]]) -> Image.Image:
    pixels = np.array(image.convert('RGBA'))
    rgb = pixels[:, :, :3].astype('int16')
    neutral = (rgb.max(2) - rgb.min(2) < 22) & (rgb.min(2) > 70)
    mask = Image.fromarray(np.where(neutral, 255, 0).astype('uint8')).copy()
    for point in seeds:
        if mask.getpixel(point) == 255:
            ImageDraw.floodfill(mask, point, 128, thresh=0)
    holes = Image.fromarray(np.where(np.array(mask) == 128, 255, 0).astype('uint8'))
    holes = holes.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.4))
    pixels[:, :, 3] = np.minimum(pixels[:, :, 3], 255 - np.array(holes))
    return Image.fromarray(pixels)

if __name__ == '__main__':
    for name, seeds in SEEDS.items():
        path = DIRECTORY / f'vip_{name}_badge.png'
        clean(Image.open(path), seeds).save(path, optimize=True)
