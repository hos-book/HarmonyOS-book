import copy from './preview-copy.json';
import symbols from './symbols.json';
import defaultCover from '../../../entry/src/main/resources/base/media/book_cover_placeholder.png';
import localCover from '../../../entry/src/main/resources/base/media/local_book_cover_placeholder.webp';
import appIcon from '../../../entry/src/main/resources/base/media/app_icon_legacy.png';
import shelfSymbol from '../../../entry/src/main/resources/base/media/theme_mist_shelf.svg';
import filterSymbol from '../../../entry/src/main/resources/base/media/theme_mist_filter.svg';
import './preview.css';

export { copy as previewCopy, appIcon };
export const viewports = {
  phone: { width: 400, height: 880 },
  tablet: { width: 834, height: 1112 },
  desktop: { width: 1280, height: 800 }
};

const scenes = ['home', 'shelf', 'record', 'profile'];
const buttonSymbols = {
  search: 'magnifyingglass', searchActive: 'magnifyingglass', filter: 'filter', filterActive: 'filter',
  group: 'folder', groupActive: 'folder', groupManage: 'folder', import: 'doc_text_badge_arrow_up',
  updates: 'arrow_clockwise', viewList: 'list_bullet', viewCollection: 'shelf', viewGrid: 'square_grid_2x2',
  add: 'plus', expand: 'arrow_up_left_and_arrow_down_right', collapse: 'arrow_down_right_and_arrow_up_left',
  close: 'xmark', back: 'chevron_left', excerpt: 'bookmark', history: 'clock', edit: 'square_and_pencil',
  done: 'checkmark', locked: 'lock'
};

function el(tag, className = '', text = '') {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  return element;
}

function picture(src, className, alt = '') {
  const image = el('img', className);
  image.src = src;
  image.alt = alt;
  image.draggable = false;
  return image;
}

function symbol(name, className = '') {
  const icon = el('span', `hm-symbol ${className}`);
  icon.setAttribute('aria-hidden', 'true');
  if (name === 'shelf' || name === 'filter') {
    icon.classList.add('vector-symbol');
    icon.style.maskImage = `url("${name === 'shelf' ? shelfSymbol : filterSymbol}")`;
  } else {
    icon.textContent = String.fromCodePoint(parseInt(symbols[name], 16));
  }
  return icon;
}

function cssColor(hex) {
  return /^#[0-9a-f]{8}$/i.test(hex) ? `#${hex.slice(3)}${hex.slice(1, 3)}` : hex;
}

