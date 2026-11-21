"""Generate 7 phone AppGallery posters (1080x1920, 9:16, JPG only).

Rules for this revision:
- No notch / camera pill on the mockup.
- The full real screenshot is shown (contain-fit, no bottom truncation),
  placed on a soft matching backdrop inside a clean rounded frame.
- Only JPG output, under the 5 MB AppGallery limit.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[4]
POSTERS = Path(__file__).resolve().parent
OUT = POSTERS
GALLERY = ROOT / "docs" / "app-gallery"
RAW = Path(r"D:\QQ\screenshot_20261121_154127_com.huan.listenbook.jpg等14项文件")

W, H = 1080, 1920
FONT_REGULAR = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"

INK = "#202124"
MUTED = "#737478"
ROSE = "#BD455E"
LINE = "#E8E0DF"

FILES = {
    1: "screenshot_20261121_153807_com.huan.listenbook (1).jpg",
    2: "screenshot_20261121_153810_com.huan.listenbook (1).jpg",
    3: "screenshot_20261121_153814_com.huan.listenbook (1).jpg",
    4: "screenshot_20261121_153819_com.huan.listenbook (1).jpg",
    8: "screenshot_20261121_153853_com.huan.listenbook (1).jpg",
    9: "screenshot_20261121_153902_com.huan.listenbook (1).jpg",
    12: "screenshot_20261121_153930_com.huan.listenbook.jpg",
    13: "screenshot_20261121_154123_com.huan.listenbook (1).jpg",
}

POSTER_SCENES = [
    {"src_idx": 1, "kicker": "首页  /  推荐与榜单", "first": "好故事", "second": "一眼就遇见",
     "note": "首页推荐、分类与榜单，发现想听想读的内容。", "chips": ["推荐榜单", "分类浏览"], "bg": "#FBF7F5"},
    {"src_idx": 2, "kicker": "书架  /  分组整理", "first": "我的书房", "second": "自己归置",
     "note": "最近阅听与分组书架，内容收进一处。", "chips": ["分组书架", "继续阅读"], "bg": "#F8F7F5"},
    {"src_idx": 3, "kicker": "书架  /  有声与阅读", "first": "有声电子书", "second": "同架收藏",
     "note": "有声书、电子书与漫画，收进同一个书架。", "chips": ["多格式", "进度续读"], "bg": "#F9F6F5"},
    {"src_idx": 4, "kicker": "记录  /  阅听足迹", "first": "阅听记录", "second": "一目了然",
     "note": "累计与连续阅听统计，足迹按时间留存。", "chips": ["阅读统计", "历史足迹"], "bg": "#F7F5F8"},
    {"src_idx": 8, "kicker": "收听  /  跟随你的节奏", "first": "戴上耳机", "second": "故事即刻开始",
     "note": "倍速、定时与续播，锁屏后也能继续听。", "chips": ["倍速调节", "睡眠定时"], "bg": "#F6F7F4"},
    {"src_idx": 9, "kicker": "阅读  /  每一页都舒适", "first": "静心阅读", "second": "调成喜欢的样子",
     "note": "字号、行距、背景与翻页方式，都由你决定。", "chips": ["阅读主题", "位置恢复"], "bg": "#F9F6F5"},
    {"src_idx": 12, "kicker": "详情  /  点开一本书", "first": "内容详情", "second": "一目了然",
     "note": "封面、简介与章节，开始阅读或收听。", "chips": ["书籍详情", "开始阅读"], "bg": "#F7F5F8"},
    {"src_idx": 13, "kicker": "漫画  /  连续翻页", "first": "漫画也能", "second": "一屏读到尾",
     "note": "本地漫画导入阅读，连续翻页与进度记忆。", "chips": ["本地导入", "连续阅读"], "bg": "#F6F7F4"},
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def brand_bar(canvas: Image.Image, index: int) -> None:
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(GALLERY / "icon.png").convert("RGB").resize((72, 72), Image.Resampling.LANCZOS)
    canvas.paste(icon, (80, 70))
    draw.text((172, 78), "简听阅读", fill=INK, font=font(38, True))
    draw.text((174, 128), "随心收听，静心阅读", fill=MUTED, font=font(24))
    draw.text((852, 86), f"{index:02d} / {len(POSTER_SCENES):02d}", fill=ROSE, font=font(28, True))
    draw.line((80, 176, 1000, 176), fill=LINE, width=2)


def headline(canvas: Image.Image, scene: dict) -> None:
    draw = ImageDraw.Draw(canvas)
    y = 224
    draw.text((80, y), scene["kicker"], fill=ROSE, font=font(26, True))
    draw.text((76, y + 46), scene["first"], fill=INK, font=font(78, True))
    draw.text((76, y + 134), scene["second"], fill=ROSE, font=font(78, True))
    draw.text((82, y + 252), scene["note"], fill=MUTED, font=font(28))
    cx = 82
    cy = y + 308
    for label in scene["chips"]:
        tw = draw.textlength(label, font=font(25))
        draw.rounded_rectangle((cx, cy, cx + tw + 48, cy + 52), radius=26, fill="#FFFFFF",
                               outline=LINE, width=1)
        draw.text((cx + 24, cy + 13), label, fill=INK, font=font(25))
        cx += tw + 72


def background_blobs(canvas: Image.Image) -> None:
    soft = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(soft)
    d.ellipse((-180, 700, 520, 1400), fill=(189, 69, 94, 22))
    d.ellipse((720, 300, 1320, 1000), fill=(120, 110, 190, 22))
    canvas.alpha_composite(soft.filter(ImageFilter.GaussianBlur(90)))


def phone_mockup(canvas: Image.Image, source: Path) -> None:
    """Draw a real phone body (dark bezel, side keys) with NO notch.

    The screen window is sized to the screenshot's own aspect ratio, so the
    whole capture fits edge to edge: no cropping and no letterbox bars.
    """
    shot = Image.open(source).convert("RGB")
    bezel = 16
    screen_h = 1142
    screen_w = round(screen_h * shot.width / shot.height)
    phone_w = screen_w + bezel * 2
    phone_h = screen_h + bezel * 2
    fx = (W - phone_w) // 2
    fy = 604
    outer_r = 58
    screen_r = 46

    # ambient shadow
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (fx + 18, fy + 30, fx + phone_w - 18, fy + phone_h + 42),
        radius=outer_r, fill=(32, 28, 28, 70))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(34)))

    # contact shadow directly under the device
    ground = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(ground).rounded_rectangle(
        (fx + 40, fy + phone_h - 10, fx + phone_w - 40, fy + phone_h + 22),
        radius=24, fill=(30, 26, 26, 60))
    canvas.alpha_composite(ground.filter(ImageFilter.GaussianBlur(16)))

    draw = ImageDraw.Draw(canvas)

    # side keys (right edge: power, left edge: volume) — phone silhouette cue
    key = "#2A2E30"
    draw.rounded_rectangle((fx + phone_w - 4, fy + 232, fx + phone_w + 3, fy + 322), radius=4, fill=key)
    draw.rounded_rectangle((fx + phone_w - 4, fy + 348, fx + phone_w + 3, fy + 438), radius=4, fill=key)
    draw.rounded_rectangle((fx - 3, fy + 250, fx + 4, fy + 340), radius=4, fill=key)
    draw.rounded_rectangle((fx - 3, fy + 356, fx + 4, fy + 446), radius=4, fill=key)

    # device body: dark metal bezel, no notch, no camera cutout
    draw.rounded_rectangle((fx, fy, fx + phone_w, fy + phone_h), radius=outer_r, fill="#1B1E20")
    draw.rounded_rectangle((fx + 2, fy + 2, fx + phone_w - 2, fy + phone_h - 2),
                           radius=outer_r - 2, outline="#3A4043", width=2)
    # inner bezel lip
    draw.rounded_rectangle((fx + bezel - 1, fy + bezel - 1,
                            fx + bezel + screen_w + 1, fy + bezel + screen_h + 1),
                           radius=screen_r, outline="#0F1112", width=2)

    # screen: exact aspect fit, fully visible
    shot = shot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_w, screen_h), radius=screen_r, fill=255)
    canvas.paste(shot, (fx + bezel, fy + bezel), mask)

    # glass sheen along the top-left of the screen for a device feel
    sheen = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon(
        [(0, 0), (screen_w * 0.62, 0), (0, screen_h * 0.42)], fill=(255, 255, 255, 26))
    sheen = sheen.filter(ImageFilter.GaussianBlur(28))
    sheen.putalpha(Image.composite(sheen.getchannel("A"), Image.new("L", (screen_w, screen_h), 0), mask))
    canvas.alpha_composite(sheen, (fx + bezel, fy + bezel))


def footer(canvas: Image.Image, section: str) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.line((80, 1816, 1000, 1816), fill=LINE, width=2)
    draw.text((80, 1844), f"简听  /  {section}", fill=MUTED, font=font(24))
    draw.text((852, 1844), "JIAN TING", fill=ROSE, font=font(23, True))


def build(scene: dict, index: int) -> Image.Image:
    canvas = Image.new("RGBA", (W, H), scene["bg"])
    background_blobs(canvas)
    brand_bar(canvas, index)
    headline(canvas, scene)
    phone_mockup(canvas, RAW / FILES[scene["src_idx"]])
    footer(canvas, scene["kicker"].split("/")[0].strip())
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # remove old multi-format posters from previous revision
    for old in OUT.glob("*poster.*"):
        old.unlink()
    for i, scene in enumerate(POSTER_SCENES, 1):
        canvas = build(scene, i).convert("RGB")
        canvas.save(OUT / f"{i:02d}-poster.jpg", "JPEG", quality=90, optimize=True)
        print(f"poster {i}: {scene['kicker']}")
    for f in sorted(OUT.glob("*.jpg")):
        print(f.name, f"{f.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
