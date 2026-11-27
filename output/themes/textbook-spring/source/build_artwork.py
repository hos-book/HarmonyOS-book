"""Draw original textbook illustrations and export the theme's PNG artwork.

Requires Pillow, numpy and resvg-py. Editable SVG originals remain in vectors/.
"""
from pathlib import Path
from io import BytesIO
import math

import numpy as np
from PIL import Image
from resvg_py import svg_to_bytes

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'theme-source' / 'assets'
VECTORS = ROOT / 'source' / 'vectors'
LIGHT = dict(paper='#F4EEDC', surface='#FCF7E9', ink='#383A31', red='#A64635',
             green='#738F7A', sage='#A5B6A0', pale='#D8DFCA', mist='#E5E8D6',
             blue='#91ADB0', water='#CBDCD3', ochre='#C8A56A', wall='#E8DAB8',
             line='#5B715F', rose='#D4A292', shadow='#B8B79E')
DARK = dict(paper='#232B28', surface='#303A33', ink='#E8DFC7', red='#D99178',
            green='#67816D', sage='#556C5B', pale='#384B40', mist='#2E3C33',
            blue='#526D70', water='#344D46', ochre='#AA9166', wall='#6C6C50',
            line='#92A48D', rose='#A17566', shadow='#18241E')


def path(d, fill='none', stroke=None, width=2, opacity=1):
    s = f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ''
    return f'<path d="{d}" fill="{fill}"{s} opacity="{opacity}"/>'


def rect(x, y, w, h, fill, rx=0, stroke=None, width=2, opacity=1):
    s = f' stroke="{stroke}" stroke-width="{width}"' if stroke else ''
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{s} opacity="{opacity}"/>'


def circle(x, y, r, fill, stroke=None, width=2, opacity=1):
    s = f' stroke="{stroke}" stroke-width="{width}"' if stroke else ''
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"{s} opacity="{opacity}"/>'


def group(body, transform='', opacity=1):
    return f'<g transform="{transform}" opacity="{opacity}">{body}</g>'


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'


def bird(x, y, scale, p, angle=0):
    return group(path('M-27-10Q-8-10 0 2Q7-14 27-19Q10-5 7 7L17 15L3 11L-5 21L-4 7Q-15-1-27-10Z', p['line']),
                 f'translate({x} {y}) rotate({angle}) scale({scale})')


def grass(x, y, scale, p):
    return group(path('M0 0Q-8-35-19-43M0 0Q2-28 13-49M0 0Q14-26 27-27M0 0Q-13-18-27-21', stroke=p['green'], width=2),
                 f'translate({x} {y}) scale({scale})')


def tree(x, y, size, p):
    body = path('M0 0Q-5-110 5-224M0-76L-49-141M2-125L53-191', stroke=p['line'], width=7)
    for cx, cy, r in [(-37,-193,48),(13,-237,53),(57,-196,47),(-55,-150,42),(1,-166,53),(46,-144,39)]:
        body += circle(cx,cy,r,p['sage'])
    body += path('M0 0Q-5-108 3-209M-1-89L-39-150M1-122L40-180', stroke=p['line'], width=4)
    for dx, dy in [(-39,-186),(26,-213),(45,-160),(-24,-151)]:
        body += path(f'M{dx-14} {dy+7}q15-17 29-6m-23 13q12-10 23-8', stroke=p['line'], width=1.3, opacity=.45)
    return group(body, f'translate({x} {y}) scale({size})')


def willow(p):
    body = path('M0 0Q80 16 191 90Q242 118 323 129', stroke=p['line'], width=9)
    for i, (x,y,l) in enumerate([(36,12,180),(79,36,230),(126,60,275),(177,83,200),(230,112,245),(284,125,165)]):
        body += path(f'M{x} {y}q-24 {l/2} 4 {l}', stroke=p['green'], width=2.2)
        for j in range(3,12):
            t=j/12
            xx=x-38*t*(1-t)+4*t*t
            yy=y+l*t
            sign=1 if j%2 else -1
            body += path(f'M{xx} {yy}q{sign*22} 6 {sign*16} 33q{-sign*17}-9 {-sign*16}-33Z',p['sage'])
            body += path(f'M{xx} {yy}l{sign*12} 25',stroke=p['green'],width=.8,opacity=.55)
    return body


