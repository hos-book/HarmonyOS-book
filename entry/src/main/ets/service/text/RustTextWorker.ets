import { transformText, transformHtmlBounded, searchOffsets } from 'libhsda_core.so';

export function runBoundedHtmlCodec(kind: string, input: string, remainingMs: number): string {
  const text: string = JSON.parse(input);
  if (text.length > 4 * 1024 * 1024) throw new Error('HTML 编解码输入过大');
  return JSON.stringify(transformHtmlBounded(text, kind === 'encode', remainingMs));
}

@Concurrent
export function scanReaderText(content: string, keyword: string, limit: number): string {
  return JSON.stringify(Array.from(searchOffsets(content, keyword, limit)));
}

@Concurrent
export function parseEpubMetadata(source: string): string {
  return transformText(source, 4);
}
