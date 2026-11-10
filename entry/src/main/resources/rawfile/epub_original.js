/* Host adapter for Qingye EpubOriginalScript. Layout, pagination and text location belong to upstream. */
(function () {
  'use strict';
  var cfg = window.hsdaEpubConfig, ready = false, previewing = false;
  var anchor = cfg.spot, current = cfg.spot, restoration = cfg.spot;
  var contentTouch = null;
  var flowing = false, viewportWidth = innerWidth, viewportHeight = innerHeight;
  function protectPagedBounds() {
    if (!cfg.paged) return;
    var body = document.body, style = getComputedStyle(body);
    var top = Math.max(0, parseFloat(style.paddingTop) || 0);
    var bottom = Math.max(0, parseFloat(style.paddingBottom) || 0);
    // Padding paginates the text but does not clip positioned content or column ink.
    // Paint the original background behind the clipped body, including its images.
    var background = document.createElement('div');
    background.setAttribute('aria-hidden', 'true');
    background.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:-1;';
    ['image', 'size', 'position', 'repeat', 'attachment', 'origin', 'clip', 'color'].forEach(function (name) {
      background.style.setProperty('background-' + name, style.getPropertyValue('background-' + name));
    });
    document.documentElement.appendChild(background);
    // Horizontal overflow is the upstream column strip; only clip vertically.
    body.style.setProperty('clip-path', 'inset(' + top + 'px -1000000px ' + bottom + 'px -1000000px)', 'important');
  }
  function setViewport(height) {
    document.documentElement.style.setProperty('--hsda-vh', height / 100 + 'px');
    document.documentElement.style.setProperty('--hsda-vmin', Math.min(innerWidth, height) / 100 + 'px');
    document.documentElement.style.setProperty('--hsda-vmax', Math.max(innerWidth, height) / 100 + 'px');
  }
  function prepareFlow(background) {
    // Ordinary chapters can be a single native scroll surface. Keep a one-screen viewport
    // for pages whose fixed/sticky content or viewport media queries need that viewport.
    var elements = Array.from(document.querySelectorAll('*')), declarations = [], safe = true, fixedBackground = null;
    if (elements.length > 20000) return false;
    elements.forEach(function (el) {
      var style = getComputedStyle(el);
      if (style.display === 'none') return;
      if (/^(fixed|sticky)$/.test(style.position)) safe = false;
      if (style.backgroundImage !== 'none' && /fixed/.test(style.backgroundAttachment)) {
        if (background && (el === document.body || el === document.documentElement) && !fixedBackground &&
            style.backgroundAttachment.split(',').every(function (value) { return value.trim() === 'fixed'; })) fixedBackground = el;
        else safe = false;
      }
      if (el.style) declarations.push(el.style);
    });
    function rules(list) {
      Array.from(list).forEach(function (rule) {
        if (/height|aspect-ratio|orientation|block-size/i.test(rule.conditionText || (rule.media && rule.media.mediaText) || '')) safe = false;
        if (rule.style) {
          // Pseudo-elements may also be fixed; conservatively keep their original viewport.
          if (/::?before|::?after/.test(rule.selectorText || '') &&
              (/fixed|sticky/.test(rule.style.position) || /fixed/.test(rule.style.backgroundAttachment))) safe = false;
          declarations.push(rule.style);
        }
        if (rule.styleSheet) rules(rule.styleSheet.cssRules);
        else if (rule.cssRules) rules(rule.cssRules);
      });
    }
    try { Array.from(document.styleSheets).forEach(function (sheet) { rules(sheet.cssRules); }); }
    catch (_) { return false; }
    if (!safe) return false;
    if (fixedBackground) {
      // Paint the original fixed background in the outer scrolling document. Text and its
      // iframe now move together in the compositor, without an inner scrollTo on every frame.
      var source = getComputedStyle(fixedBackground), root = getComputedStyle(document.documentElement);
      ['image', 'size', 'position', 'repeat', 'attachment', 'origin', 'clip', 'color'].forEach(function (name) {
        background.style.setProperty('background-' + name, source.getPropertyValue('background-' + name));
      });
      if (source.backgroundColor === 'rgba(0, 0, 0, 0)') background.style.backgroundColor = root.backgroundColor;
      fixedBackground.style.setProperty('background', 'transparent', 'important');
      document.documentElement.style.setProperty('background', 'transparent', 'important');
    }
    setViewport(parent.innerHeight);
    // Freeze only viewport-relative lengths, not author pixel/percent geometry. A definite
    // logical html height keeps percentage-height covers independent of the expanded iframe.
    var units = /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|url\([^)]*\))|([-+]?(?:\d*\.)?\d+)(?:[sld]?)(vh|vmin|vmax)\b/gi;
    declarations.forEach(function (style) {
      Array.from(style).forEach(function (name) {
        var value = style.getPropertyValue(name);
        var updated = value.replace(units, function (all, literal, number, unit) {
          return literal || 'calc(' + number + ' * var(--hsda-' + unit.toLowerCase() + '))';
        });
        if (updated !== value) style.setProperty(name, updated, style.getPropertyPriority(name));
      });
    });
    document.documentElement.style.setProperty('height', 'calc(100 * var(--hsda-vh))', 'important');
    flowing = true; viewportWidth = innerWidth; viewportHeight = parent.innerHeight;
    return true;
  }
  // Expanding a native-flow iframe changes innerHeight but does not change the reader's
  // logical viewport. Do not let that synthetic resize repaginate/reseek the chapter.
  addEventListener('resize', function (event) {
    if (!flowing) return;
    if (viewportWidth === innerWidth && viewportHeight === parent.innerHeight) {
      event.stopImmediatePropagation(); return;
    }
    viewportWidth = innerWidth; viewportHeight = parent.innerHeight; setViewport(viewportHeight);
  });
  function originalLayout() {
    var layout = document.getElementById('legado-layout');
    if (layout) layout.textContent = layout.textContent.replaceAll('img,video{object-fit:contain;}', ':where(img,video){object-fit:contain;}');
    var body = document.body, style = getComputedStyle(body);
    var inset = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
    document.documentElement.style.setProperty('--hsda-content-height', 'calc(100vh - ' + inset + 'px)');
    var compat = document.createElement('style');
    compat.textContent =
      'html{touch-action:auto!important;}' +
      'body{min-height:100vh;}' +
      'body.hsda-media-page{height:100vh!important;column-width:auto!important;column-count:auto!important;' +
        'display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;}' +
      '.hsda-media-root{display:flex!important;align-items:center!important;justify-content:center!important;' +
        'width:100%!important;height:100%!important;min-height:0!important;margin:0!important;padding:0!important;}' +
      '.hsda-media-item{display:block!important;width:100%!important;height:100%!important;min-height:0!important;}' +
      '.hsda-gallery{display:flex!important;flex-wrap:nowrap!important;overflow-x:auto!important;overflow-y:hidden!important;' +
        'scroll-snap-type:x mandatory;overscroll-behavior-x:contain;break-inside:avoid;max-width:100%;min-width:0;}' +
      '.hsda-gallery>.duokan-image-gallery-cell{flex:0 0 100%!important;min-width:0!important;box-sizing:border-box;' +
         'display:flex;flex-direction:column;align-items:center;justify-content:center;scroll-snap-align:start;scroll-snap-stop:always;}' +
      '.hsda-gallery>.duokan-image-gallery-cell img{display:block;max-height:calc(var(--hsda-content-height) - 5em)!important;' +
        'width:100%;object-fit:contain;}' +
      'audio,video{max-width:100%;break-inside:avoid;}audio{min-height:54px;}';
    document.head.appendChild(compat);
    document.querySelectorAll('audio,video').forEach(function (media) {
      media.controls = true;
      media.autoplay = false;
      media.removeAttribute('autoplay');
      media.preload = 'none';
      media.setAttribute('playsinline', '');
      media.setAttribute('controlslist', 'nodownload noremoteplayback');
      media.addEventListener('play', function () {
        if (cfg.continuous) window.parent.hsdaEpub.pauseMedia(cfg.frame);
        document.querySelectorAll('audio,video').forEach(function (other) { if (other !== media) other.pause(); });
      });
    });
    // Duokan galleries use reader-defined semantics rather than web overflow CSS.
    document.querySelectorAll('.duokan-image-gallery').forEach(function (gallery) {
      var cells = gallery.querySelectorAll(':scope > .duokan-image-gallery-cell');
      if (cells.length > 1 && !/auto|scroll/.test(getComputedStyle(gallery).overflowX)) gallery.classList.add('hsda-gallery');
    });
    var media = Array.from(body.querySelectorAll('img,svg')).filter(function (el) {
      return !el.closest('svg') || el.tagName.toLowerCase() === 'svg';
    }).filter(function (el) { return el.getClientRects().length > 0; });
    if (media.length !== 1 || body.querySelector('audio,video')) return;
    var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT), node;
    while ((node = walker.nextNode())) {
      if (!node.nodeValue.trim() || node.parentElement.closest('svg,script,style')) continue;
      var range = document.createRange(); range.selectNodeContents(node);
      if (range.getBoundingClientRect().height > 0 && getComputedStyle(node.parentElement).visibility === 'visible') return;
    }
    // Give percentage-height SVG covers a definite containing block; preserve their aspect-ratio policy.
    body.classList.add('hsda-media-page'); media[0].classList.add('hsda-media-item');
    for (var parent = media[0].parentElement; parent && parent !== body; parent = parent.parentElement) {
      parent.classList.add('hsda-media-root');
    }
  }
  function ownsPan(el, dx, dy) {
    var horizontal = Math.abs(dx) > Math.abs(dy);
    if (el && el.closest('audio,video')) return true;
    for (; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
      var style = getComputedStyle(el), max = horizontal ? el.scrollWidth - el.clientWidth : el.scrollHeight - el.clientHeight;
      var overflow = horizontal ? style.overflowX : style.overflowY;
      if (max <= 1 || !/auto|scroll/.test(overflow)) continue;
      return true;
    }
    return false;
  }
  function beginPan(x, y, dx, dy) {
    // The browser may already have scrolled before the native hit test reaches us. Keep
    // the original target and the first movement's owner for this whole touch sequence.
    if (contentTouch) {
      if (contentTouch.owned === null) contentTouch.owned = ownsPan(contentTouch.target, dx, dy);
      return contentTouch.owned;
    }
    return ownsPan(document.elementFromPoint(x, y), dx, dy);
  }
  document.addEventListener('touchstart', function (event) {
    if (!cfg.paged) return;
    if (event.touches.length !== 1) { contentTouch = { owned: true }; return; }
    var point = event.touches[0];
    contentTouch = { target: event.target, x: point.clientX, y: point.clientY, owned: null };
  }, { passive: true, capture: true });
  document.addEventListener('touchmove', function (event) {
    if (!cfg.paged || !contentTouch || event.touches.length !== 1) return;
    var point = event.touches[0], dx = point.clientX - contentTouch.x, dy = point.clientY - contentTouch.y;
    if (contentTouch.owned === null && Math.max(Math.abs(dx), Math.abs(dy)) >= 8) {
      contentTouch.owned = ownsPan(contentTouch.target, dx, dy);
    }
    // Native page turning owns only the non-scrollable page. Galleries, text areas,
    // media controls and their inertia never receive scripted scrollTo corrections.
    if (contentTouch.owned !== true && event.cancelable) event.preventDefault();
  }, { passive: false });
  originalLayout();
  function send(value) {
    value.token = cfg.token;
    if (cfg.continuous) parent.hsdaEpub.receiveFrame(cfg.frame, value);
    else if (window.epubHost) window.epubHost.report(JSON.stringify(value));
  }
  function spot() {
    var value = window.__legado.state();
    value.kind = 'position';
    if (anchor && !anchor.end) { value.snippet = anchor.snippet; value.fraction = anchor.fraction; }
    return value;
  }
  function painted(id, kind) {
    var announced = false;
    function announce() {
      if (announced) return;
      announced = true;
      current = spot();
      send({ kind: kind || 'painted', paint: id });
    }
    requestAnimationFrame(function () { requestAnimationFrame(announce); });
    setTimeout(announce, 180);
  }
  function preview(forward, id) {
    previewing = true; anchor = null;
    var value = spot();
    window.__legado.goPage(value.page + (forward ? 1 : -1), false);
    current = spot(); painted(id);
  }
  function restore(target, id) {
    anchor = target;
    window.__legado.goPage(target.page, false);
    current = spot(); painted(id);
  }
  function seek(target) {
    restoration = target;
    anchor = target.end ? null : target;
    if (target.end) window.__legado.goPage(window.__legado.state().count - 1, false);
    else window.__legado.goSpot(target.snippet, target.fraction);
    current = spot();
  }
  function turn(forward) {
    anchor = null; send({ kind: 'turn' });
    if (forward) window.__legado.next(false); else window.__legado.prev(false);
    current = spot();
  }
  function color(value, fallback) {
    var channels = (value || '').match(/[\d.]+/g);
    if (!channels || channels.length < 3 || (channels.length > 3 && Number(channels[3]) === 0)) return fallback;
    return '#' + channels.slice(0, 3).map(function (v) { return Math.round(Number(v)).toString(16).padStart(2, '0'); }).join('');
  }
  function link(href, note) {
    var url;
    try { url = new URL(href, location.href); } catch (_) { return false; }
    // Only resolve anchors in the current packaged document; never execute book scripts or navigate remotely.
    if (url.origin !== location.origin || !url.hash ||
        (url.pathname !== location.pathname && url.pathname !== cfg.path)) return false;
    var id;
    try { id = decodeURIComponent(url.hash.substring(1)); } catch (_) { return false; }
    var target = document.getElementById(id) || document.getElementsByName(id)[0];
    if (!target) return false;
    if (note || /(?:footnote|endnote)/i.test((target.getAttribute('epub:type') || '') + ' ' +
        (target.getAttribute('role') || ''))) {
      var rows = target.querySelectorAll('li'), items = [], remaining = 24000;
      function item(element, key) {
        var author = element.querySelector('.wrb-u'), content = element.querySelector('.wrb-c');
        var text = (content || element).textContent.replace(/\s+/g, ' ').trim().substring(0, Math.min(4000, remaining));
        if (!text) return;
        remaining -= text.length;
        items.push({ id: id + ':' + key, author: author ? author.textContent.trim().substring(0, 160) : '',
          text: text, avatar: '', time: '', likes: '', replyTo: '' });
      }
      if (rows.length) {
        for (var i = 0; i < rows.length && i < 100 && remaining > 0; i++) item(rows[i], i);
      } else item(target, 0);
      send({ kind: 'note', comments: { items: items, empty: items.length === 0 } });
    } else {
      anchor = null;
      send({ kind: 'turn' });
      window.__legado.goAnchor(id);
      current = spot();
      if (!cfg.continuous && !previewing) send(current);
    }
    return true;
  }
  function linkAt(x, y) {
    var element = document.elementFromPoint(x, y);
    if (element && element.closest('audio,video')) return true;
    var anchor = element && element.closest ? element.closest('a[href]') : null;
    if (!anchor) return false;
    return link(anchor.href, /noteref|footnote|endnote/i.test((anchor.getAttribute('epub:type') || '') + ' ' +
      (anchor.getAttribute('role') || '') + ' ' + (anchor.className || '')));
  }
  window.LegadoEpubHost = {
    ready: function () {
      if (cfg.restorePage >= 0) window.__legado.goPage(cfg.restorePage, false);
      ready = true; current = spot(); send(current);
      protectPagedBounds();
      var body = getComputedStyle(document.body), html = getComputedStyle(document.documentElement);
      send({ kind: 'appearance', background: color(body.backgroundColor, color(html.backgroundColor, '#ffffff')),
        foreground: color(body.color, '#303030') });
      painted(cfg.paint, 'ready');
    },
    position: function () {
      if (!ready || previewing || cfg.continuous) return;
      current = spot(); send(current);
    },
    tap: function (x, y) { send({ kind: 'tap', x: x * innerWidth, y: y * innerHeight, width: innerWidth, height: innerHeight }); },
    link: link,
    edge: function (direction) { send({ kind: 'edge', direction: direction }); }
  };
  var excerptIndex = null;
  window.addEventListener('resize', function () { excerptIndex = null; });
  function excerptCompact(value) {
    return value.replace(/[\s\u200b\ufeff]/g, '').replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉]/g,
      function (digit) { return String('⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉'.indexOf(digit) % 10); });
  }
  function excerptTextIndex() {
    if (excerptIndex) return excerptIndex;
    var nodes = [], text = [], length = 0, hidden = new WeakMap();
    function excluded(element) {
      if (!element || element === document.body) return false;
      if (hidden.has(element)) return hidden.get(element);
      var style = getComputedStyle(element);
      var value = /^(rt|rp|script|style)$/i.test(element.nodeName) || style.display === 'none' ||
        style.visibility === 'hidden' || style.visibility === 'collapse' || excluded(element.parentElement);
      hidden.set(element, value); return value;
    }
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), node;
    while ((node = walker.nextNode())) {
      if (excluded(node.parentElement)) continue;
      var value = excerptCompact(node.nodeValue || '');
      nodes.push({ node: node, offset: length }); text.push(value); length += value.length;
    }
    excerptIndex = { nodes: nodes, text: text.join('') };
    return excerptIndex;
  }
  function excerptBoundary(container, offset, index) {
    var point = document.createRange(); point.setStart(container, offset); point.collapse(true);
    for (var i = 0; i < index.nodes.length; i++) {
      var entry = index.nodes[i];
      if (entry.node === container) return entry.offset + excerptCompact(container.nodeValue.substring(0, offset)).length;
      if (point.comparePoint(entry.node, 0) >= 0) return entry.offset;
    }
    return index.text.length;
  }
  function excerptSpot(index, offset) {
    return { snippet: index.text.substring(offset, offset + 32), fraction: index.text.length ? offset / index.text.length : 0 };
  }
  document.addEventListener('selectionchange', function () {
    var selection = getSelection(), text = String(selection);
    // 多保留一个字符供宿主判断超限，不能静默处理被截断的选区。
    var value = { kind: 'selection', selected: !!text.length, selectionText: text.substring(0, 20001) };
    if (text && selection.rangeCount) {
      var range = selection.getRangeAt(0), index = excerptTextIndex();
      value.selectionStart = excerptSpot(index, excerptBoundary(range.startContainer, range.startOffset, index));
      value.selectionEnd = excerptSpot(index, excerptBoundary(range.endContainer, range.endOffset, index));
    }
    send(value);
  });
  document.addEventListener('touchmove', function () {
    if (!cfg.paged && !cfg.continuous) { anchor = null; send({ kind: 'turn' }); }
  }, { passive: true });
  window.addEventListener('wheel', function () {
    if (!cfg.continuous) { anchor = null; send({ kind: 'turn' }); }
  }, { passive: true });
  window.hsdaEpub = {
    spot: spot, seek: seek, turn: turn, preview: preview, restore: restore, linkAt: linkAt,
    beginPan: beginPan,
    prepareFlow: prepareFlow, setViewport: setViewport,
    mediaTarget: function (element) { return !!(element && element.closest && element.closest('audio,video')); },
    pauseMedia: function () { document.querySelectorAll('audio,video').forEach(function (media) { media.pause(); }); },
    commit: function () { previewing = false; current = spot(); return current; },
    reflowSpot: function () {
      anchor = cfg.continuous && parent.hsdaEpub.restoring(cfg.frame) ? restoration : current;
      return anchor;
    },
    scrolled: function (moved) { if (moved) anchor = null; current = spot(); return current; },
    readingTop: function () { return parent.hsdaEpub.readingTop(cfg.frame); }
  };
  if (cfg.continuous) parent.hsdaEpub.bindInput(cfg.frame);
}());
