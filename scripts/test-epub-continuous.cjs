// Real Chromium layout + the shipped EPUB scripts; no user profile or book data is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const vm = require('node:vm');
const { execFile, spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const ide = process.env.DEVECO_HOME;
if (!ide) throw Error('Set DEVECO_HOME to the Release IDE');
const browser = process.env.EPUB_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const load = (name, imports = {}) => {
  const exports = {};
  const source = fs.readFileSync(path.join(root, `entry/src/main/ets/service/text/${name}.ets`), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, require: () => imports });
  return exports;
};
const documentModule = load('EpubOriginalDocument');
const { EpubOriginalDocument: Document, EpubOriginalPart: Part } = documentModule;
const { EpubOriginalScript: Script, EpubOriginalLayoutOptions: Options } = load('light/EpubOriginalScript', documentModule);
const raw = name => fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', name), 'utf8');
const chapters = new Map();
for (let id = 1; id <= 12; id++) {
  const options = new Options(); options.paged = false; options.margins.top = 40; options.margins.bottom = 30;
  if (id === 3) { options.target.kind = 'spot'; options.target.snippet = 'Chapter3paragraph26:'; options.target.fraction = 0.93; }
  const injection = Script.injection(options);
   const content = `<html><head><style>body{font:20px/32px serif;background:${id % 2 ? '#ffeecc' : '#ddeeff'};color:#223344;${id === 2 ? 'background-image:linear-gradient(#ddeeff,#ddeeff);background-attachment:fixed;' : ''}}p{margin:0 0 16px}.wrb-note{display:none}</style></head><body><div id="viewport-unit" style="height:10vh"></div>` +
    Array.from({ length: 28 }, (_, n) => `<p>Chapter ${id} paragraph ${n}: 原版精排连续阅读，章节尾部仍然完整可见，相邻章节保留自己的字体和背景。${n === 0 ? '<a id="comment-link" epub:type="noteref" href="#note">6 条段评 ›</a>' : ''}</p>`).join('') +
    '<aside class="wrb-note" epub:type="footnote" id="note"><ol>' +
    Array.from({ length: 6 }, (_, n) => `<li><span class="wrb-u">读者${n}</span><span class="wrb-c">离线段评${n}。${'隐藏评论不应干扰正文的位置定位。'.repeat(70)}</span></li>`).join('') + '</ol></aside></body></html>';
  const config = { token: 1, paged: false, continuous: true, frame: id,
    spot: { snippet: options.target.snippet, fraction: options.target.fraction }, restorePage: -1 };
  chapters.set(`/${id}.html`, Document.build(content, new Part(0, 'chapter.xhtml', 0, content.length),
    `window.hsdaEpubConfig=${JSON.stringify(config)};\n${raw('epub_original.js')}\n${injection.script}`, 'test',
    injection.style + 'html{overflow:hidden!important;touch-action:auto;}'));
}
const harness = String.raw`
var messages=[], failures=[];
// Chromium's virtual-time mode throttles compositor frames; keep frame time deterministic.
window.requestAnimationFrame=fn=>setTimeout(()=>fn(performance.now()),16);
window.cancelAnimationFrame=clearTimeout;
addEventListener('error', e=>failures.push(e.message));
window.epubHost={report(raw){var m=JSON.parse(raw);messages.push(m);
  if(m.kind==='extend')setTimeout(()=>{
    var id=m.frame+m.direction;
    if(id<1||id>12)hsdaEpub.finish(m.direction,false);
    else hsdaEpub.append({id:id,url:'/'+id+'.html'},m.direction);
  },20);
}};
`;
const test = String.raw`
(async function(){
  var checks=[];
  function check(value,message){if(!value)throw Error(message);checks.push(message);}
  var delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  function view(id){return Array.from(document.querySelectorAll('iframe')).find(v=>v.src.endsWith('/'+id+'.html'));}
  async function settle(){await delay(250);hsdaEpub.spot();}
  try{
    await delay(1200);hsdaEpub.spot();await settle();
    check(messages.some(m=>m.kind==='ready'),'initial viewport paints');
    check(hsdaEpub.spot().frame===3,'preloading previous chapter preserves current chapter');
    check(hsdaEpub.spot().fraction>0.92,'opening at a chapter tail restores beyond the old scroll limit');
    var third=view(3), fourth=view(4);
    check(third.style.position==='static'&&third.clientHeight>innerHeight*2,'ordinary chapters scroll as native document content');
    check(Math.abs(third.contentDocument.getElementById('viewport-unit').offsetHeight-innerHeight/10)<=1,
      'viewport units retain the reader height after the iframe expands');
    check(hsdaEpub.spot().count>1,'native-flow progress uses reader screen height rather than expanded iframe height');
    var noteY=scrollY;
    third.contentDocument.getElementById('comment-link').click();
    var note=messages.filter(m=>m.kind==='note').at(-1);
    check(note&&note.comments.items.length===6&&note.comments.items[0].author==='读者0',
      'packaged paragraph notes open with their authors and all six comments');
    check(scrollY===noteY,'opening a note preserves the reading position');
    hsdaEpub.seek({snippet:'Chapter3paragraph0:',fraction:0});await settle();
    var first=hsdaEpub.spot();
    check(view(2).style.position!=='static'&&Math.abs(view(2).clientHeight-innerHeight)<=1,
      'fixed-background chapters keep their original viewport');
    check(first.fraction<0.03&&!first.snippet.includes('隐藏评论'),'hidden notes cannot make a chapter start report 100 percent');
    // Reach the old chapter scroll limit; the next document must already be available.
    scrollTo(0,third.parentElement.offsetTop+third.parentElement.offsetHeight-innerHeight);
    hsdaEpub.spot();await settle();fourth=view(4);
    check(!!fourth,'next chapter is prepared before crossing');
    var end=third.parentElement.offsetTop+third.parentElement.offsetHeight;
    scrollTo(0,end-innerHeight/2);hsdaEpub.spot();
    check(third.getBoundingClientRect().bottom>0&&fourth.getBoundingClientRect().top<innerHeight,
      'chapter tail and next chapter share the viewport');
    check(getComputedStyle(third.contentDocument.body).backgroundColor!==getComputedStyle(fourth.contentDocument.body).backgroundColor,
      'chapter CSS stays isolated');
    var tail=hsdaEpub.spot();hsdaEpub.turn(false);hsdaEpub.seek(tail);await settle();
    check(hsdaEpub.spot().snippet===tail.snippet,'shared chapter tail restores by character');
    // Geometry/position checks below simulate scroll offsets; real touch input is tested separately through CDP.
    scrollTo(0,end-innerHeight-80);hsdaEpub.spot();
    var win=third.contentWindow;
    var reportStart=messages.filter(m=>m.kind==='position').length;
    for(var y=0;y<1100;y+=50){scrollBy(0,50);dispatchEvent(new Event('scroll'));await delay(16);}
    check(messages.filter(m=>m.kind==='position').length-reportStart<=3,'scroll frames defer character mapping and native progress reports');
    await delay(250);hsdaEpub.spot();
    check(hsdaEpub.spot().frame===4,'scroll offsets cross the chapter without a second gesture');
    var saved=hsdaEpub.spot();hsdaEpub.turn(true);hsdaEpub.seek(saved);await settle();
    check(hsdaEpub.spot().snippet===saved.snippet,'character position restores after navigation');
    var beforeResize=hsdaEpub.spot();document.body.style.width='600px';dispatchEvent(new Event('resize'));await settle();
    check(hsdaEpub.spot().snippet===beforeResize.snippet,'window width changes preserve the reading character');
    scrollTo(0,view(4).parentElement.offsetTop-100);hsdaEpub.spot();
    check(hsdaEpub.spot().frame===3,'reverse scroll returns to previous chapter');
    for(var n=0;n<110;n++){hsdaEpub.turn(true);await delay(25);}
    check(hsdaEpub.spot().frame>=10,'continuous scrolling advances through a long book');
    check(document.querySelectorAll('iframe').length<=5,'document window remains bounded');
    check(failures.length===0,'browser reports no script errors');
    var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:true,checks});document.body.appendChild(result);
  }catch(error){var result=document.createElement('pre');result.id='result';result.textContent=JSON.stringify({ok:false,error:error.message,checks,failures,state:hsdaEpub.spot(),frames:Array.from(document.querySelectorAll('iframe')).map(v=>({url:v.src,height:v.parentElement.offsetHeight,top:v.parentElement.getBoundingClientRect().top})),messages:messages.slice(-12)});document.body.appendChild(result);}
})();`;
const page = Document.continuous(`window.hsdaEpubConfig={token:1,paint:1,top:40,bottom:30,initial:{id:3,url:'/3.html'}};\n` +
  harness + raw('epub_continuous.js') + test, 'test');
