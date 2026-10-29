"""Synchronize pinned source packages through verified GitHub archives when Git transport is unavailable."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def github(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], timeout=120))


def checkout(parent, name, repository, revision):
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise ValueError('A full immutable commit SHA is required')
    commit = github(f'repos/{repository}/git/commits/{revision}')
    archive = parent / (name + '.zip')
    with archive.open('wb') as output:
        subprocess.run(['gh', 'api', f'repos/{repository}/zipball/{revision}'],
                       stdout=output, check=True, timeout=600)
    directory = parent / name
    directory.mkdir()
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            parts = Path(member.filename).parts[1:]
            if not parts:
                continue
            target = directory.joinpath(*parts).resolve()
            if not target.is_relative_to(directory.resolve()):
                raise ValueError('Invalid archive path')
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(package.read(member))

    def git(*args):
        return subprocess.check_output(['git', '-C', str(directory), *args], timeout=120, text=True).strip()

    git('init', '-q')
    git('config', 'core.autocrlf', 'false')
    git('add', '--all')
    upstream = github(f'repos/{repository}/git/trees/{commit["tree"]["sha"]}?recursive=1')
    if upstream.get('truncated'):
        raise ValueError('Cannot verify a truncated upstream tree')
    for entry in upstream['tree']:
        if entry['mode'] == '100755':
            git('update-index', '--chmod=+x', '--', entry['path'])
        elif entry['mode'] == '160000':
            # GitHub archives omit submodule content; the recorded gitlink still belongs to the tree.
            git('update-index', '--add', '--cacheinfo', entry['mode'], entry['sha'], entry['path'])
    tree = git('write-tree')
    if tree != commit['tree']['sha']:
        raise ValueError('Archive content differs from the pinned upstream Git tree')
    git('-c', 'user.name=Archive verifier', '-c', 'user.email=archive@local',
        'commit', '-qm', f'Verified archive of {repository}@{revision}')
    (directory / '.git/upstream-archive.json').write_text(
        json.dumps({'commit': revision, 'tree': tree}), encoding='utf-8')
    return directory


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-revision')
    parser.add_argument('--application-revision')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    pins = json.loads((ROOT / 'third_party/light-source/upstream.json').read_text(encoding='utf-8'))['sources']
    with tempfile.TemporaryDirectory(prefix='hsda-light-') as folder:
        temporary = Path(folder)
        engine = checkout(temporary, 'engine', 'wip3l/harmony-book-source-engine',
                          args.engine_revision or pins['engine']['commit'])
        app = checkout(temporary, 'application', 'wip3l/qingye-reader',
                       args.application_revision or pins['application']['commit'])
        node = Path(os.environ['DEVECO_HOME']) / 'tools/node/node.exe'
        command = [str(node), str(ROOT / 'scripts/sync-light-source.cjs'), str(engine), str(app)]
        if args.check:
            command.append('--check')
        subprocess.run(command, cwd=ROOT, check=True, timeout=180)
