"""从用户提供的胶彩柔光 PNG 生成主图标和 AGC 素材。"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFilter
import math

ROOT = Path(__file__).resolve().parents[1]

def main():
    source = Image.open(ROOT / 'docs/icon-design/app_icon_gelsoft_source.png').convert('RGBA')
    # 原预览 1148×810，中心 810×810 为完整图标；两侧为网页白边。
    size = min(source.size)
    left = (source.width - size) // 2
    top = (source.height - size) // 2
    artwork = source.crop((left, top, left + size, top + size)).resize((1024, 1024), Image.Resampling.LANCZOS)
    # 预览图自带圆角及白色角落。补齐原稿的浅灰径向背景，上传直角原图，
    # 桌面和 AGC 再施加各自的系统蒙版；保留中心图案、颗粒与光晕。
    square = Image.new('RGBA', artwork.size)
    pixels = square.load()
    for y in range(1024):
        for x in range(1024):
            t = min(1.0, math.hypot(x - 512, y - 410) / 942)
            pixels[x, y] = (round(255 - 15 * t), round(255 - 13 * t), round(255 - 8 * t), 255)
    mask = Image.new('L', artwork.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((6, 6, 1017, 1017), radius=280, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    square.paste(artwork, (0, 0), mask)
    artwork = square
    # 原稿为合成位图，作为完整背景保真保存，系统负责桌面蒙版。
    background = Image.new('RGBA', artwork.size, '#FFFFFF')
    background.alpha_composite(artwork)
    foreground = Image.new('RGBA', artwork.size, (0, 0, 0, 0))
    for folder in ['AppScope/resources/base/media', 'entry/src/main/resources/base/media']:
        directory = ROOT / folder
        background.save(directory / 'app_icon_background.png', optimize=True)
        foreground.save(directory / 'app_icon_foreground.png', optimize=True)
        artwork.save(directory / 'app_icon_legacy.png', optimize=True)
        (directory / 'app_icon.json').write_text(json.dumps({'layered-image': {
            'background': '$media:app_icon_background',
            'foreground': '$media:app_icon_foreground'
        }}, indent=2) + '\n', encoding='utf-8')
    artwork.save(ROOT / 'app-icon-hd.png', optimize=True)
    artwork.resize((512, 512), Image.Resampling.LANCZOS).save(ROOT / 'docs/app-gallery/icon.png', optimize=True)
    artwork.resize((512, 512), Image.Resampling.LANCZOS).save(ROOT / 'docs/icon-design/agc-icon-512.png', optimize=True)
    background.convert('RGB').save(ROOT / 'docs/icon-design/agc-icon-1024.png', optimize=True)
    exported = ROOT / 'docs/icon-design/agc-icon-1024.png'
    assert Image.open(exported).size == (1024, 1024)
    assert exported.stat().st_size < 3 * 1024 * 1024
    print('gelsoft: exported to both resource scopes')

if __name__ == '__main__':
    main()
