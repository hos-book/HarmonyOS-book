import schema from '../../../entry/src/main/resources/rawfile/theme_editor_schema.json';
import resources from '../../../entry/src/main/resources/base/element/theme_editor.json';
import { readTheme, writeTheme } from './package.js';
import { renderDevice, viewports, previewCopy, appIcon } from './preview.js';
import './style.css';

const strings = new Map(resources.string.map(item => [item.name, item.value]));
const t = key => strings.get(key) ?? key;
const groups = ['basic', 'colors', 'backgrounds', 'tabs', 'buttons', 'icons', 'covers', 'player'];
const scenes = ['home', 'shelf', 'record', 'profile', 'player'];
const fields = new Map(schema.fields.map(field => [field.key, field]));
let assets = new Map();
const urls = new Map();
let mode = 'light';
let section = 'basic';
let scene = 'home';
let backgroundScene = 'common';
let buttonScene = 'shelf';
let buttonPreview = '';
let theme = freshTheme();
let viewport = 'phone';
let shelfLayout = 'grid';
let miniPlayer = true;
let barLayout = 'stacked';

function freshTheme() {
  return {
    format: 'jianting.theme', schemaVersion: 1, id: `custom-${crypto.randomUUID()}`,
    name: t('theme_editor_new_name'), description: '', baseThemeId: 'default',
    light: schema.fields.filter(field => field.light).map(field => ({ key: field.key, value: field.light })),
    dark: schema.fields.filter(field => field.dark).map(field => ({ key: field.key, value: field.dark }))
  };
}

function node(tag, className = '', text = '') {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text) element.textContent = text;
  return element;
}

function button(text, action, className = '') {
  const element = node('button', className, text);
  element.type = 'button';
  element.addEventListener('click', action);
  return element;
}

function value(key, colorMode = mode, fallback = '') {
  return theme[colorMode].find(token => token.key === key)?.value ?? fields.get(key)?.[colorMode] ?? fallback;
}

function set(key, current) {
  theme[mode] = theme[mode].filter(token => token.key !== key);
  if (current) theme[mode].push({ key, value: current });
  if (key.startsWith('button.')) { buttonPreview = key; scene = buttonScene; }
  renderPreview();
  if (key.endsWith('.mode')) renderInspector();
}

function fieldVisible(field) {
  const parts = field.key.split('.');
  if (parts[0] !== 'background' || parts.length !== 3 || parts[2] === 'mode') return true;
  const backdropMode = value(`background.${parts[1]}.mode`);
  if (backdropMode === 'image') return true;
  if (backdropMode === 'solid') return ['color', 'veil'].includes(parts[2]);
  if (backdropMode === 'cover') return ['color', 'blur', 'veil'].includes(parts[2]);
  return false;
}

