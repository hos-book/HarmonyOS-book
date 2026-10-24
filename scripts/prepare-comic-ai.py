"""Build the pinned external engine into a HAR; never vendor its source into this project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from comic_ai_calibration_patch import apply_calibration_patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = json.loads((ROOT / 'scripts/comic-ai-package.json').read_text(encoding='utf-8'))
OUTPUT = ROOT / 'entry/libs/aiengine.har'
STAMP = OUTPUT.with_suffix('.har.json')


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def verify(path):
    with tarfile.open(path) as package:
        metadata = json.load(package.extractfile('package/oh-package.json5'))
        app = json.load(package.extractfile('package/src/main/module.json'))['app']
        if metadata['name'] != SPEC['name'] or metadata['version'] != SPEC['version']:
            raise ValueError('Unexpected AI package name/version')
        if metadata['compatibleSdkVersion'] != SPEC['compatibleSdkVersion']:
            raise ValueError('Unexpected AI package minimum API')
        if app['apiReleaseType'] != 'Release' or app['buildMode'] != 'release':
            raise ValueError('AI package must be built with a Release SDK in release mode')
        if app['targetAPIVersion'] % 1000 != SPEC['targetSdkVersion']:
            raise ValueError('Unexpected AI package target API')
        names = set(package.getnames())
        for abi in ['arm64-v8a', 'x86_64']:
            if f'package/libs/{abi}/libcomic_pixels.so' not in names:
                raise ValueError(f'Missing native AI library: {abi}')
        if 'package/Worker.d.ets' not in names:
            raise ValueError('Missing AI Worker package entry')
        patch = json.load(package.extractfile('package/src/main/resources/rawfile/comic-colorizer/host-integration.json'))
        if patch.get('patch') != SPEC['integrationPatch']:
            raise ValueError('Missing or unexpected NNRT calibration patch')
        if patch.get('performancePatch') != SPEC.get('performancePatch'):
            raise ValueError('Missing or unexpected comic performance patch')


def install(project):
    artifact = project / 'aiengine/build/default/outputs/default/aiengine.har'
    verify(artifact)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifact, OUTPUT.with_suffix('.har.pending'))
    OUTPUT.with_suffix('.har.pending').replace(OUTPUT)
    notice_dir = ROOT / 'entry/src/main/resources/rawfile/comic_ai_engine'
    notice_dir.mkdir(parents=True, exist_ok=True)
    for name in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md']:
        shutil.copyfile(project / name, notice_dir / name)
    stamp = dict(SPEC, sha256=sha256(OUTPUT), bytes=OUTPUT.stat().st_size)
    STAMP.write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Installed {SPEC["name"]} at {SPEC["revision"]}: {OUTPUT}')


def prepare_exports(project):
    # Apply reviewed deltas only in the external checkout; keep the app dependent on the HAR.
    path = project / 'aiengine/oh-package.json5'
    package = json.loads(path.read_text(encoding='utf-8'))
    package['oh-exports'] = ['./Index.ets', './Worker.ets']
    path.write_text(json.dumps(package, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if SPEC.get('performancePatch') != 'worker-reuse-native-io-v1':
        raise ValueError('Unknown comic performance patch')
    patch = ROOT / 'scripts/comic-ai-performance.patch'
    subprocess.run(['git', 'apply', '--check', '--whitespace=nowarn', str(patch)], cwd=project, check=True)
    subprocess.run(['git', 'apply', '--whitespace=nowarn', str(patch)], cwd=project, check=True)
    apply_calibration_patch(project, SPEC['integrationPatch'])
    marker = project / 'aiengine/src/main/resources/rawfile/comic-colorizer/host-integration.json'
    metadata = json.loads(marker.read_text(encoding='utf-8'))
    metadata['performancePatch'] = SPEC['performancePatch']
    marker.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')


def build():
    ide = Path(os.environ['DEVECO_HOME']).resolve()
    sdk = json.loads((ide / 'sdk/default/sdk-pkg.json').read_text(encoding='utf-8'))['data']
    if sdk['releaseType'] != 'Release':
        raise ValueError('DEVECO_HOME must point to a Release IDE')
    env = os.environ.copy()
    env['DEVECO_SDK_HOME'] = str(ide / 'sdk')
    env['JAVA_HOME'] = str(ide / 'jbr')
    env['PATH'] = str(ide / 'tools/node') + os.pathsep + env['PATH']
    # TemporaryDirectory is outside the app checkout and removes all downloaded engine source after use.
    with tempfile.TemporaryDirectory(prefix='hsda-ai-') as directory:
        temporary = Path(directory).resolve()
        archive = temporary / 'engine.zip'
        with archive.open('wb') as target:
            subprocess.run(['gh', 'api', f'repos/{SPEC["repository"]}/zipball/{SPEC["revision"]}'],
                           stdout=target, check=True, timeout=600)
        project = temporary / 'engine'
        project.mkdir()
        with zipfile.ZipFile(archive) as package:
            # Strip GitHub's long archive prefix to keep Windows native compiler paths short.
            for member in package.infolist():
                parts = Path(member.filename).parts[1:]
                if not parts:
                    continue
                target = project.joinpath(*parts).resolve()
                if not target.is_relative_to(project.resolve()):
                    raise ValueError('Invalid source archive path')
                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with package.open(member) as source, target.open('wb') as output:
                        shutil.copyfileobj(source, output)
        # Check the pinned upstream before applying our independently verified host calibration patch.
        subprocess.run([str(ide / 'tools/node/node.exe'), 'scripts/check.mjs'],
                       cwd=project, env=env, check=True, timeout=180)
        prepare_exports(project)
        subprocess.run([str(ide / 'tools/node/node.exe'), str(ROOT / 'scripts/test-comic-ai-package.mjs'), str(project)],
                       cwd=project, env=env, check=True, timeout=60)
        subprocess.run([str(ide / 'tools/node/node.exe'), str(ide / 'tools/ohpm/bin/pm-cli.js'), 'install', '--all'],
                       cwd=project, env=env, check=True, timeout=180)
        subprocess.run([str(ide / 'tools/node/node.exe'), str(ide / 'tools/hvigor/bin/hvigorw.js'),
                        '--mode', 'module', '-p', 'module=aiengine@default', '-p', 'product=default',
                        '-p', 'buildMode=release', 'assembleHar', '--no-daemon'],
                       cwd=project, env=env, check=True, timeout=600)
        install(project)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-build', type=Path, help='Install a previously built pinned engine project outside this checkout')
    parser.add_argument('--force', action='store_true', help='Rebuild even if the existing HAR matches its stamp')
    args = parser.parse_args()
    if args.from_build:
        install(args.from_build.resolve())
    elif not args.force and OUTPUT.exists() and STAMP.exists():
        stamp = json.loads(STAMP.read_text(encoding='utf-8'))
        if all(stamp.get(key) == value for key, value in SPEC.items()) and stamp.get('sha256') == sha256(OUTPUT):
            print('Pinned AI HAR is already prepared.')
        else:
            build()
    else:
        build()
