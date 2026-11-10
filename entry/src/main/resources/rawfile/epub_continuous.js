/* Bounded original EPUB scroll window. Each chapter keeps its own CSS and viewport. */
(function () {
  'use strict';
  var cfg = window.hsdaEpubConfig, frames = [], active = null, initial = true;
  var pending = { '-1': false, '1': false }, ended = { '-1': false, '1': false };
  var scheduled = 0, touch = null, suppressClickUntil = 0, wheelTime = 0;
  var reportTimer = 0, lastReport = 0, positionDirty = false;
  var restorePending = null;
  var positionY = 0;
  var lastState = null;
  function send(value) {
    value.token = cfg.token;
    if (window.epubHost) window.epubHost.report(JSON.stringify(value));
  }
  function find(id) { return frames.find(function (frame) { return frame.id === id; }); }
  function stop() { scrollTo(0, scrollY); }
  function offsets() {
    var offset = 0;
    frames.forEach(function (frame) { frame.offset = offset; offset += frame.height; });
  }
  function state(moved) {
    if (!active || !active.ready || restorePending) return null;
    var value = active.view.contentWindow.hsdaEpub.scrolled(moved === true);
    var step = Math.max(80, innerHeight - cfg.top - cfg.bottom - 32);
    value.count = Math.max(1, Math.ceil((active.height - innerHeight) / step - 0.01) + 1);
    value.page = Math.min(value.count - 1, Math.max(0, Math.round((scrollY - active.offset) / step)));
    value.kind = 'position'; value.frame = active.id; value.token = cfg.token;
    return value;
  }
  function appearance() {
    if (active && active.appearance) send(active.appearance);
  }
  function background(frame) {
    // The iframe is clipped to the reading area, while the packaged paper remains
    // full height. Copy CSS backgrounds, including images/gradients and fixed
    // attachment; a solid cover would cut off the book's original artwork.
    var doc = frame.view.contentDocument, root = getComputedStyle(doc.documentElement);
    var body = getComputedStyle(doc.body), paper = document.createElement('div');
    var properties = ['image', 'position', 'size', 'repeat', 'attachment', 'origin', 'clip', 'color'];
    frame.section.style.isolation = 'isolate';
    paper.style.cssText = 'position:absolute;inset:0;z-index:-1;pointer-events:none;box-sizing:border-box;';
    paper.setAttribute('aria-hidden', 'true');
    properties.forEach(function (name) {
      if (!frame.section.style.getPropertyValue('background-' + name)) {
        frame.section.style.setProperty('background-' + name, root.getPropertyValue('background-' + name));
      }
      paper.style.setProperty('background-' + name, body.getPropertyValue('background-' + name));
    });
    // Transparent EPUB paper is white, matching the Web viewport default.
    if (getComputedStyle(frame.section).backgroundColor === 'rgba(0, 0, 0, 0)') frame.section.style.backgroundColor = '#fff';
    frame.section.insertBefore(paper, frame.view);
  }
  function clip(frame) {
    var top = frame.flow ? frame.top : Math.max(frame.top, Math.min(0, frame.bottom - innerHeight));
    var height = frame.flow ? frame.height : innerHeight;
    var value = 'inset(' + Math.max(0, cfg.top - top) + 'px 0 ' +
      Math.max(0, top + height - innerHeight + cfg.bottom) + 'px 0)';
    if (frame.clip !== value) { frame.clip = value; frame.view.style.clipPath = value; }
  }
  function report(force) {
    if (!positionDirty && !force) return;
    // Character ranges and the native bridge are not part of drawing a scroll frame.
    // Report after settling, with a bounded checkpoint during a long continuous gesture.
    if (!force && performance.now() - lastReport < 1000) {
      clearTimeout(reportTimer);
      reportTimer = setTimeout(function () { reportTimer = 0; report(true); }, 160);
      return;
    }
    clearTimeout(reportTimer); reportTimer = 0;
    var value = state(positionDirty);
    if (!value) return;
    positionDirty = false; lastReport = performance.now(); lastState = value; send(value);
  }
  function sync(force) {
    if (scheduled) cancelAnimationFrame(scheduled);
    scheduled = 0;
    var next = active, moved = scrollY !== positionY;
    positionY = scrollY;
    // Section positions only change when the window is extended or its layout changes.
    // Do not force parent layout on every scroll event.
    frames.forEach(function (frame) {
      if (!frame.ready) return;
      frame.top = frame.offset - positionY; frame.bottom = frame.top + frame.height;
      clip(frame);
      frame.readingTop = cfg.top - (frame.flow ? frame.top : Math.min(0, Math.max(frame.top, frame.bottom - innerHeight)));
      if (!frame.flow && frame.bottom > 0 && frame.top < innerHeight) {
        var y = Math.min(frame.height - innerHeight, Math.max(0, -frame.top));
        if (frame.scroll !== y) { frame.scroll = y; frame.view.contentWindow.scrollTo(0, y); }
      }
      if (frame.top <= cfg.top + 1 && frame.bottom > cfg.top + 1) next = frame;
    });
    var changed = next !== active;
    if (changed) { active = next; moved = true; appearance(); }
    positionDirty = positionDirty || moved;
    report(force === true || changed);
    if (!initial) extend();
  }
  function schedule() { if (!scheduled) scheduled = requestAnimationFrame(function () { sync(false); }); }
  function prune(direction) {
    while (frames.length >= 5) {
      var frame = direction > 0 ? frames[0] : frames[frames.length - 1];
      var top = frame.offset - scrollY;
      if (frame === active || !frame.ready || (direction > 0 ? top + frame.height >= 0 : top <= innerHeight)) return false;
      var y = scrollY;
      frame.observer.disconnect(); clearTimeout(frame.timeout); frame.section.remove();
      frames.splice(frames.indexOf(frame), 1);
      offsets();
      if (direction > 0) { scrollTo(0, y - frame.height); positionY = scrollY; }
      ended[String(-direction)] = false;
      send({ kind: 'discard', frame: frame.id });
    }
    return true;
  }
  function request(direction) {
    var key = String(direction);
    if (pending[key] || ended[key] || !prune(direction)) return;
    var frame = direction > 0 ? frames[frames.length - 1] : frames[0];
    if (!frame || !frame.ready) return;
    pending[key] = true;
    send({ kind: 'extend', direction: direction, frame: frame.id });
  }
  function extend() {
    if (!frames.length) return;
    if (frames[0].offset - scrollY > -innerHeight * 2) request(-1);
    var last = frames[frames.length - 1];
    if (last.offset + last.height - scrollY < innerHeight * 3) request(1);
  }
  function measure(frame) {
    if (!frame.ready) return;
    var doc = frame.view.contentDocument;
    var height = frame.flow ? Math.max(innerHeight, doc.body.scrollHeight, doc.body.offsetHeight) :
      Math.max(innerHeight, doc.documentElement.scrollHeight, doc.body.scrollHeight);
    if (Math.abs(height - frame.height) < 1) return;
    var above = frame.offset + frame.height - scrollY <= cfg.top;
    var y = scrollY, delta = height - frame.height;
    frame.height = height; frame.section.style.height = height + 'px';
    if (frame.flow) frame.view.style.height = height + 'px';
    offsets();
    if (above) { scrollTo(0, y + delta); positionY = scrollY; }
    restorePosition();
    schedule();
  }
  function add(value, direction) {
    var section = document.createElement('section'), view = document.createElement('iframe');
    section.style.height = innerHeight + 'px';
    view.setAttribute('title', value.title || '');
    view.setAttribute('scrolling', 'no');
    view.style.height = innerHeight + 'px';
    section.appendChild(view);
    var frame = { id: value.id, section: section, view: view, ready: false, height: innerHeight,
      offset: 0, top: 0, bottom: innerHeight, readingTop: cfg.top, scroll: -1,
      direction: direction, target: 0, flow: false, appearance: null, observer: null, timeout: 0 };
    var y = scrollY;
    if (direction < 0) {
      frames.unshift(frame); document.body.insertBefore(section, document.body.firstChild);
      scrollTo(0, y + innerHeight); positionY = scrollY;
    } else { frames.push(frame); document.body.appendChild(section); }
    offsets();
    if (!active) active = frame;
    frame.timeout = setTimeout(function () {
      if (frame.ready || !find(frame.id)) return;
      if (frame === active) { send({ kind: 'failure' }); return; }
      var above = frame.offset + frame.height - scrollY <= cfg.top, y = scrollY;
      frame.section.remove(); frames.splice(frames.indexOf(frame), 1);
      offsets();
      if (above) { scrollTo(0, y - frame.height); positionY = scrollY; }
      pending[String(direction)] = false;
      send({ kind: 'discard', frame: frame.id });
    }, 12000);
    view.src = value.url;
    restorePosition();
  }
  function receiveFrame(id, value) {
    var frame = find(id);
    if (!frame) return;
    value.frame = id;
    if (value.kind === 'ready') {
      frame.ready = true;
      clearTimeout(frame.timeout);
      frame.flow = frame.view.contentWindow.hsdaEpub.prepareFlow(frame.section);
      if (frame.flow) { frame.view.style.position = 'static'; frame.view.contentWindow.scrollTo(0, 0); }
      background(frame);
      frame.observer = new ResizeObserver(function () { measure(frame); });
      frame.observer.observe(frame.view.contentDocument.body);
      measure(frame);
      pending[String(frame.direction)] = false;
      if (initial && frame === active) {
        initial = false;
        seekFrame(id, frame.target, false);
        send({ kind: 'ready', paint: cfg.paint }); appearance();
      }
      schedule();
    } else if (value.kind === 'appearance') {
      frame.appearance = value;
      if (frame === active) appearance();
    } else if (value.kind === 'selection' || value.kind === 'tap' || value.kind === 'note' || value.kind === 'link') {
      if (value.kind === 'note' || value.kind === 'link') { stop(); sync(true); }
      if (value.kind === 'tap') {
        var bounds = frame.view.getBoundingClientRect();
        // Native-flow chapters can be many screens tall. Tap regions belong to the
        // visible reader viewport, not the expanded chapter's coordinate space.
        value.x += bounds.left; value.y += bounds.top;
        value.width = innerWidth; value.height = innerHeight;
      }
      send(value);
    }
  }
  function seekFrame(id, y, smooth) {
    var frame = find(id);
    if (!frame) return;
    frame.target = y;
    if (!frame.ready || frame !== active) return;
    stop();
    // 字符位置可以落在章末与下一章同屏的区域，不能按单章的一屏高度截断。
    var offset = Math.max(0, Math.min(y >= frame.height ? frame.height - innerHeight : frame.height - cfg.top - 1, y));
    restorePending = { id: id, offset: offset };
    scrollTo({ top: frame.offset + offset,
      behavior: smooth ? 'smooth' : 'instant' });
    positionY = scrollY;
    restorePosition();
    sync(true);
  }
  function restorePosition() {
    if (!restorePending) return;
    var frame = find(restorePending.id);
    if (!frame) { restorePending = null; return; }
    var target = frame.offset + restorePending.offset;
    scrollTo(0, target);
    positionY = scrollY;
    if (Math.abs(scrollY - target) < 1 || ended['1']) restorePending = null;
  }
  function move(delta) { scrollBy(0, delta); sync(false); }
  function beginTouch(event) {
    restorePending = null;
    if (event.touches.length !== 1) { touch = null; return; }
    var point = event.touches[0];
    touch = { x: point.screenX, y: point.screenY, moved: false };
  }
  function moveTouch(event) {
    if (!touch || event.touches.length !== 1) return;
    var point = event.touches[0];
    if (!touch.moved) {
      if (Math.max(Math.abs(point.screenX - touch.x), Math.abs(point.screenY - touch.y)) < 8) return;
      touch.moved = true; send({ kind: 'turn' });
    }
    suppressClickUntil = Date.now() + 500;
  }
  function endTouch() {
    touch = null;
    // touchcancel is normal when the compositor takes ownership of native scrolling.
    // scrollend (or the idle timer) captures the final position after inertia.
  }
  function bindInput(id) {
    var frame = find(id);
    if (!frame) return;
    var doc = frame.view.contentDocument;
    doc.addEventListener('touchstart', beginTouch, { passive: true });
    doc.addEventListener('touchmove', moveTouch, { passive: true });
    doc.addEventListener('touchend', endTouch, { passive: true });
    doc.addEventListener('touchcancel', endTouch, { passive: true });
    doc.addEventListener('wheel', function (event) {
      if (event.ctrlKey) return;
      restorePending = null;
      var now = performance.now();
      if (now - wheelTime > 160) send({ kind: 'turn' });
      wheelTime = now;
    }, { passive: true });
    doc.addEventListener('click', function (event) {
      if (Date.now() < suppressClickUntil) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
  }
  window.hsdaEpub = {
    receiveFrame: receiveFrame, bindInput: bindInput, seekFrame: seekFrame,
    pauseMedia: function (except) {
      frames.forEach(function (frame) {
        if (frame.ready && frame.id !== except) frame.view.contentWindow.hsdaEpub.pauseMedia();
      });
    },
    restoring: function (id) { return initial || !!(restorePending && restorePending.id === id); },
    readingTop: function (id) {
      var frame = find(id);
      return frame ? frame.readingTop : cfg.top;
    },
    append: function (value, direction) {
      if (prune(direction)) add(value, direction);
      else { pending[String(direction)] = false; send({ kind: 'discard', frame: value.id }); }
    },
    finish: function (direction, failed) {
      pending[String(direction)] = false;
      if (!failed) ended[String(direction)] = true;
      restorePosition();
    },
    spot: function () { sync(true); return restorePending ? null : lastState; },
    seek: function (target) { if (active && active.ready) active.view.contentWindow.hsdaEpub.seek(target); },
    turn: function (forward) {
      stop(); restorePending = null; send({ kind: 'turn' });
      var before = scrollY;
      move((forward ? 1 : -1) * Math.max(80, innerHeight - cfg.top - cfg.bottom - 32));
      if (scrollY === before && ended[forward ? '1' : '-1']) send({ kind: 'edge', direction: forward ? 1 : -1 });
    }
  };
  add(cfg.initial, 0);
  // Native scroll chaining owns touch/wheel and inertia. Update the visible child in the
  // scroll event itself, before this frame paints, without an additional rAF of latency.
  addEventListener('scroll', function () { sync(false); }, { passive: true });
  addEventListener('scrollend', function () { report(true); }, { passive: true });
  addEventListener('resize', function () {
    stop();
    var frame = active, target = frame && frame.ready ? frame.view.contentWindow.hsdaEpub.reflowSpot() : null;
    frames.forEach(function (item) {
      item.scroll = -1;
      if (item.flow) item.view.contentWindow.hsdaEpub.setViewport(innerHeight);
      else item.view.style.height = innerHeight + 'px';
      measure(item);
    });
    if (target) requestAnimationFrame(function () {
      if (frame === active && frame.ready) frame.view.contentWindow.hsdaEpub.seek(target);
    });
  });
}());
