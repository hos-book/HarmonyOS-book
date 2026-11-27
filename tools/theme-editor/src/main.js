import schema from '../../../entry/src/main/resources/rawfile/theme_editor_schema.json';
import resources from '../../../entry/src/main/resources/base/element/theme_editor.json';
import { readTheme, writeTheme } from './package.js';
import './style.css';

const strings = new Map(resources.string.map(item => [item.name, item.value]));
const t = key => strings.get(key) ?? key;
const groups = ['basic', 'colors', 'backgrounds', 'tabs', 'icons', 'covers', 'player'];
const scenes = ['home', 'shelf', 'record', 'profile', 'player'];
const fields = new Map(schema.fields.map(field => [field.key, field]));
let assets = new Map();
const urls = new Map();
let mode = 'light';
let section = 'basic';
let scene = 'home';
let backgroundScene = 'common';
let theme = freshTheme();

function freshTheme() {
  return {
    format: 'jianting.theme', schemaVersion: 1, id: `custom-${crypto.randomUUID()}`,
    name: t('theme_editor_new_name'), description: '', baseThemeId: 'default',
    materialStyle: 6, verticalBottomTabs: false,
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

function cssColor(hex) {
  return /^#[0-9a-f]{8}$/i.test(hex) ? `#${hex.slice(3)}${hex.slice(1, 3)}` : hex;
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
identity.append(node('div', 'brand-mark', '听'));
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
const studioNote = node('p', 'studio-note', t('theme_editor_toolbar_hint'));
studio.append(studioHeader, canvas, studioNote);
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
      backgroundScene === 'profile' && field.key === 'background.profileCard') && fieldVisible(field)).forEach(field => body.append(renderField(field)));
  }
  inspector.append(body);
}

function renderBasic(body) {
  const name = node('input'); name.value = theme.name;
  name.addEventListener('input', () => { theme.name = name.value; renderPreview(); });
  const description = node('textarea'); description.value = theme.description; description.rows = 3;
  description.addEventListener('input', () => { theme.description = description.value; });
  const material = node('select');
  [['6', '跟随系统'], ['2', '强'], ['3', '均衡'], ['4', '弱']].forEach(([key, label]) => {
    const option = node('option', '', label); option.value = key; material.append(option);
  });
  material.value = String(theme.materialStyle);
  material.addEventListener('change', () => { theme.materialStyle = Number(material.value); renderPreview(); });
  const vertical = node('input'); vertical.type = 'checkbox'; vertical.checked = theme.verticalBottomTabs;
  vertical.addEventListener('change', () => { theme.verticalBottomTabs = vertical.checked; renderPreview(); });
  body.append(labeled(t('theme_editor_name'), name), labeled(t('theme_editor_description'), description),
    labeled(t('theme_editor_material'), material), labeled(t('theme_editor_vertical'), vertical));
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
  }
  input.id = `input-${field.key}`;
  return wrapper;
}

function focusField(key, colorMode) {
  const field = fields.get(key); if (!field) return;
  mode = colorMode; section = field.section;
  if (key.startsWith('background.') && key.split('.').length === 3) backgroundScene = key.split('.')[1];
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
  element.addEventListener('keydown', event => { if (event.key === 'Enter') focusField(key, colorMode); });
  return element;
}

function icon(key, fallback, colorMode, className = '') {
  const path = assetUrl(value(key, colorMode));
  const result = node(path ? 'img' : 'span', `preview-icon ${className}`, path ? '' : fallback);
  if (path) { result.src = path; result.alt = t(fields.get(key)?.label ?? 'theme_editor_edit'); }
  return hook(result, key, colorMode);
}

function cover(colorMode, player = false) {
  const key = player ? 'cover.playerPlaceholder' : 'cover.placeholder';
  const source = assetUrl(value(key, colorMode));
  const result = node('div', `book-cover ${player ? 'player-cover' : ''}`);
  if (source) { const img = node('img'); img.src = source; img.alt = t('theme_editor_preview_book'); result.append(img); }
  if (!source || value('cover.illustratedPlaceholder', colorMode) === 'true') {
    const caption = node('span', 'cover-title', t('theme_editor_preview_book'));
    caption.style.color = cssColor(value('cover.title', colorMode)); result.append(caption);
  }
  const decoration = value('cover.decoration', colorMode);
  if (decoration !== '0') {
    result.style.border = `2px solid ${cssColor(value('cover.edge', colorMode))}`;
    if (decoration === '2') result.style.boxShadow = 'inset 6px 0 8px #0003';
  }
  return hook(result, key, colorMode);
}

