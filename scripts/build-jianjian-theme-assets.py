"""Rebuild the Baibian Jianjian theme from the project's existing character artwork.

Requires Pillow and NumPy. Original character files are never changed. Backgrounds
leave the content area quiet; local covers reserve the existing title/author slots.
"""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'entry/src/main/resources'
MEDIA = RESOURCES / 'base/media'


def rgb(color):
    return tuple(bytes.fromhex(color.lstrip('#')))


def gradient(size, top, bottom, glows):
    width, height = size
    yy, xx = np.mgrid[0:height, 0:width]
    mix = (yy / max(height - 1, 1))[..., None]
    pixels = np.array(rgb(top)) * (1 - mix) + np.array(rgb(bottom)) * mix
    for x, y, radius, color, opacity in glows:
        distance = ((xx / width - x) ** 2 + (yy / height - y) ** 2) / (radius ** 2)
        weight = (np.exp(-distance * 2.4) * opacity)[..., None]
        pixels = pixels * (1 - weight) + np.array(rgb(color)) * weight
    return Image.fromarray(np.uint8(pixels.clip(0, 255))).convert('RGBA')


def sprite(name):
    source = Image.open(MEDIA / f'jianjian_red_{name}.png').convert('RGBA')
    source.putalpha(source.getchannel('A').point(lambda value: 0 if value < 16 else value))
    return source.crop(source.getbbox())


def place(canvas, name, box, opacity=1, outline=0):
    character = sprite(name)
    character.thumbnail((round(box[2]), round(box[3])), Image.Resampling.LANCZOS)
    x = round(box[0] + (box[2] - character.width) / 2)
    y = round(box[1] + box[3] - character.height)
    layer = Image.new('RGBA', canvas.size)
    if outline:
        mask = Image.new('L', canvas.size)
        mask.paste(character.getchannel('A'), (x, y))
        mask = mask.filter(ImageFilter.MaxFilter(outline * 2 + 1))
        border = Image.new('RGBA', canvas.size, '#FFF8F8')
        border.putalpha(mask)
        layer.alpha_composite(border)
    layer.alpha_composite(character, (x, y))
    if opacity < 1:
        layer.putalpha(layer.getchannel('A').point(lambda value: round(value * opacity)))
    canvas.alpha_composite(layer)


def sparkle(draw, x, y, radius, color):
    draw.polygon([(x, y - radius), (x + radius * .28, y - radius * .28),
                  (x + radius, y), (x + radius * .28, y + radius * .28),
                  (x, y + radius), (x - radius * .28, y + radius * .28),
                  (x - radius, y), (x - radius * .28, y - radius * .28)], fill=color)


def heart(draw, x, y, radius, color):
    points = []
    for angle in np.linspace(0, 2 * math.pi, 72):
        points.append((x + radius * math.sin(angle) ** 3,
                       y - radius * (13 * math.cos(angle) - 5 * math.cos(2 * angle)
                                     - 2 * math.cos(3 * angle) - math.cos(4 * angle)) / 16))
    draw.polygon(points, fill=color)


def decorations(canvas, dark, variant=0):
    width, height = canvas.size
    overlay = Image.new('RGBA', canvas.size)
    draw = ImageDraw.Draw(overlay)
    color = (239, 164, 190, 30 if dark else 68)
    # Small details stay near the outer edge and below the main text region.
    for x, y, size in [(.09, .09, .012), (.91, .17, .015), (.08, .70, .010),
                       (.89, .75, .011), (.16, .88, .014), (.56, .96, .008)]:
        sparkle(draw, width * x, height * y, width * size, color)
    for x, y in [(.86, .08), (.06, .83), (.9, .93)]:
        heart(draw, x * width, y * height, width * .014, color)
    for phase in [0, .035]:
        points = [(x, height * (.95 + phase + .023 * math.sin(x / width * math.pi * 2 + variant)))
                  for x in range(width)]
        draw.line(points, fill=color, width=max(1, round(width / 380)))
    canvas.alpha_composite(overlay)


def background(dark, scene):
    image = gradient((900, 1600), '#271D29' if dark else '#FFF6F8',
                     '#211A23' if dark else '#FFEDF3', [
                         (.92, .04, .50, '#6B374F' if dark else '#FFC4D8', .32),
                         (.02, .80, .42, '#443254' if dark else '#E6D8FF', .24),
                         (.80, .97, .39, '#743C57' if dark else '#FFCCE1', .36)])
    decorations(image, dark, scene)
    pose = ['happy', 'reading', 'sleepy'][scene]
    place(image, pose, (640, 1320, 200, 220), .18 if dark else .20)
    return image


def cover(dark, local):
    image = gradient((600, 800), '#342433' if dark else '#FFF4F7',
                     '#563345' if dark else '#F7C9DA', [
                         (.18, .16, .65, '#8F526A' if dark else '#FFFFFF', .32),
                         (.88, .80, .52, '#81566C' if dark else '#E6D5FF', .27)])
    overlay = Image.new('RGBA', image.size)
    draw = ImageDraw.Draw(overlay)
    frame = (236, 169, 195, 80) if dark else (187, 90, 128, 58)
    draw.rounded_rectangle((25, 25, 575, 775), radius=30, outline=frame, width=2)
    draw.line([(50, 74), (252, 74)], fill=frame, width=2)
    draw.line([(348, 74), (550, 74)], fill=frame, width=2)
    heart(draw, 300, 74, 15, frame)
    sparkle(draw, 82, 650, 14, frame)
    sparkle(draw, 534, 470, 12, frame)
    image.alpha_composite(overlay)
    if local:
        place(image, 'reading', (214, 642, 172, 142), 1, 2)
    else:
        place(image, 'heart', (92, 352, 416, 410), 1, 3)
    return image


def profile_banner(dark):
    image = gradient((1200, 440), '#392633' if dark else '#FFE9F1',
                     '#30232E' if dark else '#FFF5F8', [
                         (.94, .45, .48, '#794456' if dark else '#FFC4DA', .50),
                         (.1, .95, .60, '#4C354B' if dark else '#FFE0ED', .24)])
    # Profile name/account remain on the left; the character sits on the far right.
    place(image, 'happy', (900, 54, 260, 350), .48 if dark else .65)
    return image


def main():
    for mode in ['base', 'dark']:
        dark = mode == 'dark'
        target = RESOURCES / mode / 'media'
        target.mkdir(parents=True, exist_ok=True)
        assets = {name: background(dark, i)
                  for i, name in enumerate(['background', 'shelf_background', 'record_background'])}
        assets.update(cover=cover(dark, False), local_cover=cover(dark, True),
                      profile_card=profile_banner(dark))
        for name, image in assets.items():
            image.convert('RGB').save(target / f'theme_jianjian_{name}.webp', quality=88, method=6)
    for role, pose in [('home', 'happy'), ('shelf', 'reading'), ('record', 'sleepy'), ('profile', 'heart')]:
        image = Image.new('RGBA', (160, 160))
        place(image, pose, (5, 5, 150, 150), 1, 1)
        image.save(MEDIA / f'theme_jianjian_{role}.png', optimize=True)
    print('Generated 12 light/dark theme images and 4 transparent Jianjian tab icons.')


if __name__ == '__main__':
    main()