const nativePage = Document.continuous(`window.hsdaEpubConfig={token:1,paint:1,top:40,bottom:30,initial:{id:3,url:'/3.html'}};\n` +
  harness.replace(/window.requestAnimationFrame=.*\nwindow.cancelAnimationFrame=clearTimeout;/, '') + raw('epub_continuous.js'), 'test');

// Browser-dispatched TouchEvents do not execute default scrolling. Use actual input to catch
// touch-action, passive-listener and iframe scroll-chain regressions.
async function nativeScroll(url, temp) {
  const chrome = spawn(browser, ['--headless=new', '--no-first-run', '--no-default-browser-check',
    `--user-data-dir=${temp}/native-profile`, '--remote-debugging-pipe', 'about:blank'],
  { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });
  let serial = 0, buffer = '', sessionId;
  const pending = new Map();
  chrome.stdio[4].on('data', data => {
    buffer += data.toString();
    let end;
    while ((end = buffer.indexOf('\0')) >= 0) {
      const message = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
      const job = pending.get(message.id);
      if (job) { pending.delete(message.id); clearTimeout(job.timeout); message.error ? job.reject(Error(JSON.stringify(message.error))) : job.resolve(message.result); }
    }
  });
  const command = (method, params = {}, attached = true) => new Promise((resolve, reject) => {
    const id = ++serial;
    pending.set(id, { resolve, reject, timeout: setTimeout(() => { pending.delete(id); reject(Error('CDP timeout: ' + method)); }, 8000) });
    chrome.stdio[3].write(JSON.stringify({ id, method, params, ...(attached && sessionId ? { sessionId } : {}) }) + '\0');
  });
  const evaluate = async expression => {
    const value = await command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (value.exceptionDetails) throw Error(JSON.stringify(value.exceptionDetails));
    return value.result.value;
  };
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  try {
    const { targetId } = await command('Target.createTarget', { url: 'about:blank' });
    sessionId = (await command('Target.attachToTarget', { targetId, flatten: true })).sessionId;
    await command('Emulation.setDeviceMetricsOverride', { width: 430, height: 900, deviceScaleFactor: 1, mobile: true });
    await command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
    await command('Page.navigate', { url: url + '/native' });
    let ready = false;
    for (let n = 0; n < 40 && !ready; n++) { await delay(100); ready = await evaluate('!!(window.hsdaEpub && hsdaEpub.spot() && document.querySelectorAll("iframe").length >= 2)'); }
    assert.ok(ready, 'native input fixture loads');
    await evaluate(`(() => {var v=Array.from(document.querySelectorAll('iframe')).find(v=>v.src.endsWith('/3.html'));
      scrollTo(0,v.parentElement.offsetTop+v.parentElement.offsetHeight-innerHeight/2);hsdaEpub.spot();})()`);
    await delay(150);
    await evaluate(`(() => {window.childScrollCalls=0;for(var v of document.querySelectorAll('iframe')){
      if(v.style.position!=='static')continue;var original=v.contentWindow.scrollTo;
      v.contentWindow.scrollTo=function(){parent.childScrollCalls++;return original.apply(this,arguments)};}})()`);
    const start = await evaluate('scrollY');
    await command('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 215, y: 760 }] });
    for (let y = 740; y >= 180; y -= 20) {
      await command('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 215, y }] }); await delay(16);
    }
    await command('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await delay(650);
    const result = await evaluate('({y:scrollY,state:hsdaEpub.spot(),failures,childScrollCalls})');
    assert.ok(result.y > start + 450, 'native touch scrolls through the iframe into the parent document: ' + JSON.stringify(result));
    assert.equal(result.state.frame, 4, 'one real touch gesture crosses the chapter');
    assert.deepEqual(result.failures, []);
    assert.equal(result.childScrollCalls, 0, 'normal scrolling never drives an inner chapter scroll offset');
    console.log('EPUB native touch: compositor scroll chaining crosses chapters in one gesture');
  } finally {
    for (const job of pending.values()) clearTimeout(job.timeout);
    const exited = new Promise(resolve => chrome.once('exit', resolve)); chrome.kill(); await exited;
  }
}
(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-epub-continuous-'));
  const server = http.createServer((req, res) => {
    const html = req.url === '/' ? page : req.url === '/native' ? nativePage : chapters.get(req.url);
    res.writeHead(html ? 200 : 404, { 'Content-Type': 'text/html; charset=utf-8' });res.end(html || '');
  });
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const output = await new Promise((resolve, reject) => execFile(browser, ['--headless=new', '--disable-gpu',
      '--no-first-run', '--no-default-browser-check', `--user-data-dir=${temp}/profile`, '--window-size=430,900',
      '--disable-background-timer-throttling', '--run-all-compositor-stages-before-draw', '--virtual-time-budget=16000',
      '--dump-dom', `http://127.0.0.1:${server.address().port}/`],
    { windowsHide: true, timeout: 45000, maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) reject(new Error(`${error.message}\n${stderr.slice(-2000)}`));else resolve(stdout);
    }));
    const result = output.match(/<pre id="result">([\s\S]*?)<\/pre>/);
    assert.ok(result, 'browser test must finish');
    const value = JSON.parse(result[1].replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>'));
    assert.equal(value.ok, true, JSON.stringify(value));
    console.log(`EPUB continuous Chromium: ${value.checks.join('; ')}`);
    await nativeScroll(`http://127.0.0.1:${server.address().port}`, temp);
  } finally {
    server.closeAllConnections();await new Promise(resolve => server.close(resolve));
    const resolved = fs.realpathSync(temp);
    assert.equal(path.dirname(resolved).toLowerCase(), fs.realpathSync(os.tmpdir()).toLowerCase());
    assert.ok(path.basename(resolved).startsWith('hsda-epub-continuous-'));
    fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 8, retryDelay: 200 });
  }
})().catch(error => { console.error(error);process.exitCode = 1; });
