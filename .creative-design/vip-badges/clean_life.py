"""从原始金属素材重建轮廓，去掉中性背景和投影，保留封闭高光。"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parent
im = Image.open(root / 'vip_life_new.png').convert('RGB')
a = np.asarray(im).astype(int)
metal = (a.max(2)-a.min(2)>34) & (a[:,:,0]>a[:,:,2])
# 字母浅金色高光与背景色差较小，使用独立阈值保护笔画。
metal[:,1600:] = ((a.max(2)-a.min(2)>18) & (a[:,:,0]>a[:,:,2]))[:,1600:]
mask = Image.fromarray((metal*255).astype('uint8')).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
# 只让外部及三个真正的孔洞透明；金属内部的白色反光仍为实体。
work = mask.convert('RGB')
for seed in [(0,0),(690,730),(1350,720),(2250,810)]:
 ImageDraw.floodfill(work, seed, (255,0,255), thresh=0)
b = np.asarray(work)
alpha = Image.fromarray(np.where((b[:,:,0]==255)&(b[:,:,1]==0)&(b[:,:,2]==255),0,255).astype('uint8'))
alpha = alpha.filter(ImageFilter.GaussianBlur(3)).point(lambda x: 255 if x>=128 else 0)
alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
im.putalpha(alpha)
im = im.crop(im.getbbox())
pad = round(max(im.size)*0.08)
full = Image.new('RGBA',(im.width+2*pad,im.height+2*pad))
full.paste(im,(pad,pad))
# 保持既有完整标识画布尺寸，避免改变会员中心布局比例。
full = full.resize((2238,825),Image.Resampling.LANCZOS)
full.save(root/'vip_life_badge.png')
media=root.parents[1]/'entry/src/main/resources/base/media'
full.save(media/'vip_life_badge.png')
symbol=im.crop((0,0,1160,im.height))
symbol=symbol.crop(symbol.getbbox())
symbol=symbol.resize((512,229),Image.Resampling.LANCZOS)
symbol.save(media/'vip_life_symbol.png')
preview=Image.new('RGB',full.size,(35,35,35));preview.paste(full,mask=full.getchannel('A'))
preview.save(root/'_preview_life_clean.jpg')
print('full',full.size,'symbol',symbol.size)
