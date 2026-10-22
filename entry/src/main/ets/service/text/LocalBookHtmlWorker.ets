import { LocalBookHtmlText } from './LocalBookHtmlText';

@Concurrent
export function cleanLocalBookHtmlBatch(html: string[]): string {
  return JSON.stringify(html.map((item: string): string => LocalBookHtmlText.clean(item)));
}
