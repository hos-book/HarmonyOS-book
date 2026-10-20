"""把生成的 JPEG 白底标识抠成透明 PNG：边缘泛洪去白底 + 内部封闭白洞镂空 + 裁边。"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from clean_counters import clean, SEEDS

d = r"D:\HSDA\.creative-design\vip-badges"
files = {
    "vip_month_new.png": "vip_month_badge.png",
    "vip_year_new.png": "vip_year_badge.png",
    "vip_life_new.png": "vip_life_badge.png",
}

MARKER = (255, 0, 255)


def label_components(mask):
    """两遍连通域（4 邻域），返回 label 图（0 为背景）。"""
    h, w = mask.shape
    parent = {}

    def find(x):
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:
            parent[x], x = root, parent[x]
        return root

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    labels = np.zeros((h, w), dtype=np.int32)
    next_id = 1
    ys, xs = np.where(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        up = labels[y - 1, x] if y > 0 else 0
        left = labels[y, x - 1] if x > 0 else 0
        if up == 0 and left == 0:
            labels[y, x] = next_id
            parent[next_id] = next_id
            next_id += 1
        elif up != 0 and left == 0:
            labels[y, x] = up
        elif up == 0 and left != 0:
            labels[y, x] = left
        else:
            labels[y, x] = up
            union(up, left)

    flat = labels.reshape(-1)
    for i in np.nonzero(flat)[0].tolist():
        flat[i] = find(flat[i])
    return labels.reshape(h, w)


for src, dst in files.items():
    im = Image.open(os.path.join(d, src)).convert("RGB")
    w, h = im.size

    # 外围加 1px 白边，保证外部背景连通，从 (0,0) 一次泛洪即可
    work = Image.new("RGB", (w + 2, h + 2), (255, 255, 255))
    work.paste(im, (1, 1))
    ImageDraw.floodfill(work, (0, 0), MARKER, thresh=54)

    arr = np.array(work).astype(np.int32)
    marked = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)

    # 仅纯白中性色才视为封闭白洞（如∞环洞、P 字 counter）；
    # 金属高光偏暖/偏紫，饱和度差更大，必须保留
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    near_white = (mx > 252) & ((mx - mn) < 5)
    holes = near_white & ~marked

    if holes.any():
        lab = label_components(holes)
        counts = np.bincount(lab.ravel())
        big = counts >= 800
        big[0] = False
        holes = big[lab]

    bg = marked | holes
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8), mode="L")
    # 腐蚀 1px 去掉 JPEG 边缘白色毛刺，再轻微羽化
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.5))

    rgba = work.convert("RGBA")
    rgba.putalpha(alpha)

    rgba = rgba.crop((1, 1, w + 1, h + 1))
    bbox = rgba.getbbox()
    rgba = rgba.crop(bbox)
    cw, ch = rgba.size
    px = int(max(cw, ch) * 0.08)
    canvas = Image.new("RGBA", (cw + px * 2, ch + px * 2), (0, 0, 0, 0))
    canvas.paste(rgba, (px, px), rgba)
    canvas = clean(canvas, SEEDS[dst.split('_')[1]])
    canvas.save(os.path.join(d, dst))
    a = np.asarray(canvas.split()[-1])
    print(dst, canvas.size, "transparent_ratio=%.3f" % (a == 0).mean())