function assetUrl(path) {
  if (!assets.has(path)) return '';
  if (!urls.has(path)) {
    const extension = path.split('.').pop().toLowerCase();
    const types = { svg: 'image/svg+xml', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
    urls.set(path, URL.createObjectURL(new Blob([assets.get(path)], { type: types[extension] ?? 'image/png' })));
  }
  return urls.get(path);
}

const app = document.querySelector('#app');
const header = node('header', 'app-header');
const identity = node('div', 'identity');
const brandIcon = node('img', 'brand-mark');
brandIcon.src = appIcon;
brandIcon.alt = t('theme_editor_preview_author');
identity.append(brandIcon);
const heading = node('div');
heading.append(node('h1', '', t('theme_editor_web_title')), node('p', '', t('theme_editor_web_subtitle')));
identity.append(heading);
const actions = node('div', 'header-actions');
const importInput = node('input');
importInput.type = 'file';
importInput.accept = '.jttheme';
importInput.hidden = true;
const importButton = button(t('theme_editor_import'), () => importInput.click(), 'secondary');
const exportButton = button(t('theme_editor_export'), exportPackage, 'primary');
actions.append(importButton, exportButton, importInput);
header.append(identity, actions);
const workspace = node('main', 'workspace');
const sidebar = node('aside', 'sidebar');
sidebar.append(node('p', 'eyebrow', t('theme_editor_title')));
const navigation = node('nav', 'section-nav');
groups.forEach((group, index) => {
  const entry = button('', () => {
    section = group;
    if (group === 'player') scene = 'player';
    else if (group === 'buttons') scene = buttonScene;
    renderNavigation(); renderInspector(); renderPreview();
  }, 'nav-item');
  entry.dataset.section = group;
  entry.append(node('span', 'nav-number', String(index + 1).padStart(2, '0')), node('span', '', t(`theme_editor_${group}`)));
  navigation.append(entry);
});
const sidebarFooter = node('div', 'sidebar-footer');
sidebarFooter.append(node('span', 'tiny-dot'), node('p', '', t('theme_editor_web_note')));
sidebar.append(navigation, sidebarFooter);
const studio = node('section', 'studio');
const studioHeader = node('div', 'studio-header');
studioHeader.append(node('span', 'eyebrow', t('theme_editor_preview')));
const sceneNav = node('div', 'scene-nav');
scenes.forEach(item => {
  const entry = button(t(`theme_editor_${item}`), () => { scene = item; renderPreview(); });
  entry.dataset.scene = item;
  sceneNav.append(entry);
});
studioHeader.append(sceneNav);
const canvas = node('div', 'preview-canvas');
const previewToolbar = node('div', 'preview-toolbar');
function previewSelect(label, choices, current, onChange) {
  const wrapper = node('label', 'preview-option');
  const select = node('select');
  choices.forEach(key => {
    const option = node('option', '', previewCopy[key]); option.value = key; select.append(option);
  });
  select.value = current;
  select.addEventListener('change', () => { onChange(select.value); renderPreview(); });
  wrapper.append(node('span', '', label), select);
  return wrapper;
}
const viewportOption = previewSelect(previewCopy.window, Object.keys(viewports), viewport, current => { viewport = current; });
const shelfOption = previewSelect(previewCopy.shelfView, ['grid', 'list', 'collection'], shelfLayout, current => { shelfLayout = current; buttonPreview = ''; });
const barOption = previewSelect(previewCopy.barLayout, ['stacked', 'inline'], barLayout, current => { barLayout = current; });
const miniOption = node('label', 'preview-option preview-toggle');
const miniInput = node('input'); miniInput.type = 'checkbox'; miniInput.checked = miniPlayer;
miniInput.addEventListener('change', () => { miniPlayer = miniInput.checked; renderPreview(); });
miniOption.append(miniInput, node('span', '', previewCopy.miniPlayer));
previewToolbar.append(viewportOption, shelfOption, barOption, miniOption);
const studioNote = node('p', 'studio-note', previewCopy.previewNote);
studio.append(studioHeader, previewToolbar, canvas, studioNote);
const inspector = node('aside', 'inspector');
workspace.append(sidebar, studio, inspector);
const toast = node('div', 'toast');
toast.setAttribute('role', 'status');
app.append(header, workspace, toast);

function notify(message) {
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(notify.timer);
  notify.timer = setTimeout(() => toast.classList.remove('visible'), 3500);
}

function renderNavigation() {
  navigation.querySelectorAll('button').forEach(entry => {
    entry.classList.toggle('active', entry.dataset.section === section);
    entry.setAttribute('aria-current', entry.dataset.section === section ? 'page' : 'false');
  });
}

function labeled(title, element) {
  const wrapper = node('label', 'field');
  wrapper.append(node('span', 'field-title', title), element);
  return wrapper;
}

function renderInspector() {
  inspector.replaceChildren();
  const inspectorHeader = node('div', 'inspector-header');
  inspectorHeader.append(node('h2', '', t(`theme_editor_${section}`)));
  const modes = node('div', 'mode-switch');
  ['light', 'dark'].forEach(item => modes.append(button(t(`theme_editor_${item}`), () => {
    mode = item; renderInspector(); renderPreview();
  }, item === mode ? 'active' : '')));
  inspectorHeader.append(modes);
  inspector.append(inspectorHeader);
  const body = node('div', 'inspector-body');
  if (section === 'basic') renderBasic(body);
  else {
    if (section === 'buttons') {
      const select = node('select');
      ['shelf', 'record'].forEach(item => {
        const option = node('option', '', t(`theme_editor_${item}`));
        option.value = item; select.append(option);
      });
      select.value = buttonScene;
      select.addEventListener('change', () => {
        buttonScene = select.value; scene = buttonScene; buttonPreview = '';
        renderInspector(); renderPreview();
      });
      body.append(labeled(t('theme_editor_button_page'), select), node('p', 'button-hint', t('theme_editor_buttons_hint')));
    }
    if (section === 'backgrounds') {
      const select = node('select');
      ['common', ...scenes.slice(0, 4)].forEach(item => {
        const option = node('option', '', t(`theme_editor_${item}`));
        option.value = item; select.append(option);
      });
      select.value = backgroundScene;
      select.addEventListener('change', () => {
        backgroundScene = select.value; scene = backgroundScene === 'common' ? 'home' : backgroundScene;
        renderInspector(); renderPreview();
      });
      body.append(labeled(t('theme_editor_background_hint'), select));
    }
    schema.fields.filter(field => field.section === section && (section !== 'backgrounds' ||
      field.key.startsWith(`background.${backgroundScene}.`) ||
      backgroundScene === 'common' && field.key === 'background.coverBackdrop' ||
      backgroundScene === 'profile' && field.key === 'background.profileCard') &&
      (section !== 'buttons' || field.key.startsWith(`button.${buttonScene}.`)) && fieldVisible(field))
      .forEach(field => body.append(renderField(field)));
  }
  inspector.append(body);
}

function renderBasic(body) {
  const name = node('input'); name.value = theme.name;
  name.addEventListener('input', () => { theme.name = name.value; renderPreview(); });
  const description = node('textarea'); description.value = theme.description; description.rows = 3;
  description.addEventListener('input', () => { theme.description = description.value; });
  body.append(labeled(t('theme_editor_name'), name), labeled(t('theme_editor_description'), description));
  const hint = node('div', 'hint-card');
  hint.append(node('div', 'hint-symbol', '✦'), node('p', '', t('theme_editor_web_note')),
    node('small', '', '.jttheme'));
  body.append(hint);
}

function renderField(field) {
  const wrapper = node('div', 'field');
  wrapper.id = `field-${field.key}`;
  const title = node('label', 'field-title', t(field.label));
  title.htmlFor = `input-${field.key}`;
  wrapper.append(title);
  let input;
  if (field.type === 'color') {
    const row = node('div', 'color-row');
    const picker = node('input', 'color-picker'); picker.type = 'color';
    const current = value(field.key); picker.value = current.length === 9 ? `#${current.slice(3)}` : current;
    input = node('input', 'hex-input'); input.value = current; input.spellcheck = false;
    input.setAttribute('aria-label', t(field.label));
    input.addEventListener('change', () => {
      if (/^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i.test(input.value)) {
        set(field.key, input.value.toUpperCase()); picker.value = input.value.length === 9 ? `#${input.value.slice(3)}` : input.value;
      } else { input.value = value(field.key); notify(t('theme_editor_invalid_color')); }
    });
    picker.addEventListener('input', () => {
      const alpha = value(field.key).length === 9 ? value(field.key).slice(1, 3) : '';
      input.value = `#${alpha}${picker.value.slice(1)}`.toUpperCase(); set(field.key, input.value);
    });
    row.append(picker, input); wrapper.append(row);
  } else if (field.type === 'range') {
    input = node('input'); input.type = 'range'; input.min = field.min; input.max = field.max;
    input.step = 1; input.value = value(field.key);
    const output = node('output', '', input.value); title.append(output);
    input.addEventListener('input', () => { output.value = input.value; set(field.key, input.value); });
    wrapper.append(input);
  } else if (field.type === 'select') {
    input = node('select');
    field.choices.forEach(choice => { const option = node('option', '', t(choice.label)); option.value = choice.value; input.append(option); });
    input.value = value(field.key); input.addEventListener('change', () => set(field.key, input.value));
    wrapper.append(input);
  } else if (field.type === 'toggle') {
    input = node('input'); input.type = 'checkbox'; input.checked = value(field.key) === 'true';
    input.addEventListener('change', () => set(field.key, String(input.checked))); wrapper.append(input);
  } else {
    input = node('input'); input.type = 'file'; input.accept = 'image/png,image/jpeg,image/webp,image/svg+xml'; input.hidden = true;
    const imageArea = node('div', 'asset-area');
    const source = assetUrl(value(field.key));
    if (source) { const img = node('img'); img.src = source; img.alt = t(field.label); imageArea.append(img); }
    else imageArea.append(node('span', 'asset-empty', '+'));
    imageArea.append(button(t('theme_editor_pick'), () => input.click(), 'asset-pick'));
    input.addEventListener('change', async () => {
      const file = input.files[0]; if (!file) return;
      const key = `assets/${crypto.randomUUID()}.${file.name.split('.').pop().toLowerCase()}`;
      assets.set(key, new Uint8Array(await file.arrayBuffer())); set(field.key, key); renderInspector();
    });
    wrapper.append(imageArea, input);
    if (source) wrapper.append(button(t('theme_editor_clear'), () => { set(field.key, ''); renderInspector(); }, 'text-button'));
    if (field.section === 'buttons') wrapper.append(button(t('theme_editor_button_preview'), () => {
      buttonPreview = field.key; scene = buttonScene; renderPreview();
    }, 'text-button button-preview'));
  }
  input.id = `input-${field.key}`;
  return wrapper;
}

function focusField(key, colorMode) {
  const field = fields.get(key); if (!field) return;
  mode = colorMode; section = field.section;
  if (key.startsWith('background.') && key.split('.').length === 3) backgroundScene = key.split('.')[1];
  if (key === 'background.profileCard') backgroundScene = 'profile';
  if (key === 'background.coverBackdrop') backgroundScene = 'common';
  if (key.startsWith('button.')) { buttonScene = key.split('.')[1]; scene = buttonScene; buttonPreview = key; }
  renderNavigation(); renderInspector(); renderPreview();
  const selected = document.getElementById(`field-${key}`);
  selected?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  selected?.classList.add('highlight');
}

function hook(element, key, colorMode) {
  element.tabIndex = 0;
  element.title = t(fields.get(key)?.label ?? 'theme_editor_edit');
  element.classList.add('editable');
  element.addEventListener('click', event => { event.stopPropagation(); focusField(key, colorMode); });
  element.addEventListener('keydown', event => {
    if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); focusField(key, colorMode); }
  });
  return element;
}

