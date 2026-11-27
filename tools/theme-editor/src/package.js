import { zip, unzip, strToU8, strFromU8 } from 'fflate';

export async function readTheme(file) {
  const files = await new Promise((resolve, reject) => {
    file.arrayBuffer().then(buffer => unzip(new Uint8Array(buffer), (error, result) => error ? reject(error) : resolve(result)), reject);
  });
  const manifest = JSON.parse(strFromU8(files['manifest.json']));
  if (manifest.format !== 'jianting.theme' || manifest.schemaVersion !== 1) throw new Error('请选择简听主题文件');
  const theme = JSON.parse(strFromU8(files['theme.json']));
  const assets = new Map(Object.entries(files).filter(([key]) => key.startsWith('assets/') && !key.endsWith('/')));
  return { theme, assets };
}

export async function writeTheme(theme, assets) {
  const files = {
    'manifest.json': strToU8(JSON.stringify({ format: 'jianting.theme', schemaVersion: 1, theme: 'theme.json' })),
    'theme.json': strToU8(JSON.stringify(theme, null, 2))
  };
  for (const token of [...theme.light, ...theme.dark]) {
    if (token.value.startsWith('assets/')) files[token.value] = assets.get(token.value);
  }
  const bytes = await new Promise((resolve, reject) => zip(files, { level: 6 }, (error, result) => error ? reject(error) : resolve(result)));
  return new Blob([bytes], { type: 'application/zip' });
}
