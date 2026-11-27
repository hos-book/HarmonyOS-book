"""Prepare the independent Shengqiao voice package using the local GitHub session."""

import argparse
import base64
import json
from pathlib import Path
import re
import subprocess


def source(path: str) -> str:
    return subprocess.run(
        ['gh', 'api', f'repos/zyt174/shengqiao-hap/contents/{path}',
         '-H', 'Accept: application/vnd.github.raw+json'],
        check=True, capture_output=True, encoding='utf-8', timeout=45,
    ).stdout


def voice_rows(text: str, array: str) -> list[dict]:
    body = re.search(r'export const ' + array + r'[^=]*=\s*\[([\s\S]*?)\n\];', text).group(1)
    rows = []
    for raw in re.findall(r'\{([^{}]+)\}', body):
        fields = dict(re.findall(r'(\w+)\s*:\s*\x27([^\x27]*)\x27', raw))
        row = {
            'key': fields['key'], 'name': fields['name'],
            'channel': 'huawei' if array == 'HUAWEI_VOICES' else 'edge',
            'sid': fields.get('sid', fields.get('voice', '')),
            'sampleRate': int(re.search(r'\bsr:\s*(\d+)', raw).group(1)) if 'sr:' in raw else 48000,
            'style': fields.get('style', ''),
            'vip': bool(re.search(r'\bvip:\s*true', raw)),
        }
        rows.append(row)
    return rows


def builtin_rows(text: str) -> list[dict]:
    body = re.search(r'export const BUILTIN_TIMBRES[^=]*=\s*\{([\s\S]*?)\n\};', text).group(1)
    return [
        {'key': 'cl_' + sid, 'name': name, 'channel': 'celia', 'sid': sid,
         'sampleRate': 16000, 'style': '', 'vip': False}
        for sid, name in re.findall(r"'([0-9]+)'\s*:\s*\[\s*'([^']+)'", body)
    ]


def main() -> None:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--output', type=Path, default=Path('artifacts/plugins/shengqiao.jtplugin'))
    output = args.parse_args().output
    config = source('entry/src/main/ets/model/config.ets')
    native = source('entry/src/main/cpp/napi_init.cpp')
    voices = source('entry/src/main/ets/model/voices.ets')
    celia = source('entry/src/main/ets/services/CeliaApi.ets')
    secrets = []
    key = [0x5A, 0x3C, 0x91, 0xE7, 0x2B, 0x6D, 0xF4, 0x18]
    for name in ['SK_SECRET', 'SK_TTS', 'SK_TOKEN', 'SK_CLIENT', 'SK_EDGE']:
        body = re.search(r'\b' + name + r'\[\]\s*=\s*"([^"]+)"', native).group(1).encode('utf-8')
        values = bytes(v ^ key[i % 8] ^ ((i * 31 + 7) & 255) for i, v in enumerate(body))
        secrets.append(base64.b64encode(values).decode('ascii'))
    for name in ['AK', 'SK']:
        body = re.search(r"\bconst " + name + r"\s*=\s*'([^']+)'", celia).group(1).encode('utf-8')
        values = bytes(v ^ key[i % 8] ^ ((i * 31 + 7) & 255) for i, v in enumerate(body))
        secrets.append(base64.b64encode(values).decode('ascii'))
    pack = {
        'format': 1, 'id': 'shengqiao', 'abi': 'shengqiao-tts-v1',
        'version': re.search(r"APP_VERSION\s*=\s*'([^']+)'", config).group(1),
        'secrets': secrets,
        'voices': builtin_rows(voices) + voice_rows(voices, 'HUAWEI_VOICES') + voice_rows(voices, 'EDGE_VOICES'),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{output}: version {pack["version"]}, {len(pack["voices"])} voices')


if __name__ == '__main__':
    main()
