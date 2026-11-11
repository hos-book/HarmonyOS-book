"""放大原有绿色「声波」和灰底彩色「夜曲」图标主体，保留各自背景。

用法：python scripts/build_app_icon_wave.py
依赖 Pillow。始终从设计源图生成，重复运行不会累积放大。
"""

from pathlib import Path
import json

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/icon-design'
MEDIA_DIRS = (
    ROOT / 'AppScope/resources/base/media',
    ROOT / 'entry/src/main/resources/base/media',
)
SIZE = 1024
SCALE = 1.15


def build_icon(name, variant=None):
    with Image.open(DESIGN / f'app_icon_{name}_foreground_source.png') as source:
        foreground = source.convert('RGBA')
    if foreground.size != (SIZE, SIZE):
        raise ValueError('图标设计源图必须为 1024×1024')
    enlarged_size = round(SIZE * SCALE)
    enlarged = foreground.resize((enlarged_size, enlarged_size), Image.Resampling.LANCZOS)
    inset = (enlarged_size - SIZE) // 2
    foreground = enlarged.crop((inset, inset, inset + SIZE, inset + SIZE))
    if foreground.getbbox() is None:
        raise ValueError('图标前景为空')
    if variant == 'lifewhite':
        # 中性书页改为炭黑，保留彩色声波和原始抗锯齿透明度。
        foreground.putdata([
            (52, 52, 52, a) if max(r, g, b) - min(r, g, b) < 28 else (r, g, b, a)
            for r, g, b, a in foreground.getdata()
        ])
    output_name = variant or name
    for media_dir in MEDIA_DIRS:
        if variant == 'lifewhite':
            background = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 255))
            background.save(media_dir / f'app_icon_{output_name}_background.png', optimize=True)
            descriptor = {'layered-image': {
                'background': f'$media:app_icon_{output_name}_background',
                'foreground': f'$media:app_icon_{output_name}_foreground'}}
            (media_dir / f'app_icon_{output_name}.json').write_text(
                json.dumps(descriptor, indent=2) + '\n', encoding='utf-8')
        else:
            with Image.open(media_dir / f'app_icon_{name}_background.png') as source:
                background = source.convert('RGBA')
        foreground.save(media_dir / f'app_icon_{output_name}_foreground.png', optimize=True)
        Image.alpha_composite(background, foreground).convert('RGB').save(
            media_dir / f'app_icon_{output_name}_legacy.png', optimize=True)
    print(f'{output_name}: {SCALE:.0%}; foreground bounds: {foreground.getbbox()}')


if __name__ == '__main__':
    from optimize_app_assets import optimize_icons
    for icon_name in ('wave', 'life'):
        build_icon(icon_name)
    build_icon('life', 'lifewhite')
    optimize_icons()
