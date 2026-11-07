/* Host adapter for Qingye EpubOriginalScript. Layout, pagination and text location belong to upstream. */
(function () {
  'use strict';
  var cfg = window.hsdaEpubConfig, ready = false, previewing = false;
  var anchor = cfg.spot, current = cfg.spot;
  function send(value) {
    value.token = cfg.token;
    if (window.epubHost) window.epubHost.report(JSON.stringify(value));
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
  window.LegadoEpubHost = {
    ready: function () {
      if (cfg.restorePage >= 0) window.__legado.goPage(cfg.restorePage, false);
      ready = true; current = spot(); send(current);
      var body = getComputedStyle(document.body), html = getComputedStyle(document.documentElement);
      send({ kind: 'appearance', background: color(body.backgroundColor, color(html.backgroundColor, '#ffffff')),
        foreground: color(body.color, '#303030') });
      painted(cfg.paint, 'ready');
    },
    position: function () {
      if (!ready || previewing) return;
      current = spot(); send(current);
    },
    tap: function (x, y) { send({ kind: 'tap', x: x * innerWidth, y: y * innerHeight, width: innerWidth, height: innerHeight }); },
    link: function (href) { send({ kind: 'link', href: href }); },
    edge: function (direction) { send({ kind: 'edge', direction: direction }); }
  };
  document.addEventListener('selectionchange', function () {
    send({ kind: 'selection', selected: !!String(getSelection()).length });
  });
  document.addEventListener('touchmove', function () {
    if (!cfg.paged) { anchor = null; send({ kind: 'turn' }); }
  }, { passive: true });
  window.addEventListener('wheel', function () { anchor = null; send({ kind: 'turn' }); }, { passive: true });
  window.hsdaEpub = {
    spot: spot, seek: seek, turn: turn, preview: preview, restore: restore,
    commit: function () { previewing = false; current = spot(); return current; },
    reflowSpot: function () { anchor = current; return current; }
  };
}());