export function renderDevice(context) {
  const { colorMode, scene, fields, hook, t, width, height, buttonPreview, miniPlayer, barLayout } = context;
  const value = key => context.value(key, colorMode);
  const color = key => cssColor(value(`color.${key}`));
  const asset = key => context.assetUrl(value(key));
  const edit = (element, key) => hook(element, key, colorMode);
  const phone = el('div', `app-preview ${colorMode} scene-${scene} bar-${barLayout}`);
  phone.style.width = `${width}px`;
  phone.style.height = `${height}px`;
  phone.dataset.mode = colorMode;
  phone.style.setProperty('--book-columns', width < 320 ? 2 : width < 600 ? 3 : Math.max(4, Math.floor((width - 32) / 144)));
  fields.forEach(field => {
    if (field.section === 'colors') phone.style.setProperty(`--${field.key.slice(6)}`, color(field.key.slice(6)));
  });

  function themedIcon(key, name, className = '') {
    const source = asset(key);
    return edit(source ? picture(source, `theme-icon ${className}`, t(fields.get(key).label)) :
      symbol(name, className), key);
  }

  function cover(book, kind = 'online', className = '', physical = true) {
    const key = kind === 'player' ? 'cover.playerPlaceholder' : kind === 'local' ? 'cover.localPlaceholder' : 'cover.placeholder';
    const source = physical ? '' : asset(key);
    const card = el('div', `preview-cover ${physical ? 'physical-cover' : ''} ${className}`);
    card.append(picture(source || (kind === 'player' ? appIcon : kind === 'local' ? localCover : defaultCover), 'cover-art', book.title));
    if (kind === 'local' || kind === 'online' && !physical && value('cover.illustratedPlaceholder') === 'true') {
      const caption = el('div', `cover-lettering ${kind === 'local' ? 'local-lettering' : ''}`);
      const titleKey = kind === 'local' ? 'cover.localTitle' : 'cover.title';
      const title = el('strong', '', book.title);
      title.style.color = physical ? '#493E35' : cssColor(value(titleKey));
      const author = el('small', '', book.author);
      author.style.color = physical ? '#64584B' : cssColor(value('cover.author'));
      author.style.background = physical ? 'transparent' : cssColor(value('cover.authorBackground'));
      if (!physical) { edit(title, titleKey); edit(author, 'cover.author'); }
      caption.append(title, author);
      card.append(caption);
    }
    if (!physical) {
      card.dataset.decoration = value('cover.decoration');
      card.style.setProperty('--cover-edge', cssColor(value('cover.edge')));
    }
    return physical ? card : edit(card, key);
  }

  function backdrop() {
    let backdropScene = value(`background.${scene}.mode`) === 'common' ? 'common' : scene;
    const prefix = `background.${backdropScene}.`;
    const mode = value(prefix + 'mode');
    const layer = el('div', 'preview-backdrop');
    phone.classList.toggle('custom-backdrop', mode !== 'theme');
    if (mode === 'theme') {
      layer.style.background = scene === 'home' ?
        `linear-gradient(180deg, ${color('homeTop')}, ${color('homeMid')} 48%, ${color('homeBottom')})` :
        color(scene === 'profile' ? 'settingsBackground' : 'background');
      if (scene === 'home' && value('background.coverBackdrop') === 'true') {
        const glow = picture(asset('cover.placeholder') || defaultCover, 'cover-atmosphere');
        layer.append(glow);
      }
    } else {
      layer.style.background = cssColor(value(prefix + 'color'));
      const source = mode === 'image' ? asset(prefix + 'image') :
        mode === 'cover' ? asset('cover.playerPlaceholder') || appIcon : '';
      const blur = Number(value(prefix + 'blur'));
      if (source) {
        const image = picture(source, 'backdrop-image');
        image.addEventListener('load', () => {
          const bleed = mode === 'image' ? blur * 4 : 0;
          const scale = Math.max((width + bleed) / image.naturalWidth, (height + bleed) / image.naturalHeight) *
            (mode === 'image' ? Number(value(prefix + 'scale')) / 100 : 1);
          const imageWidth = image.naturalWidth * scale;
          const imageHeight = image.naturalHeight * scale;
          image.style.width = `${imageWidth}px`;
          image.style.height = `${imageHeight}px`;
          image.style.left = `${(width - imageWidth) * (mode === 'cover' ? .5 : Number(value(prefix + 'positionX')) / 100)}px`;
          image.style.top = `${(height - imageHeight) * (mode === 'cover' ? .5 : Number(value(prefix + 'positionY')) / 100)}px`;
        });
        image.style.filter = `blur(${blur}px)`;
        layer.append(image);
      }
      const veil = el('div', 'backdrop-veil');
      veil.style.background = colorMode === 'dark' || scene === 'player' ? '#0D0D0D' : '#FFFFFF';
      veil.style.opacity = Number(value(prefix + 'veil')) / 100;
      layer.append(veil);
    }
    phone.append(layer);
  }

  function statusbar() {
    const bar = el('div', `harmony-statusbar harmony-statusbar-${scene === 'player' ? 'dark' : colorMode}`);
    bar.dataset.component = 'statusbar';
    bar.dataset.figmaNodeId = '36:3656';
    bar.append(el('span', 'harmony-statusbar-time', copy.previewTime));
    const icons = el('span', 'harmony-statusbar-icons');
    icons.setAttribute('aria-hidden', 'true');
    ['wifi', 'single-card', 'dual-card', 'battery'].forEach(name => icons.append(el('i', `harmony-statusbar-icon harmony-statusbar-icon-${name}`)));
    bar.append(icons);
    return bar;
  }

  function toolbarButton(key) {
    const source = asset(key);
    const role = key.split('.')[2];
    const button = el('button', `preview-header-button ${source ? 'custom' : 'system'}`);
    button.type = 'button';
    button.setAttribute('aria-label', t(fields.get(key).label));
    const filter = key.startsWith('button.record.filter') ? asset('icon.Filter') : '';
    button.append(source || filter ? picture(source || filter, source ? 'whole-button' : 'theme-icon') : symbol(buttonSymbols[role]));
    button.classList.toggle('active', ['searchActive', 'groupActive', 'filterActive', 'done', 'locked'].includes(role));
    return edit(button, key);
  }

  function header() {
    const shell = el('header', `preview-header harmony-titlebar harmony-titlebar--normal ${scene === 'home' ? 'home-header' : ''}`);
    shell.append(statusbar());
    const row = el('div', 'preview-title-row');
    if (scene === 'home') {
      const search = edit(el('div', 'home-search'), 'color.homeControl');
      search.append(themedIcon('icon.Search', 'magnifyingglass'), el('span', '', copy.search));
      const source = edit(el('div', 'home-source'), 'color.homeAccent');
      source.append(el('span', '', copy.source), symbol('chevron_down'));
      row.append(search, source);
    } else if (scene === 'player') {
      row.append(symbol('chevron_down'), el('span', 'player-top-label', copy.player), symbol('music_note_list'));
    } else {
      row.append(edit(el('h3', '', copy[scene]), 'color.textPrimary'));
      const actions = el('div', 'preview-header-actions');
      const selected = (normal, variants) => variants.includes(buttonPreview) ? buttonPreview : normal;
      if (scene === 'shelf') {
        const viewKey = { grid: 'viewList', list: 'viewCollection', collection: 'viewGrid' }[context.shelfLayout];
        const keys = [selected('button.shelf.search', ['button.shelf.searchActive'])];
        if (context.shelfLayout !== 'collection') keys.push('button.shelf.filter');
        keys.push(selected(`button.shelf.${context.shelfLayout === 'collection' ? 'groupManage' : 'group'}`, ['button.shelf.groupActive', 'button.shelf.groupManage']),
          'button.shelf.import', 'button.shelf.updates', selected(`button.shelf.${viewKey}`, ['button.shelf.viewList', 'button.shelf.viewCollection', 'button.shelf.viewGrid']));
        keys.forEach(key => actions.append(toolbarButton(key)));
      } else if (scene === 'record') {
        if (buttonPreview === 'button.record.back') row.prepend(toolbarButton(buttonPreview));
        [selected('button.record.filter', ['button.record.filterActive']), 'button.record.excerpt', 'button.record.history',
          selected('button.record.edit', ['button.record.done', 'button.record.locked'])].forEach(key => actions.append(toolbarButton(key)));
      }
      row.append(actions);
    }
    shell.append(row);
    return shell;
  }

  function chips(labels, active = 0, className = '') {
    const row = el('div', `preview-chips ${className}`);
    labels.forEach((label, index) => row.append(edit(el('span', index === active ? 'selected' : '', label), index === active ? 'color.brandSoft' : 'color.textSecondary')));
    return row;
  }

  function heading(text) {
    const row = el('div', 'preview-section-heading');
    row.append(edit(el('h4', '', text), 'color.textPrimary'), symbol('chevron_right'));
    return row;
  }

  function home(scroll) {
    scroll.append(chips(copy.channels), chips(copy.categories, 1));
    const hero = el('section', 'home-hero');
    const description = el('div', 'hero-description');
    description.append(edit(el('h4', '', copy.books[0].title), 'color.textPrimary'),
      edit(el('p', '', copy.books[0].author), 'color.textSecondary'), edit(el('p', 'hero-intro', copy.intro), 'color.textSecondary'));
    const deck = el('div', 'hero-deck');
    deck.append(cover(copy.books[2], 'local', 'deck-back', false), cover(copy.books[0], 'online', 'deck-front', false));
    hero.append(description, deck);
    const dots = el('div', 'carousel-dots');
    [0, 1, 2, 3].forEach(index => dots.append(el('i', index === 0 ? 'active' : '')));
    scroll.append(hero, dots);
    [copy.recommendations, copy.ranking].forEach(title => {
      const section = el('section', 'home-book-section');
      section.append(heading(title));
      const rows = el('div', 'home-book-rows');
      copy.books.slice(0, width >= 600 ? 6 : 3).forEach(book => {
        const row = el('div', 'home-book-row');
        const details = el('div', 'book-metadata');
        details.append(edit(el('h4', '', book.title), 'color.textPrimary'), edit(el('p', '', book.author), 'color.textSecondary'),
          el('p', 'book-intro', copy.intro));
        row.append(cover(book, book.local ? 'local' : 'online', '', false), details);
        rows.append(row);
      });
      section.append(rows); scroll.append(section);
    });
  }

  function shelf(scroll) {
    if (buttonPreview === 'button.shelf.searchActive') {
      const search = el('div', 'shelf-search');
      search.append(symbol('magnifyingglass'), el('span', '', copy.search));
      scroll.append(search);
    }
    const collection = context.shelfLayout === 'collection' || ['add', 'expand', 'collapse', 'close'].some(role => buttonPreview === `button.shelf.${role}`);
    if (collection) {
      copy.collectionNames.forEach((name, index) => {
        const folder = el('section', 'shelf-folder');
        const title = el('div', 'folder-title');
        title.append(symbol('folder'), el('h4', '', name), el('small', '', copy.collectionCount));
        if (buttonPreview.startsWith('button.shelf.') && index === 0) {
          ['button.shelf.add', buttonPreview === 'button.shelf.collapse' ? buttonPreview : 'button.shelf.expand', 'button.shelf.close']
            .forEach(key => title.append(toolbarButton(key)));
        }
        const books = el('div', 'folder-books');
        copy.books.slice(index, index + 2).forEach(book => books.append(cover(book, book.local ? 'local' : 'online')));
        folder.append(title, books); scroll.append(folder);
      });
      return;
    }
    scroll.append(chips(copy.shelfGroups, 0, 'shelf-segments'));
    const grid = el('div', context.shelfLayout === 'list' ? 'shelf-list' : 'shelf-grid');
    copy.books.forEach(book => {
      const item = el('article', 'shelf-book');
      item.append(cover(book, book.local ? 'local' : 'online'));
      const details = el('div', 'book-metadata');
      details.append(edit(el('h4', '', book.title), 'color.textPrimary'));
      if (context.shelfLayout === 'list') details.append(el('p', '', book.author), el('small', '', copy.latest));
      details.append(edit(el('p', 'reading-progress', book.progress), 'color.textTertiary'));
      item.append(details);
      if (context.shelfLayout === 'list') item.append(el('p', 'list-intro', copy.intro));
      grid.append(item);
    });
    scroll.append(grid);
  }

  function record(scroll) {
    const summary = el('div', 'record-summary');
    [[copy.total, copy.totalValue, 'clock'], [copy.streak, copy.streakValue, 'calendar']].forEach(([label, amount, name]) => {
      const tag = edit(el('div', 'summary-capsule'), 'color.controlFallback');
      tag.append(symbol(name), el('span', '', label), el('strong', '', amount)); summary.append(tag);
    });
    scroll.append(summary);
    const chart = edit(el('section', 'activity-card'), 'color.surface');
    const title = el('div', 'activity-title');
    title.append(symbol('calendar'), el('strong', '', copy.week), el('span', '', copy.weekValue), symbol('chevron_down'));
    const plot = el('div', 'activity-plot');
    [52, 78, 44, 92, 66, 83, 58].forEach((height, index) => {
      const day = el('div', 'activity-day');
      const column = el('div', 'activity-column');
      const bar = el('div', 'activity-bar'); bar.style.height = `${height}%`;
      [0, 1, 2].forEach(kind => bar.append(el('i', `series-${kind}`)));
      column.append(bar); day.append(column, el('small', '', copy.days[index])); plot.append(day);
    });
    const legend = el('div', 'activity-legend');
    copy.legend.forEach((label, index) => { const entry = el('span'); entry.append(el('i', `series-${index}`), document.createTextNode(label)); legend.append(entry); });
    chart.append(title, plot, legend); scroll.append(chart);
    const quote = el('div', 'daily-quote');
    quote.append(el('small', '', copy.quoteLabel), el('p', '', copy.quote)); scroll.append(quote);
    const history = el('div', 'history-heading');
    history.append(el('h4', '', copy.history), chips(copy.filters)); scroll.append(history);
    [copy.today, copy.yesterday].forEach((label, dayIndex) => {
      scroll.append(el('div', 'record-date', label));
      copy.books.slice(dayIndex * 2, dayIndex * 2 + 2).forEach(book => {
        const row = el('div', 'record-book');
        row.append(cover(book, book.local ? 'local' : 'online'));
        const details = el('div', 'book-metadata');
        details.append(edit(el('h4', '', book.title), 'color.textPrimary'), el('p', '', book.chapter));
        const meta = el('div', 'record-meta');
        meta.append(symbol(book.kind === '阅读' ? 'book_open_fill' : 'headphones_fill'), el('span', '', book.kind),
          el('span', '', '08:32'), el('span', '', book.progress));
        details.append(meta);
        row.append(details, symbol('play_fill', 'record-resume')); scroll.append(row);
      });
    });
  }

  function profile(scroll) {
    const card = edit(el('section', 'profile-account'), 'background.profileCard');
    const image = asset('background.profileCard');
    if (image) card.style.backgroundImage = `url("${image}")`;
    const account = el('div', 'profile-identity');
    const avatar = el('div', 'profile-avatar'); avatar.append(symbol('person'));
    const name = el('div');
    name.append(edit(el('h4', '', copy.account), 'color.textPrimary'), el('p', '', copy.accountDetail));
    account.append(avatar, name);
    const membership = el('div', 'profile-membership');
    membership.append(el('span', '', copy.membershipHint), el('span', 'membership-label', copy.membership));
    card.append(account, membership); scroll.append(card);
    copy.profileGroups.forEach(items => {
      const group = edit(el('div', 'profile-menu'), 'color.profileMenuSurface');
      items.forEach(item => {
        const row = el('div', 'profile-menu-row harmony-list harmony-list-single');
        const icon = symbol(item.symbol, 'profile-menu-icon'); icon.style.color = item.color;
        row.append(icon, el('span', '', item.label), symbol('chevron_right'));
        group.append(row);
      });
      scroll.append(group);
    });
  }

  function player(scroll) {
    const content = el('div', 'player-body');
    const artwork = el('div', 'player-artwork');
    artwork.append(cover(copy.books[0], 'player', 'player-cover', false));
    const metadata = el('div', 'player-metadata');
    metadata.append(el('h4', '', copy.books[0].chapter), el('p', '', copy.books[0].title), el('small', '', copy.playerAuthor));
    const controls = el('div', 'player-panel');
    const track = el('div', 'player-track'); track.append(el('span'));
    const time = el('div', 'player-time'); time.append(el('span', '', copy.elapsed), el('span', '', copy.duration));
    const transport = el('div', 'player-transport');
    [['gobackward_15', copy.rewind], ['backward_end_fill', copy.previous], ['play_fill', copy.play],
      ['forward_end_fill', copy.next], ['goforward_15', copy.forward]].forEach(([name, label], index) => {
      const control = el('span', `transport-control transport-${index}`); control.setAttribute('aria-label', label);
      control.append(symbol(name)); transport.append(control);
    });
    const bottom = el('div', 'player-bottom');
    bottom.append(el('span', '', copy.speed), symbol('timer'), symbol('music_note_list'), symbol('arrow_down_circle'));
    controls.append(track, time, transport, bottom);
    content.append(artwork, metadata, controls); scroll.append(content);
  }

  function bottomBar() {
    const dock = el('nav', `preview-dock harmony-bottomtab ${miniPlayer ? 'with-player' : ''}`);
    dock.dataset.component = 'bottomtab'; dock.dataset.variant = '4';
    const bar = el('div', 'harmony-bottomtab__bar harmony-bottomtab__bar--4');
    const tabs = el('div', 'harmony-bottomtab__tabs');
    const names = ['house', 'shelf', 'clock', 'person'];
    scenes.forEach((item, index) => {
      const active = item === scene;
      const key = `tab.${item}.${active && value(`tab.${item}.selected`) ? 'selected' : 'normal'}`;
      const tab = el('div', `harmony-bottomtab__tab ${active ? 'harmony-bottomtab__tab--active' : ''}`);
      tab.style.color = cssColor(value(active ? 'tab.selectedColor' : 'tab.normalColor'));
      tab.append(themedIcon(key, names[index], 'harmony-bottomtab__tab-icon'),
        edit(el('span', 'harmony-bottomtab__tab-label', t(`theme_editor_${item}`)), active ? 'tab.selectedColor' : 'tab.normalColor'));
      tabs.append(tab);
    });
    bar.append(tabs);
    if (miniPlayer) {
      const mini = edit(el('div', 'preview-mini-player'), 'color.controlFallback');
      mini.append(cover(copy.books[0], 'player', 'mini-cover', false));
      const text = el('div', 'mini-metadata');
      text.append(el('strong', '', copy.books[0].title), el('small', '', copy.books[0].chapter));
      mini.append(text, symbol('play_fill'), symbol('forward_end_fill'), symbol('music_note_list'));
      dock.append(mini);
    }
    dock.append(bar); phone.append(dock);
  }

  backdrop();
  const scroll = el('div', `preview-scroll preview-${scene}`);
  if (scene === 'home') home(scroll);
  else if (scene === 'shelf') shelf(scroll);
  else if (scene === 'record') record(scroll);
  else if (scene === 'profile') profile(scroll);
  else player(scroll);
  phone.append(scroll, header());
  if (scene !== 'player') bottomBar();
  const indicator = el('div', 'harmony-bottomtab__indicator');
  indicator.append(el('div', 'harmony-bottomtab__indicator-bar'));
  phone.append(indicator);
  return phone;
}
