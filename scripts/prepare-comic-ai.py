"""Build the pinned external engine into a HAR; never vendor its source into this project."""
import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
import urllib.request
from comic_ai_calibration_patch import apply_calibration_patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = json.loads((ROOT / 'scripts/comic-ai-package.json').read_text(encoding='utf-8'))
OUTPUT = ROOT / 'entry/libs/aiengine.har'
STAMP = OUTPUT.with_suffix('.har.json')


def download_archive(revision, output):
    # Keep credentials in memory; urllib avoids gh's occasionally stalled archive stream on Windows.
    token = subprocess.check_output(['gh', 'auth', 'token'], timeout=30).decode().strip()
    request = urllib.request.Request(
        f'https://api.github.com/repos/{SPEC["repository"]}/zipball/{revision}',
        headers={'Authorization': 'Bearer ' + token, 'User-Agent': 'HSDA-package-builder'})
    with urllib.request.urlopen(request, timeout=60) as source, output.open('wb') as target:
        shutil.copyfileobj(source, target)


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def prepare_sources_from_existing_models(project):
    """Verify every file against the pinned Git tree while reusing identical bundled model bytes."""
    if not OUTPUT.exists():
        return False
    tree = json.loads(subprocess.check_output([
        'gh', 'api', f'repos/{SPEC["repository"]}/git/trees/{SPEC["revision"]}?recursive=1'], timeout=60))
    if tree.get('truncated'):
        raise ValueError('Cannot verify a truncated AI source tree')
    files = [entry for entry in tree['tree'] if entry['type'] == 'blob']
    models = [entry for entry in files if entry['path'].startswith('models/comic-colorizer/') and entry['path'].endswith('.ms')]
    if not models or any(entry['size'] > 8 * 1024 * 1024 for entry in files if entry not in models):
        return False

    def destination(entry):
        target = (project / entry['path']).resolve()
        if not target.is_relative_to(project.resolve()) or entry['mode'] not in ['100644', '100755']:
            raise ValueError('Invalid AI source tree entry')
        target.parent.mkdir(parents=True, exist_ok=True)
        return target

    with tarfile.open(OUTPUT) as package:
        for entry in models:
            member = 'package/src/main/resources/rawfile/comic-colorizer/' + Path(entry['path']).name
            try:
                source = package.extractfile(member)
            except KeyError:
                return False
            digest = hashlib.sha1(f'blob {entry["size"]}\0'.encode(), usedforsecurity=False)
            copied = 0
            with source, destination(entry).open('wb') as target:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
                    copied += len(chunk)
                    target.write(chunk)
            if copied != entry['size'] or digest.hexdigest() != entry['sha']:
                return False

    token = subprocess.check_output(['gh', 'auth', 'token'], timeout=30).decode().strip()
    def fetch(entry):
        request = urllib.request.Request(
            f'https://api.github.com/repos/{SPEC["repository"]}/git/blobs/{entry["sha"]}',
            headers={'Authorization': 'Bearer ' + token, 'User-Agent': 'HSDA-package-builder'})
        for attempt in range(2):
            try:
                with urllib.request.urlopen(request, timeout=25) as response:
                    blob = json.load(response)
                break
            except (OSError, ValueError):
                if attempt:
                    raise
        if blob.get('encoding') != 'base64':
            raise ValueError('Unexpected AI source blob encoding')
        data = base64.b64decode(blob['content'])
        actual = hashlib.sha1(f'blob {len(data)}\0'.encode() + data, usedforsecurity=False).hexdigest()
        if len(data) != entry['size'] or actual != entry['sha']:
            raise ValueError('AI source blob does not match the pinned Git tree: ' + entry['path'])
        return entry, data

    print(f'Reusing {len(models)} verified model files; fetching {len(files) - len(models)} source files.', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for entry, data in pool.map(fetch, [entry for entry in files if entry not in models]):
            target = destination(entry)
            target.write_bytes(data)
            if entry['mode'] == '100755':
                target.chmod(0o755)
    print('AI sources and reused models match the pinned Git tree.', flush=True)
    return True


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
    prepare_bundled_models(project)
    if SPEC.get('performancePatch') == 'upstream-worker-reuse-native-io-v1':
        if SPEC['integrationPatch'] != 'upstream-fp32-nnrt-v1':
            raise ValueError('Unknown upstream calibration contract')
        # These patches were merged upstream. Its check.mjs plus our package regression
        # suite verify cancellation, worker reuse, native IO and FP32 fallback before build.
        marker = project / 'aiengine/src/main/resources/rawfile/comic-colorizer/host-integration.json'
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(json.dumps({'patch': SPEC['integrationPatch'],
                                     'performancePatch': SPEC['performancePatch']}, indent=2) + '\n', encoding='utf-8')
        return
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


def prepare_bundled_models(project):
    # The app has no Light Page account/OBS ticket service. Retain offline installation;
    # the new engine verifies these same pinned assets through the host copy callback.
    models = {
        'alac.ms': 'c212815a335a006b4bbf336af1c25c6158aaeac077f35f2775af381b83fe9934',
        'alac-npu-portrait.ms': 'db162d1620a560c86fe883484311133e11ba5e4b24790cefe355043f9928e3e0',
        'alac-npu-landscape.ms': '2abbc0e27cb1dbf859a835072c4c7f06982e70cd0e57ff401008501b33ce40fd'
    }
    destination = project / 'aiengine/src/main/resources/rawfile/comic-colorizer'
    destination.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        with tarfile.open(OUTPUT) as package:
            for name, digest in models.items():
                member = 'package/src/main/resources/rawfile/comic-colorizer/' + name
                try:
                    with package.extractfile(member) as source, (destination / name).open('wb') as target:
                        shutil.copyfileobj(source, target)
                except KeyError:
                    continue
                if sha256(destination / name) != digest:
                    (destination / name).unlink()
    missing = [name for name, digest in models.items()
               if not (destination / name).exists() or sha256(destination / name) != digest]
    if missing:
        archive = project.parent / 'model-assets.zip'
        download_archive(SPEC['modelAssetsRevision'], archive)
        with zipfile.ZipFile(archive) as package:
            for name in missing:
                suffix = '/aiengine/src/main/resources/rawfile/comic-colorizer/' + name
                member = next(item for item in package.namelist() if item.endswith(suffix))
                with package.open(member) as source, (destination / name).open('wb') as target:
                    shutil.copyfileobj(source, target)
                if sha256(destination / name) != models[name]:
                    raise ValueError('Bundled model hash mismatch: ' + name)


def build():
    ide = Path(os.environ['DEVECO_HOME']).resolve()
    sdk = json.loads((ide / 'sdk/default/sdk-pkg.json').read_text(encoding='utf-8'))['data']
    if sdk['releaseType'] != 'Release':
        raise ValueError('DEVECO_HOME must point to a Release IDE')
    env = os.environ.copy()
    env['DEVECO_SDK_HOME'] = str(ide / 'sdk')
    env['JAVA_HOME'] = str(ide / 'jbr')
    env['PATH'] = str(ide / 'tools/node') + os.pathsep + env['PATH']
    if os.name == 'nt':
        # Upstream native tests pass Windows paths to bash; WSL bash.exe cannot consume them.
        # Git Bash handles those paths and delegates the compiler to WSL when needed.
        git = shutil.which('git')
        git_bash = Path(git).resolve().parent.parent / 'bin' if git else None
        if git_bash and (git_bash / 'bash.exe').is_file():
            env['PATH'] = str(git_bash) + os.pathsep + env['PATH']
    # TemporaryDirectory is outside the app checkout and removes all downloaded engine source after use.
    with tempfile.TemporaryDirectory(prefix='hsda-ai-') as directory:
        temporary = Path(directory).resolve()
        archive = temporary / 'engine.zip'
        project = temporary / 'engine'
        project.mkdir()
        if not prepare_sources_from_existing_models(project):
            download_archive(SPEC['revision'], archive)
        if archive.exists():
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
