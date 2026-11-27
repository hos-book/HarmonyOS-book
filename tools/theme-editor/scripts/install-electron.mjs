import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { unzipSync } from 'fflate';
import { join, dirname } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const { version } = JSON.parse(await readFile(join(root, 'node_modules/electron/package.json'), 'utf8'));
const response = await fetch(`https://github.com/electron/electron/releases/download/v${version}/electron-v${version}-win32-x64.zip`, {
  signal: AbortSignal.timeout(240_000)
});
if (!response.ok) throw new Error(`Electron download: ${response.status}`);
const files = unzipSync(new Uint8Array(await response.arrayBuffer()));
const target = join(root, 'node_modules/electron/dist');
await mkdir(target, { recursive: true });
for (const [name, bytes] of Object.entries(files)) {
  const destination = join(target, name);
  if (name.endsWith('/')) await mkdir(destination, { recursive: true });
  else {
    await mkdir(dirname(destination), { recursive: true });
    await writeFile(destination, bytes);
  }
}
await writeFile(join(root, 'node_modules/electron/path.txt'), 'electron.exe');
console.log(`Electron ${version} ready`);
