"""生成 1024×1024 分层应用图标。运行：python scripts/generate_app_icon.py

依赖 Pillow。用几何路径重绘现有四色斜条，避免放大旧位图产生模糊。
前景保留原构图；背景完全不透明、铺满画布，不添加边框或圆角蒙版。
"""

from math import hypot
from pathlib import Path

from PIL import Image, ImageDraw
from optimize_app_assets import optimize_icons


ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SUPERSAMPLE = 4
DESIGN_SIZE = 216
# 原图设计坐标：起点、终点、半径、颜色。
BARS = (
    ((87.5, 53.5), (59.0, 82.0), 9.5, (139, 92, 246, 255)),
    ((130.0, 60.5), (66.0, 124.5), 9.5, (249, 115, 22, 255)),
    ((144.0, 96.5), (103.0, 137.5), 9.5, (250, 204, 21, 255)),
    ((160.0, 130.5), (136.0, 154.5), 9.5, (139, 92, 246, 102)),
)
MEDIA_DIRS = (
    ROOT / "AppScope/resources/base/media",
    ROOT / "entry/src/main/resources/base/media",
)


def make_foreground():
    scale = SIZE * SUPERSAMPLE / DESIGN_SIZE
    canvas = Image.new("RGBA", (SIZE * SUPERSAMPLE,) * 2, (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    for start, end, radius, color in BARS:
        x1, y1 = (coordinate * scale for coordinate in start)
        x2, y2 = (coordinate * scale for coordinate in end)
        radius *= scale
        length = hypot(x2 - x1, y2 - y1)
        nx, ny = -(y2 - y1) / length * radius, (x2 - x1) / length * radius
        draw.polygon(
            [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny),
             (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)],
            fill=color,
        )
        for x, y in ((x1, y1), (x2, y2)):
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    foreground = make_foreground()
    background = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    legacy = Image.alpha_composite(background, foreground)
    for media_dir in MEDIA_DIRS:
        for layer, bitmap in (("foreground", foreground), ("background", background), ("legacy", legacy)):
            path = media_dir / f"app_icon_{layer}.png"
            bitmap.save(path, optimize=True)
            print(f"{path.relative_to(ROOT)}: {bitmap.width}x{bitmap.height}")


if __name__ == "__main__":
    main()
    optimize_icons()
