"""Check SDK channel, compatibility and layered icons before publishing an APP/HAP."""

import argparse
import io
import json
import re
import struct
import zipfile
from pathlib import Path


def verify_hap(data, name, args):
    with zipfile.ZipFile(io.BytesIO(data)) as hap:
        app = json.loads(hap.read('module.json'))['app']
        summary = {key: app.get(key) for key in (
            'bundleName', 'versionName', 'versionCode', 'minAPIVersion',
            'targetAPIVersion', 'compileSdkVersion', 'apiReleaseType', 'buildMode', 'debug')}
        summary['module'] = name
        errors = []
        default_forms = []
        for resource in hap.namelist():
            if resource.startswith('resources/') and '/profile/' in resource and resource.endswith('.json'):
                profile = json.loads(hap.read(resource))
                for form in profile.get('forms', []):
                    if form.get('isDefault') is True:
                        default_forms.append(form.get('name', resource))
        summary['defaultForms'] = default_forms
        if len(default_forms) > 1:
            errors.append('Multiple default forms: ' + ', '.join(default_forms))
        if app.get('apiReleaseType') != 'Release':
            errors.append('SDK channel must be Release')
        if app.get('debug') is not False:
            errors.append('debug must be false')
        if app.get('buildMode') != 'release':
            errors.append('buildMode must be release')
        if app.get('bundleName') != 'com.huan.listenbook':
            errors.append('unexpected bundleName')
        if app.get('versionName') != args.version:
            errors.append('unexpected versionName')
        if app.get('versionCode') != args.version_code:
            errors.append('unexpected versionCode')
        # HarmonyOS stores the platform version prefix together with the API number.
        for field, expected in [('minAPIVersion', args.min_api), ('targetAPIVersion', args.target_api)]:
            value = app.get(field)
            if not isinstance(value, int) or value % 1000 != expected:
                errors.append(f'{field} must be API {expected}')
        for layer in ('foreground', 'background'):
            path = f'resources/base/media/app_icon_{layer}.png'
            if path not in hap.namelist():
                errors.append(f'missing {layer} icon')
                continue
            png = hap.read(path)
            if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or png[12:16] != b'IHDR':
                errors.append(f'invalid {layer} PNG')
                continue
            size = struct.unpack('>II', png[16:24])
            summary[f'{layer}Icon'] = list(size)
            if size != (1024, 1024):
                errors.append(f'{layer} icon must be 1024x1024')
        summary['errors'] = errors
        return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--version-code', required=True, type=int)
    parser.add_argument('--min-api', type=int, default=20)
    parser.add_argument('--target-api', type=int, default=26)
    parser.add_argument('--name-cache', type=Path,
                        help='SDK-generated name cache from this release build; checks dynamic source property compatibility')
    args = parser.parse_args()
    if args.package.suffix.lower() == '.app':
        with zipfile.ZipFile(args.package) as app:
            results = [verify_hap(app.read(name), name, args)
                       for name in app.namelist() if name.endswith('.hap')]
    elif args.package.suffix.lower() == '.hap':
        results = [verify_hap(args.package.read_bytes(), args.package.name, args)]
    else:
        parser.error('package must be an APP or HAP')
    if not results:
        parser.error('APP contains no HAP modules')
    if args.name_cache is not None:
        cache = json.loads(args.name_cache.read_text(encoding='utf-8'))
        properties = cache.get('PropertyCache', {})
        dynamic_exports = ['EpubParserService', 'createEpubReaderController', 'createEpubReaderBuilder',
                           'LocalRuleQuickJsRequest', 'LocalRuleQuickJsRuntime']
        renamed_exports = [name for name in dynamic_exports if properties.get(name, name) != name]
        if renamed_exports:
            for result in results:
                result['errors'].append('Obfuscation breaks dynamic module exports: ' + ', '.join(renamed_exports))
        source_root = Path(__file__).resolve().parents[1] / 'entry/src/main/ets'
        contracts = [
            'service/rulesource/light/upstream/core/nativesource/NativeSourceSpec.ts',
            'service/rulesource/LocalRuleRuntimeTypes.ets',
            'model/LocalRulePanel.ets',
        ]
        wire_names = set()
        for contract in contracts:
            wire_names.update(re.findall(r'^  (\w+)\??\s*:',
                                         (source_root / contract).read_text(encoding='utf-8'), re.MULTILINE))
        renamed = sorted(key for key, value in properties.items() if key in wire_names and key != value)
        if renamed:
            for result in results:
                result['errors'].append('Property obfuscation breaks dynamic source JSON/script contracts: ' +
                                        ', '.join(renamed[:12]))
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 1 if any(result['errors'] for result in results) else 0


if __name__ == '__main__':
    raise SystemExit(main())
