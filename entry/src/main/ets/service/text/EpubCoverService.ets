import { BookCoverImageService } from './BookCoverImageService';
import { EpubParserService } from './EpubParserService';

/** 从原 EPUB 的封面资源直接解码，不依赖章节渲染或系统阅读组件。 */
export class EpubCoverService {
  static async extract(parser: EpubParserService, directory: string): Promise<string> {
    const path = parser.getBookInfo().bookCoverImage;
    if (!path) return '';
    try {
      const bytes = await parser.readResource(path, 16 * 1024 * 1024);
      return bytes.byteLength > 0 ? await BookCoverImageService.decode(bytes, directory) : '';
    } catch (_error) { return ''; }
  }
}
