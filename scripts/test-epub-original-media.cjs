// Real browser regression for packaged cover geometry and page-internal scrolling.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const vm = require('node:vm');
const { spawn, execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
function load(name, imports = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, `entry/src/main/ets/service/text/${name}.ets`), 'utf8'),
    { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText,
  { exports, require: () => imports });
  return exports;
}
const documentModule = load('EpubOriginalDocument');
const { EpubOriginalDocument: Document, EpubOriginalPart: Part } = documentModule;
const { EpubOriginalScript: Script, EpubOriginalLayoutOptions: Options } = load('light/EpubOriginalScript', documentModule);
const raw = name => fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', name), 'utf8');
const picture = 'data:image/svg+xml;base64,' + Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="#975630"/></svg>').toString('base64');
const cover = `<div style="text-align:center"><svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 600 800" preserveAspectRatio="xMidYMid meet"><image href="${picture}" width="600" height="800"/></svg></div>`;
const gallery = '<p id="before">Illustrations</p><div class="duokan-image-gallery" style="width:95%;margin:0 auto">' +
  Array.from({ length: 3 }, (_, i) => `<div class="duokan-image-gallery-cell"><img src="${picture}"/><p>Illustration ${i + 1}</p></div>`).join('') +
  '</div><div id="inner-scroll" style="height:140px;overflow-y:auto">' + '<p>Page internal text</p>'.repeat(16) + '</div><p>Following content</p>';
const pages = new Map();
const assets = new Map();
if (process.env.EPUB_TEST_FILE) {
  const media = JSON.parse(execFileSync('python', ['-c',
    'import zipfile,json,base64,sys;z=zipfile.ZipFile(sys.argv[1]);print(json.dumps({i.filename:base64.b64encode(z.read(i)).decode() for i in z.infolist() if i.filename.lower().endswith((".mp3",".mp4")) and i.file_size<=64*1024*1024}))',
    process.env.EPUB_TEST_FILE], { windowsHide: true, encoding: 'utf8', maxBuffer: 96 * 1024 * 1024 }));
  for (const [name, bytes] of Object.entries(media)) assets.set(name, Buffer.from(bytes, 'base64'));
}
// A generated silent WAV keeps the playback regression runnable without a personal book.
if (!assets.size) {
  const wav = Buffer.alloc(44 + 8000 * 2 * 3);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(8000, 24); wav.writeUInt32LE(16000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
  wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40); assets.set('audio.wav', wav);
}
function chapter(url, content, paged, continuous = false, styles = '') {
  const options = new Options(); options.paged = paged; options.margins.top = 40; options.margins.bottom = 30;
  const injection = Script.injection(options);
  const source = `<html><head><style>body{font:18px/24px serif;background:#eee}p{margin:8px 0}${styles}</style></head><body>${content}</body></html>`;
  const config = { token: 1, paged, continuous, frame: 1, restorePage: -1, spot: { snippet: '', fraction: 0 } };
  pages.set(url, Document.build(source, new Part(0, 'test.xhtml', 0, source.length),
    `window.hsdaEpubConfig=${JSON.stringify(config)};window.messages=[];window.epubHost={report(raw){messages.push(JSON.parse(raw))}};` +
    raw('epub_original.js') + injection.script, 'test', injection.style + (continuous ? 'html{overflow:hidden!important;touch-action:auto;}' : '')));
}
chapter('/cover-scroll', cover, false);
chapter('/cover-paged', cover, true);
chapter('/image', `<div><img src="${picture}"/></div>`, false);
chapter('/fill', `<img src="${picture}"/>`, true, false, 'img{object-fit:cover}');
chapter('/gallery', gallery, true);
chapter('/bounds', '<div id="above" style="position:fixed;top:0;left:0;width:100%;height:60px;background:red"></div>' +
  '<div id="below" style="position:fixed;bottom:0;left:0;width:100%;height:50px;background:blue"></div>' +
  '<p id="start">Beginning of the chapter and its saved position.</p>' +
  '<p>Original typesetting stays inside the reading viewport.</p>'.repeat(45) +
  '<p id="later">Destination paragraph after the internal link.</p>' + '<p>Following content.</p>'.repeat(15),
  true, false, 'body{background:linear-gradient(#dceedd 50%,#ddccbb 50%) fixed}');
