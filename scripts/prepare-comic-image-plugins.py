"""Prepare the two independently imported comic image plugins."""

import argparse
import base64
import json
import subprocess
from pathlib import Path
from urllib.parse import urljoin


def download(address):
    return subprocess.run(
        ['curl', '--location', '--http1.1', '--max-time', '60', '--fail', '--silent', '--show-error', address],
        check=True, stdout=subprocess.PIPE,
    ).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'artifacts/plugins')
    parser.add_argument('--release-base', default='https://github.com/honjow/koma-sources/releases/download/image-plugins-v1/')
    args = parser.parse_args()
    catalog = json.loads(download(urljoin(args.release_base, 'index.json')))
    args.output.mkdir(parents=True, exist_ok=True)
    for plugin_id in ('comic-watermarks', 'edge-banners'):
        entry = next(pack for pack in catalog['packs'] if pack['id'] == plugin_id)
        manifest_url = urljoin(args.release_base, entry['path'])
        manifest = json.loads(download(manifest_url))
        wasm = download(urljoin(manifest_url, manifest['processor']['path']))
        package = {
            'format': 1, 'id': plugin_id, 'version': manifest['version'],
            'abi': manifest['processor']['abi'],
            'parameters': json.dumps(manifest.get('parameters', {}), ensure_ascii=False, separators=(',', ':')),
            'wasm': base64.b64encode(wasm).decode('ascii'),
        }
        path = args.output / f'{plugin_id}.jtplugin'
        path.write_text(json.dumps(package, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
        print(f'{plugin_id} v{manifest["version"]}: {path}')


if __name__ == '__main__':
    main()
