"""从已确认的离线 HTML 导出五款图标，避免预览与资源绘制逻辑分叉。

依赖 Chrome 和 Pillow。用法：python scripts/build_selected_app_icons.py
可用 CHROME_PATH 指定 Chrome 可执行文件。
"""
import base64
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('waveberry', 'waveorange', 'wavegraphite', 'wavepurple', 'waveclear')


def main():
    chrome = Path(os.environ.get('CHROME_PATH', 'C:/Program Files/Google/Chrome/Application/chrome.exe'))
    html = (ROOT / 'docs/icon-design/icon-selected-preview.html').read_text(encoding='utf-8')
    html = html.replace('function drawIcon(p) {', 'function drawIcon(p, part) {')
    html = html.replace('if(p.glass){drawGlassIcon(ctx);',
                        'if(p.glass){ctx.clearRect(0,0,1024,1024);if(part!=="background")drawGlassIcon(ctx);')
    html = html.replace(" const layer=document.createElement('canvas');",
                        ' if(part==="background")return canvas.toDataURL("image/png");'
                        'if(part==="foreground")ctx.clearRect(0,0,1024,1024);'
                        " const layer=document.createElement('canvas');")
    export = """
 const output=palettes.map(p=>({background:drawIcon(p,'background'),
   foreground:drawIcon(p,'foreground'),legacy:drawIcon(p)}));
 const result=document.createElement('pre');result.id='exported-icons';
 result.textContent=JSON.stringify(output);document.body.append(result);
"""
    html = html.replace('});select(4);', '});select(4);' + export)
    with tempfile.TemporaryDirectory(prefix='hsda-icon-export-') as tmp:
        page = Path(tmp) / 'export.html'
        page.write_text(html, encoding='utf-8')
        result = subprocess.run([str(chrome), '--headless', '--disable-gpu', '--no-sandbox',
                                 '--user-data-dir=' + str(Path(tmp) / 'chrome'),
                                 '--dump-dom', '--virtual-time-budget=5000', page.as_uri()],
                                capture_output=True, timeout=60, check=True)
        match = re.search(r'<pre id="exported-icons">(.*?)</pre>', result.stdout.decode('utf-8'), re.S)
        if not match:
            raise RuntimeError('HTML 图标导出失败，未写入任何资源')
        icons = json.loads(match.group(1))
    if len(icons) != len(NAMES):
        raise ValueError('预览必须恰好包含五款已确认图标')
    for name, layers in zip(NAMES, icons):
        for directory in ('AppScope/resources/base/media', 'entry/src/main/resources/base/media'):
            target = ROOT / directory
            for part, data in layers.items():
                image = Image.open(io.BytesIO(base64.b64decode(data.split(',', 1)[1]))).convert('RGBA')
                if image.size != (1024, 1024):
                    raise ValueError('图标尺寸不是 1024×1024')
                if name == 'waveclear' and part == 'background' and image.getchannel('A').getextrema() != (0, 0):
                    raise ValueError('透明玻璃背景不得带底色')
                image.save(target / f'app_icon_{name}_{part}.png', optimize=True)
            descriptor = {'layered-image': {
                'background': f'$media:app_icon_{name}_background',
                'foreground': f'$media:app_icon_{name}_foreground'}}
            (target / f'app_icon_{name}.json').write_text(json.dumps(descriptor, indent=2) + '\n', encoding='utf-8')
        print(f'{name}: foreground / background / legacy exported')


if __name__ == '__main__':
    from optimize_app_assets import optimize_icons
    main()
    optimize_icons()
