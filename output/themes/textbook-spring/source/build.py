"""Rebuild the editable theme and its importable package."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse

ROOT=Path(__file__).resolve().parents[1]


def pack():
    package=ROOT/'theme-source'
    output=ROOT/'课本里的春天.jttheme'
    with ZipFile(output,'w',compression=ZIP_DEFLATED) as archive:
        for name in ['manifest.json','theme.json']:
            archive.write(package/name,name)
        for file in sorted((package/'assets').iterdir()):
            archive.write(file,'assets/'+file.name)
    print(f'Exported: {output}')
    print(f'Size: {output.stat().st_size/1024/1024:.2f} MiB')


def main():
    parser=argparse.ArgumentParser(description='Build Textbook Spring artwork and package.')
    parser.add_argument('--pack-only',action='store_true')
    args=parser.parse_args()
    if args.pack_only:
        pack()
    else:
        import build_artwork
        import build_icons
        import build_theme
        import build_previews
        build_artwork.main()
        build_icons.build_icons()
        build_theme.main()
        build_previews.main()
        pack()


if __name__=='__main__':
    main()