function renderPhone(colorMode) {
  const { width, height } = viewports[viewport];
  const group = node('div', `device-group ${colorMode === mode ? 'selected-mode' : ''}`);
  const caption = button(t(`theme_editor_${colorMode}`), () => {
    mode = colorMode; renderInspector(); renderPreview();
  }, 'device-caption');
  const frame = node('div', `device-frame ${viewport}`);
  frame.append(renderDevice({
    colorMode, scene, fields, hook, t, value, assetUrl, width, height,
    buttonPreview, shelfLayout, miniPlayer, barLayout
  }));
  group.append(caption, frame, node('p', 'device-dimensions', `${width} × ${height} ${previewCopy.windowUnit}`));
  return group;
}

function layoutPreview() {
  const { width, height } = viewports[viewport];
  const available = canvas.clientWidth;
  const columns = available >= (viewport === 'phone' ? 660 : 1120) ? 2 : 1;
  const gap = 28;
  const columnWidth = (available - gap * (columns - 1)) / columns;
  const maxHeight = Math.max(520, window.innerHeight - 300);
  const scale = Math.min(1, (columnWidth - 12) / width, maxHeight / height);
  canvas.querySelectorAll('.device-group').forEach(group => {
    group.hidden = columns === 1 && !group.classList.contains('selected-mode');
    group.style.width = `${width * scale}px`;
    const frame = group.querySelector('.device-frame');
    frame.style.width = `${width * scale}px`;
    frame.style.height = `${height * scale}px`;
    frame.querySelector('.app-preview').style.transform = `scale(${scale})`;
  });
}

