"""Render the Apricot Study theme as static WebP resources.

Requires fontTools, Pillow, resvg-py and the Windows SimSun font.
Vector artwork is composed in memory and rasterized before packaging.
"""
from pathlib import Path
import argparse
import io
import math

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from PIL import Image
from resvg_py import svg_to_bytes


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'entry/src/main/resources'
LIGHT = {
    'paper': '#F5F0E6', 'surface': '#FAF7EF', 'fiber': '#9A8D78',
    'ink': '#514B41', 'gold': '#857050', 'branch': '#8F8976',
    'petal': '#FCF8EF', 'petal_edge': '#B9A08D', 'leaf': '#A0A18E',
    'far': '#DDDCD1', 'middle': '#D2D2C4', 'near': '#C5C6B6',
    'seal': '#A67867', 'cover': '#E5D9C1', 'binding': '#B09A77',
    'label': '#F4EDDF', 'thread': '#FAF5EA',
}
DARK = {
    'paper': '#242321', 'surface': '#2E2D29', 'fiber': '#B2A692',
    'ink': '#E3DED3', 'gold': '#C4B08B', 'branch': '#9A9380',
    'petal': '#8C8372', 'petal_edge': '#A69A86', 'leaf': '#868C7C',
    'far': '#30312D', 'middle': '#393B34', 'near': '#44473C',
    'seal': '#9C7768', 'cover': '#464136', 'binding': '#302E28',
    'label': '#36342E', 'thread': '#B8AB92',
}


def paper(width, height, palette, fill):
    marks = []
    for i in range(round(width * height / 18000)):
        x = (i * 173.31 + 19) % width
        y = (i * 257.77 + 41) % height
        length = 2 + i % 6
        marks.append(f'M{x:.1f} {y:.1f}l{length} {((i % 5) - 2) * .35:.2f}')
    return (f'<rect width="{width}" height="{height}" fill="{fill}"/>\n'
            f'<path d="{" ".join(marks)}" fill="none" stroke="{palette["fiber"]}" '
            'stroke-width=".6" opacity=".045"/>')


def outline_text(text, x, y, size, color, font):
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font['head'].unitsPerEm
    paths = []
    for i, char in enumerate(text):
        pen = SVGPathPen(glyphs)
        glyphs[cmap[ord(char)]].draw(pen)
        paths.append(f'<path d="{pen.getCommands()}" transform="translate({x} '
                     f'{y + i * size * 1.28:.2f}) scale({scale:.6f} {-scale:.6f})"/>')
    return f'<g fill="{color}">{"".join(paths)}</g>'


def seal(x, y, size, palette, font, opacity=1):
    return (f'<g transform="translate({x} {y})" opacity="{opacity}">'
            f'<rect x="0" y="0" width="{size}" height="{size * 1.65}" rx="2" '
            f'fill="{palette["seal"]}"/>'
            f'<rect x="2.5" y="2.5" width="{size - 5}" height="{size * 1.65 - 5}" '
            f'rx=".6" fill="none" stroke="{palette["label"]}" stroke-width=".8"/>'
            + outline_text('藏书', size * .20, size * .72, size * .60,
                           palette['label'], font) + '</g>')


def blossom(x, y, size, angle, palette):
    petals = []
    for rotation in range(0, 360, 72):
        petals.append(f'<path d="M0 1C-7-1-10-8-5-11C0-15 7-10 6-5Q5-1 0 1Z" '
                      f'transform="rotate({rotation})"/>')
    stamens = []
    for rotation in range(0, 360, 60):
        radians = math.radians(rotation)
        dx, dy = math.cos(radians) * 4, math.sin(radians) * 4
        stamens.append(f'<path d="M0 0L{dx:.2f} {dy:.2f}"/>'
                       f'<circle cx="{dx:.2f}" cy="{dy:.2f}" r=".8"/>')
    return (f'<g transform="translate({x} {y}) rotate({angle}) scale({size})">'
            f'<g fill="{palette["petal"]}" stroke="{palette["petal_edge"]}" '
            f'stroke-width=".55">{"".join(petals)}</g>'
            f'<g stroke="{palette["gold"]}" fill="{palette["gold"]}" '
            f'stroke-width=".45">{"".join(stamens)}</g></g>')