chapter('/translucent', '<p>Translucent paper</p>', true, false,
  'body{background:rgba(0,255,0,.5)}@media(min-width:600px){body{background:rgba(0,0,255,.5)}}');
chapter('/inner', gallery, false, true);
chapter('/playback', Array.from(assets.keys()).map(name => {
  const tag = name.endsWith('.mp4') ? 'video' : 'audio';
  return `<${tag} class="duokan-${tag}" style="width:300px;${tag === 'video' ? 'height:180px;' : ''}"><source src="/${name}" type="${Document.mime(name)}"/></${tag}>`;
}).join(''), true);
pages.set('/continuous', Document.continuous('window.hsdaEpubConfig={token:1,paint:1,top:40,bottom:30,initial:{id:1,url:"/inner"}};' +
  'window.messages=[];window.epubHost={report(raw){var m=JSON.parse(raw);messages.push(m);if(m.kind==="extend")setTimeout(()=>hsdaEpub.finish(m.direction,false),0)}};' + raw('epub_continuous.js'), 'test'));
pages.set('/', `<html><body><iframe id="view" style="width:400px;height:800px;border:0"></iframe><script>
(async()=>{
  var checks=[], frame=document.getElementById('view');
  var delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  function check(value,message){if(!value)throw Error(message);checks.push(message)}
  function event(media,name,action){return new Promise((resolve,reject)=>{
    var timer=setTimeout(()=>finish(Error(name+' timeout: '+media.currentSrc+' state='+media.readyState)),8000);
    function finish(error){clearTimeout(timer);media.removeEventListener(name,done);media.removeEventListener('error',failed);error?reject(error):resolve()}
    function done(){finish()}function failed(){finish(Error('media error '+media.error?.code+': '+media.currentSrc))}
    media.addEventListener(name,done,{once:true});media.addEventListener('error',failed,{once:true});action();
  })}
  async function open(url){frame.src=url;await new Promise(resolve=>frame.onload=resolve);await delay(500);return frame.contentWindow}
  try{
    for(var url of ['/cover-scroll','/cover-paged','/image']){
      var win=await open(url), image=win.document.querySelector('image,img'), rect=image.getBoundingClientRect();
      check(Math.abs((rect.top+rect.bottom)/2-405)<2,url+' cover is vertically centered in the usable viewport');
      check(Math.abs((rect.left+rect.right)/2-200)<2,url+' cover is horizontally centered');
      check(win.document.documentElement.scrollHeight<=802&&win.document.documentElement.scrollWidth<=402,url+' cover fits one page');
    }
    win=await open('/fill');check(win.getComputedStyle(win.document.querySelector('img')).objectFit==='cover','explicit original cover fit is retained');
    win=await open('/gallery');var el=win.document.querySelector('.duokan-image-gallery'), r=el.getBoundingClientRect(), x=r.left+r.width/2,y=r.top+r.height/2;
    var page=win.hsdaEpub.spot().page;
    check(el.scrollWidth>el.clientWidth*2.5,'Duokan gallery becomes a horizontal strip');
    check(win.hsdaEpub.beginPan(x,y,-20,0),'gallery owns horizontal swipe');
    check(win.getComputedStyle(win.document.documentElement).touchAction==='auto','paged viewport allows browser-native nested scrolling');
    check(el.style.scrollSnapType==='','hit testing never disables or resets native snap');
    el.scrollTo(el.clientWidth,0);await delay(500);
    check(el.scrollLeft>el.clientWidth*0.9,'gallery advances to the next image');
    check(win.hsdaEpub.spot().page===page,'gallery does not turn the reading page');
    check(win.hsdaEpub.beginPan(x,y,20,0),'gallery can swipe back');
    check(el.scrollLeft>el.clientWidth*0.9,'repeated native hit tests preserve the current image');
    var box=win.document.getElementById('inner-scroll');box.scrollIntoView();r=box.getBoundingClientRect();
    check(win.hsdaEpub.beginPan(r.left+20,r.top+20,0,-20),'bounded vertical text area owns vertical swipe');
    box.scrollTop=100;check(box.scrollTop>=95,'page-internal text can scroll');
    win=await open('/continuous');var child=win.document.querySelector('iframe').contentWindow;
    el=child.document.querySelector('.duokan-image-gallery');r=el.getBoundingClientRect();x=r.left+r.width/2;y=r.top+r.height/2;
    var start=win.scrollY;
    function touch(type,dx,dy){var point=new child.Touch({identifier:1,target:el,clientX:x+dx,clientY:y+dy,screenX:x+dx,screenY:y+dy});return el.dispatchEvent(new child.TouchEvent(type,{view:child,bubbles:true,cancelable:true,touches:type==='touchend'?[]:[point],changedTouches:[point]}))}
    touch('touchstart',0,0);check(touch('touchmove',-240,0),'continuous gallery touch is not blocked by a script listener');touch('touchend',-240,0);
    el.scrollTo(el.clientWidth,0);await delay(500);
    check(el.scrollLeft>el.clientWidth*0.9,'continuous gallery retains native overflow and snap');
    check(win.scrollY===start,'inner gallery swipe keeps chapter scroll position');
    win=await open('/playback');
    for(var media of win.document.querySelectorAll('audio,video')){
      check(media.controls&&!media.autoplay,'Duokan '+media.tagName+' has manual playback controls');
      var prevented=!media.dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true}));
      check(!prevented,'media clicks reach browser controls without triggering page turns');
      await event(media,'loadeddata',()=>{media.preload='auto';media.load()});
      check(media.duration>0&&media.readyState>=2,'packaged '+media.tagName+' loads and decodes');
      await media.play();check(!media.paused,'packaged '+media.tagName+' starts playing');
      media.pause();await event(media,'seeked',()=>{media.currentTime=Math.min(1,media.duration/2)});
      check(media.currentTime>0,'packaged '+media.tagName+' supports seeking');
    }
    frame.remove();var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:true,checks});document.body.appendChild(result);
  }catch(error){var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:false,error:error.message,checks});document.body.appendChild(result)}
})();</script></body></html>`);

