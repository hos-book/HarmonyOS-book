"""保留 1024px 桌面图层，复用相同图层并将独立应用内预览限制为 512px。

图标生成脚本会调用 optimize_icons()；也可直接运行本脚本。
设计源图和 AGC 导出不参与处理，PNG 保留原色及透明度。
"""

import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MEDIA_DIRS = (
    ROOT / 'AppScope/resources/base/media',
    ROOT / 'entry/src/main/resources/base/media',
)
REUSED_PREVIEWS = ('cartoon', 'clay', 'enamel', 'ink', 'leather', 'origami', 'retro', 'waveclear')
LAYER_ALIASES = {'app_icon_wavepurple_foreground': 'app_icon_waveorange_foreground'}


def assert_identical(source, target):
    with Image.open(source) as original, Image.open(target) as shared:
        if original.size != shared.size or original.convert('RGBA').tobytes() != shared.convert('RGBA').tobytes():
            raise ValueError(f'{source.name} 已与 {target.name} 不同，请先更新图标预览/图层引用')


def optimize_icons():
    # 先核验全部待合并资源，防止设计更新后误把不同图片共用。
    for directory in MEDIA_DIRS:
        for name in REUSED_PREVIEWS:
            source = directory / f'app_icon_{name}_legacy.png'
            if source.exists():
                assert_identical(source, directory / f'app_icon_{name}_foreground.png')
        for alias, shared in LAYER_ALIASES.items():
            source = directory / f'{alias}.png'
            if source.exists():
                assert_identical(source, directory / f'{shared}.png')

    for directory in MEDIA_DIRS:
        before = sum(path.stat().st_size for path in directory.glob('app_icon*'))
        for alias, shared in LAYER_ALIASES.items():
            for descriptor in directory.glob('app_icon*.json'):
                original = descriptor.read_text(encoding='utf-8')
                updated = original.replace(f'$media:{alias}"', f'$media:{shared}"')
                if updated != original:
                    descriptor.write_text(updated, encoding='utf-8')
            (directory / f'{alias}.png').unlink(missing_ok=True)
        for name in REUSED_PREVIEWS:
            (directory / f'app_icon_{name}_legacy.png').unlink(missing_ok=True)
        for preview in directory.glob('app_icon*_legacy.png'):
            with Image.open(preview) as original:
                if max(original.size) <= 512:
                    continue
                image = original.copy()
            image.thumbnail((512, 512), Image.Resampling.LANCZOS)
            encoded = io.BytesIO()
            image.save(encoded, format='PNG', optimize=True)
            preview.write_bytes(encoded.getvalue())
        # 资源描述仍指向完整分层 PNG，桌面和发布检查继续使用 1024px。
        for descriptor in directory.glob('app_icon*.json'):
            layers = json.loads(descriptor.read_text(encoding='utf-8')).get('layered-image', {})
            for reference in layers.values():
                with Image.open(directory / (reference.removeprefix('$media:') + '.png')) as image:
                    if image.size != (1024, 1024):
                        raise ValueError(f'{descriptor.name}: 桌面图层必须为 1024×1024')
        after = sum(path.stat().st_size for path in directory.glob('app_icon*'))
        print(f'{directory.relative_to(ROOT)}: {before:,} -> {after:,} bytes (saved {before - after:,})')


if __name__ == '__main__':
    optimize_icons()
