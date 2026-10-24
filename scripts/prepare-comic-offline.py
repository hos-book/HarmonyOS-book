"""Prepare pinned offline comic translation assets. Requires Python + requests.

Run before an App build: python scripts/prepare-comic-offline.py
Prepares bundled runtime only; --models downloads development models outside the
App resources (COMIC_MODEL_DIR overrides the temporary directory). Never uploads data.
"""
import base64
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import tarfile
import requests
import os
import argparse
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'entry/src/main/resources/rawfile/comic_offline'
MANIFEST = ROOT / 'scripts/comic-offline-assets.json'


def prepare_model(model, item):
    target = Path(os.environ.get('COMIC_MODEL_DIR', str(Path(tempfile.gettempdir()) / 'comic-translation-models'))) / model['id'] / item['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == item['sha256']:
        return model['id'] + '/' + item['path'] + ' verified'
    temporary = target.with_suffix(target.suffix + '.tmp')
    try:
        with requests.get('https://www.modelscope.cn/api/v1/models/' + model['model'] + '/repo/',
                          params={'Revision': model['revision'], 'FilePath': item['path']},
                          stream=True, timeout=(15, 45)) as response:
            response.raise_for_status()
            size = 0
            with temporary.open('wb') as stream:
                for block in response.iter_content(1024 * 1024):
                    size += len(block)
                    if size > item['size']:
                        raise ValueError('Asset exceeds pinned size')
                    stream.write(block)
        if temporary.stat().st_size != item['size'] or hashlib.sha256(temporary.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Asset checksum mismatch: ' + item['path'])
        temporary.replace(target)
        return model['id'] + '/' + item['path'] + ' downloaded'
    finally:
        temporary.unlink(missing_ok=True)


def main():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    DEST.mkdir(parents=True, exist_ok=True)
    parser = argparse.ArgumentParser()
    parser.add_argument('--models', action='store_true', help='Prepare development models outside the App resources')
    if parser.parse_args().models:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            for result in pool.map(lambda task: prepare_model(task[0], task[1]),
                                   [(model, item) for model in manifest['models'] for item in model['files']]):
                print(result, flush=True)
    runtime = manifest['runtime']
    if all((DEST / item['path']).exists() and
           hashlib.sha256((DEST / item['path']).read_bytes()).hexdigest() == item['sha256']
           for item in runtime['files']):
        print('Runtime verified')
        return
    response = requests.get(runtime['url'], timeout=(15, 60))
    response.raise_for_status()
    archive = response.content
    if base64.b64encode(hashlib.sha512(archive).digest()).decode() != runtime['sha512']:
        raise ValueError('Runtime archive checksum mismatch')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        for item in runtime['files']:
            data = tar.extractfile('package/' + item['source']).read()
            if hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Runtime file checksum mismatch')
            (DEST / item['path']).write_bytes(data)
    print('Offline comic translation assets ready')


if __name__ == '__main__':
    main()
