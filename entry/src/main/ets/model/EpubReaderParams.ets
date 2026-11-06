import { bookParser } from '@hms.core.readerservice.bookParser';
import { readerCore } from '@hms.core.readerservice.readerComponent';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';

/** 仅传递类型和参数；本模块不得创建 ReaderKit 对象或引入阅读组件。 */
export class EpubReaderParams {
  controller: readerCore.ReaderComponentController | null = null;
  handler: bookParser.BookParserHandler | null = null;
  tapRegions: string = ReaderTapPolicy.DEFAULT;
  tapLeftPercent: number = 33;
  tapRightPercent: number = 33;
  tapTopPercent: number = 33;
  tapBottomPercent: number = 33;
  startResourceIndex: number = 0;
  startDomPos: string = '';
  pageConfig: readerCore.ReaderSetting | null = null;
  onReady: () => void = () => {};
  onError: (message: string, code: number) => void = () => {};
  onReaderPageShow: (info: readerCore.PageDataInfo) => void = () => {};
  onContentTap: () => void = () => {};
  onManualPageTurn: (active: boolean, immediate?: boolean) => void = () => {};
}
