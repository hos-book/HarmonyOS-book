"""Write the complete Textbook Spring theme using the documented 135 fields."""

from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "theme-source"

LIGHT = {
    "background": "#F4EEDC",
    "surface": "#FCF8ED",
    "settingsBackground": "#F4EEDC",
    "profileMenuSurface": "#F2FCF8ED",
    "textPrimary": "#383A31",
    "textSecondary": "#6E7061",
    "textTertiary": "#858675",
    "iconPrimary": "#383A31",
    "iconSecondary": "#717B6C",
    "divider": "#267C8068",
    "appDivider": "#267C8068",
    "brand": "#A64635",
    "brandHover": "#963E30",
    "brandPressed": "#803326",
    "brandDisabled": "#66A64635",
    "brandSoft": "#1AA64635",
    "brandDark": "#78372D",
    "onBrand": "#FFFAEE",
    "controlFallback": "#F2FCF8ED",
    "controlTint": "#33FFF9E8",
    "stroke": "#558E927A",
    "shadow": "#10383A31",
    "homeTop": "#EAE6D1",
    "homeMid": "#F4EEDC",
    "homeBottom": "#F4EEDC",
    "statusScrim": "#66F4EEDC",
    "floatingMask": "#F4EEDC",
    "homeAccent": "#A64635",
    "homeAccentSoft": "#1AA64635",
    "homeControl": "#E6FCF8ED",
    "homeSurface": "#E6FCF8ED",
    "homeShadow": "#10383A31",
    "progressTrack": "#338EA398",
    "detailTop": "#30383A31",
    "detailMid": "#DDF4EEDC",
    "detailBottom": "#F4EEDC",
}

DARK = {
    "background": "#232B28",
    "surface": "#303A33",
    "settingsBackground": "#232B28",
    "profileMenuSurface": "#F2303A33",
    "textPrimary": "#E8DFC7",
    "textSecondary": "#B8B5A3",
    "textTertiary": "#929C8D",
    "iconPrimary": "#E8DFC7",
    "iconSecondary": "#ADB8A4",
    "divider": "#33A9B49F",
    "appDivider": "#33A9B49F",
    "brand": "#D99178",
    "brandHover": "#E5A28B",
    "brandPressed": "#BF7D66",
    "brandDisabled": "#66D99178",
    "brandSoft": "#22D99178",
    "brandDark": "#BD7964",
    "onBrand": "#232B28",
    "controlFallback": "#F2303A33",
    "controlTint": "#16E8DFC7",
    "stroke": "#44879B8A",
    "shadow": "#220F1713",
    "homeTop": "#2D3830",
    "homeMid": "#27312B",
    "homeBottom": "#232B28",
    "statusScrim": "#66232B28",
    "floatingMask": "#232B28",
    "homeAccent": "#D99178",
    "homeAccentSoft": "#22D99178",
    "homeControl": "#E6303A33",
    "homeSurface": "#E6303A33",
    "homeShadow": "#220F1713",
    "progressTrack": "#44879B8A",
    "detailTop": "#88232B28",
    "detailMid": "#DD232B28",
    "detailBottom": "#232B28",
}

SHELF_BUTTONS = (
    "search", "searchActive", "filter", "group", "groupActive",
    "groupManage", "import", "updates", "viewList", "viewCollection",
    "viewGrid", "add", "expand", "collapse", "close",
)
RECORD_BUTTONS = (
    "back", "filter", "filterActive", "excerpt", "history", "edit",
    "done", "locked",
)


def kebab(value):
    return re.sub(r"([a-z])([A-Z])", r"\1-\2", value).lower()


def mode_fields(mode, colors):
    fields = {f"color.{key}": value for key, value in colors.items()}
    for page in ("common", "home", "shelf", "record", "profile"):
        scene = "home" if page == "common" else page
        background = {
            "mode": "image",
            "image": f"assets/background-{scene}-{mode}.png",
            "color": colors["background"],
            "veil": "0",
            "blur": "0",
            "positionX": "50",
            "positionY": "50",
            "scale": "100",
        }
        fields.update({f"background.{page}.{key}": value
                       for key, value in background.items()})

    fields["background.profileCard"] = f"assets/profile-card-{mode}.png"
    fields["background.coverBackdrop"] = "false"

    for tab in ("home", "shelf", "record", "profile"):
        for state in ("normal", "selected"):
            fields[f"tab.{tab}.{state}"] = f"assets/tab-{tab}-{state}-{mode}.svg"
    fields["tab.normalColor"] = colors["textSecondary"]
    fields["tab.selectedColor"] = colors["brand"]

    for group, buttons in (("shelf", SHELF_BUTTONS), ("record", RECORD_BUTTONS)):
        for button in buttons:
            fields[f"button.{group}.{button}"] = (
                f"assets/button-{group}-{kebab(button)}-{mode}.png"
            )

    for icon in ("Search", "Filter", "Grid", "List", "ChevronRight"):
        fields[f"icon.{icon}"] = f"assets/icon-{kebab(icon)}-{mode}.svg"

    fields.update({
        "cover.placeholder": f"assets/cover-default-{mode}.png",
        "cover.localPlaceholder": f"assets/cover-local-{mode}.png",
        "cover.playerPlaceholder": f"assets/cover-player-{mode}.png",
        "cover.title": colors["textPrimary"],
        "cover.localTitle": colors["textPrimary"],
        "cover.author": colors["textSecondary"],
        "cover.authorBackground": "#00000000",
        "cover.label": "#CCA64635" if mode == "light" else "#CC834C3D",
        "cover.edge": "#A6AB93" if mode == "light" else "#76866E",
        "cover.decoration": "1",
        "cover.illustratedPlaceholder": "true",
        "background.player.mode": "image",
        "background.player.image": f"assets/player-{mode}.png",
        "background.player.color": "#293D37" if mode == "light" else "#182921",
        "background.player.veil": "18",
        "background.player.blur": "0",
        "background.player.positionX": "50",
        "background.player.positionY": "50",
        "background.player.scale": "100",
    })
    return [{"key": key, "value": value} for key, value in fields.items()]


def main():
    PACKAGE.mkdir(parents=True, exist_ok=True)
    manifest = {"format": "jianting.theme", "schemaVersion": 1, "theme": "theme.json"}
    theme = {
        "format": "jianting.theme",
        "schemaVersion": 1,
        "id": "custom-textbook-spring",
        "name": "课本里的春天",
        "description": "米白纸页、朱红批注与青绿山水；春日学堂、书窗竹影、纸页钢笔、庭院藏书，四页各成一景。",
        "baseThemeId": "default",
        "materialStyle": 4,
        "verticalBottomTabs": False,
        "light": mode_fields("light", LIGHT),
        "dark": mode_fields("dark", DARK),
    }
    for name, document in (("manifest.json", manifest), ("theme.json", theme)):
        (PACKAGE / name).write_text(
            json.dumps(document, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(f"Theme written: {PACKAGE / 'theme.json'}")
    print(f"Mode fields: light={len(theme['light'])}, dark={len(theme['dark'])}")


if __name__ == "__main__":
    main()