def bamboo(p):
    body = ''
    for x, lean, ht in [(30,18,390),(98,-28,470),(145,31,330)]:
        body += path(f'M{x} 480l{lean} {-ht}',stroke=p['green'],width=8)
        for j in range(1,6):
            yy=480-j*ht/6
            xx=x+lean*j/6
            body += path(f'M{xx-6} {yy}h12',stroke=p['line'],width=2)
    for x,y,a in [(36,319,-25),(111,283,150),(75,201,-50),(78,115,160),(157,365,-15),(159,218,15)]:
        leaves=path('M0 0Q48-26 111-19M25-12L46-63M62-23L95-53',stroke=p['green'],width=2)
        for dx,dy,rot in [(29,-15,-30),(53,-22,35),(75,-23,50),(46,-53,-15),(91,-45,60)]:
            leaves+=group(path('M0 0Q8-28 47-38Q27-8 0 0Z',p['sage']),f'translate({dx} {dy}) rotate({rot})')
        body+=group(leaves,f'translate({x} {y}) rotate({a})')
    return body


def landscape(p):
    body = path('M0 246Q90 223 160 171Q211 124 255 152Q328 190 378 135Q447 51 491 107Q557 182 616 120Q689 52 743 101Q846 203 924 167Q1004 127 1080 186V640H0Z',p['mist'])
    body += path('M0 365Q77 315 141 302Q212 288 267 232Q335 166 402 218Q472 282 535 234Q602 177 670 216Q771 295 840 238Q934 159 1080 258V640H0Z',p['pale'])
    body += path('M0 419Q153 316 299 387Q421 444 541 378Q685 300 841 349Q974 384 1080 342V640H0Z',p['sage'])
    body += path('M0 507Q161 437 323 469Q529 511 668 419Q844 361 1080 424V640H0Z',p['water'])
    body += path('M-20 557Q238 450 458 509Q616 549 825 456M326 587Q454 559 583 567M760 530Q881 493 995 509',stroke=p['blue'],width=2.6,opacity=.65)
    for x,y,w in [(16,584,110),(650,580,95),(420,541,50),(870,567,110)]:
        body += path(f'M{x} {y}h{w}m{-w*.75} 12h{w*.45}',stroke=p['blue'],width=1.4,opacity=.7)
    return body


def school(p):
    body = rect(0,100,348,151,p['wall'])
    body += path('M-25 103L163 5L375 101L348 114H0Z',p['green'],p['line'],3)
    body += path('M-17 101L163 17L366 100',stroke=p['sage'],width=6)
    body += path('M-13 111H364M9 116H341M163 8V-62',stroke=p['line'],width=3)
    body += path('M165-62Q195-72 219-54L217-16Q192-32 165-23Z',p['red'])
    body += rect(139,140,69,111,p['red']) + rect(145,146,56,105,p['rose'])
    body += path('M173 149V250',stroke=p['red'],width=2)
    body += circle(165,206,2,p['ochre']) + circle(182,206,2,p['ochre'])
    for x in [26,81,231,286]:
        body += rect(x,144,35,58,p['surface'],stroke=p['line'],width=2)
        body += path(f'M{x+17.5} 144v58m-17.5-29h35',stroke=p['green'],width=2)
        body += rect(x-4,205,43,5,p['ochre'])
    body += path('M-13 251H361M-20 259H368M-28 268H375',stroke=p['line'],width=3)
    body += path('M18 130h88M237 130h94M16 224h88M235 225h97',stroke=p['ochre'],width=1.5)
    return body


def home_scene(p):
    b = landscape(p)
    b += path('M0 470Q185 403 387 441L479 480Q306 492 165 558Q57 597 0 583Z',p['pale'])
    b += path('M575 358Q623 367 656 415Q689 452 719 466L793 471Q727 420 703 376Q681 337 636 330Z',p['wall'])
    b += group(school(p),'translate(539 142) scale(.9)')
    b += tree(948,397,.84,p)+tree(515,381,.53,p)
    b += path('M168 488Q261 372 368 479L368 496Q256 405 168 507Z',p['wall'],p['line'],2.7)
    b += path('M170 481Q262 369 368 472M170 465Q260 354 365 456',stroke=p['green'],width=3)
    for x,y in [(184,452),(211,425),(244,412),(277,410),(311,420),(341,439)]:
        b+=path(f'M{x} {y}v20',stroke=p['line'],width=2.5)
    for x,y,s in [(88,475,1),(133,465,.7),(409,449,.7),(962,445,.8),(1015,457,1.1)]:
        b+=grass(x,y,s,p)
    b+=bird(418,124,.7,p,-8)+bird(352,154,.42,p,5)
    return b


