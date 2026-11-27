"""Draw the textbook theme's original SVG icons and raster paper-tag buttons.

Run with Python 3.11+ and resvg-py. SVG artwork stays editable beside this script.
"""

from pathlib import Path

from resvg_py import svg_to_bytes


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "theme-source" / "assets"
VECTORS = ROOT / "source" / "vectors"

PALETTES = {
    "light": {
        "ink": "#62675B", "brand": "#A64635", "soft": "#EEDCD0",
        "paper": "#FBF8EF", "edge": "#D1C8B3", "on_brand": "#FFF7E6",
        "fold": "#E8DFCA",
    },
    "dark": {
        "ink": "#B4BBA8", "brand": "#D99178", "soft": "#52413A",
        "paper": "#303B34", "edge": "#617160", "on_brand": "#232B28",
        "fold": "#465348",
    },
}


def svg_document(body, size=48):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 48 48">{body}</svg>\n'
    )


def lines(body, color, width=2.4):
    return (
        f'<g fill="none" stroke="{color}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-linejoin="round">{body}</g>'
    )


def tab_art(name, palette, selected):
    color = palette["brand"] if selected else palette["ink"]
    fill = palette["soft"] if selected else "none"
    drawings = {
        "home": (
            f'<path d="M9 23L24 10L39 23L36 24H12Z" fill="{fill}"/>'
            '<path d="M9 23L24 10L39 23M13 22V37H35V22M7 38H41"/>'
            '<path d="M21 37V28Q24 26 27 28V37M17 25V27M31 25V27"/>'
            '<path d="M24 10V6M24 6H32L29 9H24"/>'
        ),
        "shelf": (
            f'<rect x="8" y="12" width="8" height="25" rx="1.8" fill="{fill}"/>'
            f'<rect x="17" y="9" width="8" height="28" rx="1.8" fill="{fill}"/>'
            f'<path d="M27 14L34 12L40 35L33 37Z" fill="{fill}"/>'
            '<path d="M11 17H13M20 14H22M29 18L35 16M11 31H13M20 31H22"/>'
            '<path d="M6 39H42"/>'
        ),
        "record": (
            f'<path d="M11 8H31Q34 8 34 11V37Q34 40 31 40H11Q8 40 8 37V11Q8 8 11 8Z" fill="{fill}"/>'
            '<path d="M15 8V40M6 15H11M6 23H11M6 32H11M20 16H27M20 22H25"/>'
            f'<path d="M28 33L31 25L38 13Q39 11 41 13L42 14Q43 15 42 17L35 29Z" fill="{fill}"/>'
            '<path d="M31 25L35 29M37 16L41 19M28 33L29 30"/>'
        ),
        "profile": (
            f'<rect x="8" y="8" width="32" height="32" rx="5" fill="{fill}"/>'
            '<path d="M13 15V13H18M35 15V13H30M13 33V35H18M35 33V35H30"/>'
            '<circle cx="24" cy="20" r="5"/>'
            '<path d="M16 32Q16 27 24 27Q32 27 32 32"/>'
        ),
    }
    return lines(drawings[name], color)


