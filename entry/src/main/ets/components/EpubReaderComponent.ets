import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import lazy { bookParser } from '@hms.core.readerservice.bookParser';
import lazy { ReadPageComponent, readerCore } from '@hms.core.readerservice.readerComponent';
import { EpubReaderParams } from '../model/EpubReaderParams';

export function createEpubReaderController(): readerCore.ReaderComponentController {
  return new readerCore.ReaderComponentController();
}

export function createEpubReaderBuilder(): WrappedBuilder<[EpubReaderParams]> {
  return wrapBuilder(buildEpubReader);
}

@Builder
export function buildEpubReader(params: EpubReaderParams) {
  if (params.controller !== null) {
    EpubReaderComponent({
      controller: params.controller,
      handler: params.handler,
      tapRegions: params.tapRegions,
      tapLeftPercent: params.tapLeftPercent,
      tapRightPercent: params.tapRightPercent,
      tapTopPercent: params.tapTopPercent,
      tapBottomPercent: params.tapBottomPercent,
      startResourceIndex: params.startResourceIndex,
      startDomPos: params.startDomPos,
      pageConfig: params.pageConfig,
      onReady: params.onReady,
      onError: params.onError,
      onReaderPageShow: params.onReaderPageShow,
      onContentTap: params.onContentTap,
      onManualPageTurn: params.onManualPageTurn
    })
  }
}

@ComponentV2
export struct EpubReaderComponent {
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  private tapTracker: ReaderTouchTracker = new ReaderTouchTracker();
  private contentHeight: number = 0;
  @Param controller: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  @Param handler: bookParser.BookParserHandler | null = null;
  @Param startResourceIndex: number = 0;
  @Param startDomPos: string = '';
  @Param pageConfig: readerCore.ReaderSetting | null = null;
  @Event onReady: () => void = () => {};
  @Event onError: (message: string, code: number) => void = (_message: string, _code: number): void => {};
  @Event onReaderPageShow: (info: readerCore.PageDataInfo) => void = (_info: readerCore.PageDataInfo): void => {};
  @Event onContentTap: () => void = () => {};
  @Event onManualPageTurn: (active: boolean, immediate?: boolean) => void = () => {};

  private initialized: boolean = false;
  private pageShowRegistered: boolean = false;
  private contentWidth: number = 0;

  aboutToAppear(): void {
    this.initializeReaderKit().catch((err: BusinessError): void => {
      this.emitReaderError(err);
    });
  }

  aboutToDisappear(): void {
    if (this.pageShowRegistered) {
      try {
        this.controller.off('pageShow');
      } catch (_e) {
        // Reader Kit 可能已经释放回调。
      }
      this.pageShowRegistered = false;
    }
    if (this.initialized) {
      try {
        this.controller.releaseBook();
      } catch (_e) {
        // 验证中途失败时只做尽力释放。
      }
      this.initialized = false;
    }
  }

  private async initializeReaderKit(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.controller.init(context);
    this.initialized = true;
    const pageConfig = this.pageConfig;
    if (pageConfig !== null) {
      this.controller.setPageConfig(pageConfig);
    }
    this.controller.on('pageShow', (info: readerCore.PageDataInfo): void => {
      this.onReaderPageShow(info);
    });
    this.pageShowRegistered = true;

    const parserHandler = this.handler;
    if (parserHandler !== null) {
      this.controller.registerBookParser(parserHandler);
      await this.controller.startPlay(Math.max(0, this.startResourceIndex), this.startDomPos);
    }
    this.onReady();
  }

  private handleReaderCallback(err: BusinessError): void {
    if (err !== undefined && err.code !== 0) {
      this.emitReaderError(err);
    }
  }

  private emitReaderError(err: BusinessError): void {
    const code = typeof err.code === 'number' ? err.code : 0;
    const message = err.message ? err.message : 'ReaderKit 初始化失败';
    this.onError(message, code);
  }

  private handleContentTap(event: GestureEvent): void {
    if (!this.tapTracker.canTap()) return;
    const finger = event.fingerList[0];
    if (finger === undefined) return;
    const action = ReaderTapPolicy.resolve(this.tapRegions, finger.localX, finger.localY,
      this.contentWidth, this.contentHeight, this.tapLeftPercent, this.tapRightPercent, this.tapTopPercent, this.tapBottomPercent);
    if (action === 1) { this.onManualPageTurn(false); this.onContentTap(); }
    else if ((action === 0 || action === 2) && this.initialized) {
      this.onManualPageTurn(true, true);
      try { this.controller.flipPage(action === 2); } catch (_error) { this.onManualPageTurn(false); }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ReadPageComponent({
        controller: this.controller,
        readerCallback: (err: BusinessError, _data: readerCore.ReaderComponentController): void => {
          this.handleReaderCallback(err);
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    // 底色/纹理由父页面的 ReaderBackground 铺；ReaderKit 自身底色走 pageConfig.themeColor
    .onTouch((event: TouchEvent): void => {
      this.tapTracker.update(event);
      if (event.type === TouchType.Down || event.type === TouchType.Cancel) this.onManualPageTurn(false);
      else if (!this.tapTracker.canTap()) this.onManualPageTurn(true);
    })
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions): void => {
      if (typeof newValue.height === 'number') this.contentHeight = newValue.height;
      if (typeof newValue.width === 'number') {
        this.contentWidth = newValue.width;
      }
    })
    .priorityGesture(
      TapGesture().onAction((event: GestureEvent): void => this.handleContentTap(event))
    )
  }
}
