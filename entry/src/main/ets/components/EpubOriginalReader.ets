import { webview } from '@kit.ArkWeb';
import { emitter } from '@kit.BasicServicesKit';
import { ReaderCommentMessages } from '../model/ReaderComment';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EpubOriginalDocument, EpubOriginalPart } from '../service/text/EpubOriginalDocument';
import { EpubOriginalStore, EpubOriginalResource } from '../service/text/EpubOriginalStore';
import { EpubOriginalPosition, EpubOriginalSpot, EpubOriginalPositionIndex } from '../service/text/EpubOriginalPosition';
import { EpubOriginalLayoutOptions, EpubOriginalScript } from '../service/text/light/EpubOriginalScript';
import { LocalRuleWebSession } from '../service/rulesource/LocalRuleWebSession';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';
import { AppColor } from '../theme/Theme';
import { ReaderAiAction } from '../model/ReaderAi';
import { ReaderSelectionMenu } from '../utils/ReaderSelectionMenu';

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
  openLinkAt: (x: number, y: number) => Promise<boolean> = async (): Promise<boolean> => false;
  beginPan: (x: number, y: number, dx: number, dy: number) => Promise<boolean> = async (): Promise<boolean> => false;
}

class EpubOriginalCheckpoint {
  request: EpubOriginalRequest = new EpubOriginalRequest();
  parts: EpubOriginalPart[] = [];
  index: number = 0;
  spot: EpubOriginalSpot = new EpubOriginalSpot();
  position: Promise<EpubOriginalSpot> = Promise.resolve(new EpubOriginalSpot());
}

class EpubOriginalMessage extends EpubOriginalSpot {
  comments: ReaderCommentMessages = new ReaderCommentMessages();
  kind: string = '';
  token: number = 0;
  direction: number = 0;
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  href: string = '';
  selected: boolean = false;
  selectionText: string = '';
  selectionStart: EpubOriginalSpot = new EpubOriginalSpot();
  selectionEnd: EpubOriginalSpot = new EpubOriginalSpot();
  paint: number = 0;
  background: string = '';
  foreground: string = '';
  frame: number = 0;
}

class EpubOriginalConfig {
  path: string = '';
  token: number = 0;
  paged: boolean = true;
  spot: EpubOriginalSpot = new EpubOriginalSpot();
  restorePage: number = -1;
  paint: number = 0;
  continuous: boolean = false;
  frame: number = 0;
}

class EpubOriginalFrameInfo {
  id: number = 0;
  url: string = '';
}

class EpubOriginalFrame extends EpubOriginalFrameInfo {
  request: EpubOriginalRequest = new EpubOriginalRequest();
  parts: EpubOriginalPart[] = [];
  index: number = 0;
  document: string = '';
}

class EpubContinuousConfig {
  token: number = 0;
  paint: number = 0;
  top: number = 0;
  bottom: number = 0;
  initial: EpubOriginalFrameInfo = new EpubOriginalFrameInfo();
}