function renderPhone(colorMode) {
  const group = node('div', `phone-group ${colorMode === mode ? 'selected-mode' : ''}`);
  const caption = button(t(`theme_editor_${colorMode}`), () => { mode = colorMode; renderInspector(); renderPreview(); }, 'phone-caption');
  const phone = node('div', `phone ${colorMode} ${scene === 'player' ? 'player-scene' : ''}`);
  const color = key => cssColor(value(`color.${key}`, colorMode));
  for (const field of schema.fields.filter(field => field.section === 'colors')) {
    phone.style.setProperty(`--${field.key.slice(6)}`, cssColor(value(field.key, colorMode)));
  }
  let backdropScene = scene;
  if (value(`background.${scene}.mode`, colorMode) === 'common') backdropScene = 'common';
  const prefix = `background.${backdropScene}.`;
  const backdropMode = value(prefix + 'mode', colorMode);
  phone.style.background = `linear-gradient(160deg, ${color('homeTop')}, ${color('homeMid')} 40%, ${color('homeBottom')})`;
  if (backdropMode === 'solid' || backdropMode === 'image' || scene === 'player') {
    phone.style.background = cssColor(value(prefix + 'color', colorMode));
    let imageUrl = backdropMode === 'image' ? assetUrl(value(prefix + 'image', colorMode)) : '';
    if (backdropMode === 'cover') imageUrl = assetUrl(value('cover.playerPlaceholder', colorMode));
    if (imageUrl) {
      const background = node('div', 'phone-background');
      background.style.backgroundImage = `url("${imageUrl}")`;
      background.style.backgroundPosition = backdropMode === 'cover' ? '50% 50%' :
        `${value(prefix + 'positionX', colorMode)}% ${value(prefix + 'positionY', colorMode)}%`;
      background.style.filter = `blur(${Number(value(prefix + 'blur', colorMode)) * .65}px)`;
      const imageScale = backdropMode === 'cover' ? 1 : Number(value(prefix + 'scale', colorMode)) / 100;
      background.style.transform = `scale(${imageScale + Number(value(prefix + 'blur', colorMode)) / 200})`;
      phone.append(background);
    }
    const veil = node('div', 'phone-veil'); veil.style.background = colorMode === 'dark' || scene === 'player' ? '#0D0D0D' : '#fff';
    veil.style.opacity = Number(value(prefix + 'veil', colorMode)) / 100; phone.append(veil);
  }
  const content = node('div', 'phone-content');
  const top = node('div', 'phone-top'); top.append(node('span', '', '9:41'), node('span', '', '••• ▰'));
  const title = node('div', 'phone-title');
  title.append(hook(node('h3', '', t(`theme_editor_${scene}`)), 'color.textPrimary', colorMode), icon('icon.Search', '⌕', colorMode));
  content.append(top, title);
  if (scene === 'player') {
    const player = node('div', 'player-content');
    player.append(cover(colorMode, true), node('h4', '', t('theme_editor_preview_book')),
      node('p', '', t('theme_editor_preview_progress')));
    const progress = node('div', 'player-track'); progress.append(node('span'));
    const controls = node('div', 'player-controls'); controls.append(node('span', '', '◀'), node('span', 'play-button', '▶'), node('span', '', '▶'));
    player.append(progress, controls); content.append(player);
  } else {
    content.append(hook(node('p', 'phone-subtitle', theme.description || t('theme_editor_preview_hint')), 'color.textSecondary', colorMode));
    if (scene === 'record') {
      const summary = hook(node('div', 'record-card'), 'color.surface', colorMode);
      summary.append(node('p', '', t('theme_editor_preview_record')), hook(node('strong', '', t('theme_editor_preview_record_value')), 'color.brand', colorMode));
      const chart = node('div', 'chart'); [36, 62, 44, 80, 52, 95, 64].forEach(height => { const bar = node('i'); bar.style.height = `${height}%`; chart.append(bar); });
      summary.append(chart); content.append(summary);
    } else if (scene === 'profile') {
      const profile = hook(node('div', 'profile-card'), 'background.profileCard', colorMode);
      const picture = assetUrl(value('background.profileCard', colorMode));
      if (picture) profile.style.backgroundImage = `url("${picture}")`;
      profile.append(node('div', 'avatar', '听'), node('h4', '', t('theme_editor_preview_author')));
      content.append(profile);
      ['shelf', 'record', 'basic'].forEach(item => {
        const row = hook(node('div', 'menu-row'), 'color.profileMenuSurface', colorMode);
        row.append(node('span', '', t(`theme_editor_${item}`)), icon('icon.ChevronRight', '›', colorMode)); content.append(row);
      });
    } else {
      const bookCard = hook(node('div', 'book-card'), 'color.surface', colorMode);
      const detail = node('div', 'book-detail');
      detail.append(node('h4', '', t('theme_editor_preview_book')), node('p', '', t('theme_editor_preview_author')),
        hook(node('span', 'reading-label', '继续阅读'), 'color.brandSoft', colorMode));
      bookCard.append(cover(colorMode), detail); content.append(bookCard);
      const sectionTitle = node('div', 'content-heading'); sectionTitle.append(node('span', '', '为你精选'), icon('icon.Filter', '☷', colorMode)); content.append(sectionTitle);
      const shelf = node('div', 'mini-shelf'); shelf.append(cover(colorMode), cover(colorMode)); content.append(shelf);
    }
    const bottom = node('div', `phone-tabs ${theme.verticalBottomTabs ? 'vertical-tabs' : ''}`);
    if (theme.verticalBottomTabs) {
      const miniPlayer = node('div', 'preview-mini-player');
      miniPlayer.append(node('span', '', '▶'), node('span', '', t('theme_editor_preview_book')));
      content.append(miniPlayer);
    }
    bottom.style.backdropFilter = `blur(${({ 2: 8, 3: 18, 4: 28, 6: 20 })[theme.materialStyle]}px)`;
    const glyphs = ['⌂', '▥', '◷', '♙'];
    scenes.slice(0, 4).forEach((item, index) => {
      const active = scene === item;
      const key = active && value(`tab.${item}.selected`, colorMode) ? `tab.${item}.selected` : `tab.${item}.normal`;
      const tab = node('div', `phone-tab ${active ? 'active' : ''}`);
      tab.style.color = cssColor(value(active ? 'tab.selectedColor' : 'tab.normalColor', colorMode));
      tab.append(icon(key, glyphs[index], colorMode), node('small', '', t(`theme_editor_${item}`))); bottom.append(tab);
    });
    content.append(bottom);
  }
  content.append(node('div', 'home-indicator'));
  phone.append(content); group.append(caption, phone, node('p', 'theme-caption', theme.name));
  return group;
}

function renderPreview() {
  sceneNav.querySelectorAll('button').forEach(entry => entry.classList.toggle('active', entry.dataset.scene === scene));
  canvas.replaceChildren(renderPhone('light'), renderPhone('dark'));
}

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