def branch(palette):
    trunk = ('M350-9C321 38 306 73 263 106C230 133 195 145 156 168'
             'C121 187 80 207 22 224C70 204 109 185 149 163'
             'C187 141 226 124 257 100C297 70 315 28 337-9Z')
    twigs = ('M265 104Q251 72 255 34M251 77Q222 66 211 45 '
             'M203 143Q171 126 154 93M181 131Q147 136 128 127 '
             'M145 170Q120 157 102 161M93 198Q72 175 65 151 '
             'M300 66Q328 68 344 51M233 124Q237 161 216 185 '
             'M170 160Q170 188 152 205M62 214Q50 238 24 250')
    leaves = []
    for x, y, angle in [(254, 49, -16), (177, 124, -55), (236, 150, 30),
                         (78, 183, -48), (304, 64, 67), (159, 187, 37)]:
        leaves.append(f'<g transform="translate({x} {y}) rotate({angle})">'
                      f'<path d="M0 0Q-13-15-4-31Q10-16 0 0Z" fill="{palette["leaf"]}" opacity=".64"/>'
                      f'<path d="M0 0L-3-25" stroke="{palette["branch"]}" '
                      'stroke-width=".7" fill="none"/></g>')
    flowers = [blossom(x, y, size, angle, palette) for x, y, size, angle in [
        (255, 30, 1.25, 8), (211, 45, .95, 25), (153, 91, 1.2, -8),
        (127, 127, .85, 14), (65, 150, .95, 20), (216, 185, 1.15, 31),
        (152, 205, .8, -18), (25, 249, .8, 15), (341, 51, 1.25, -12)]]
    return (f'<path d="{trunk}" fill="{palette["branch"]}"/>'
            f'<path d="{twigs}" stroke="{palette["branch"]}" stroke-width="1.8" '
            f'fill="none" stroke-linecap="round"/>{"".join(leaves)}{"".join(flowers)}')


def landscape(palette):
    far = ('M0 198C58 200 91 172 133 148S194 108 226 126'
           'C265 151 298 165 337 151S402 103 451 115'
           'C491 125 501 151 542 149S613 103 657 119'
           'C696 133 724 174 770 162S850 128 900 156V340H0Z')
    middle = ('M0 237C54 211 87 232 128 214S193 183 243 205'
              'C286 224 318 247 363 233S439 203 487 221'
              'C529 237 567 204 610 219S682 253 728 233'
              'C778 213 834 210 900 230V340H0Z')
    near = ('M0 277Q52 261 88 273T169 279Q207 265 230 272T291 301'
            'Q349 325 401 306T486 292Q525 293 554 303Q596 318 645 294'
            'T731 271Q770 278 801 262T860 258L900 272V340H0Z')
    return (f'<path d="{far}" fill="{palette["far"]}"/>'
            f'<path d="{middle}" fill="{palette["middle"]}" opacity=".52"/>'
            f'<path d="{near}" fill="{palette["near"]}" opacity=".38"/>'
            f'<path d="M92 250q115-21 221-5t203 10m-128 30q92-11 192-1" '
            f'stroke="{palette["paper"]}" stroke-width="5" opacity=".72" fill="none"/>')


def lattice(palette):
    lines = []
    for x in [0, 94, 188, 282]:
        lines.append(f'M{x} 0v342m12-342v342')
    for y in [0, 106, 212, 330]:
        lines.append(f'M0 {y}h294m-294 12h294')
    for x in [12, 106, 200]:
        for y in [12, 118, 224]:
            lines.append(f'M{x + 41} {y + 12}l29 35-29 35-29-35Z')
    return (f'<path d="{" ".join(lines)}" stroke="{palette["branch"]}" '
            'stroke-width="3" fill="none"/>')


def background(palette, scene, font):
    parts = [paper(900, 1600, palette, palette['paper'])]
    if scene == 'home':
        parts += [f'<circle cx="731" cy="1430" r="48" fill="{palette["gold"]}" opacity=".035"/>',
                  f'<g transform="translate(0 1400) scale(1 .6)" opacity=".50">{landscape(palette)}</g>',
                  f'<g transform="translate(655 30) scale(.82)" opacity=".24">{branch(palette)}</g>',
                  seal(816, 1472, 22, palette, font, .22)]
    elif scene == 'shelf':
        parts += [f'<g transform="translate(666 80) skewY(-12)" opacity=".025">{lattice(palette)}</g>',
                  f'<g transform="translate(672 30) scale(.72)" opacity=".20">{branch(palette)}</g>',
                  f'<g transform="translate(0 1430) scale(1 .51)" opacity=".38">{landscape(palette)}</g>',
                  seal(78, 1470, 21, palette, font, .20)]
    else:
        parts += [f'<g transform="translate(0 1410) scale(1 .57)" opacity=".43">{landscape(palette)}</g>',
                  f'<g transform="translate(689 54) scale(.65)" opacity=".21">{branch(palette)}</g>',
                  seal(816, 1472, 21, palette, font, .19)]
    return svg(900, 1600, parts)


