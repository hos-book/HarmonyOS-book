import { cleanHtmlBatch, transformText, replaceEpubImages } from 'libhsda_core.so';

@Concurrent
export function cleanLocalBookHtmlBatch(html: string[]): string {
  return JSON.stringify(cleanHtmlBatch(html));
}

@Concurrent
export function cleanEpubBody(html: string, prefix: string, images: string[]): string {
  return replaceEpubImages(transformText(html, 0), prefix, images);
}
