import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { SourceCoverService } from './SourceCoverService';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { LightSourceCoverCache } from './rulesource/light/LightSourceCoverCache';

export class CoverLoadHandle {
  promise: Promise<string>;
  cancel: () => void;
  constructor(promise: Promise<string>, cancel: () => void) {
    this.promise = promise;
    this.cancel = cancel;
  }
}

class CoverLoadJob {
  key: string = '';
  url: string = '';
  headers: Record<string, string> = {};
  consumers: Set<number> = new Set<number>();
  speculative: boolean = false;
  started: boolean = false;
  promise: Promise<string> = Promise.resolve('');
  finish: (value: string) => void = () => {};
  fail: (error: Error) => void = () => {};
}

/** Display and prefetch share one queue. Images render local files only. */
export class CoverLoader {
  private static jobs: Map<string, CoverLoadJob> = new Map<string, CoverLoadJob>();
  private static queue: CoverLoadJob[] = [];
  private static active: number = 0;
  private static background: number = 0;
  private static sequence: number = 0;
  private static headers: Map<string, Record<string, string>> = new Map<string, Record<string, string>>();
  private static files: Map<string, string> = new Map<string, string>();
  private static failures: Map<string, number> = new Map<string, number>();

  static init(): void { /* Cache directory is created lazily. */ }

  static registerHeaders(url: string, headers: Record<string, string>): void {
    const copy: Record<string, string> = {};
    for (const name of Object.keys(headers).sort()) {
      const lower = name.toLowerCase();
      if (!['host', 'content-length', 'accept-encoding'].includes(lower)) copy[lower] = headers[name];
    }
    CoverLoader.headers.delete(url);
    CoverLoader.headers.set(url, copy);
    for (const key of CoverLoader.headers.keys()) {
      if (CoverLoader.headers.size <= 512) break;
      CoverLoader.headers.delete(key);
    }
  }

  private static requestHeaders(url: string): Record<string, string> {
    return CoverLoader.headers.get(url) ?? {
      'user-agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
    };
  }

  private static key(url: string): string {
    return SourceCoverService.isEncoded(url) ? `${LocalRuleSourceRepository.getCoverRevision()}:${url}` :
      JSON.stringify([url, CoverLoader.requestHeaders(url)]);
  }

