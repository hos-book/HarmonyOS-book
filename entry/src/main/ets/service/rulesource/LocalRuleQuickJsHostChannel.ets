import { taskpool, util } from '@kit.ArkTS';

/** JSON-only mailbox for one bounded task. Never shared with another source or execution. */
export class LocalRuleQuickJsHostReply {
  value: string = 'null';
  error: string = '';
}

export class LocalRuleQuickJsHostChannel {
  readonly control: Int32Array = new Int32Array(new SharedArrayBuffer(16));
  readonly response: Uint8Array = new Uint8Array(new SharedArrayBuffer(8 * 1024 * 1024));
  error: string = '';
  private closed: boolean = false;
  private busy: boolean = false;
  private startedAt: number = Date.now();
  private handler: (name: string, payload: string) => Promise<string>;
  private check: () => void;

  constructor(handler: (name: string, payload: string) => Promise<string>, check: () => void) {
    this.handler = handler;
    this.check = check;
  }

  tick(): void {
    if (this.closed) return;
    try {
      if (Date.now() - this.startedAt >= 16 * 60 * 1000) throw new Error('脚本超过最长运行时间');
      this.check();
    } catch (error) {
      this.error = error instanceof Error ? error.message : '书源请求已取消';
      this.close();
    }
  }

  async answer(sequence: number, name: string, payload: string): Promise<void> {
    this.tick();
    if (this.closed) return;
    if (this.busy || sequence !== Atomics.load(this.control, 3) || name.length > 128 ||
      payload.length > 4 * 1024 * 1024) {
      this.error = '脚本宿主请求无效';
      this.close();
      return;
    }
    this.busy = true;
    const reply = new LocalRuleQuickJsHostReply();
    try {
      reply.value = await this.handler(name, payload);
    } catch (error) {
      reply.error = error instanceof Error ? error.message : '脚本宿主调用失败';
    }
    this.busy = false;
    this.tick();
    if (this.closed) return;
    const encoded = new util.TextEncoder().encodeInto(JSON.stringify(reply));
    if (encoded.length > this.response.length) {
      this.error = '脚本宿主返回超过 8 MiB 限制';
      this.close();
      return;
    }
    this.response.set(encoded);
    Atomics.store(this.control, 2, encoded.length);
    Atomics.store(this.control, 1, 1);
    Atomics.notify(this.control, 1);
  }

  close(): void {
    this.closed = true;
    Atomics.store(this.control, 0, 1);
    Atomics.notify(this.control, 1);
  }

  /** Called only in the taskpool worker; the UI thread never blocks on Atomics.wait. */
  static call(control: Int32Array, response: Uint8Array, name: string, payload: string): string {
    if (Atomics.load(control, 0) !== 0) throw new Error('书源请求已取消');
    Atomics.store(control, 1, 0);
    const sequence = Atomics.add(control, 3, 1) + 1;
    taskpool.Task.sendData(sequence, name, payload);
    const startedAt = Date.now();
    while (Atomics.load(control, 1) === 0) {
      if (Atomics.load(control, 0) !== 0 || Date.now() - startedAt >= 15 * 60 * 1000) {
        Atomics.store(control, 0, 1);
        throw new Error('脚本宿主等待已取消或超时');
      }
      Atomics.wait(control, 1, 0, 50);
    }
    if (Atomics.load(control, 0) !== 0) throw new Error('书源请求已取消');
    const length = Atomics.load(control, 2);
    if (length < 0 || length > response.length) throw new Error('脚本宿主返回长度无效');
    return util.TextDecoder.create('utf-8').decodeToString(response.subarray(0, length));
  }
}
