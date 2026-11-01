"""Render a CPU preview of the actual ArkTS rig vertices exported by test-jianjian-rig.cjs.

Usage: python scripts/preview-jianjian-rig.py path/to/mesh-frames.json
Pillow and NumPy are required only for this development preview, never in the App.
"""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

root=Path(__file__).resolve().parents[1]
path=Path(sys.argv[1])
data=json.loads(path.read_text())
w,h,cols,rows=(data[k] for k in ['width','height','columns','rows'])
art=np.asarray(Image.open(root/'entry/src/main/resources/base/media/jianjian_native_idle.png').convert('RGBA'))
left=np.asarray(Image.open(root/'entry/src/main/resources/base/media/jianjian_native_lid_left.png').convert('RGBA'))
right=np.asarray(Image.open(root/'entry/src/main/resources/base/media/jianjian_native_lid_right.png').convert('RGBA'))
uv=np.array([(x*w/cols,y*h/rows) for y in range(rows+1) for x in range(cols+1)])
triangles=[]
for y in range(rows):
    for x in range(cols):
        a=y*(cols+1)+x
        triangles.extend([(a,a+1,a+cols+1),(a+1,a+cols+2,a+cols+1)])
frames=[]
for i,positions in enumerate(data['frames']):
    image=Image.fromarray(art)
    if i in [20,21,40,41,42,43]: image=Image.alpha_composite(image,Image.fromarray(left))
    if i in [20,21]: image=Image.alpha_composite(image,Image.fromarray(right))
    texture=np.asarray(image,dtype='float32')
    vertices=np.array(positions).reshape(-1,2)+[32,16]
    canvas=np.zeros((h+32,w+64,4),dtype='uint8')
    for tri in triangles:
        indices=list(tri)
        p=vertices[indices]
        lo=np.maximum(np.floor(p.min(axis=0)).astype(int),0)
        hi=np.minimum(np.ceil(p.max(axis=0)).astype(int),[canvas.shape[1]-1,canvas.shape[0]-1])
        xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1))
        dx=xx+.5-p[0,0];dy=yy+.5-p[0,1]
        a=p[1]-p[0];b=p[2]-p[0];det=a[0]*b[1]-a[1]*b[0]
        s=(dx*b[1]-dy*b[0])/det;t=(a[0]*dy-a[1]*dx)/det
        inside=(s>=-1e-5)&(t>=-1e-5)&(s+t<=1.00001)
        if not inside.any(): continue
        src=uv[indices]
        sample=src[0]+s[inside,None]*(src[1]-src[0])+t[inside,None]*(src[2]-src[0])
        sx=np.clip(sample[:,0],0,w-1);sy=np.clip(sample[:,1],0,h-1)
        ix=sx.astype(int);iy=sy.astype(int);fx=(sx-ix)[:,None];fy=(sy-iy)[:,None]
        ix1=np.minimum(ix+1,w-1);iy1=np.minimum(iy+1,h-1)
        color=(texture[iy,ix]*(1-fx)+texture[iy,ix1]*fx)*(1-fy)+(texture[iy1,ix]*(1-fx)+texture[iy1,ix1]*fx)*fy
        canvas[yy[inside],xx[inside]]=color.clip(0,255).astype('uint8')
    output=Image.new('RGBA',(w+64,h+32),(245,240,238,255))
    output.alpha_composite(Image.fromarray(canvas))
    frames.append(output.convert('RGB'))
frames[0].save(path.parent/'jianjian-mesh-motion.gif',save_all=True,append_images=frames[1:],duration=83,loop=0)
sheet=Image.new('RGB',((w+64)*4,h+32),'white')
for col,i in enumerate([0,18,36,48]): sheet.paste(frames[i],(col*(w+64),0))
sheet.save(path.parent/'jianjian-mesh-poses.png')
print(path.parent/'jianjian-mesh-motion.gif')
