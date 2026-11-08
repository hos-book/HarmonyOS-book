// Real browser regression for packaged cover geometry and page-internal scrolling.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const vm = require('node:vm');
const { execFile } = require('node:child_process');
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
chapter('/inner', gallery, false, true);
pages.set('/continuous', Document.continuous('window.hsdaEpubConfig={token:1,paint:1,top:40,bottom:30,initial:{id:1,url:"/inner"}};' +
  'window.messages=[];window.epubHost={report(raw){var m=JSON.parse(raw);messages.push(m);if(m.kind==="extend")setTimeout(()=>hsdaEpub.finish(m.direction,false),0)}};' + raw('epub_continuous.js'), 'test'));
pages.set('/', `<html><body><iframe id="view" style="width:400px;height:800px;border:0"></iframe><script>
(async()=>{
  var checks=[], frame=document.getElementById('view');
  var delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  function check(value,message){if(!value)throw Error(message);checks.push(message)}
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
    win.hsdaEpub.movePan(-240,0);win.hsdaEpub.endPan(false);await delay(500);
    check(el.scrollLeft>el.clientWidth*0.9,'gallery advances to the next image');
    check(win.hsdaEpub.spot().page===page,'gallery does not turn the reading page');
    check(win.hsdaEpub.beginPan(x,y,20,0),'gallery can swipe back');win.hsdaEpub.movePan(240,0);win.hsdaEpub.endPan(true);
    check(el.scrollLeft>el.clientWidth*0.9,'cancelled gallery swipe restores its original image');
    var box=win.document.getElementById('inner-scroll');box.scrollIntoView();r=box.getBoundingClientRect();
    check(win.hsdaEpub.beginPan(r.left+20,r.top+20,0,-20),'bounded vertical text area owns vertical swipe');
    win.hsdaEpub.movePan(0,-100);win.hsdaEpub.endPan(false);check(box.scrollTop>=95,'page-internal text can scroll');
    win=await open('/continuous');var child=win.document.querySelector('iframe').contentWindow;
    el=child.document.querySelector('.duokan-image-gallery');r=el.getBoundingClientRect();x=r.left+r.width/2;y=r.top+r.height/2;
    var start=win.scrollY;
    function touch(type,dx,dy){var point=new child.Touch({identifier:1,target:el,clientX:x+dx,clientY:y+dy,screenX:x+dx,screenY:y+dy});return el.dispatchEvent(new child.TouchEvent(type,{view:child,bubbles:true,cancelable:true,touches:type==='touchend'?[]:[point],changedTouches:[point]}))}
    touch('touchstart',0,0);check(touch('touchmove',-240,0),'continuous gallery touch is not blocked by a script listener');touch('touchend',-240,0);
    el.scrollTo(el.clientWidth,0);await delay(500);
    check(el.scrollLeft>el.clientWidth*0.9,'continuous gallery retains native overflow and snap');
    check(win.scrollY===start,'inner gallery swipe keeps chapter scroll position');
    frame.remove();var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:true,checks});document.body.appendChild(result);
  }catch(error){var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:false,error:error.message,checks});document.body.appendChild(result)}
})();</script></body></html>`);
(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-epub-media-'));
  const server = http.createServer((req, res) => {
    res.writeHead(pages.has(req.url) ? 200 : 404, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(pages.get(req.url) || '');
  });
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const output = await new Promise((resolve, reject) => execFile(process.env.EPUB_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', `--user-data-dir=${temp}/profile`, '--window-size=430,900',
        '--disable-background-timer-throttling', '--run-all-compositor-stages-before-draw', '--virtual-time-budget=14000', '--dump-dom', `http://127.0.0.1:${server.address().port}/`],
      { windowsHide: true, timeout: 45000, maxBuffer: 4 * 1024 * 1024 }, (error, stdout) => error ? reject(error) : resolve(stdout)));
    const result = output.match(/<pre id="result">([\s\S]*?)<\/pre>/); assert.ok(result, 'browser tests must finish');
    const value = JSON.parse(result[1].replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>'));
    assert.equal(value.ok, true, JSON.stringify(value)); console.log(`EPUB media Chromium: ${value.checks.join('; ')}`);
  } finally {
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    const resolved = fs.realpathSync(temp);
    assert.equal(path.dirname(resolved).toLowerCase(), fs.realpathSync(os.tmpdir()).toLowerCase());
    assert.ok(path.basename(resolved).startsWith('hsda-epub-media-'));
    fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 8, retryDelay: 200 });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
