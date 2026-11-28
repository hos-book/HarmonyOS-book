import { zip, unzip, strToU8, strFromU8 } from 'fflate';

function themeContent(theme) {
  return {
    format: theme.format, schemaVersion: theme.schemaVersion, id: theme.id,
    name: theme.name, description: theme.description, baseThemeId: theme.baseThemeId,
    light: theme.light.filter(token => token.key !== 'icon.ChevronRight'),
    dark: theme.dark.filter(token => token.key !== 'icon.ChevronRight')
  };
}

export async function readTheme(file) {
  const files = await new Promise((resolve, reject) => {
    file.arrayBuffer().then(buffer => unzip(new Uint8Array(buffer), (error, result) => error ? reject(error) : resolve(result)), reject);
  });
  const manifest = JSON.parse(strFromU8(files['manifest.json']));
  if (manifest.format !== 'jianting.theme' || manifest.schemaVersion !== 1) throw new Error('请选择简听主题文件');
  const theme = themeContent(JSON.parse(strFromU8(files['theme.json'])));
  const assets = new Map(Object.entries(files).filter(([key]) => key.startsWith('assets/') && !key.endsWith('/')));
  return { theme, assets };
}

export async function writeTheme(theme, assets) {
  const document = themeContent(theme);
  const files = {
    'manifest.json': strToU8(JSON.stringify({ format: 'jianting.theme', schemaVersion: 1, theme: 'theme.json' })),
    'theme.json': strToU8(JSON.stringify(document, null, 2))
  };
  for (const token of [...document.light, ...document.dark]) {
    if (token.value.startsWith('assets/')) files[token.value] = assets.get(token.value);
  }
  const bytes = await new Promise((resolve, reject) => zip(files, { level: 6 }, (error, result) => error ? reject(error) : resolve(result)));
  return new Blob([bytes], { type: 'application/zip' });
}