// Media decoding uses wall time; a virtual-time dump can finish before loadeddata/play.
async function browserResult(url, temp) {
  const chrome = spawn(process.env.EPUB_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--mute-audio', '--autoplay-policy=no-user-gesture-required',
      '--no-first-run', '--no-default-browser-check', `--user-data-dir=${temp}/profile`,
      '--window-size=430,900', '--remote-debugging-pipe', 'about:blank'],
    { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });
  let serial = 0, buffer = '', sessionId;
  const pending = new Map();
  chrome.stdio[4].on('data', data => {
    buffer += data.toString(); let end;
    while ((end = buffer.indexOf('\0')) >= 0) {
      const message = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
      const job = pending.get(message.id);
      if (job) { pending.delete(message.id); clearTimeout(job.timeout); message.error ? job.reject(Error(JSON.stringify(message.error))) : job.resolve(message.result); }
    }
  });
  function command(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++serial;
      pending.set(id, { resolve, reject, timeout: setTimeout(() => { pending.delete(id); reject(Error('CDP timeout: ' + method)); }, 8000) });
      chrome.stdio[3].write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + '\0');
    });
  }
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function evaluate(expression) {
    const value = await command('Runtime.evaluate', { expression, returnByValue: true });
    if (value.exceptionDetails) throw Error(JSON.stringify(value.exceptionDetails));
    return value.result.value;
  }
  async function swipe(x, y, dx, dy) {
    await command('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    for (let n = 1; n <= 20; n++) {
      await command('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx * n / 20, y: y + dy * n / 20 }] });
      await delay(16);
    }
    await command('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await delay(600);
  }
  async function nativeNested(value) {
    await command('Emulation.setDeviceMetricsOverride', { width: 430, height: 900, deviceScaleFactor: 1, mobile: true });
    await command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
    await command('Page.navigate', { url: url + 'gallery' });
    let ready = false;
    for (let n = 0; n < 40 && !ready; n++) {
      await delay(100); ready = await evaluate('!!(window.hsdaEpub && window.__legado && window.messages.some(m=>m.kind==="ready"))');
    }
    assert.ok(ready, 'native gallery is ready');
    const rect = await evaluate(`(() => {var el=document.querySelector('.hsda-gallery'),r=el.getBoundingClientRect();
      return {x:r.left,y:r.top,w:r.width,h:r.height,page:hsdaEpub.spot().page};})()`);
    await swipe(rect.x + rect.w * .85, rect.y + rect.h / 2, -rect.w * .7, 0);
    const forward = await evaluate('document.querySelector(".hsda-gallery").scrollLeft');
    assert.ok(forward > rect.w * .9 && forward < rect.w * 1.1, 'native swipe snaps to one image without script correction: ' + forward);
    assert.equal(await evaluate('hsdaEpub.spot().page'), rect.page, 'gallery swipe never moves the reading page');
    await swipe(rect.x + rect.w * .15, rect.y + rect.h / 2, rect.w * .7, 0);
    assert.ok(await evaluate('document.querySelector(".hsda-gallery").scrollLeft') < 2, 'reverse native swipe returns to the first image');
    const box = await evaluate(`(() => {var r=document.getElementById('inner-scroll').getBoundingClientRect();return {x:r.left+20,y:r.top+120}})()`);
    await swipe(box.x, box.y, 0, -100);
    assert.ok(await evaluate('document.getElementById("inner-scroll").scrollTop') >= 80, 'native vertical text scrolling works inside a paged chapter');
    assert.equal(await evaluate('hsdaEpub.spot().page'), rect.page, 'vertical inner scrolling keeps the chapter page');
    value.checks.push('real touch: native gallery forward/reverse snap and nested vertical scrolling preserve the reading page');
    return value;
  }
  async function protectedBounds(value) {
    await command('Page.navigate', { url: url + 'bounds' });
    for (let n = 0; n < 40; n++) {
      await delay(100);
      if (await evaluate('!!(window.hsdaEpub && window.messages.some(m=>m.kind==="ready"))')) break;
    }
    assert.ok(await evaluate('hsdaEpub.spot().count > 2'), 'bounds fixture has several pages');
    assert.equal(await evaluate('document.elementFromPoint(200,20)?.id'), '', 'positioned content cannot enter the header');
    assert.equal(await evaluate('document.elementFromPoint(200,innerHeight-10)?.id'), '', 'positioned content cannot enter the footer');
    for (const page of [0, 1]) {
      await evaluate(`__legado.goPage(${page},false)`); await delay(100);
      const png = await command('Page.captureScreenshot', { format: 'png' });
      const file = path.join(temp, `bounds-${page}.png`); fs.writeFileSync(file, Buffer.from(png.data, 'base64'));
      const colors = JSON.parse(execFileSync('python', ['-c',
        'from PIL import Image;import json,sys;i=Image.open(sys.argv[1]).convert("RGB");print(json.dumps([i.getpixel((200,20)),i.getpixel((200,i.height-10))]))', file],
      { windowsHide: true, encoding: 'utf8' }));
      assert.deepEqual(colors, [[220, 238, 221], [221, 204, 187]], 'original fixed background continues through protected header/footer on page ' + page);
    }
    await evaluate('hsdaEpub.seek({snippet:"Beginningofthechapter",fraction:0})');
    const before = await evaluate('hsdaEpub.spot()');
    assert.equal(await evaluate('LegadoEpubHost.link("#later",false)'), true);
    const after = await evaluate('hsdaEpub.spot()');
    assert.ok(after.page > before.page && after.fraction > before.fraction, 'internal anchors update both page and saved character position');
    const saved = after.snippet;
    await evaluate('hsdaEpub.seek(' + JSON.stringify(after) + ')');
    assert.equal(await evaluate('hsdaEpub.spot().snippet'), saved, 'internal anchor position survives restore');
    await command('Page.navigate', { url: url + 'translucent' });
    await delay(700);
    for (const width of [430, 720]) {
      await command('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: true });
      await delay(300);
      const png = await command('Page.captureScreenshot', { format: 'png' });
      const file = path.join(temp, `paper-${width}.png`); fs.writeFileSync(file, Buffer.from(png.data, 'base64'));
      const colors = JSON.parse(execFileSync('python', ['-c',
        'from PIL import Image;import json,sys;i=Image.open(sys.argv[1]).convert("RGB");print(json.dumps([i.getpixel((200,y)) for y in [20,450,i.height-10]]))', file],
      { windowsHide: true, encoding: 'utf8' }));
      const expected = width === 430 ? [127, 255, 127] : [127, 127, 255];
      assert.deepEqual(colors, [expected, expected, expected], 'translucent paper renders once and follows responsive styles at width ' + width);
    }
    value.checks.push('paged header/footer clip positioned content while preserving fixed backgrounds on later pages; internal anchor progress restores');
    return value;
  }
  try {
    const { targetId } = await command('Target.createTarget', { url: 'about:blank' });
    sessionId = (await command('Target.attachToTarget', { targetId, flatten: true })).sessionId;
    await command('Page.navigate', { url });
    for (let n = 0; n < 180; n++) {
      await new Promise(resolve => setTimeout(resolve, 250));
      const value = await command('Runtime.evaluate', { expression: 'document.getElementById("result")?.textContent', returnByValue: true });
      if (value.exceptionDetails) throw Error(JSON.stringify(value.exceptionDetails));
      if (value.result.value) {
        const result = JSON.parse(value.result.value);
        return result.ok ? await protectedBounds(await nativeNested(result)) : result;
      }
    }
    throw Error('browser tests must finish');
  } finally {
    for (const job of pending.values()) clearTimeout(job.timeout);
    const exited = new Promise(resolve => chrome.once('exit', resolve)); chrome.kill(); await exited;
  }
}
(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-epub-media-'));
  const server = http.createServer((req, res) => {
    const asset = decodeURIComponent(req.url.replace(/^\/assets\//, ''));
    if (assets.has(asset)) {
      const bytes = assets.get(asset), range = new documentModule.EpubOriginalRange(bytes.length, req.headers.range || '');
      const headers = { 'Content-Type': Document.mime(asset), 'Accept-Ranges': 'bytes' };
      if (!range.valid) { res.writeHead(416, { ...headers, 'Content-Range': 'bytes */' + bytes.length });res.end();return; }
      if (range.partial) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${range.size}`;
      const data = bytes.subarray(range.start, range.end + 1);headers['Content-Length'] = data.length;
      res.writeHead(range.partial ? 206 : 200, headers);res.end(data);return;
    }
    res.writeHead(pages.has(req.url) ? 200 : 404, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end((pages.get(req.url) || '').replaceAll(Document.ORIGIN, `http://127.0.0.1:${server.address().port}/`));
  });
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const value = await browserResult(`http://127.0.0.1:${server.address().port}/`, temp);
    assert.equal(value.ok, true, JSON.stringify(value)); console.log(`EPUB media Chromium: ${value.checks.join('; ')}`);
  } finally {
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    const resolved = fs.realpathSync(temp);
    assert.equal(path.dirname(resolved).toLowerCase(), fs.realpathSync(os.tmpdir()).toLowerCase());
    assert.ok(path.basename(resolved).startsWith('hsda-epub-media-'));
    fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 8, retryDelay: 200 });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
