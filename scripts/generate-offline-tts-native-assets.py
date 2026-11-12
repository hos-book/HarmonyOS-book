"""Generate the native archive allowlist from the application-owned pinned spec."""
import argparse
import json
import re
from pathlib import Path


def read_models(spec, piper_spec):
    data = json.loads(spec.read_text(encoding='utf-8'))
    if data.get('appModelId') != 'kokoro-int8-v1_1' or data.get('modelId') != 'kokoro-int8-multi-lang-v1_1':
        raise ValueError('Unsupported offline TTS model')
    if len(data['files']) != 364 or sum(item['bytes'] for item in data['files']) != 194288036:
        raise ValueError('Unexpected pinned offline TTS asset budget')
    models = [(data['appModelId'], data['modelId'], data['files'])]
    if piper_spec is not None:
        piper = json.loads(piper_spec.read_text(encoding='utf-8'))
        expected = {
            'piper-chaowen-int8-v1': ('vits-piper-zh_CN-chaowen-medium-int8', 20933252),
            'piper-xiaoya-int8-v1': ('vits-piper-zh_CN-xiao_ya-medium-int8', 20933412),
        }
        if piper.get('schemaVersion') != 1 or len(piper.get('models', [])) != len(expected):
            raise ValueError('Invalid Piper model catalog')
        seen = set()
        for model in piper['models']:
            model_id = model['appModelId']
            if model_id not in expected or model_id in seen:
                raise ValueError('Unexpected Piper model')
            archive_root, budget = expected[model_id]
            if (model['archiveRoot'] != archive_root or len(model['files']) != 8
                    or sum(item['bytes'] for item in model['files']) != budget):
                raise ValueError('Unexpected pinned Piper asset budget')
            seen.add(model_id)
            models.append((model_id, archive_root, model['files']))
    return models


def asset_rows(files):
    seen = set()
    rows = []
    for item in files:
        name, size = item['path'], item['bytes']
        if (not name or name in seen or name.startswith('/') or '\\' in name or ':' in name
                or any(part in ('', '.', '..') for part in name.split('/'))
                or len(name) > 256 or any(ord(c) < 32 or ord(c) > 126 for c in name)
                or not isinstance(size, int) or size <= 0 or size > 128 * 1024 * 1024
                or re.fullmatch('[0-9a-f]{64}', item['sha256']) is None):
            raise ValueError('Invalid pinned archive path or size')
        seen.add(name)
        rows.append('  {' + json.dumps(name) + ', ' + str(size) + 'ULL},')
    return '\n'.join(rows)


def generate(spec, piper_spec, output):
    models = read_models(spec, piper_spec)
    arrays = []
    entries = []
    for index, (model_id, archive_root, files) in enumerate(models):
        symbol = f'OFFLINE_TTS_NATIVE_ASSETS_{index}'
        arrays.append(f'static constexpr OfflineTtsNativeAsset {symbol}[] = {{\n'
                      + asset_rows(files) + '\n};\n')
        entries.append('  {' + json.dumps(model_id) + ', ' + json.dumps(archive_root)
                       + ', ' + symbol + ', ' + str(len(files)) + ', '
                       + str(sum(item['bytes'] for item in files)) + 'ULL},')
    content = ('// Generated from the application-owned offline TTS asset specs. Do not edit.\n'
               '#pragma once\n#include <cstddef>\n#include <cstdint>\n'
               'struct OfflineTtsNativeAsset { const char *name; uint64_t bytes; };\n'
               'struct OfflineTtsNativeModel {\n'
               '  const char *id; const char *archiveRoot; const OfflineTtsNativeAsset *assets;\n'
               '  size_t count; uint64_t bytes;\n};\n'
               + '\n'.join(arrays)
               + 'static constexpr OfflineTtsNativeModel OFFLINE_TTS_NATIVE_MODELS[] = {\n'
               + '\n'.join(entries) + '\n};\n')
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists() or output.read_text(encoding='utf-8') != content:
        output.write_text(content, encoding='utf-8', newline='\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--piper-spec', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    generate(args.spec, args.piper_spec, args.output)