class EpubOriginalBridge {
  receive: (value: string) => void = (_value: string): void => {};
  report(value: string): void {
    if (typeof value !== 'string' || value.length > 65536) return;
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
  @Param paperColor: string = '#FFFFFF';
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
  @Event adjacent: (forward: boolean, chapter: number, notify: boolean) => Promise<EpubOriginalRequest | null> = async () => null;
  @Event onChapter: (request: EpubOriginalRequest) => void = () => {};
  @Event onSelectionChange: (selected: boolean) => void = () => {};
  @Event onExcerpt: (chapter: number, start: number, end: number, text: string) => void = () => {};
  @Event onAi: (chapter: number, action: ReaderAiAction, text: string) => void = () => {};
  @Event onAppearance: (background: string, foreground: string) => void = () => {};
  @Event onNote: (chapter: number, comments: ReaderCommentMessages) => void = () => {};
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
  private continuousScript: string = '';
  private frames: EpubOriginalFrame[] = [];
  private frameSerial: number = 0;
  private activeFrame: number = 0;
  private extending: Set<number> = new Set<number>();
  private document: string = '';
  private documentUrl: string = '';
  private parts: EpubOriginalPart[] = [];
  private partIndex: number = 0;
  private active: EpubOriginalRequest = new EpubOriginalRequest();
  private positionText: string = '';
  private positionIndex: EpubOriginalPositionIndex = new EpubOriginalPositionIndex('');
  private activePaged: boolean = true;
  private layoutInsets: string = '';
  private layoutTimer: number = -1;
  private layoutUpdating: boolean = false;
  private checkpoint: EpubOriginalCheckpoint | null = null;
  private completing: boolean = false;
  private paintResolve: ((ready: boolean) => void) | null = null;
  private paintTimeout: number = -1;
  private paintSerial: number = 0;
  private selectionText: string = '';
  private selectionFrame: number = 0;
  private selectionSerial: number = -1;
  private selectionStart: EpubOriginalSpot | null = null;
  private selectionEnd: EpubOriginalSpot | null = null;
  private backgroundHandler = (): void => {
    if (this.attached) this.controller.runJavaScript('window.hsdaEpub && window.hsdaEpub.pauseMedia()').catch((): void => {});
  };

  aboutToAppear(): void {
    this.alive = true;
    emitter.on('app.reader.background', this.backgroundHandler);
    this.bridge.receive = (value: string): void => this.message(value);
    this.commands.capture = async (): Promise<void> => this.capture();
    this.commands.turn = (forward: boolean): void => this.turn(forward);
    this.commands.seek = (offset: number): void => { this.seek(offset); };
    this.commands.prepare = (forward: boolean): Promise<boolean> => this.prepare(forward);
    this.commands.complete = (commit: boolean): Promise<void> => this.complete(commit);
    this.commands.openLinkAt = (x: number, y: number): Promise<boolean> => this.openLinkAt(x, y);
    this.commands.beginPan = (x: number, y: number, dx: number, dy: number): Promise<boolean> => this.beginPan(x, y, dx, dy);
    this.open().catch((error: Error): void => this.fail(error.message));
  }

  aboutToDisappear(): void {
    emitter.off('app.reader.background', this.backgroundHandler);
    this.backgroundHandler();
    this.alive = false; this.serial++;
    if (this.timeout >= 0) clearTimeout(this.timeout);
    if (this.layoutTimer >= 0) clearTimeout(this.layoutTimer);
    this.layoutTimer = -1;
    this.commands.capture = async (): Promise<void> => {};
    this.commands.turn = (_forward: boolean): void => {};
    this.commands.seek = (_offset: number): void => {};
    this.commands.prepare = async (_forward: boolean): Promise<boolean> => false;
    this.commands.complete = async (_commit: boolean): Promise<void> => {};
    this.commands.openLinkAt = async (): Promise<boolean> => false;
    this.commands.beginPan = async (): Promise<boolean> => false;
    this.finishPaint(false);
    this.frames = []; this.extending.clear();
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
    const continuous = await context.resourceManager.getRawFileContent('epub_continuous.js');
    this.continuousScript = util.TextDecoder.create('utf-8').decodeToString(continuous);
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

  private insetKey(): string {
    return `${this.insetTop}:${this.insetBottom}:${this.insetLeft}:${this.insetRight}`;
  }

  @Monitor('insetTop', 'insetBottom', 'insetLeft', 'insetRight')
  private insetsChanged(): void {
    this.scheduleLayout();
  }

  private scheduleLayout(): void {
    if (!this.alive || !this.attached || !this.initialPageReady ||
      this.layoutTimer >= 0 || this.layoutInsets === this.insetKey()) return;
    this.layoutTimer = setTimeout((): void => {
      this.layoutTimer = -1;
      this.refreshLayout().catch((error: Error): void => this.fail(error.message));
    }, 50);
  }

  private async refreshLayout(): Promise<void> {
    if (!this.alive || this.loading || this.layoutUpdating || this.checkpoint !== null || this.completing ||
      !this.parts.length || this.layoutInsets === this.insetKey()) return;
    this.layoutUpdating = true;
    const ticket = this.serial;
    try {
      const result = await this.controller.runJavaScript('JSON.stringify(window.hsdaEpub.spot())');
      if (!this.alive || ticket !== this.serial) return;
      const parsed: EpubOriginalMessage | string | null = JSON.parse(result);
      const message: EpubOriginalMessage | null = typeof parsed === 'string' ? JSON.parse(parsed) : parsed;
      // 连续视口调整期间可能暂时尚未完成字符恢复，保留当前文档，待恢复后再读取。
      if (message === null) return;
      const spot = this.parseSpot(result);
      if (!this.paged) {
        if (!this.selectContinuousFrame(message.frame)) return;
      }
      // 重排按当前字符恢复，不能回到初次打开章节的位置或沿用旧版面页码。
      this.reportPosition(spot);
      await this.loadPart(this.partIndex, 0, false, spot, false);
    } finally {
      this.layoutUpdating = false;
      this.scheduleLayout();
    }
  }

  private async load(): Promise<void> {
    this.finishPaint(false);
    this.checkpoint = null;
    this.frames = []; this.extending.clear(); this.activeFrame = 0;
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
    restore: EpubOriginalSpot | null = null, restorePage: boolean = true): Promise<void> {
    if (!this.paged) { await this.loadContinuous(index, offset, end, restore); return; }
    const ticket = ++this.serial;
    this.loading = true;
    const part = this.parts[index];
    const source = await fileIo.readText(`${this.active.root}/${part.spine}.html`);
    if (!this.alive || ticket !== this.serial) return;
    this.partIndex = index;
    const painted = this.waitForPaint();
    const config = new EpubOriginalConfig();
    config.token = ticket; config.paged = this.paged; config.spot = this.spot(offset, end);
    config.path = '/assets/' + EpubOriginalDocument.assetPath(part.href);
    config.paint = this.paintSerial;
    if (restore !== null) { config.spot = restore; config.restorePage = restorePage ? restore.page : -1; }
    this.layoutInsets = this.insetKey();
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

  private async continuousFrame(request: EpubOriginalRequest, parts: EpubOriginalPart[], index: number,
    offset: number, end: boolean, ticket: number, restore: EpubOriginalSpot | null = null): Promise<EpubOriginalFrame> {
    const frame = new EpubOriginalFrame();
    frame.id = ++this.frameSerial; frame.request = request; frame.parts = parts; frame.index = index;
    frame.url = `${EpubOriginalDocument.ORIGIN}chapter/${ticket}/${frame.id}.html`;
    const part = parts[index];
    const source = await fileIo.readText(`${request.root}/${part.spine}.html`);
    const config = new EpubOriginalConfig();
    config.token = ticket; config.paged = false; config.continuous = true; config.frame = frame.id;
    config.path = '/assets/' + EpubOriginalDocument.assetPath(part.href);
    config.spot = EpubOriginalPosition.spot(request.text.substring(part.offset, part.offset + part.length),
      Math.max(0, offset - part.offset));
    config.spot.end = end;
    if (restore !== null) config.spot = restore;
    const options = new EpubOriginalLayoutOptions();
    options.paged = false;
    options.margins.top = this.insetTop; options.margins.bottom = this.insetBottom;
    options.margins.left = this.insetLeft; options.margins.right = this.insetRight;
    options.target.kind = end ? 'end' : 'spot';
    options.target.snippet = config.spot.snippet; options.target.fraction = config.spot.fraction;
    const injection = EpubOriginalScript.injection(options);
    const script = `window.hsdaEpubConfig=${JSON.stringify(config).replace(/</g, '\\u003c')};\n${this.script}\n${injection.script}`;
    frame.document = EpubOriginalDocument.build(source, part, script, util.generateRandomUUID().replace(/-/g, ''),
      injection.style + 'html{overflow:hidden!important;touch-action:auto;}');
    return frame;
  }

  private async loadContinuous(index: number, offset: number, end: boolean,
    restore: EpubOriginalSpot | null = null): Promise<void> {
    const ticket = ++this.serial;
    this.loading = true; this.frames = []; this.extending.clear();
    this.layoutInsets = this.insetKey();
    const frame = await this.continuousFrame(this.active, this.parts, index, offset, end, ticket, restore);
    if (!this.alive || ticket !== this.serial) return;
    this.frames = [frame]; this.partIndex = index; this.activeFrame = frame.id;
    const painted = this.waitForPaint();
    const config = new EpubContinuousConfig();
    config.token = ticket; config.paint = this.paintSerial;
    config.top = this.insetTop; config.bottom = this.insetBottom;
    config.initial.id = frame.id; config.initial.url = frame.url;
    const script = `window.hsdaEpubConfig=${JSON.stringify(config)};\n${this.continuousScript}`;
    this.document = EpubOriginalDocument.continuous(script, util.generateRandomUUID().replace(/-/g, ''));
    this.documentUrl = `${EpubOriginalDocument.ORIGIN}chapter/${ticket}.html`;
    this.controller.loadUrl(this.documentUrl);
    if (!await painted && this.alive && ticket === this.serial) throw new Error('Page readiness timed out');
  }

  private async extendContinuous(id: number, forward: boolean): Promise<void> {
    const direction = forward ? 1 : -1;
    const frame = this.frames.find((item: EpubOriginalFrame): boolean => item.id === id);
    if (!frame || this.paged || this.extending.has(direction)) return;
    const ticket = this.serial;
    this.extending.add(direction);
    try {
      let request = frame.request;
      let parts = frame.parts;
      let index = frame.index + direction;
      if (index < 0 || index >= parts.length) {
        const adjacent = await this.adjacent(forward, request.chapter, false);
        if (!this.alive || ticket !== this.serial) return;
        if (adjacent === null) {
          await this.controller.runJavaScript(`window.hsdaEpub.finish(${direction},false)`);
          return;
        }
        request = adjacent;
        parts = await EpubOriginalStore.parts(request.root, request.chapter);
        index = forward ? 0 : parts.length - 1;
      }
      const next = await this.continuousFrame(request, parts, index, parts[index].offset, false, ticket);
      if (!this.alive || ticket !== this.serial) return;
      if (!this.frames.includes(frame)) {
        await this.controller.runJavaScript(`window.hsdaEpub.finish(${direction},true)`);
        return;
      }
      this.frames.push(next);
      const info = new EpubOriginalFrameInfo();
      info.id = next.id; info.url = next.url;
      await this.controller.runJavaScript(`window.hsdaEpub.append(${JSON.stringify(info)},${direction})`);
    } catch (_error) {
      if (this.alive && ticket === this.serial) {
        await this.controller.runJavaScript(`window.hsdaEpub.finish(${direction},true)`).catch((): void => {});
      }
    } finally { if (ticket === this.serial) this.extending.delete(direction); }
  }

  private selectContinuousFrame(id: number): boolean {
    const frame = this.frames.find((item: EpubOriginalFrame): boolean => item.id === id);
    if (!frame) return false;
    if (this.activeFrame !== id) {
      this.activeFrame = id; this.active = frame.request; this.parts = frame.parts; this.partIndex = frame.index;
      this.onChapter(this.active);
    }
    return true;
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
    if (!this.alive || this.loading || this.layoutUpdating || this.checkpoint !== null || this.completing) return false;
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
        const request = await this.adjacent(forward, this.active.chapter, true);
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
    finally { this.completing = false; this.scheduleLayout(); }
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
    if (text !== this.positionText) {
      this.positionText = text;
      this.positionIndex = new EpubOriginalPositionIndex(text);
    }
    const offset = part.offset + this.positionIndex.offset(spot);
    this.onPosition(this.active.chapter, offset, Math.max(0, spot.page), Math.max(1, spot.count));
  }

  private message(value: string): void {
    if (!this.alive) return;
    try {
      const message: EpubOriginalMessage = JSON.parse(value);
      if (message.token !== this.serial) return;
      if (!this.paged) {
        if (message.kind === 'failure') { this.fail('Continuous page readiness timed out'); return; }
        if (message.kind === 'extend') { this.extendContinuous(message.frame, message.direction > 0); return; }
        if (message.kind === 'discard') {
          this.frames = this.frames.filter((item: EpubOriginalFrame): boolean => item.id !== message.frame);
          return;
        }
        if (message.kind === 'position' && !this.selectContinuousFrame(message.frame)) return;
      }
      if (message.kind === 'ready') {
        this.loading = false; clearTimeout(this.timeout); this.timeout = -1;
        if (message.paint === this.paintSerial) this.finishPaint(true);
        this.scheduleLayout();
      }
      else if (message.kind === 'painted' && message.paint === this.paintSerial) this.finishPaint(true);
      else if (message.kind === 'selection') {
        if (message.selected === true && typeof message.selectionText === 'string' && message.selectionText.length <= 20001) {
          if (!this.paged && !this.frames.some((item: EpubOriginalFrame): boolean => item.id === message.frame)) return;
          this.selectionText = message.selectionText;
          this.selectionStart = this.validSelectionSpot(message.selectionStart) ? message.selectionStart : null;
          this.selectionEnd = this.validSelectionSpot(message.selectionEnd) ? message.selectionEnd : null;
          this.selectionFrame = message.frame;
          this.selectionSerial = this.serial;
        }
        this.onSelectionChange(message.selected === true);
      }
      else if (message.kind === 'note') {
        const frame = this.paged ? null : this.frames.find((item: EpubOriginalFrame): boolean => item.id === message.frame);
        if (!this.paged && !frame) return;
        if (!message.comments || !Array.isArray(message.comments.items) || message.comments.items.length > 100) return;
        if (message.comments.items.some((item): boolean => typeof item.id !== 'string' ||
          typeof item.author !== 'string' || typeof item.text !== 'string' || item.text.length > 4000)) return;
        this.onNote(frame ? frame.request.chapter : this.active.chapter, message.comments);
      }
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
        if (!this.paged) {
          const parsed: EpubOriginalMessage | string = JSON.parse(result);
          this.message(typeof parsed === 'string' ? parsed : JSON.stringify(parsed));
          return;
        }
        const spot = this.parseSpot(result);
        this.reportPosition(spot);
      }
    } catch (_error) { /* 最近一次位置报告仍然有效。 */ }
  }

  private async openLinkAt(x: number, y: number): Promise<boolean> {
    if (!this.alive || this.loading || this.layoutUpdating || !this.paged || this.checkpoint !== null ||
      !Number.isFinite(x) || !Number.isFinite(y)) return false;
    const ticket = this.serial;
    try {
      const raw = await this.controller.runJavaScript(`window.hsdaEpub.linkAt(${x},${y})`);
      const value: boolean | string = JSON.parse(raw);
      return ticket !== this.serial || value === true || value === 'true';
    } catch (_error) { return false; }
  }

  private async beginPan(x: number, y: number, dx: number, dy: number): Promise<boolean> {
    if (!this.alive || this.loading || !this.paged || this.checkpoint !== null ||
      ![x, y, dx, dy].every((value: number): boolean => Number.isFinite(value))) return false;
    const ticket = this.serial;
    try {
      const raw = await this.controller.runJavaScript(`window.hsdaEpub.beginPan(${x},${y},${dx},${dy})`);
      const value: boolean | string = JSON.parse(raw);
      return ticket !== this.serial || value === true || value === 'true';
    } catch (_error) { return false; }
  }

  private turn(forward: boolean): void {
    if (this.loading || this.layoutUpdating || !this.alive || !this.attached || this.checkpoint !== null) return;
    this.controller.runJavaScript(`window.hsdaEpub.turn(${forward})`).catch((): void => this.fail());
  }

  private async seek(offset: number): Promise<void> {
    if (this.loading || this.layoutUpdating || !this.alive || !this.parts.length || this.checkpoint !== null) return;
    let index = 0;
    for (let at = 0; at < this.parts.length; at++) if (this.parts[at].offset <= offset) index = at;
    try {
      if (index !== this.partIndex) await this.loadPart(index, offset, false);
      else await this.controller.runJavaScript(`window.hsdaEpub.seek(${JSON.stringify(this.spot(offset))})`);
    } catch (_error) { this.fail(); }
  }

  private response(url: string, headers: Header[] = []): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseCode(200); response.setReasonMessage('OK');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' }]);
    if (url === this.documentUrl) {
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType('text/html'); response.setResponseData(this.document); return response;
    }
    const frame = this.frames.find((item: EpubOriginalFrame): boolean => item.url === url);
    if (frame !== undefined) {
      response.setResponseEncoding('utf-8'); response.setResponseMimeType('text/html');
      response.setResponseData(frame.document); return response;
    }
    const path = EpubOriginalDocument.path(url);
    const mime = EpubOriginalDocument.mime(path);
    if (mime.startsWith('text/') || mime === 'image/svg+xml') response.setResponseEncoding('utf-8');
    response.setResponseMimeType(mime || 'text/plain');
    if (!path || !mime) {
      response.setResponseCode(403); response.setReasonMessage('Forbidden'); response.setResponseData(''); return response;
    }
    response.setResponseIsReady(false);
    if (mime.startsWith('audio/') || mime.startsWith('video/')) {
      const range = headers.find((header: Header): boolean => header.headerKey.toLowerCase() === 'range')?.headerValue ?? '';
      EpubOriginalStore.resourceChunk(this.active.root, path, range).then((resource: EpubOriginalResource): void => {
        const span = resource.range;
        const responseHeaders: Header[] = [
          { headerKey: 'Cache-Control', headerValue: 'no-store' },
          { headerKey: 'Accept-Ranges', headerValue: 'bytes' },
          { headerKey: 'Content-Length', headerValue: String(resource.bytes.byteLength) }
        ];
        if (!span.valid) {
          response.setResponseCode(416); response.setReasonMessage('Range Not Satisfiable');
          responseHeaders.push({ headerKey: 'Content-Range', headerValue: `bytes */${span.size}` });
        } else if (span.partial) {
          response.setResponseCode(206); response.setReasonMessage('Partial Content');
          responseHeaders.push({ headerKey: 'Content-Range', headerValue: `bytes ${span.start}-${span.end}/${span.size}` });
        }
        response.setResponseHeader(responseHeaders); response.setResponseData(resource.bytes);
      }).catch((): void => {
        response.setResponseCode(404); response.setReasonMessage('Not Found'); response.setResponseData('');
      }).finally((): void => response.setResponseIsReady(true));
      return response;
    }
    EpubOriginalStore.resource(this.active.root, path).then((bytes: ArrayBuffer): void => {
      response.setResponseData(mime === 'text/css' ? EpubOriginalDocument.css(
        util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes)), path) : bytes);
    }).catch((): void => {
      response.setResponseCode(404); response.setReasonMessage('Not Found'); response.setResponseData('');
    }).finally((): void => response.setResponseIsReady(true));
    return response;
  }

  private validSelectionSpot(spot: EpubOriginalSpot | undefined): boolean {
    return spot !== undefined && spot !== null && typeof spot.snippet === 'string' && spot.snippet.length <= 32 &&
      Number.isFinite(spot.fraction) && spot.fraction >= 0 && spot.fraction <= 1;
  }

  private emitExcerpt(frame: EpubOriginalFrame | null | undefined, text: string): void {
    const request = frame ? frame.request : this.active;
    const part = frame ? frame.parts[frame.index] : this.parts[this.partIndex];
    const start = this.selectionStart;
    const end = this.selectionEnd;
    if (!part || !start || !end) {
      this.onExcerpt(request.chapter, -1, -1, text); return;
    }
    const source = request.text.substring(part.offset, part.offset + part.length);
    const index = new EpubOriginalPositionIndex(source);
    const from = index.offset(start);
    let to = index.offset(end);
    if (!/\s$/.test(text)) {
      while (to > from && /\s/.test(source.charAt(to - 1))) to--;
    }
    this.onExcerpt(request.chapter, part.offset + from, part.offset + to, text);
  }

  private selectionMenu(): EditMenuOptions {
    return {
      onCreateMenu: (items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(false, items),
      onPrepareMenu: (items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(false, items),
      onMenuItemClick: (item: TextMenuItem, _range: TextRange): boolean => {
        if (!ReaderSelectionMenu.isReaderAction(item.id)) return false;
        if (!this.alive || this.loading || this.checkpoint !== null || this.selectionSerial !== this.serial) return true;
        const frame = this.paged ? null : this.frames.find((value: EpubOriginalFrame): boolean => value.id === this.selectionFrame);
        if (!this.paged && frame === undefined) return true;
        const chapter = frame ? frame.request.chapter : this.active.chapter;
        const text = this.selectionText;
        this.selectionText = ''; this.selectionSerial = -1;
        if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.EXCERPT))) this.emitExcerpt(frame, text);
        else if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY))) this.onAi(chapter, ReaderAiAction.Dictionary, text);
        else if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE))) this.onAi(chapter, ReaderAiAction.Summarize, '');
        this.onSelectionChange(false);
        // 仅清除受控本地文档的选区，保留 Web 位置与阅读会话。
        this.controller.runJavaScript('getSelection().removeAllRanges();' +
          'for(var i=0;i<frames.length;i++){frames[i].getSelection().removeAllRanges();}').catch((): void => {});
        return true;
      }
    };
  }

  build() {
    Stack() {
      if (this.visible) {
        // 等初始空白页完成，再加载章节，避免初始导航取消章节资源请求。
        Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
          .width('100%').height('100%').backgroundColor(this.paperColor)
          .javaScriptAccess(true).fileAccess(false).domStorageAccess(false).databaseAccess(false)
          .geolocationAccess(false).mixedMode(MixedMode.None).zoomAccess(false)
          .darkMode(WebDarkMode.Off).forceDarkAccess(false)
          .mediaPlayGestureAccess(true)
          .editMenuOptions(this.selectionMenu())
          .overScrollMode(OverScrollMode.NEVER).horizontalScrollBarAccess(false).verticalScrollBarAccess(!this.paged)
          .javaScriptProxy({ object: this.bridge, name: 'epubHost', methodList: ['report'], controller: this.controller })
          .onInterceptRequest((event): WebResourceResponse => this.response(event?.request.getRequestUrl() ?? '',
            event?.request.getRequestHeader() ?? []))
          .onLoadIntercept((event): boolean => {
            const url = event?.data.getRequestUrl() ?? '';
            return url !== 'about:blank' && url !== this.documentUrl &&
              !this.frames.some((item: EpubOriginalFrame): boolean => item.url === url);
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
          .width('100%').height('100%').backgroundColor(this.paperColor)
      }
    }.width('100%').height('100%').clip(true)
  }
}
