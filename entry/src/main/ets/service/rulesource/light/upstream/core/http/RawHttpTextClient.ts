import { connection, socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

interface RawHttpTarget {
  host: string;
  port: number;
  path: string;
}

interface RawHttpBodyResult {
  complete: boolean;
  data: Uint8Array;
}

/**
 * Minimal plain-HTTP reader used only as a compatibility fallback.
 * It deliberately parses chunked bodies itself so a peer closing the socket
 * after the final chunk cannot make Network Kit discard an otherwise valid file.
 */
export class RawHttpTextClient {
  static async get(url: string, maxBytes: number, timeoutMs: number): Promise<string> {
    const target = this.parseTarget(url);
    // ArkUI-X 的 connection 声明里没有 getAddressesByName，取不到时走调用方的异常兜底。
    const addresses = await (connection as any).getAddressesByName(target.host);
    if (!addresses || addresses.length === 0) throw new Error('TCP兜底无法解析域名');
    let lastError = 'TCP兜底连接失败';
    for (const address of addresses) {
      try {
        return await this.getFromAddress(target, address.address, maxBytes, timeoutMs);
      } catch (error) {
        lastError = this.errorMessage(error as Object);
      }
    }
    throw new Error(lastError);
  }

  private static getFromAddress(target: RawHttpTarget, address: string, maxBytes: number,
    timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const tcp = socket.constructTCPSocketInstance();
      const chunks: Uint8Array[] = [];
      let receivedBytes = 0;
      let settled = false;
      const finish = (body: string = '', errorMessage: string = ''): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timeoutId);
        try {
          tcp.off('message', onMessage);
          tcp.off('close', onClose);
          tcp.off('error', onError);
        } catch (_) {
        }
        tcp.close().catch((): void => {
        });
        if (errorMessage) reject(new Error(errorMessage));
        else resolve(body);
      };
      const tryFinish = (closed: boolean): boolean => {
        try {
          const bytes = RawHttpTextClient.merge(chunks, receivedBytes);
          const result = RawHttpTextClient.extractBody(bytes, closed);
          if (!result.complete) return false;
          const text = util.TextDecoder.create('utf-8')
            .decodeWithStream(result.data, { stream: false });
          finish(text.replace(/^\uFEFF/, ''));
          return true;
        } catch (error) {
          finish('', RawHttpTextClient.errorMessage(error as Object));
          return true;
        }
      };
      const onMessage = (info: socket.SocketMessageInfo): void => {
        if (settled || !info.message) return;
        const copy = new Uint8Array(info.message).slice();
        receivedBytes += copy.byteLength;
        if (receivedBytes > maxBytes + 64 * 1024) {
          finish('', 'TCP兜底响应过大');
          return;
        }
        chunks.push(copy);
        tryFinish(false);
      };
      const onClose = (): void => {
        if (!settled && !tryFinish(true)) finish('', 'TCP兜底收到不完整响应');
      };
      const onError = (error: Object): void => {
        if (!settled && !tryFinish(false)) {
          finish('', `TCP兜底网络错误: ${RawHttpTextClient.errorMessage(error)}`);
        }
      };
      const timeoutId = setTimeout(() => finish('', 'TCP兜底请求超时'), timeoutMs);
      tcp.on('message', onMessage);
      tcp.on('close', onClose);
      tcp.on('error', onError);
      const addressFamily = address.includes(':') ? 2 : 1;
      tcp.bind({ address: addressFamily === 2 ? '::' : '0.0.0.0', family: addressFamily, port: 0 })
        .then((): Promise<void> => tcp.connect({
          address: { address: address, family: addressFamily, port: target.port },
          timeout: timeoutMs
        }))
        .then((): Promise<void> => {
          const hostHeader = target.port === 80 ? target.host : `${target.host}:${target.port}`;
          const request = `GET ${target.path} HTTP/1.1\r\n` +
            `Host: ${hostHeader}\r\n` +
            `User-Agent: Mozilla/5.0 (Linux; HarmonyOS; Mobile) AppleWebKit/537.36 Safari/537.36\r\n` +
            `Accept: application/json,text/plain,*/*\r\n` +
            `Accept-Language: zh-CN,zh;q=0.9\r\n` +
            `Accept-Encoding: identity\r\n` +
            `Connection: close\r\n\r\n`;
          return tcp.send({ data: request, encoding: 'UTF-8' });
        })
        .catch((error: Object): void => {
          finish('', `TCP兜底连接失败: ${RawHttpTextClient.errorMessage(error)}`);
        });
    });
  }

  private static parseTarget(url: string): RawHttpTarget {
    const match = (url || '').match(/^http:\/\/([^/:?#]+)(?::(\d+))?([^#]*)$/i);
    if (!match) throw new Error('TCP兜底仅支持普通 HTTP 地址');
    let path = match[3] || '/';
    if (!path.startsWith('/')) path = `/${path}`;
    return {
      host: match[1],
      port: Number(match[2] || '80') || 80,
      path: path
    };
  }

  private static extractBody(response: Uint8Array, closed: boolean): RawHttpBodyResult {
    const headerEnd = this.findSequence(response, [13, 10, 13, 10], 0);
    if (headerEnd < 0) return { complete: false, data: new Uint8Array() };
    const headerBytes = response.slice(0, headerEnd);
    const headerText = util.TextDecoder.create('utf-8')
      .decodeWithStream(headerBytes, { stream: false });
    const statusMatch = headerText.match(/^HTTP\/\d(?:\.\d)?\s+(\d{3})/i);
    const status = statusMatch ? Number(statusMatch[1]) : 0;
    if (status < 200 || status >= 300) throw new Error(`TCP兜底 HTTP ${status || '响应异常'}`);
    const body = response.slice(headerEnd + 4);
    if (/transfer-encoding\s*:\s*[^\r\n]*chunked/i.test(headerText)) {
      return this.decodeChunked(body);
    }
    const lengthMatch = headerText.match(/content-length\s*:\s*(\d+)/i);
    if (lengthMatch) {
      const length = Number(lengthMatch[1]) || 0;
      if (body.byteLength < length) return { complete: false, data: new Uint8Array() };
      return { complete: true, data: body.slice(0, length) };
    }
    return closed ? { complete: true, data: body } : { complete: false, data: new Uint8Array() };
  }

  private static decodeChunked(body: Uint8Array): RawHttpBodyResult {
    const chunks: Uint8Array[] = [];
    let total = 0;
    let offset = 0;
    while (offset < body.byteLength) {
      const lineEnd = this.findSequence(body, [13, 10], offset);
      if (lineEnd < 0) return { complete: false, data: new Uint8Array() };
      const sizeText = this.ascii(body.slice(offset, lineEnd)).split(';')[0].trim();
      const size = parseInt(sizeText, 16);
      if (!Number.isFinite(size) || size < 0) throw new Error('TCP兜底分块格式错误');
      offset = lineEnd + 2;
      if (size === 0) return { complete: true, data: this.merge(chunks, total) };
      if (offset + size + 2 > body.byteLength) return { complete: false, data: new Uint8Array() };
      const chunk = body.slice(offset, offset + size);
      chunks.push(chunk);
      total += chunk.byteLength;
      offset += size;
      if (body[offset] !== 13 || body[offset + 1] !== 10) throw new Error('TCP兜底分块结尾错误');
      offset += 2;
    }
    return { complete: false, data: new Uint8Array() };
  }

  private static findSequence(data: Uint8Array, sequence: number[], start: number): number {
    for (let i = Math.max(0, start); i <= data.byteLength - sequence.length; i++) {
      let matched = true;
      for (let j = 0; j < sequence.length; j++) {
        if (data[i + j] !== sequence[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  private static ascii(data: Uint8Array): string {
    let result = '';
    for (let i = 0; i < data.byteLength; i++) result += String.fromCharCode(data[i]);
    return result;
  }

  private static merge(chunks: Uint8Array[], total: number): Uint8Array {
    if (chunks.length === 1) return chunks[0];
    const merged = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      merged.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return merged;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error && error.message) return error.message;
    if (error && typeof error === 'object') {
      const record = error as Record<string, Object>;
      const message = String(record['message'] || record['reason'] || '').trim();
      const code = String(record['code'] || '').trim();
      if (message) return code ? `${message} (${code})` : message;
    }
    const text = String(error || '').trim();
    return text && !text.includes('[object Object]') ? text : '未知错误';
  }
}