def books(p, x, y, scale=1):
    body=''
    for dx, h, w, col in [(0,103,30,'red'),(34,132,25,'green'),(62,115,35,'wall'),(101,144,27,'blue')]:
        body+=rect(dx,-h,w,h,p[col],2,stroke=p['line'],width=1)
        body+=path(f'M{dx+6} {-h+13}h{w-12}m0 7h{-w+12}M{dx+6}-18h{w-12}',stroke=p['surface'],width=1.5,opacity=.7)
    body+=group(rect(0,-121,28,121,p['rose'],2,stroke=p['line'],width=1)+path('M6-106h16M6-24h16M6-17h16',stroke=p['surface'],width=1.5), 'translate(136 -1) rotate(-15)')
    return group(body,f'translate({x} {y}) scale({scale})')


def shelf_scene(p):
    b=path('M0 542Q216 479 408 524Q652 558 833 487Q945 462 1080 503V640H0Z',p['mist'])
    b+=rect(190,65,584,449,p['wall'],4,stroke=p['line'],width=3)
    b+=rect(207,82,550,411,p['water'],stroke=p['line'],width=2)
    b+=path('M210 338Q321 252 419 316Q507 385 598 281Q681 207 755 263V489H210Z',p['pale'])
    b+=path('M210 409Q371 347 510 388Q643 424 755 356V489H210Z',p['sage'])
    b+=circle(606,176,48,p['surface'],opacity=.7)
    b+=path('M478 83V493M207 282H757',stroke=p['green'],width=13)
    b+=path('M216 90H746V482H216Z',stroke=p['line'],width=2)
    b+=rect(159,494,645,26,p['green'],2,stroke=p['line'],width=2)
    b+=rect(180,519,606,13,p['wall'])
    b+=books(p,239,494,1.08)
    b+=rect(448,460,141,29,p['red'],3,stroke=p['line'],width=1.5)
    b+=rect(460,464,122,20,p['surface'],1)
    b+=path('M466 471H574M466 477H574',stroke=p['ochre'],width=1)
    b+=rect(439,438,136,21,p['blue'],2,stroke=p['line'],width=1.2)
    b+=rect(447,442,119,12,p['surface'])
    b+=group(bamboo(p),'translate(824 25) scale(.88)')
    b+=path('M835 443H976L955 526H857Z',p['rose'],p['red'],2)+path('M850 459H961M861 506H951',stroke=p['wall'],width=2)
    b+=path('M120 560H888M243 580H731',stroke=p['shadow'],width=2,opacity=.6)
    b+=bird(343,185,.55,p)+bird(385,211,.34,p)
    return b


def notebook(p):
    b=path('M0 47Q139 0 264 48Q392 0 531 47L547 330Q400 284 271 332Q139 284-15 330Z',p['green'],p['line'],2)
    b+=path('M3 34Q139-12 264 35Q391-11 527 34L533 308Q395 263 267 315Q140 267-5 308Z',p['surface'],p['line'],2)
    b+=path('M264 35L267 315M2 309Q135 274 266 323Q400 274 537 309',stroke=p['ochre'],width=2)
    for j in range(8):
        y=75+j*26
        b+=path(f'M25 {y}Q132 {y-29} 240 {y+4}M290 {y+4}Q395 {y-29} 505 {y}',stroke=p['blue'],width=1.2,opacity=.65)
    b+=path('M51 49L48 293M478 48L483 291',stroke=p['rose'],width=1.5,opacity=.6)
    b+=path('M258 315L251 363L266 351L283 365L276 313Z',p['red'])
    return b


def pen(p):
    b=path('M0 0H27V-214Q13-230 0-214Z',p['green'],p['line'],2)
    b+=rect(-2,-196,31,17,p['ochre'],3)
    b+=path('M2 0L13 49L25 0Z',p['ochre'],p['line'],1.5)
    b+=path('M13 12V44',stroke=p['line'],width=1.5)+circle(13,10,3,p['line'])
    b+=path('M9-205V-145Q10-137 17-137',stroke=p['ochre'],width=3)
    return b


