"""从用户的 1970x1140 图标设计稿提取八款 1024px 分层图标。

python scripts/extract_app_icon_variants.py "D:/download/简听图标设计规格.jpeg" --glass "D:/download/简听图标设计规格.png"
依赖 Pillow。源稿为扁平 JPEG；边缘采样重建不透明背景，主体以柔和蒙版
保留在透明前景中，不把稿件上的圆角、说明文字或页面留白带入图标。
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
STYLES = ('leather', 'enamel', 'ink', 'clay', 'glass', 'origami', 'embroidery', 'retro')
SIZE = 1024
# 在 420px 设计格中的取景框：以书本/收音机的视觉重心居中，
# 不把右侧淡声波和投影与主体等权计算；只移动取景框，不拉伸原图。
# 普通款放大约 1.24–1.62 倍，独立玻璃稿本身占比较大，只略收紧边距。
FRAMING = (
    (58, 63, 358, 363),   # 拟物：主体右移约 1.3%
    (80, 85, 340, 345),   # 珐琅：主体右移约 3.8%
    (69, 76, 357, 364),   # 水墨：沿用视觉中心，主体比上一版等比放大约 18%
    (55, 53, 365, 363),   # 黏土：主体右移约 3.2%
    (16, 16, 404, 404),   # 新磨砂玻璃
    (60, 62, 360, 362),   # 折纸：主体右移约 2.0%
    (36, 35, 376, 375),   # 刺绣：主体右移约 1.8%
    (65, 65, 355, 355),   # 复古搪瓷：主体右移约 3.4%
)


def extract(source: Image.Image, index: int, glass: Image.Image | None = None):
    x = 70 + (index % 4) * 470
    y = 70 + (index // 4) * 525
    tile = source.crop((x, y, x + 420, y + 420)).convert('RGB')
    # 圆角区域只包含稿件底色。用同一行/列的图标内部纹理修补四角。
    pixels = tile.load()
    radius = 72
    for py in range(420):
        for px in range(420):
            dx = max(radius - px, px - (419 - radius), 0)
            dy = max(radius - py, py - (419 - radius), 0)
            if dx and dy and dx * dx + dy * dy > (radius - 3) ** 2:
                sx = min(max(px, radius + 4), 419 - radius - 4)
                sy = min(max(py, radius + 4), 419 - radius - 4)
                a, b = pixels[sx, py], pixels[px, sy]
                pixels[px, py] = tuple(round((a[c] + b[c]) / 2) for c in range(3))

    if index == 4 and glass is not None:
        # 新玻璃稿为独立正方形图，按比例居中裁剪，排除底部水印。
        if glass.width != glass.height:
            raise ValueError('玻璃稿必须为正方形')
        inset = glass.width // 16
        tile = glass.crop((inset, inset, glass.width - inset, glass.height - inset))
        tile = tile.convert('RGB').resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        pixels = tile.load()

    # 从上下边缘插值背景，不保留主体的重复影像。
    side = tile.width
    background = Image.new('RGB', (side, side))
    bg = background.load()
    edge = round(side * 8 / 420)
    for px in range(side):
        top = pixels[px, edge]
        bottom = pixels[px, side - 1 - edge]
        for py in range(side):
            t = py / (side - 1)
            bg[px, py] = tuple(round(top[c] * (1 - t) + bottom[c] * t) for c in range(3))
    background = background.filter(ImageFilter.GaussianBlur(side * 6 / 420)).convert('RGBA')
    mask = Image.new('L', (side, side), 0)
    margin = round(side * 20 / 420)
    ImageDraw.Draw(mask).rectangle((margin, margin, side - margin - 1, side - margin - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(side * 7 / 420))
    foreground = tile.convert('RGBA')
    foreground.putalpha(mask)
    crop = tuple(round(value * side / 420) for value in FRAMING[index])
    background = background.crop(crop).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    foreground = foreground.crop(crop).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return background, foreground, Image.alpha_composite(background, foreground)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--glass', type=Path, required=True, help='用户指定的替换磨砂玻璃图')
    args = parser.parse_args()
    source = Image.open(args.source)
    glass = Image.open(args.glass)
    if source.size != (1970, 1140):
        raise ValueError('设计稿尺寸必须为 1970x1140，其他版本请重新核对裁剪坐标')
    for index, style in enumerate(STYLES):
        background, foreground, legacy = extract(source, index, glass)
        name = f'app_icon_{style}'
        for folder in ('AppScope/resources/base/media', 'entry/src/main/resources/base/media'):
            media = ROOT / folder
            for layer, bitmap in (('background', background), ('foreground', foreground), ('legacy', legacy)):
                bitmap.save(media / f'{name}_{layer}.png', optimize=True)
            descriptor = {'layered-image': {'background': f'$media:{name}_background',
                                            'foreground': f'$media:{name}_foreground'}}
            (media / f'{name}.json').write_text(json.dumps(descriptor, indent=2) + '\n', encoding='utf-8')
        print(f'{name}: 1024x1024 background / foreground / legacy')


if __name__ == '__main__':
    main()
