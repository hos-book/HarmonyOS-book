import { PodcastFeedParser } from './PodcastFeedParser';
import { PodcastXmlStream } from './PodcastXmlStream';
import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

@Concurrent
export function parsePodcastFeed(xmlText: string, feedUrl: string): string {
  return JSON.stringify(PodcastFeedParser.parse(xmlText, feedUrl));
}

@Concurrent
export async function downloadPodcastFeed(feedUrl: string): Promise<string> {
  const client = http.createHttp();
  const decoder = util.TextDecoder.create('utf-8');
  const parser = new PodcastXmlStream(feedUrl);
  let received: number = 0;
  let failure: string = '';
  try {
    client.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (failure) return;
      received += chunk.byteLength;
      if (received > PodcastFeedParser.MAX_BYTES) {
        failure = 'podcast_feed_too_large'; client.destroy(); return;
      }
      try { parser.append(decoder.decodeToString(new Uint8Array(chunk), { stream: true })); }
      catch (error) { failure = error instanceof Error ? error.message : 'podcast_invalid_feed'; client.destroy(); }
    });
    const status = await client.requestInStream(feedUrl, {
      method: http.RequestMethod.GET, connectTimeout: 15000, readTimeout: 600000, usingCache: false,
      header: { 'User-Agent': 'Mozilla/5.0', 'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*' }
    }).catch((error: BusinessError): never => {
      console.warn(`[PodcastRSS] request failed: ${error.code} ${error.message}`);
      throw new Error(failure || (error.code === 2300028 ? 'podcast_timeout' : 'podcast_fetch_failed'));
    });
    if (failure) throw new Error(failure);
    if (status < 200 || status >= 300) throw new Error('podcast_fetch_failed');
    parser.append(decoder.decodeToString(new Uint8Array(0), { stream: false }));
    return JSON.stringify(parser.finish());
  } finally { client.destroy(); }
}