def record_scene(p):
    b=path('M0 534Q194 471 412 514Q633 557 864 491Q984 476 1080 514V640H0Z',p['mist'])
    b+=path('M142 524L814 477L968 542L268 603Z',p['shadow'],opacity=.35)
    b+=group(notebook(p),'translate(180 171) rotate(-6 264 160) scale(1.16)')
    b+=group(pen(p),'translate(797 377) rotate(25) scale(1.2)')
    b+=group(path('M0 0Q0-66 14-134',stroke=p['green'],width=2)+path('M5-41Q-65-70-43-110Q2-96 5-41ZM10-67Q67-83 66-129Q19-117 10-67ZM14-107Q-25-141-7-169Q25-145 14-107Z',p['sage'])+path('M4-44L-36-100M11-69L58-118M14-107L-5-158',stroke=p['green'],width=1.2), 'translate(523 369) rotate(25)')
    b+=rect(848,421,83,107,p['blue'],7,stroke=p['line'],width=2)
    b+=path('M858 415H923V437H858Z',p['green'])
    b+=rect(861,457,56,40,p['wall'],2)
    b+=path('M875 469H901M875 478H901M879 487H896',stroke=p['red'],width=2)
    b+=path('M134 582Q167 588 193 582M881 569h97',stroke=p['ochre'],width=2)
    return b


def gate(p):
    b=rect(0,40,380,358,p['wall'])
    b+=circle(190,217,145,p['water'])
    b+=path('M46 221Q95 165 160 188Q232 241 333 164V349H46Z',p['pale'])
    b+=path('M47 279Q148 224 240 283Q281 305 334 265V358H47Z',p['sage'])
    b+=path('M174 300Q235 319 219 360Q214 379 247 399H154Q184 370 170 349Q151 330 174 300Z',p['surface'])
    b+=path('M0 42L-23 23Q191 56 403 23L380 42Z',p['green'],p['line'],3)
    b+=path('M-20 23Q190 51 401 23',stroke=p['sage'],width=4)
    b+=circle(190,217,145,'none',p['line'],5)
    b+=circle(190,217,155,'none',p['ochre'],2)
    for j in range(7):
        y=74+j*43
        b+=path(f'M6 {y}h22M352 {y}h22',stroke=p['ochre'],width=2)
    b+=path('M-17 399H397M-28 411H408',stroke=p['line'],width=3)
    return b


def profile_scene(p):
    b=path('M0 493Q170 447 388 500Q578 541 794 474Q962 443 1080 481V640H0Z',p['mist'])
    b+=tree(231,499,1.24,p)
    b+=group(gate(p),'translate(471 98)')
    b+=path('M619 510Q672 542 644 591H827Q745 540 727 510Z',p['wall'])
    b+=path('M62 502H416V526H62Z',p['green'],p['line'],2)
    b+=rect(91,526,17,52,p['wall'],stroke=p['line'],width=1.5)+rect(370,526,17,52,p['wall'],stroke=p['line'],width=1.5)
    b+=group(books(p,0,0,.6),'translate(176 499)')
    b+=path('M919 488Q914 371 961 323M932 428Q904 395 886 381M943 389Q990 363 1003 344',stroke=p['green'],width=4)
    for x,y,s in [(959,326,14),(885,381,16),(1003,344,12)]:
        for angle in range(0,360,72):
            b+=circle(x+math.cos(math.radians(angle))*s*.7,y+math.sin(math.radians(angle))*s*.7,s*.65,p['rose'])
        b+=circle(x,y,4,p['ochre'])
    b+=path('M878 473H970L957 546H890Z',p['red'],p['line'],2)+path('M888 486H959M899 534H949',stroke=p['wall'],width=2)
    b+=bird(393,111,.64,p,-10)+bird(336,142,.4,p)
    return b


SCENES = {'home': home_scene, 'shelf': shelf_scene, 'record': record_scene, 'profile': profile_scene}


def background(p, scene):
    b=rect(0,0,1080,2160,p['paper'])
    b+=path('M55 208H1025M55 212H1025',stroke=p['red'],width=1,opacity=.15)
    b+=path('M55 231V293M1025 231V293',stroke=p['red'],width=1.2,opacity=.17)
    if scene=='home':
        b+=group(willow(p),'translate(18 -40) scale(.95)',.47)
        b+=bird(841,328,.9,p,-8)+bird(903,291,.48,p)
    elif scene=='shelf':
        b+=group(bamboo(p),'translate(1066 -65) rotate(135) scale(.64)',.38)
        b+=path('M77 301H190M77 314H144',stroke=p['green'],width=1.5,opacity=.25)
    elif scene=='record':
        b+=group(path('M0 0H170V170H0ZM85 0V170M0 85H170',stroke=p['red'],width=1.3)+path('M0 0L170 170M170 0L0 170',stroke=p['red'],width=1,opacity=.4),'translate(856 260) rotate(7)',.12)
        b+=group(path('M0 0Q0-56 47-84Q47-29 0 0Z',p['sage'])+path('M-10 13L33-67',stroke=p['green'],width=1.5),'translate(94 354) rotate(-20)',.45)
    else:
        b+=group(willow(p),'translate(1080 20) scale(-.65 .65)',.33)
        b+=circle(153,318,39,'none',p['red'],1.6,.18)
        b+=path('M139 299h28v38h-28Z',stroke=p['red'],width=1,opacity=.18)
    b+=rect(0,2034,1080,126,p['water'] if scene=='home' else p['mist'])
    b+=group(SCENES[scene](p),'translate(0 1396)')
    return svg(1080,2160,b)