SYMBOLS = {
    "search": '<circle cx="21" cy="21" r="11"/><path d="M29 29L39 39"/>',
    "filter": (
        '<path d="M8 13H19M25 13H40M8 24H29M35 24H40M8 35H13M19 35H40"/>'
        '<path d="M22 9V17M32 20V28M16 31V39"/>'
    ),
    "grid": (
        '<rect x="9" y="9" width="12" height="12" rx="2"/>'
        '<rect x="27" y="9" width="12" height="12" rx="2"/>'
        '<rect x="9" y="27" width="12" height="12" rx="2"/>'
        '<rect x="27" y="27" width="12" height="12" rx="2"/>'
    ),
    "list": (
        '<path d="M19 12H39M19 24H39M19 36H39"/>'
        '<rect x="8" y="9" width="5" height="6" rx="1"/>'
        '<rect x="8" y="21" width="5" height="6" rx="1"/>'
        '<rect x="8" y="33" width="5" height="6" rx="1"/>'
    ),
    "chevron-right": '<path d="M19 11L31 24L19 37"/>',
    "group": (
        '<path d="M8 15V12Q8 9 11 9H21L25 14H37Q40 14 40 17V34Q40 38 36 38H12Q8 38 8 34Z"/>'
        '<path d="M8 20H40M17 26V32M24 26V32M31 26V32"/>'
    ),
    "group-manage": (
        '<path d="M8 15V12Q8 9 11 9H21L25 14H37Q40 14 40 17V22M8 15V33Q8 37 12 37H22M8 20H38"/>'
        '<circle cx="33" cy="33" r="9"/><path d="M33 28V38M28 33H38"/>'
    ),
    "import": (
        '<path d="M24 7V29M16 21L24 29L32 21"/>'
        '<path d="M8 27V37Q8 40 11 40H37Q40 40 40 37V27M8 31H16L19 35H29L32 31H40"/>'
    ),
    "updates": (
        '<path d="M38 20A15 15 0 0 0 12 13L8 17M8 17V7M8 17H18"/>'
        '<path d="M10 28A15 15 0 0 0 36 35L40 31M40 31V41M40 31H30"/>'
    ),
    "collection": (
        '<path d="M7 8H41V40H7ZM7 25H41M13 12V21M19 11V21M25 14L28 21"/>'
        '<path d="M13 31H23M13 35H23M31 30V36M36 29V36"/>'
    ),
    "add": '<path d="M24 10V38M10 24H38"/>',
    "expand": '<path d="M11 18L24 31L37 18"/>',
    "collapse": '<path d="M11 30L24 17L37 30"/>',
    "close": '<path d="M13 13L35 35M35 13L13 35"/>',
    "back": '<path d="M29 10L15 24L29 38M16 24H40"/>',
    "excerpt": (
        '<path d="M15 9H37V39H11V15"/>'
        '<path d="M10 11Q6 14 7 19H14V13H8M21 11Q17 14 18 19H25V13H19"/>'
        '<path d="M17 26H31M17 32H28"/>'
    ),
    "history": (
        '<path d="M9 17A16 16 0 1 1 9 31M8 8V18H18"/>'
        '<path d="M25 14V25L32 29"/>'
    ),
    "edit": (
        '<path d="M10 30L30 10Q32 8 34 10L38 14Q40 16 38 18L18 38L8 40Z"/>'
        '<path d="M10 30L18 38M28 12L36 20M13 33L30 16M8 40L12 36"/>'
    ),
    "done": '<path d="M10 25L20 35L39 13"/>',
    "locked": (
        '<rect x="10" y="21" width="28" height="20" rx="4"/>'
        '<path d="M16 21V15A8 8 0 0 1 32 15V21M24 29V34"/>'
        '<circle cx="24" cy="28.5" r="1"/>'
    ),
}


BUTTONS = {
    "shelf": {
        "search": "search", "search-active": "search", "filter": "filter",
        "group": "group", "group-active": "group", "group-manage": "group-manage",
        "import": "import", "updates": "updates", "view-list": "list",
        "view-collection": "collection", "view-grid": "grid", "add": "add",
        "expand": "expand", "collapse": "collapse", "close": "close",
    },
    "record": {
        "back": "back", "filter": "filter", "filter-active": "filter",
        "excerpt": "excerpt", "history": "history", "edit": "edit",
        "done": "done", "locked": "locked",
    },
}


def button_art(symbol, palette, active):
    face = palette["brand"] if active else palette["paper"]
    edge = palette["brand"] if active else palette["edge"]
    ink = palette["on_brand"] if active else palette["ink"]
    fold = palette["on_brand"] if active else palette["fold"]
    plate = (
        f'<path d="M11 3H35L45 13V37Q45 45 37 45H11Q3 45 3 37V11Q3 3 11 3Z" '
        f'fill="{face}" stroke="{edge}" stroke-width="1.15"/>'
        f'<path d="M35 3V10Q35 13 38 13H45Z" fill="{fold}" '
        f'fill-opacity="{0.20 if active else 0.70}"/>'
        '<g transform="translate(9 9) scale(.625)">'
        + lines(SYMBOLS[symbol], ink, 2.8) + '</g>'
    )
    return svg_document(plate, 144)


def build_icons():
    ASSETS.mkdir(parents=True, exist_ok=True)
    VECTORS.mkdir(parents=True, exist_ok=True)
    total = 0
    for mode, palette in PALETTES.items():
        for name in ("home", "shelf", "record", "profile"):
            for state in ("normal", "selected"):
                filename = f"tab-{name}-{state}-{mode}.svg"
                art = svg_document(tab_art(name, palette, state == "selected"))
                (ASSETS / filename).write_text(art, encoding="utf-8")
                total += 1
        for name in ("search", "filter", "grid", "list", "chevron-right"):
            filename = f"icon-{name}-{mode}.svg"
            art = svg_document(lines(SYMBOLS[name], palette["ink"], 2.6))
            (ASSETS / filename).write_text(art, encoding="utf-8")
            total += 1
        for group, entries in BUTTONS.items():
            for name, symbol in entries.items():
                stem = f"button-{group}-{name}-{mode}"
                active = name.endswith("-active") or name == "done"
                art = button_art(symbol, palette, active)
                (VECTORS / f"{stem}.svg").write_text(art, encoding="utf-8")
                (ASSETS / f"{stem}.png").write_bytes(svg_to_bytes(svg_string=art))
                total += 1
    print(f"Created {total} theme assets: 16 Tab SVG, 10 function SVG, 46 button PNG.")


if __name__ == "__main__":
    build_icons()
