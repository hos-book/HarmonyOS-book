"""Prepare the pinned punctuation model before building (Python 3, standard library)."""

import hashlib
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

URL = ('https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/'
       'sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2')
ARCHIVE_BYTES = 64717756
ARCHIVE_SHA256 = 'c0d5aa5f8eeb686032345e180bedf39319dc2e0556781c6264bcadba8328a6e1'
MODEL_BYTES = 75519198
MODEL_SHA256 = '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1'
MODEL = Path(__file__).resolve().parents[1] / 'entry/src/main/resources/rawfile/audio_subtitles/punctuation.int8.onnx'


def valid(path, size, digest):
    if not path.is_file() or path.stat().st_size != size:
        return False
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest() == digest


def main():
    if valid(MODEL, MODEL_BYTES, MODEL_SHA256):
        print('Punctuation model verified; no download needed.')
        return
    MODEL.parent.mkdir(parents=True, exist_ok=True)
    part = MODEL.with_suffix('.onnx.part')
    try:
        with tempfile.TemporaryDirectory(prefix='jianting-subtitle-') as temp:
            archive = Path(temp) / 'punctuation.tar.bz2'
            request = urllib.request.Request(URL, headers={'User-Agent': 'Jianting-Asset-Preparation/1.0'})
            with urllib.request.urlopen(request, timeout=60) as response, archive.open('wb') as output:
                received = 0
                while block := response.read(1024 * 1024):
                    received += len(block)
                    if received > ARCHIVE_BYTES:
                        raise ValueError('Punctuation archive exceeds pinned size')
                    output.write(block)
            if not valid(archive, ARCHIVE_BYTES, ARCHIVE_SHA256):
                raise ValueError('Punctuation archive checksum mismatch')
            with tarfile.open(archive, 'r:bz2') as package:
                members = [member for member in package.getmembers()
                           if member.isfile() and member.name.endswith('/model.int8.onnx')]
                if len(members) != 1 or members[0].size != MODEL_BYTES:
                    raise ValueError('Unexpected punctuation archive layout')
                # Read one bounded member; never extract archive-controlled filesystem paths.
                with package.extractfile(members[0]) as source, part.open('wb') as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
            if not valid(part, MODEL_BYTES, MODEL_SHA256):
                raise ValueError('Punctuation model checksum mismatch')
            part.replace(MODEL)
        print('Punctuation model downloaded and verified.')
    finally:
        part.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