def cover(p, kind):
    square=kind=='player'
    h=720 if square else 1008
    b=rect(0,0,720,h,p['paper'])
    b+=rect(0,0,29,h,p['red'])+rect(29,0,8,h,p['ochre'])
    b+=rect(62,32,620,h-64,'none',stroke=p['red'],width=2)
    b+=rect(70,40,604,h-80,'none',stroke=p['ochre'],width=1)
    b+=path('M107 108H629M107 113H629',stroke=p['red'],width=1.5)
    b+=path('M105 78h28m12 0h28m12 0h28M538 78h28m12 0h28',stroke=p['green'],width=2,opacity=.65)
    scene=home_scene if kind=='default' else shelf_scene if kind=='local' else profile_scene
    b+=group(scene(p),f'translate(69 {h-393}) scale(.56)')
    b+=rect(582,h-113,43,51,p['red'],2)
    b+=path(f'M591 {h-104}h25v32h-25Zm7 5v22m10-22v22m-17-11h25',stroke=p['paper'],width=1.7)
    return svg(720,h,b)


def player(mode):
    p=dict(DARK)
    p.update(paper='#283D38' if mode=='light' else '#172A27',mist='#304C43',pale='#3B5C4C',sage='#4E6D59',water='#243F3A',blue='#68867B',line='#9EAD94')
    b=rect(0,0,1080,2160,p['paper'])
    b+=circle(805,294,76,'#D3D5AE',opacity=.65)
    b+=circle(777,267,71,p['paper'])
    b+=group(willow(p),'translate(-14 -30) scale(1.08)',.38)
    b+=group(landscape(p),'translate(0 1520)',.72)
    b+=bird(786,1402,.7,p)+bird(729,1442,.42,p)
    for x,y in [(202,483),(892,681),(910,1240),(130,1124),(748,420)]:
        b+=circle(x,y,2,p['ochre'],opacity=.4)
    b+=path('M560 1990h175M609 2004h91M691 2018h132',stroke=p['line'],width=1.3,opacity=.28)
    return svg(1080,2160,b)


def profile_card(p):
    b=rect(0,0,1080,420,p['surface'])
    b+=group(profile_scene(p),'translate(553 5) scale(.60)',.55)
    b+=path('M33 90V32H146M33 330V388H146',stroke=p['red'],width=1.3,opacity=.35)
    b+=path('M70 346h290M70 355h180',stroke=p['red'],width=1,opacity=.13)
    return svg(1080,420,b)


def export(name, drawing):
    (VECTORS/f'{name}.svg').write_text(drawing,encoding='utf-8')
    rendered=Image.open(BytesIO(svg_to_bytes(svg_string=drawing))).convert('RGB')
    pixels=np.asarray(rendered).astype(np.float32)
    rng=np.random.default_rng(37)
    grain=rng.normal(0,.72,(rendered.height,rendered.width,1))
    pixels=np.clip(pixels+grain,0,255).astype(np.uint8)
    image=Image.fromarray(pixels).quantize(colors=192,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    image.save(ASSETS/f'{name}.png',optimize=True)
    print(f'{name}.png {rendered.width}x{rendered.height}')


def main():
    ASSETS.mkdir(parents=True,exist_ok=True)
    VECTORS.mkdir(parents=True,exist_ok=True)
    for mode,p in [('light',LIGHT),('dark',DARK)]:
        for scene in SCENES:
            export(f'background-{scene}-{mode}',background(p,scene))
        for kind in ['default','local','player']:
            export(f'cover-{kind}-{mode}',cover(p,kind))
        export(f'profile-card-{mode}',profile_card(p))
        export(f'player-{mode}',player(mode))


if __name__=='__main__':
    main()
