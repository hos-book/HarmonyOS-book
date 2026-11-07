import { webview } from '@kit.ArkWeb';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EpubOriginalDocument, EpubOriginalPart } from '../service/text/EpubOriginalDocument';
import { EpubOriginalStore } from '../service/text/EpubOriginalStore';
import { EpubOriginalPosition, EpubOriginalSpot } from '../service/text/EpubOriginalPosition';
import { EpubOriginalLayoutOptions, EpubOriginalScript } from '../service/text/light/EpubOriginalScript';
import { LocalRuleWebSession } from '../service/rulesource/LocalRuleWebSession';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';
import { AppColor } from '../theme/Theme';

export class EpubOriginalRequest {
  root: string = '';
  chapter: number = 0;
  text: string = '';
  offset: number = 0;
  end: boolean = false;
}

export class EpubOriginalController {
  capture: () => Promise<void> = async (): Promise<void> => {};
  turn: (forward: boolean) => void = (_forward: boolean): void => {};
  seek: (offset: number) => void = (_offset: number): void => {};
  prepare: (forward: boolean) => Promise<boolean> = async (_forward: boolean): Promise<boolean> => false;
  complete: (commit: boolean) => Promise<void> = async (_commit: boolean): Promise<void> => {};
}

class EpubOriginalCheckpoint {
  request: EpubOriginalRequest = new EpubOriginalRequest();
  parts: EpubOriginalPart[] = [];
  index: number = 0;
  spot: EpubOriginalSpot = new EpubOriginalSpot();
  position: Promise<EpubOriginalSpot> = Promise.resolve(new EpubOriginalSpot());
}

class EpubOriginalMessage extends EpubOriginalSpot {
  kind: string = '';
  token: number = 0;
  direction: number = 0;
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  href: string = '';
  selected: boolean = false;
  paint: number = 0;
  background: string = '';
  foreground: string = '';
}

class EpubOriginalConfig {
  token: number = 0;
  paged: boolean = true;
  spot: EpubOriginalSpot = new EpubOriginalSpot();
  restorePage: number = -1;
  paint: number = 0;
}

class EpubOriginalBridge {
  receive: (value: string) => void = (_value: string): void => {};
  report(value: string): void {
    if (typeof value !== 'string' || value.length > 4096) return;
    setTimeout((): void => this.receive(value), 0);
  }
}

