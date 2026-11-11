"""Build optional model packs: app-specific encrypted comic pack and subtitle ZIP."""
import argparse
import hashlib
import json
import os
import re
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from model_pack_key import load_key, key_id

ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = ROOT / 'artifacts/model-packs/v1'
CHUNK_BYTES = 4 * 1024 * 1024
PUNCTUATION = ROOT / 'entry/src/main/resources/rawfile/audio_subtitles/punctuation.int8.onnx'
ASR_BASE = ('https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03/'
            'resolve/ec0ba42ddef79fe0bd20c3563f14368f48e69a2c/')


def specifications():
    # Keep the application's allowlist as the single source of sizes and SHA256 values.
    source = (ROOT / 'entry/src/main/ets/model/AiModelPack.ets').read_text(encoding='utf-8')
    result = {}
    for pack in re.finditer(r"new AiModelPack\('([^']+)', '([^']+)', \[(.*?)\n  \]\)", source, re.S):
        assets = [dict(name=m[0], local=m[1], bytes=int(m[2]), sha256=m[3]) for m in re.findall(
            r"new AiModelAsset\('([^']+)', '([^']+)', (\d+),\s*'([a-f0-9]{64})'\)", pack[3])]
        if not assets:
            raise ValueError('Missing model assets: ' + pack[1])
        result[pack[1]] = dict(id=pack[1], directory=pack[2], assets=assets)
    if set(result) != {'comic-color-v1', 'audio-subtitle-v1'}:
        raise ValueError('Model catalog was not parsed completely')
    return result


def pack_path(pack):
    return PACK_DIR / ('Jianting-' + pack['id'] + ('.jtmodel' if encrypted(pack) else '.zip'))


def encrypted(pack):
    return pack['id'] == 'comic-color-v1'


def manifest(pack):
    value = dict(format=2 if encrypted(pack) else 1, id=pack['id'], chunkBytes=CHUNK_BYTES)
    if encrypted(pack):
        value.update(cipher='AES-256-GCM', keyId=key_id(load_key()))
    return value


def aad(pack, asset, index):
    return f"JiantingModelPack/v2/{pack['id']}/{asset['name']}/{index}".encode('utf-8')


def cipher_for(pack):
    if not encrypted(pack):
        return None
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    return AESGCM(load_key())


def license_text(pack):
    base = ROOT / 'entry/src/main/resources/rawfile'
    paths = sorted((base / 'comic_ai_engine').glob('*')) if pack['id'] == 'comic-color-v1' else [
        p for p in sorted((base / 'audio_subtitles').glob('*'))
        if p.is_file() and ('LICENSE' in p.name or p.suffix == '.md')]
    text = '\n\n'.join(p.name + '\n' + p.read_text(encoding='utf-8') for p in paths if p.is_file())
    if not text or len(text.encode('utf-8')) > 60000:
        raise ValueError('Missing or excessive model license text')
    return text


def check_stream(source, asset):
    digest, size = hashlib.sha256(), 0
    while chunk := source.read(CHUNK_BYTES):
        size += len(chunk)
        if size > asset['bytes']:
            raise ValueError('Model exceeds pinned size: ' + asset['name'])
        digest.update(chunk)
    if size != asset['bytes'] or digest.hexdigest() != asset['sha256']:
        raise ValueError('Model checksum mismatch: ' + asset['name'])


