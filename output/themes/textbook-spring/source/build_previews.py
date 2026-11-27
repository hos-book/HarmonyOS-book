"""Compose presentation artwork from the exported theme assets."""
from pathlib import Path
from io import BytesIO
from PIL import Image, ImageDraw, ImageFont
from resvg_py import svg_to_bytes

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'theme-source'/'assets'
SERIF='C:/Windows/Fonts/simsun.ttc'
SANS='C:/Windows/Fonts/msyh.ttc'
PAGES=['home','shelf','record','profile']
NAMES=['首页','书架','记录','我的']
SCENES=['春日学堂','书窗竹影','纸页钢笔','庭院藏书']


def font(size,serif=False):
    return ImageFont.truetype(SERIF if serif else SANS,size)


def txt(im,xy,text,size,color,serif=False,anchor=None):
    ImageDraw.Draw(im).text(xy,text,font=font(size,serif),fill=color,anchor=anchor)


def pic(name,size):
    file=ASSETS/name
    if file.suffix=='.svg':
        im=Image.open(BytesIO(svg_to_bytes(svg_string=file.read_text(encoding='utf-8')))).convert('RGBA')
    else:
        im=Image.open(file).convert('RGBA')
    return im.resize(size,Image.Resampling.LANCZOS)


def paste(im,item,xy):
    im.alpha_composite(item,xy)


def panel(im,box,fill,outline,radius=13):
    layer=Image.new('RGBA',im.size)
    ImageDraw.Draw(layer).rounded_rectangle(box,radius,fill,outline,width=1)
    im.alpha_composite(layer)


