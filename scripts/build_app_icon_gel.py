"""从用户提供的 SVG 生成胶彩备用图标及开屏图层，保留渐变和滤镜。

用法：python scripts/build_app_icon_gel.py
依赖 Chrome 和 Pillow；可通过 CHROME_PATH 指定 Chrome。
"""

import base64
import copy
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/icon-design/app_icon_gel_source.svg'
MEDIA_DIRS = (
    ROOT / 'AppScope/resources/base/media',
    ROOT / 'entry/src/main/resources/base/media',
)
SVG_NS = 'http://www.w3.org/2000/svg'
SIZE = 1024


def main():
    chrome = Path(os.environ.get('CHROME_PATH', 'C:/Program Files/Google/Chrome/Application/chrome.exe'))
    ET.register_namespace('', SVG_NS)
    source = ET.fromstring(SOURCE.read_text(encoding='utf-8'))
    source.set('width', str(SIZE))
    source.set('height', str(SIZE))
    background = copy.deepcopy(source)
    foreground = copy.deepcopy(source)
    # 分层背景铺满画布，桌面的最终外形由系统蒙版决定。
    for child in list(background):
        if child.tag == f'{{{SVG_NS}}}rect':
            child.attrib.pop('rx', None)
        elif child.tag != f'{{{SVG_NS}}}defs':
            background.remove(child)
    for child in list(foreground):
        if child.tag == f'{{{SVG_NS}}}rect' and 'mask' not in child.attrib:
            foreground.remove(child)
    layers = {
        name: 'data:image/svg+xml;base64,' + base64.b64encode(ET.tostring(svg)).decode('ascii')
        for name, svg in (('background', background), ('foreground', foreground), ('legacy', source))
    }
    # 烘焙 SVG 渐变，避免设备 SVG 引擎把零宽高 line 的渐变解析成整条暗色。
    media = ROOT / 'entry/src/main/resources/base/media'
    for index in range(1, 5):
        svg = (ROOT / f'docs/icon-design/splash_gel_bar{index}.svg').read_bytes()
        layers[f'splash_gel_bar{index}'] = 'data:image/svg+xml;base64,' + base64.b64encode(svg).decode('ascii')
    glow = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 720" width="1024" height="1024">
      <defs><radialGradient id="glow"><stop offset="0" stop-color="#7B4DFF"/>
      <stop offset=".34" stop-color="#B45BE8"/><stop offset=".62" stop-color="#FF4FCB"/>
      <stop offset=".88" stop-color="#3FC3FF"/><stop offset="1" stop-color="#3FC3FF" stop-opacity="0"/>
      </radialGradient><filter id="blur" x="-100%" y="-100%" width="300%" height="300%">
      <feGaussianBlur stdDeviation="46"/></filter></defs>
      <circle cx="330" cy="324" r="150" fill="url(#glow)" filter="url(#blur)"/></svg>'''
    layers['splash_gel_glow'] = 'data:image/svg+xml;base64,' + base64.b64encode(glow.encode()).decode('ascii')
    html = '''<!doctype html><meta charset="utf-8"><pre id="exported-icons"></pre><script>
const sources = __SOURCES__;
(async () => {
  const output = {};
  for (const [name, url] of Object.entries(sources)) {
    const image = new Image();
    image.src = url;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1024;
    canvas.getContext('2d').drawImage(image, 0, 0, 1024, 1024);
    output[name] = canvas.toDataURL('image/png');
  }
  document.getElementById('exported-icons').textContent = JSON.stringify(output);
})().catch(error => document.getElementById('exported-icons').textContent = String(error));
</script>'''.replace('__SOURCES__', json.dumps(layers))
    with tempfile.TemporaryDirectory(prefix='hsda-gel-') as temp:
        page = Path(temp) / 'export.html'
        page.write_text(html, encoding='utf-8')
        result = subprocess.run([
            str(chrome), '--headless', '--disable-gpu',
            '--user-data-dir=' + str(Path(temp) / 'chrome'),
            '--dump-dom', '--virtual-time-budget=5000', page.as_uri(),
        ], capture_output=True, timeout=60, check=True)
        match = re.search(r'<pre id="exported-icons">(.*?)</pre>', result.stdout.decode('utf-8'), re.S)
        if not match:
            raise RuntimeError('SVG 导出失败，未写入图标资源')
        exported = json.loads(match.group(1))
    images = {}
    for name in layers:
        image = Image.open(io.BytesIO(base64.b64decode(exported[name].split(',', 1)[1]))).convert('RGBA')
        if image.size != (SIZE, SIZE) or image.getbbox() is None:
            raise ValueError(f'{name}: 图标尺寸或内容无效')
        images[name] = image
    if images['background'].getchannel('A').getextrema() != (255, 255):
        raise ValueError('桌面分层背景必须完整铺满')
    if images['foreground'].getchannel('A').getextrema() != (0, 255):
        raise ValueError('桌面前景必须保留透明区域和图标主体')
    for directory in MEDIA_DIRS:
        for name, image in images.items():
            if name.startswith('splash_'):
                if directory == media:
                    edge = 720 if name == 'splash_gel_glow' else 420
                    image.resize((edge, edge), Image.Resampling.LANCZOS).save(directory / f'{name}.png', optimize=True)
                continue
            image.save(directory / f'app_icon_gel_{name}.png', optimize=True)
        descriptor = {'layered-image': {
            'background': '$media:app_icon_gel_background',
            'foreground': '$media:app_icon_gel_foreground',
        }}
        (directory / 'app_icon_gel.json').write_text(
            json.dumps(descriptor, indent=2) + '\n', encoding='utf-8')
    print('gel: 1024x1024 background / foreground / legacy exported to both resource scopes')


if __name__ == '__main__':
    main()