def verify_pack(path, pack):
    cipher = cipher_for(pack)
    with zipfile.ZipFile(path) as archive:
        if json.loads(archive.read('model-pack.json')) != manifest(pack):
            raise ValueError('Model pack manifest mismatch')
        expected = {'model-pack.json', 'LICENSE.txt'}
        if not archive.read('LICENSE.txt') or archive.getinfo('LICENSE.txt').file_size > 60000:
            raise ValueError('Missing model license')
        for asset in pack['assets']:
            digest = hashlib.sha256()
            for offset in range(0, asset['bytes'], CHUNK_BYTES):
                name = f"{asset['name']}/{offset // CHUNK_BYTES}.bin"
                expected.add(name)
                info = archive.getinfo(name)
                if info.file_size != min(CHUNK_BYTES, asset['bytes'] - offset) + (28 if cipher else 0):
                    raise ValueError('Model chunk size mismatch')
                chunk = archive.read(info)
                if cipher:
                    chunk = cipher.decrypt(chunk[:12], chunk[12:], aad(pack, asset, offset // CHUNK_BYTES))
                digest.update(chunk)
            if digest.hexdigest() != asset['sha256']:
                raise ValueError('Model pack checksum mismatch: ' + asset['name'])
        if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
            raise ValueError('Unexpected or duplicate model pack entries')


def write_pack(pack, open_asset):
    output = pack_path(pack)
    if output.exists():
        verify_pack(output, pack)
        print('Verified model pack:', output, flush=True)
        return output
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + '.part')
    cipher = cipher_for(pack)
    try:
        # STORE makes each bounded chunk readable without decompressing a full model into memory.
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('model-pack.json', json.dumps(manifest(pack)))
            archive.writestr('LICENSE.txt', license_text(pack))
            for asset in pack['assets']:
                digest = hashlib.sha256()
                with open_asset(asset) as source:
                    for offset in range(0, asset['bytes'], CHUNK_BYTES):
                        chunk = source.read(min(CHUNK_BYTES, asset['bytes'] - offset))
                        if len(chunk) != min(CHUNK_BYTES, asset['bytes'] - offset):
                            raise ValueError('Truncated model: ' + asset['name'])
                        digest.update(chunk)
                        if cipher:
                            nonce = os.urandom(12)
                            chunk = nonce + cipher.encrypt(nonce, chunk, aad(pack, asset, offset // CHUNK_BYTES))
                        archive.writestr(f"{asset['name']}/{offset // CHUNK_BYTES}.bin", chunk)
                    if source.read(1) or digest.hexdigest() != asset['sha256']:
                        raise ValueError('Model checksum mismatch: ' + asset['name'])
        verify_pack(temporary, pack)
        temporary.replace(output)
        print('Created model pack:', output, f'({output.stat().st_size / 2**20:.2f} MiB)', flush=True)
        return output
    finally:
        temporary.unlink(missing_ok=True)


def update_checksums():
    paths = sorted(p for p in PACK_DIR.iterdir() if p.suffix in ('.zip', '.jtmodel'))
    lines = []
    for path in paths:
        with path.open('rb') as source:
            lines.append(hashlib.file_digest(source, 'sha256').hexdigest() + '  ' + path.name)
    (PACK_DIR / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def comic_pack(har=None):
    pack = specifications()['comic-color-v1']
    output = pack_path(pack)
    # Never silently replace a lost key after distributing an encrypted package.
    load_key(create=not output.exists())
    if output.exists():
        verify_pack(output, pack)
    else:
        with tarfile.open(har or ROOT / 'entry/libs/aiengine.har') as archive:
            write_pack(pack, lambda asset: archive.extractfile(
                'package/src/main/resources/rawfile/comic-colorizer/' + asset['name']))
    # Superseded plaintext exports must not accompany the encrypted release.
    (PACK_DIR / 'Jianting-comic-color-v1.zip').unlink(missing_ok=True)
    update_checksums()
    return output


def externalize_har(path):
    """Only replace the HAR after the independent encrypted pack verifies completely."""
    comic_pack(path)
    temporary = path.with_suffix('.har.externalizing')
    try:
        with tarfile.open(path) as source:
            if not any(member.isfile() and member.name.endswith(('.ms', '.onnx', '.gguf')) for member in source):
                return
        with tarfile.open(path) as source, tarfile.open(temporary, 'w:gz', compresslevel=9) as target:
            for member in source:
                if member.isfile() and member.name.endswith(('.ms', '.onnx', '.gguf')):
                    continue
                target.addfile(member, source.extractfile(member) if member.isfile() else None)
        with tarfile.open(temporary) as archive:
            if any(member.isfile() and member.name.endswith(('.ms', '.onnx', '.gguf')) for member in archive):
                raise ValueError('Model weights remain in the HAR')
            # Keep engine bytecode, native libraries, metadata and licenses byte-for-byte.
            with tarfile.open(path) as original:
                before = [entry for entry in original if not (entry.isfile() and entry.name.endswith(('.ms', '.onnx', '.gguf')))]
                after = archive.getmembers()
                if [(entry.name, entry.size, entry.type) for entry in before] != [(entry.name, entry.size, entry.type) for entry in after]:
                    raise ValueError('Unexpected engine files changed during model export')
                for entry in before:
                    if entry.isfile():
                        with original.extractfile(entry) as a, archive.extractfile(entry.name) as b:
                            if hashlib.file_digest(a, 'sha256').digest() != hashlib.file_digest(b, 'sha256').digest():
                                raise ValueError('Engine file bytes changed during model export: ' + entry.name)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def download(url, target, asset):
    request = urllib.request.Request(url, headers={'User-Agent': 'Jianting-Model-Packs/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response, target.open('wb') as output:
        received = 0
        while block := response.read(1024 * 1024):
            received += len(block)
            if received > asset['bytes']:
                raise ValueError('Downloaded model exceeds pinned size')
            output.write(block)
            if received % (32 * 1024 * 1024) == 0:
                print(f"Downloading {asset['name']}: {received / 2**20:.0f} MiB", flush=True)
    with target.open('rb') as source:
        check_stream(source, asset)


def subtitle_pack():
    pack = specifications()['audio-subtitle-v1']
    output = pack_path(pack)
    if output.exists():
        write_pack(pack, lambda asset: None)
        PUNCTUATION.unlink(missing_ok=True)
        print('Verified subtitle model pack:', output, flush=True)
        return
    with tempfile.TemporaryDirectory(prefix='hsda-subtitle-pack-') as directory:
        temporary = Path(directory)
        for asset in pack['assets']:
            target = temporary / asset['name']
            if asset['name'] != 'punctuation.int8.onnx':
                download(ASR_BASE + asset['name'], target, asset)
            elif PUNCTUATION.exists():
                with PUNCTUATION.open('rb') as source:
                    check_stream(source, asset)
                shutil.copyfile(PUNCTUATION, target)
            else:
                url = ('https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/'
                       'sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2')
                archive = temporary / 'punctuation.tar.bz2'
                download(url, archive, dict(name='punctuation archive', bytes=64717756,
                    sha256='c0d5aa5f8eeb686032345e180bedf39319dc2e0556781c6264bcadba8328a6e1'))
                with tarfile.open(archive) as tar:
                    members = [m for m in tar.getmembers() if m.isfile() and m.name.endswith('/model.int8.onnx')]
                    if len(members) != 1 or members[0].size != asset['bytes']:
                        raise ValueError('Unexpected punctuation archive')
                    with tar.extractfile(members[0]) as source, target.open('wb') as out:
                        shutil.copyfileobj(source, out, CHUNK_BYTES)
                with target.open('rb') as source:
                    check_stream(source, asset)
        write_pack(pack, lambda asset: (temporary / asset['name']).open('rb'))
    PUNCTUATION.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--subtitle', action='store_true')
    parser.add_argument('--comic', action='store_true')
    args = parser.parse_args()
    if args.subtitle:
        subtitle_pack()
        update_checksums()
    if args.comic:
        comic_pack()
    if not args.subtitle and not args.comic:
        parser.error('Select --subtitle or --comic')


if __name__ == '__main__':
    main()