def cover(im,mode,xy,size,title,kind='default'):
    paste(im,pic(f'cover-{kind}-{mode}.png',size),xy)
    ink='#383A31' if mode=='light' else '#E8DFC7'
    txt(im,(xy[0]+size[0]//2,xy[1]+size[1]*.27),title,round(size[0]*.15),ink,True,'mt')


def phone(mode,page):
    i=PAGES.index(page)
    im=pic(f'background-{page}-{mode}.png',(456,912))
    dark=mode=='dark'
    ink='#E8DFC7' if dark else '#383A31'
    muted='#B8B5A3' if dark else '#6E7061'
    red='#D99178' if dark else '#A64635'
    surface=(48,58,51,226) if dark else (252,248,237,226)
    outline=(135,155,138,100) if dark else (166,171,147,95)
    txt(im,(29,16),'9:41',13,ink)
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((394,20,422,31),3,outline=ink,width=1)
    d.rectangle((397,23,418,28),fill=ink)
    d.rectangle((424,23,426,28),fill=ink)
    txt(im,(28,61),NAMES[i],32,ink,True)
    if page in ['shelf','record']:
        buttons=['search','group','view-grid'] if page=='shelf' else ['filter','excerpt','edit']
        for j,button in enumerate(buttons):
            paste(im,pic(f'button-{page}-{button}-{mode}.png',(36,36)),(300+j*43,64))
    else:
        paste(im,pic(f'icon-search-{mode}.svg',(27,27)),(395,68))
    if page=='home':
        txt(im,(29,126),'春光正好，翻开新的一页',17,muted,True)
        panel(im,(27,176,429,320),surface,outline)
        txt(im,(47,197),'今日共读',14,red)
        txt(im,(47,229),'读一页春光',29,ink,True)
        txt(im,(47,276),'把文字，读成眼里的风景。',15,muted,True)
        txt(im,(28,354),'课外书房',23,ink,True)
        txt(im,(381,362),'更多',13,muted)
        for j,title in enumerate(['春日集','山水间','小城故事']):
            cover(im,mode,(29+j*140,399),(116,162),title,'local' if j==2 else 'default')
            txt(im,(30+j*140,575),title,15,ink,True)
    elif page=='shelf':
        txt(im,(28,127),'全部书籍',17,red)
        txt(im,(139,127),'正在阅读',17,muted)
        txt(im,(250,127),'已读完',17,muted)
        d.line((29,157,95,157),fill=red,width=2)
        for j,title in enumerate(['朝花夕拾','春水','小橘灯']):
            cover(im,mode,(29+j*140,193),(116,163),title,'local' if j==2 else 'default')
            txt(im,(29+j*140,369),title,17,ink,True)
            txt(im,(29+j*140,399),['读至 32%','读至 18%','本地书籍'][j],12,muted)
        panel(im,(28,459,428,540),surface,outline)
        txt(im,(46,477),'书页里的四季',20,ink,True)
        txt(im,(46,508),'让每一本好书，都有自己的位置。',13,muted,True)
    elif page=='record':
        panel(im,(28,137,428,273),surface,outline)
        txt(im,(48,156),'累计阅听',14,muted)
        txt(im,(252,156),'连续阅听',14,muted)
        txt(im,(48,193),'12.5',43,ink,True)
        txt(im,(151,224),'小时',13,muted)
        txt(im,(252,193),'07',43,ink,True)
        txt(im,(322,224),'天',13,muted)
        txt(im,(28,309),'阅读手记',24,ink,True)
        panel(im,(28,356,428,519),surface,outline)
        txt(im,(49,375),'摘录 · 春日集',14,red)
        txt(im,(49,411),'一页书，一窗春色。',24,ink,True)
        txt(im,(49,455),'把读过的时光，留在这里。',16,muted,True)
        txt(im,(49,490),'今天  09:41',12,muted)
    else:
        panel(im,(28,140,428,297),surface,outline)
        layer=pic(f'profile-card-{mode}.png',(400,156))
        mask=Image.new('L',layer.size)
        ImageDraw.Draw(mask).rounded_rectangle((0,0,399,155),13,fill=255)
        layer.putalpha(mask)
        paste(im,layer,(28,140))
        d=ImageDraw.Draw(im)
        d.ellipse((49,169,118,238),fill=red)
        txt(im,(84,184),'阅',31,'#232B28' if dark else '#FFF7E7',True,'mt')
        txt(im,(138,173),'爱读书的你',24,ink,True)
        txt(im,(139,214),'在字里行间，看见春天',13,muted)
        panel(im,(28,333,428,548),surface,outline)
        for j,label in enumerate(['主题与背景','我的书源','阅读设置','下载管理']):
            yy=351+j*49
            txt(im,(52,yy),label,18,ink,True)
            paste(im,pic(f'icon-chevron-right-{mode}.svg',(18,18)),(387,yy+4))
            if j<3:
                ImageDraw.Draw(im).line((49,yy+37,406,yy+37),fill=outline,width=1)
    for j,tab in enumerate(PAGES):
        state='selected' if tab==page else 'normal'
        paste(im,pic(f'tab-{tab}-{state}-{mode}.svg',(33,33)),(43+j*112,833))
        txt(im,(59+j*112,873),NAMES[j],12,red if tab==page else muted,anchor='mt')
    ImageDraw.Draw(im).rounded_rectangle((174,900,282,904),2,fill=ink)
    mask=Image.new('L',im.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,455,911),29,fill=255)
    im.putalpha(mask)
    return im


def mode_preview(mode):
    dark=mode=='dark'
    board=Image.new('RGBA',(2240,1540),'#18231F' if dark else '#FAF6EB')
    ink='#E8DFC7' if dark else '#383A31'
    red='#D99178' if dark else '#A64635'
    muted='#A6B19E' if dark else '#75806B'
    line='#3E5144' if dark else '#D5D5BC'
    txt(board,(96,55),'简听阅读  /  原创课本主题',22,red)
    txt(board,(91,112),'课本里的春天',88,ink,True)
    txt(board,(100,224),'米白纸页 · 朱红批注 · 青绿山水 · 四页四景',26,muted,True)
    txt(board,(2135,79),'深色 · 夜读' if dark else '浅色 · 晨读',29,red,True,'rt')
    txt(board,(2135,127),'DESIGN PREVIEW',17,muted,anchor='rt')
    ImageDraw.Draw(board).line((96,287,2144,287),fill=line,width=2)
    for j,page in enumerate(PAGES):
        x=96+j*530
        txt(board,(x,319),f'0{j+1}  {SCENES[j]}',28,ink,True)
        paste(board,phone(mode,page),(x,380))
        txt(board,(x,1316),f'{NAMES[j]}  /  独立背景',20,muted)
    txt(board,(96,1412),'浅深两套配色  ·  4 组双态 Tab  ·  23 项整按钮  ·  独立夜读播放器',23,ink,True)
    txt(board,(96,1465),'设计展示 · 原生布局与材质以 App 呈现为准',18,muted)
    board.convert('RGB').save(ROOT/('深色预览.png' if dark else '浅色预览.png'),optimize=True)


def overview():
    board=Image.new('RGBA',(2240,2570),'#FAF6EB')
    txt(board,(91,63),'一册春天，四页风景。',76,'#383A31',True)
    txt(board,(97,174),'四个 Tab 各自成景  /  浅色与深色背景原图总览',25,'#75806B')
    for row,mode in enumerate(['light','dark']):
        y=280+row*1110
        for col,page in enumerate(PAGES):
            x=96+col*530
            txt(board,(x,y-39),f'{NAMES[col]} · {SCENES[col]}',25,'#A64635',True)
            paste(board,pic(f'background-{page}-{mode}.png',(456,912)),(x,y))
        txt(board,(96,y+935),'浅色 / 晨读' if row==0 else '深色 / 夜读',21,'#75806B')
    txt(board,(96,2455),'中央留白承载内容，边角插画陪伴阅读。',30,'#383A31',True)
    txt(board,(96,2511),'课本里的春天 · 简听阅读主题',20,'#75806B')
    board.convert('RGB').save(ROOT/'背景总览.png',optimize=True)


def main():
    for mode in ['light','dark']:
        mode_preview(mode)
    overview()
    print('Presentation images rendered.')


if __name__=='__main__':
    main()
