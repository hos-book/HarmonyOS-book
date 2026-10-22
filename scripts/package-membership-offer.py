"""Build a dependency-free Huawei FunctionGraph Node.js ZIP; contains no signing secrets."""
from pathlib import Path
import json, subprocess, tempfile, zipfile

root = Path(__file__).resolve().parents[1]
server = root / 'server'
with tempfile.TemporaryDirectory(prefix='membership-offer-') as temporary:
    output = Path(temporary)
    subprocess.run(['node', str(server / 'node_modules/typescript/bin/tsc'),
                    '--target', 'ES2022', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
                    '--strict', '--skipLibCheck', '--outDir', str(output),
                    'src/membership-offer.ts', 'src/membership-offer-function.ts'], cwd=server, check=True)
    # FunctionGraph Node runtime supports a CommonJS handler; dynamically load the ESM implementation.
    (output / 'index.js').write_text(
        "exports.handler = async (event) => (await import('./membership-offer-function.mjs')).handlerEntry(event);\n",
        encoding='utf-8')
    artifact = server / 'dist/membership-offer-function.zip'
    artifact.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(artifact, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.write(output / 'index.js', 'index.js')
        archive.writestr('membership-offer.mjs', (output / 'membership-offer.js').read_text(encoding='utf-8'))
        archive.writestr('membership-offer-function.mjs',
                         (output / 'membership-offer-function.js').read_text(encoding='utf-8')
                         .replace("'./membership-offer.js'", "'./membership-offer.mjs'"))
    print(artifact)