/** 受全局 Web 租约保护的本地原版阅读器；桥仅报告位置与用户操作。 */
@ComponentV2
export struct EpubOriginalReader {
  @Param request: EpubOriginalRequest = new EpubOriginalRequest();
  @Param commands: EpubOriginalController = new EpubOriginalController();
  @Param paged: boolean = true;
  @Param insetTop: number = 0;
  @Param insetBottom: number = 0;
  @Param insetLeft: number = 20;
  @Param insetRight: number = 20;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Event onPosition: (chapter: number, offset: number, page: number, count: number) => void = () => {};
  @Event onChapterEdge: (forward: boolean) => void = () => {};
  @Event onCenterTap: () => void = () => {};
  @Event onTurn: () => void = () => {};
  @Event onFailure: () => void = () => {};
  @Event adjacent: (forward: boolean) => Promise<EpubOriginalRequest | null> = async () => null;
  @Event onChapter: (request: EpubOriginalRequest) => void = () => {};
  @Event onSelectionChange: (selected: boolean) => void = () => {};
  @Event onAppearance: (background: string, foreground: string) => void = () => {};
  @Local visible: boolean = false;
  @Local loading: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: EpubOriginalBridge = new EpubOriginalBridge();
  private lease: number = 0;
  private alive: boolean = false;
  private attached: boolean = false;
  private initialPageReady: boolean = false;
  private serial: number = 0;
  private timeout: number = -1;
  private script: string = '';
  private document: string = '';
  private documentUrl: string = '';
  private parts: EpubOriginalPart[] = [];
  private partIndex: number = 0;
  private active: EpubOriginalRequest = new EpubOriginalRequest();
  private activePaged: boolean = true;
  private checkpoint: EpubOriginalCheckpoint | null = null;
  private completing: boolean = false;
  private paintResolve: ((ready: boolean) => void) | null = null;
  private paintTimeout: number = -1;
  private paintSerial: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.bridge.receive = (value: string): void => this.message(value);
    this.commands.capture = async (): Promise<void> => this.capture();
    this.commands.turn = (forward: boolean): void => this.turn(forward);
    this.commands.seek = (offset: number): void => { this.seek(offset); };
    this.commands.prepare = (forward: boolean): Promise<boolean> => this.prepare(forward);
    this.commands.complete = (commit: boolean): Promise<void> => this.complete(commit);
    this.open().catch((error: Error): void => this.fail(error.message));
  }

  aboutToDisappear(): void {
    this.alive = false; this.serial++;
    if (this.timeout >= 0) clearTimeout(this.timeout);
    this.commands.capture = async (): Promise<void> => {};
    this.commands.turn = (_forward: boolean): void => {};
    this.commands.seek = (_offset: number): void => {};
    this.commands.prepare = async (_forward: boolean): Promise<boolean> => false;
    this.commands.complete = async (_commit: boolean): Promise<void> => {};
    this.finishPaint(false);
    this.onSelectionChange(false);
    this.bridge.receive = (_value: string): void => {};
    const lease = this.lease;
    this.lease = 0;
    setTimeout((): void => LocalRuleWebSession.release(lease), 0);
  }

  private async open(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('Reader context unavailable');
    const script = await context.resourceManager.getRawFileContent('epub_original.js');
    this.script = util.TextDecoder.create('utf-8').decodeToString(script);
    const lease = await LocalRuleWebSession.acquire(15000);
    if (!this.alive) { LocalRuleWebSession.release(lease); return; }
    this.lease = lease;
    this.visible = true;
  }

  @Monitor('request', 'paged')
  private requestChanged(): void {
    if (this.attached && this.initialPageReady && this.alive) {
      if (this.request === this.active && this.activePaged === this.paged) return;
      this.load().catch((error: Error): void => this.fail(error.message));
    }
  }

  private async load(): Promise<void> {
    this.finishPaint(false);
    this.checkpoint = null;
    const ticket = ++this.serial;
    this.loading = true;
    const request = this.request;
    const parts = await EpubOriginalStore.parts(request.root, request.chapter);
    if (!this.alive || ticket !== this.serial) return;
    this.active = request; this.parts = parts;
    this.activePaged = this.paged;
    let index = 0;
    for (let at = 0; at < parts.length; at++) if (parts[at].offset <= request.offset) index = at;
    await this.loadPart(request.end ? parts.length - 1 : index, request.offset, request.end);
  }

  private spot(offset: number, end: boolean = false): EpubOriginalSpot {
    const part = this.parts[this.partIndex];
    const spot = EpubOriginalPosition.spot(this.active.text.substring(part.offset, part.offset + part.length),
      Math.max(0, offset - part.offset));
    spot.end = end;
    return spot;
  }

  private async loadPart(index: number, offset: number, end: boolean,
    restore: EpubOriginalSpot | null = null): Promise<void> {
    const ticket = ++this.serial;
    this.loading = true;
    const part = this.parts[index];
    const source = await fileIo.readText(`${this.active.root}/${part.spine}.html`);
    if (!this.alive || ticket !== this.serial) return;
    this.partIndex = index;
    const painted = this.waitForPaint();
    const config = new EpubOriginalConfig();
    config.token = ticket; config.paged = this.paged; config.spot = this.spot(offset, end);
    config.paint = this.paintSerial;
    if (restore !== null) { config.spot = restore; config.restorePage = restore.page; }
    const options = new EpubOriginalLayoutOptions();
    options.paged = this.paged;
    options.margins.top = this.insetTop; options.margins.bottom = this.insetBottom;
    options.margins.left = this.insetLeft; options.margins.right = this.insetRight;
    options.target.kind = end ? 'end' : 'spot';
    options.target.snippet = config.spot.snippet; options.target.fraction = config.spot.fraction;
    const injection = EpubOriginalScript.injection(options);
    const script = `window.hsdaEpubConfig=${JSON.stringify(config).replace(/</g, '\\u003c')};\n${this.script}\n${injection.script}`;
    this.document = EpubOriginalDocument.build(source, part, script, util.generateRandomUUID().replace(/-/g, ''),
      injection.style);
    this.documentUrl = `${EpubOriginalDocument.ORIGIN}chapter/${ticket}.html`;
    this.controller.loadUrl(this.documentUrl);
    if (this.timeout >= 0) clearTimeout(this.timeout);
    this.timeout = setTimeout((): void => {
      if (this.alive && ticket === this.serial && this.loading) this.fail('Page readiness timed out');
    }, 12000);
    if (!await painted && this.alive && ticket === this.serial) throw new Error('Page readiness timed out');
  }

  private waitForPaint(): Promise<boolean> {
    this.finishPaint(false);
    this.paintSerial++;
    return new Promise<boolean>((resolve: (ready: boolean) => void): void => {
      this.paintResolve = resolve;
      this.paintTimeout = setTimeout((): void => this.finishPaint(false), 12000);
    });
  }

  private finishPaint(ready: boolean): void {
    if (this.paintTimeout >= 0) clearTimeout(this.paintTimeout);
    this.paintTimeout = -1;
    const resolve = this.paintResolve;
    this.paintResolve = null;
    if (resolve !== null) resolve(ready);
  }

  private async readSpot(): Promise<EpubOriginalSpot> {
    const result = await this.controller.runJavaScript('JSON.stringify(window.hsdaEpub.spot())');
    return this.parseSpot(result);
  }

  private parseSpot(value: string): EpubOriginalSpot {
    // ArkWeb 的脚本返回值可能再包一层 JSON 字符串；桥回调本身没有这一层。
    const parsed: EpubOriginalSpot | string = JSON.parse(value);
    const spot: EpubOriginalSpot = typeof parsed === 'string' ? JSON.parse(parsed) : parsed;
    if (!Number.isFinite(spot.page) || !Number.isFinite(spot.count)) throw new Error('Invalid page position');
    return spot;
  }

  /** 与普通电子书相同：先预览，松手确认才提交；回弹恢复原页。 */
  private async prepare(forward: boolean): Promise<boolean> {
    if (!this.alive || this.loading || this.checkpoint !== null || this.completing) return false;
    const ticket = this.serial;
    const checkpoint = new EpubOriginalCheckpoint();
    checkpoint.request = this.active; checkpoint.parts = this.parts; checkpoint.index = this.partIndex;
    this.checkpoint = checkpoint;
    try {
      checkpoint.position = this.readSpot();
      checkpoint.spot = await checkpoint.position;
      if (!this.alive || this.completing || this.checkpoint !== checkpoint || ticket !== this.serial) return false;
      const edge = forward ? checkpoint.spot.page >= checkpoint.spot.count - 1 : checkpoint.spot.page === 0;
      if (!edge) {
        const painted = this.waitForPaint();
        await this.controller.runJavaScript(`window.hsdaEpub.preview(${forward},${this.paintSerial})`);
        return await painted;
      }
      const next = this.partIndex + (forward ? 1 : -1);
      if (next >= 0 && next < this.parts.length) {
        await this.loadPart(next, this.parts[next].offset, !forward);
      } else {
        const request = await this.adjacent(forward);
        if (!request || !this.alive || this.completing || this.checkpoint !== checkpoint) return false;
        const parts = await EpubOriginalStore.parts(request.root, request.chapter);
        if (!this.alive || this.completing || this.checkpoint !== checkpoint) return false;
        this.active = request; this.parts = parts;
        await this.loadPart(forward ? 0 : parts.length - 1, 0, !forward);
      }
      return this.alive && this.checkpoint === checkpoint;
    } catch (_error) {
      this.finishPaint(false);
      return false;
    }
  }

  private async complete(commit: boolean): Promise<void> {
    const checkpoint = this.checkpoint;
    if (checkpoint === null || this.completing || !this.alive) return;
    this.completing = true;
    try {
      checkpoint.spot = await checkpoint.position;
      if (!commit) {
        if (this.active !== checkpoint.request || this.partIndex !== checkpoint.index || this.loading) {
          this.active = checkpoint.request; this.parts = checkpoint.parts;
          await this.loadPart(checkpoint.index, 0, false, checkpoint.spot);
        } else {
          const painted = this.waitForPaint();
          await this.controller.runJavaScript(`window.hsdaEpub.restore(${JSON.stringify(checkpoint.spot)},${this.paintSerial})`);
          await painted;
        }
      }
      if (!this.alive || this.checkpoint !== checkpoint) return;
      const value = await this.controller.runJavaScript('JSON.stringify(window.hsdaEpub.commit())');
      if (!this.alive || this.checkpoint !== checkpoint) return;
      const spot = this.parseSpot(value);
      this.checkpoint = null;
      if (commit) this.onChapter(this.active);
      this.reportPosition(spot);
    } catch (_error) { this.fail(); }
    finally { this.completing = false; }
  }

  private fail(reason: string = 'Original page operation failed'): void {
    if (!this.alive) return;
    hilog.error(0x0000, 'EpubOriginalReader', 'chapter %{public}d: %{public}s', this.active.chapter, reason);
    this.onFailure();
  }

  private reportPosition(spot: EpubOriginalSpot): void {
    if (this.checkpoint !== null) return;
    if (!Number.isFinite(spot.fraction) || typeof spot.snippet !== 'string' || !this.parts.length) return;
    const part = this.parts[this.partIndex];
    const text = this.active.text.substring(part.offset, part.offset + part.length);
    const offset = part.offset + EpubOriginalPosition.offset(text, spot);
    hilog.debug(0, 'EpubOriginalReader', 'position chapter %{public}d part %{public}d page %{public}d/%{public}d',
      this.active.chapter, this.partIndex, spot.page + 1, spot.count);
    this.onPosition(this.active.chapter, offset, Math.max(0, spot.page), Math.max(1, spot.count));
  }

  private message(value: string): void {
    if (!this.alive) return;
    try {
      const message: EpubOriginalMessage = JSON.parse(value);
      if (message.token !== this.serial) return;
      if (message.kind === 'ready') {
        this.loading = false; clearTimeout(this.timeout); this.timeout = -1;
        if (message.paint === this.paintSerial) this.finishPaint(true);
      }
      else if (message.kind === 'painted' && message.paint === this.paintSerial) this.finishPaint(true);
      else if (message.kind === 'selection') this.onSelectionChange(message.selected === true);
      else if (message.kind === 'appearance' && /^#[0-9a-f]{6}$/i.test(message.background) &&
        /^#[0-9a-f]{6}$/i.test(message.foreground)) this.onAppearance(message.background, message.foreground);
      else if (message.kind === 'position') this.reportPosition(message);
      else if (message.kind === 'turn' && this.checkpoint === null) this.onTurn();
      else if (message.kind === 'edge') {
        if (this.checkpoint !== null) return;
        const forward = message.direction > 0;
        const index = this.partIndex + (forward ? 1 : -1);
        if (index >= 0 && index < this.parts.length) {
          this.loadPart(index, this.parts[index].offset, !forward).catch((): void => this.fail());
        } else this.onChapterEdge(forward);
      } else if (message.kind === 'tap') {
        const action = ReaderTapPolicy.resolve(this.tapRegions, message.x, message.y, message.width, message.height,
          this.tapLeftPercent, this.tapRightPercent, this.tapTopPercent, this.tapBottomPercent);
        if (action === 1) this.onCenterTap();
        else if (action === 0 || action === 2) this.turn(action === 2);
      }
    } catch (_error) { /* 仅接收当前页面的有界位置报告。 */ }
  }

  private async capture(): Promise<void> {
    if (!this.alive || !this.attached || this.loading || this.checkpoint !== null) return;
    const ticket = this.serial;
    try {
      const result = await this.controller.runJavaScript('JSON.stringify(window.hsdaEpub.spot())');
      if (this.alive && ticket === this.serial) {
        const spot = this.parseSpot(result);
        this.reportPosition(spot);
      }
    } catch (_error) { /* 最近一次位置报告仍然有效。 */ }
  }

  private turn(forward: boolean): void {
    if (this.loading || !this.alive || !this.attached || this.checkpoint !== null) return;
    this.controller.runJavaScript(`window.hsdaEpub.turn(${forward})`).catch((): void => this.fail());
  }

  private async seek(offset: number): Promise<void> {
    if (this.loading || !this.alive || !this.parts.length || this.checkpoint !== null) return;
    let index = 0;
    for (let at = 0; at < this.parts.length; at++) if (this.parts[at].offset <= offset) index = at;
    try {
      if (index !== this.partIndex) await this.loadPart(index, offset, false);
      else await this.controller.runJavaScript(`window.hsdaEpub.seek(${JSON.stringify(this.spot(offset))})`);
    } catch (_error) { this.fail(); }
  }

  private response(url: string): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseCode(200); response.setReasonMessage('OK');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' }]);
    if (url === this.documentUrl) {
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType('text/html'); response.setResponseData(this.document); return response;
    }
    const path = EpubOriginalDocument.path(url);
    const mime = EpubOriginalDocument.mime(path);
    if (mime.startsWith('text/') || mime === 'image/svg+xml') response.setResponseEncoding('utf-8');
    response.setResponseMimeType(mime || 'text/plain');
    if (!path || !mime) {
      response.setResponseCode(403); response.setReasonMessage('Forbidden'); response.setResponseData(''); return response;
    }
    response.setResponseIsReady(false);
    EpubOriginalStore.resource(this.active.root, path).then((bytes: ArrayBuffer): void => {
      response.setResponseData(mime === 'text/css' ? EpubOriginalDocument.css(
        util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes)), path) : bytes);
    }).catch((): void => {
      response.setResponseCode(404); response.setReasonMessage('Not Found'); response.setResponseData('');
    }).finally((): void => response.setResponseIsReady(true));
    return response;
  }

  build() {
    Stack() {
      if (this.visible) {
        // 等初始空白页完成，再加载章节，避免初始导航取消章节资源请求。
        Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
          .width('100%').height('100%').backgroundColor(Color.White)
          .javaScriptAccess(true).fileAccess(false).domStorageAccess(false).databaseAccess(false)
          .geolocationAccess(false).mixedMode(MixedMode.None).zoomAccess(false)
          .darkMode(WebDarkMode.Off).forceDarkAccess(false)
          .overScrollMode(OverScrollMode.NEVER).horizontalScrollBarAccess(false).verticalScrollBarAccess(!this.paged)
          .javaScriptProxy({ object: this.bridge, name: 'epubHost', methodList: ['report'], controller: this.controller })
          .onInterceptRequest((event): WebResourceResponse => this.response(event?.request.getRequestUrl() ?? ''))
          .onLoadIntercept((event): boolean => {
            const url = event?.data.getRequestUrl() ?? '';
            return url !== 'about:blank' && url !== this.documentUrl;
          })
          .onControllerAttached((): void => {
            this.attached = true;
            if (this.initialPageReady) this.load().catch((error: Error): void => this.fail(error.message));
          })
          .onPageEnd((event): void => {
            if (event?.url !== 'about:blank' || this.initialPageReady) return;
            this.initialPageReady = true;
            if (this.attached) this.load().catch((error: Error): void => this.fail(error.message));
          })
      }
      if (this.loading) {
        Stack() { LoadingProgress().width(40).height(40).color(AppColor.Brand) }
          .width('100%').height('100%').backgroundColor(Color.White)
      }
    }.width('100%').height('100%').clip(true)
  }
}