function renderPreview() {
  const offsets = new Map([...canvas.querySelectorAll('.app-preview')].map(preview => [
    preview.dataset.mode, canvas.dataset.scene === scene ? preview.querySelector('.preview-scroll').scrollTop : 0
  ]));
  sceneNav.querySelectorAll('button').forEach(entry => entry.classList.toggle('active', entry.dataset.scene === scene));
  shelfOption.hidden = scene !== 'shelf';
  barOption.hidden = scene === 'player';
  miniOption.hidden = scene === 'player';
  canvas.dataset.scene = scene;
  canvas.replaceChildren(renderPhone('light'), renderPhone('dark'));
  canvas.querySelectorAll('.app-preview').forEach(preview => {
    preview.querySelector('.preview-scroll').scrollTop = offsets.get(preview.dataset.mode) ?? 0;
  });
  layoutPreview();
}

new ResizeObserver(layoutPreview).observe(canvas);
window.addEventListener('resize', layoutPreview);

importInput.addEventListener('change', async () => {
  const file = importInput.files[0]; if (!file) return;
  importButton.disabled = true;
  try {
    const imported = await readTheme(file);
    urls.forEach(url => URL.revokeObjectURL(url)); urls.clear();
    theme = imported.theme; assets = imported.assets;
    renderInspector(); renderPreview();
  } catch (error) { notify(error.message || t('theme_editor_failed')); }
  finally { importButton.disabled = false; importInput.value = ''; }
});

async function exportPackage() {
  if (!theme.name.trim()) { notify(t('theme_editor_empty_name')); return; }
  exportButton.disabled = true;
  try {
    const blob = await writeTheme(theme, assets);
    const url = URL.createObjectURL(blob); const anchor = node('a'); anchor.href = url; anchor.download = `${theme.name}.jttheme`;
    anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); notify(t('theme_editor_exported'));
  } catch (error) { notify(error.message || t('theme_editor_failed')); }
  finally { exportButton.disabled = false; }
}

renderNavigation(); renderInspector(); renderPreview();