  static cached(url: string): string {
    if (SourceCoverService.isEncoded(url)) return SourceCoverService.cached(url);
    const key = CoverLoader.key(url);
    const path = CoverLoader.files.get(key);
    if (path) {
      try { if (fs.accessSync(path.replace(/^file:\/\//, ''))) return path; } catch (_error) {}
      CoverLoader.files.delete(key);
    }
    return '';
  }

  static acquire(url: string): CoverLoadHandle { return CoverLoader.enqueue(url, false); }

  static prefetch(url: string, _highPriority: boolean = false): void {
    CoverLoader.enqueue(url, true).promise.catch((): void => {});
  }

  /** Small look-ahead; speculative work never fills all foreground slots. */
  static prefetchMany(urls: string[], _priorityCount: number = 12): void {
    for (const job of [...CoverLoader.queue]) {
      job.speculative = false;
      CoverLoader.prune(job);
    }
    for (const url of urls.slice(0, 4)) CoverLoader.prefetch(url);
  }

  private static enqueue(url: string, speculative: boolean): CoverLoadHandle {
    if (!url.startsWith('http')) return new CoverLoadHandle(Promise.resolve(url), () => {});
    const cached = CoverLoader.cached(url);
    if (cached) return new CoverLoadHandle(Promise.resolve(cached), () => {});
    const key = CoverLoader.key(url);
    if ((CoverLoader.failures.get(key) ?? 0) > Date.now()) {
      return new CoverLoadHandle(Promise.reject(new Error('Cover cooldown')), () => {});
    }
    let job = CoverLoader.jobs.get(key);
    if (!job) {
      if (CoverLoader.jobs.size >= 128) {
        return new CoverLoadHandle(Promise.reject(new Error('Cover queue full')), () => {});
      }
      job = new CoverLoadJob();
      job.key = key;
      job.url = url;
      job.headers = CoverLoader.requestHeaders(url);
      const created = job;
      job.promise = new Promise<string>((resolve, reject) => { created.finish = resolve; created.fail = reject; });
      CoverLoader.jobs.set(key, job);
      CoverLoader.queue.push(job);
    }
    const current = job;
    const id = ++CoverLoader.sequence;
    if (speculative) current.speculative = true;
    else current.consumers.add(id);
    CoverLoader.pump();
    return new CoverLoadHandle(current.promise, (): void => {
      current.consumers.delete(id);
      if (!speculative) current.speculative = false;
      CoverLoader.prune(current);
    });
  }

  private static prune(job: CoverLoadJob): void {
    if (job.started || job.consumers.size > 0 || job.speculative) return;
    CoverLoader.queue = CoverLoader.queue.filter((item: CoverLoadJob): boolean => item !== job);
    CoverLoader.jobs.delete(job.key);
    job.finish('');
  }

  private static pump(): void {
    while (CoverLoader.active < 4 && CoverLoader.queue.length > 0) {
      let index = CoverLoader.queue.findIndex((job: CoverLoadJob): boolean => job.consumers.size > 0);
      if (index < 0) {
        if (CoverLoader.background >= 1) return;
        index = 0;
      }
      const job = CoverLoader.queue.splice(index, 1)[0];
      const background = job.consumers.size === 0;
      job.started = true;
      CoverLoader.active++;
      if (background) CoverLoader.background++;
      CoverLoader.run(job).then(job.finish).catch((error: Error): void => {
        if (job.consumers.size > 0 || job.speculative) {
          CoverLoader.failures.set(job.key, Date.now() + 300000);
          for (const key of CoverLoader.failures.keys()) {
            if (CoverLoader.failures.size <= 512) break;
            CoverLoader.failures.delete(key);
          }
        }
        job.fail(error);
      }).finally((): void => {
        CoverLoader.jobs.delete(job.key);
        CoverLoader.active--;
        if (background) CoverLoader.background--;
        CoverLoader.pump();
      });
    }
  }

  private static async run(job: CoverLoadJob): Promise<string> {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        if (SourceCoverService.isEncoded(job.url)) return await SourceCoverService.resolve(job.url);
        const path = await LightSourceCoverCache.materialize(`plain-cover-v1:${job.key}`, async (): Promise<Uint8Array> => {
          const request = http.createHttp();
          try {
            const response = await request.request(job.url, { header: job.headers,
              expectDataType: http.HttpDataType.ARRAY_BUFFER, connectTimeout: 10000, readTimeout: 15000,
              maxLimit: 8 * 1024 * 1024 });
            if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) ||
              response.result.byteLength === 0 || response.result.byteLength > 8 * 1024 * 1024) {
              throw new Error('Invalid cover response');
            }
            return new Uint8Array(response.result);
          } finally { request.destroy(); }
        });
        CoverLoader.files.set(job.key, path);
        for (const key of CoverLoader.files.keys()) {
          if (CoverLoader.files.size <= 256) break;
          CoverLoader.files.delete(key);
        }
        return path;
      } catch (error) {
        if (attempt > 0 || (job.consumers.size === 0 && !job.speculative)) {
          if (error instanceof Error) throw error;
          throw new Error('Cover load failed');
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 800));
        if (job.consumers.size === 0 && !job.speculative) return '';
      }
    }
    throw new Error('Cover load failed');
  }

  static invalidate(url: string): void {
    if (SourceCoverService.isEncoded(url)) { SourceCoverService.invalidate(url); return; }
    const key = CoverLoader.key(url);
    const path = CoverLoader.files.get(key);
    CoverLoader.files.delete(key);
    if (path) { try { fs.unlinkSync(path.replace(/^file:\/\//, '')); } catch (_error) {} }
  }

  static async loadOriginal(url: string): Promise<ArrayBuffer> {
    const handle = CoverLoader.acquire(url);
    try {
      const path = await handle.promise;
      const file = await fs.open(path.replace(/^file:\/\//, ''), fs.OpenMode.READ_ONLY);
      try {
        const size = (await fs.stat(file.fd)).size;
        if (size <= 0 || size > 8 * 1024 * 1024) throw new Error('Invalid cover size');
        const bytes = new ArrayBuffer(size);
        if (await fs.read(file.fd, bytes) !== size) throw new Error('Incomplete cover read');
        return bytes;
      } finally { await fs.close(file); }
    } finally { handle.cancel(); }
  }
}
