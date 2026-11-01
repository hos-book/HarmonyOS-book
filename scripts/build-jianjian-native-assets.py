"""Build registered eyelid overlays from the original Jianjian artwork (Pillow + NumPy).

This is a native 2D sprite asset pipeline, not a Cubism model exporter.
Original artwork and Live2D PSD/parts are never modified.
"""
from pathlib import Path
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '角色资产/简听娘-红色系列一-透明底.png'
MEDIA = ROOT / 'entry/src/main/resources/base/media'


def eyelid(source, box, reverse=False):
    x0, y0, x1, y1 = box
    w, h = x1-x0, y1-y0
    # Interpolate skin from the surrounding original pixels in a rounded eye mask.
    # Keeping the boundary fixed avoids flat rectangular skin-colour stickers.
    mask = Image.new('L', (w, h))
    draw = ImageDraw.Draw(mask)
    draw.polygon([(22,8),(w*.52,2),(w-26,18),(w-5,h*.4),
                  (w-3,h*.72),(w-22,h-8),(w*.45,h-2),(18,h-13),(3,h*.65),(5,h*.43)],fill=255)
    pixels=np.asarray(source.crop(box).convert('RGB')).astype('float32')
    region=np.asarray(mask)>0
    pixels[region]=np.median(pixels[-5:,:,:].reshape(-1,3),axis=0)
    inner=region[1:-1,1:-1]
    for _ in range(2200):
        average=(pixels[:-2,1:-1]+pixels[2:,1:-1]+pixels[1:-1,:-2]+pixels[1:-1,2:])*.25
        pixels[1:-1,1:-1][inner]=average[inner]
    patch = Image.fromarray(pixels.clip(0,255).astype('uint8')).convert('RGBA')
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    patch.putalpha(mask)
    draw = ImageDraw.Draw(patch)
    # A curved closed lid rather than flattening the full face or swapping portrait art.
    points=[]
    for u in np.linspace(0, 1, 100):
        points.append((18+u*(w-36), h*.51+24*np.sin(np.pi*u)))
    draw.line(points, fill=(94, 39, 47, 255), width=7, joint='curve')
    edge = points[-1] if reverse else points[0]
    direction = 1 if reverse else -1
    for dx, dy in [(12, -12), (18, -4)]:
        draw.line([edge,(edge[0]+direction*dx,edge[1]+dy)],fill=(94,39,47,255),width=5)
    layer=Image.new('RGBA',source.size)
    layer.alpha_composite(patch,(x0,y0))
    return layer


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--preview',type=Path)
    args=parser.parse_args()
    source=Image.open(SOURCE).convert('RGBA')
    bounds=source.getbbox()
    if bounds is None:
        raise ValueError('Original artwork is empty')
    width,height=bounds[2]-bounds[0],bounds[3]-bounds[1]
    size=(round(width*384/height),384)
    left=eyelid(source,(655,766,850,953))
    right=eyelid(source,(980,759,1176,950),True)
    for name,layer in [('jianjian_native_idle',source),('jianjian_native_lid_left',left),('jianjian_native_lid_right',right)]:
        layer.crop(bounds).resize(size,Image.Resampling.LANCZOS).save(MEDIA/(name+'.png'),optimize=True)
    if args.preview:
        args.preview.mkdir(parents=True,exist_ok=True)
        poses=[source,Image.alpha_composite(source,left),Image.alpha_composite(Image.alpha_composite(source,left),right)]
        sheet=Image.new('RGB',(size[0]*3,384),(245,240,238))
        for i,pose in enumerate(poses):
            pose=pose.crop(bounds).resize(size,Image.Resampling.LANCZOS)
            sheet.paste(pose,(i*size[0],0),pose)
        sheet.save(args.preview/'jianjian-native-poses.png')
        poses[-1].crop((620,700,1210,1030)).save(args.preview/'jianjian-closed-eyes-detail.png')
    print('Generated base and 2 registered RGBA overlays:',size,'source crop:',bounds)


if __name__=='__main__':
    main()