def profile_card(palette, font):
    parts = [paper(900, 420, palette, palette['surface']),
             f'<g transform="translate(612 -24) scale(.88)" opacity=".24">{branch(palette)}</g>',
             f'<g transform="translate(0 318) scale(1 .31)" opacity=".24">{landscape(palette)}</g>',
             f'<path d="M25 85V25h100M775 25h100v60M25 335v60h100M775 395h100v-60" '
             f'stroke="{palette["gold"]}" stroke-width="1.2" fill="none" opacity=".22"/>',
             seal(824, 310, 21, palette, font, .32)]
    return svg(900, 420, parts)


def cover(palette, local, font):
    fill = palette['label'] if local else palette['cover']
    parts = [paper(360, 504, palette, fill),
             f'<path d="M0 0h28v504H0Z" fill="{palette["binding"]}"/>',
             f'<path d="M28 0h4v504h-4Z" fill="{palette["gold"]}" opacity=".42"/>',
             f'<path d="M38 0v504" stroke="{palette["thread"]}" opacity=".56"/>',
             f'<rect x="48" y="21" width="289" height="462" fill="none" '
             f'stroke="{palette["gold"]}" stroke-width="1.3" opacity=".60"/>',
             f'<rect x="54" y="27" width="277" height="450" fill="none" '
             f'stroke="{palette["gold"]}" stroke-width=".6" opacity=".30"/>']
    for y in [49, 149, 253, 357, 457]:
        parts += [f'<circle cx="13" cy="{y}" r="2.4" fill="{palette["ink"]}" opacity=".55"/>',
                  f'<path d="M0 {y - 5}L13 {y}L0 {y + 5}M13 {y}h22" '
                  f'stroke="{palette["thread"]}" stroke-width="1.25" fill="none"/>']
    if local:
        parts += [f'<g transform="translate(41 370) scale(.35 .32)" opacity=".65">{landscape(palette)}</g>',
                  f'<g transform="translate(200 9) scale(.43)" opacity=".54">{branch(palette)}</g>',
                  f'<path d="M82 89h188m-181 6h174" stroke="{palette["gold"]}" '
                  'stroke-width=".7" opacity=".34"/>',
                  f'<rect x="286" y="42" width="25" height="65" fill="{palette["surface"]}" '
                  f'stroke="{palette["gold"]}" stroke-width=".65"/>',
                  outline_text('杏笺', 292, 62, 13, palette['gold'], font),
                  seal(284, 427, 21, palette, font, .85)]
    else:
        parts += [f'<circle cx="148" cy="283" r="67" fill="{palette["label"]}" opacity=".48"/>',
                  f'<g transform="translate(37 331) scale(.36 .45)" opacity=".85">{landscape(palette)}</g>',
                  f'<g transform="translate(74 144) scale(.53)" opacity=".85">{branch(palette)}</g>',
                  f'<rect x="252" y="45" width="54" height="158" fill="{palette["label"]}" '
                  f'stroke="{palette["gold"]}" stroke-width="1"/>',
                  f'<rect x="257" y="50" width="44" height="148" fill="none" '
                  f'stroke="{palette["gold"]}" stroke-width=".6" opacity=".48"/>',
                  outline_text('杏笺书斋', 267, 81, 24, palette['ink'], font),
                  seal(78, 389, 24, palette, font, .95)]
    return svg(360, 504, parts)


def svg(width, height, parts):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">\n' + '\n'.join(parts) + '\n</svg>\n')


def main():
    parser = argparse.ArgumentParser(description='Draw the Apricot Study theme resources.')
    parser.add_argument('--font', default='C:/Windows/Fonts/simsun.ttc')
    args = parser.parse_args()
    with TTFont(args.font, fontNumber=0) as font:
        for mode, palette in [('base', LIGHT), ('dark', DARK)]:
            media = RESOURCES / mode / 'media'
            drawings = {
                'background': background(palette, 'home', font),
                'shelf_background': background(palette, 'shelf', font),
                'record_background': background(palette, 'record', font),
                'profile_card': profile_card(palette, font),
                'cover': cover(palette, False, font),
                'local_cover': cover(palette, True, font),
            }
            for name, drawing in drawings.items():
                destination = media / f'theme_apricot_{name}.webp'
                pixels = svg_to_bytes(svg_string=drawing)
                with Image.open(io.BytesIO(pixels)) as rendered:
                    rendered.convert('RGB').save(destination, 'WEBP', quality=92, method=6)
                print(destination.relative_to(ROOT))


if __name__ == '__main__':
    main()
