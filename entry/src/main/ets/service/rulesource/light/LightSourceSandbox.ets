import { LocalRuleQuickJsRequest, LocalRuleQuickJsRuntime } from '../LocalRuleQuickJsRuntime';
import { util } from '@kit.ArkTS';
import { LightSourceHtmlCodec } from './LightSourceHtmlCodec';
import { LightSourceTiming } from './LightSourceTiming';

class LightDecodeRequest {
  kind: string = '';
  text: string = '';
  id: number = 0;
  charset: string = 'utf-8';
  data: number[] = [];
  stream: boolean = false;
  fatal: boolean = false;
  ignoreBOM: boolean = false;
}
class LightDecodeValue {
  value: string = '';
  error: string = '';
}
class LightDecodeEnvelope {
  value: string = '';
  key: string = '';
  request: LightDecodeRequest | undefined = undefined;
}

/** No platform objects cross into the imported source engine. */
export class LightSourceSandbox {
  private static imageQueue: number[] = [];
  private static imageSequence: number = 0;
  private static imageActive: boolean = false;

  static async evaluateImage(script: string, input: Uint8Array, cancelled: () => boolean): Promise<Uint8Array> {
    if (!input.length || input.length > 20 * 1024 * 1024 || script.length > 384 * 1024) {
      throw new Error('图片脚本输入超过限制');
    }
    if (LightSourceSandbox.imageQueue.length + (LightSourceSandbox.imageActive ? 1 : 0) >= 4) {
      throw new Error('图片脚本队列已满，请稍后重试');
    }
    const ticket = ++LightSourceSandbox.imageSequence;
    LightSourceSandbox.imageQueue.push(ticket);
    const queuedAt = Date.now();
    try {
      while (LightSourceSandbox.imageActive || LightSourceSandbox.imageQueue[0] !== ticket) {
        if (cancelled()) throw new Error('书源请求已取消');
        if (Date.now() - queuedAt >= 30000) throw new Error('图片脚本排队超时');
        await new Promise<void>((resolve): void => { setTimeout(resolve, 25); });
      }
      if (cancelled()) throw new Error('书源请求已取消');
    } catch (error) {
      LightSourceSandbox.imageQueue = LightSourceSandbox.imageQueue.filter((id: number): boolean => id !== ticket);
      throw new Error(error instanceof Error ? error.message : '图片脚本排队失败');
    }
    LightSourceSandbox.imageQueue.shift();
    LightSourceSandbox.imageActive = true;
    let timer: number = -1;
    try {
      const signal = new Int32Array(new SharedArrayBuffer(4));
      const startedAt = Date.now();
      timer = setInterval((): void => {
        if (cancelled() || Date.now() - startedAt >= 10000) Atomics.store(signal, 0, 1);
      }, 25);
      const request = new LocalRuleQuickJsRequest();
      request.script = script;
      request.binaryInput = input;
      request.cancelSignal = signal;
      const result = await LocalRuleQuickJsRuntime.execute(request);
      if (cancelled()) throw new Error('书源请求已取消');
      if (Date.now() - startedAt >= 10000) throw new Error('图片脚本超时');
      if (!result.success) throw new Error(result.errorMessage || '图片脚本执行失败');
      return result.bytes;
    } finally {
      if (timer >= 0) clearInterval(timer);
      LightSourceSandbox.imageActive = false;
    }
  }

  static async evaluateNative(script: string, sourceUrl: string, timeoutMs: number): Promise<string> {
    const request = new LocalRuleQuickJsRequest();
    request.script = script;
    request.sourceUrl = sourceUrl;
    request.timeoutMs = Math.max(1, Math.min(2000, timeoutMs));
    request.stackLimitBytes = 1024 * 1024;
    const result = await LocalRuleQuickJsRuntime.execute(request);
    if (!result.success) throw new Error(result.errorMessage || '原生 JS 执行失败');
    if (result.value.length > 8 * 1024 * 1024) throw new Error('原生 JS 输出超过限制');
    return JSON.stringify({value:result.value,elapsedMs:result.elapsedMs});
  }
  static async evaluateNativeHost(script: string, sourceUrl: string, timeoutMs: number,
    handler: (name: string, payload: string) => Promise<string>, check: () => void): Promise<string> {
    const request = new LocalRuleQuickJsRequest();
    request.script = script;
    request.sourceUrl = sourceUrl;
    request.timeoutMs = Math.max(1, Math.min(2000, timeoutMs));
    request.hostHandler = handler;
    request.hostCheck = check;
    check();
    const result = await LocalRuleQuickJsRuntime.execute(request);
    check();
    if (!result.success) throw new Error(result.errorMessage || '原生 JS 执行失败');
    return result.value;
  }
  static async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    const responses: Record<string, LightDecodeValue> = {};
    const decoders: Map<number, util.TextDecoder> = new Map<number, util.TextDecoder>();
    const deadline = Date.now() + 10000;
    for (let replay = 0; replay < 64 && Date.now() < deadline; replay++) {
      const envelope = await LightSourceSandbox.evaluateStep(script, sourceUrl, responses, deadline, timingId, replay);
      if (!envelope.request) return envelope.value;
      const pending = envelope.request;
      if (pending.data.length > 4 * 1024 * 1024 || !envelope.key) throw new Error('字符解码输入超过限制');
      const response = new LightDecodeValue();
      try {
        if (pending.kind === 'html-encode' || pending.kind === 'html-decode') {
          response.value = await LightSourceHtmlCodec.execute(pending.kind,pending.text);
          responses[envelope.key] = response;
          continue;
        }
        let decoder = decoders.get(pending.id);
        if (!decoder) {
          decoder = util.TextDecoder.create(pending.charset, {fatal:pending.fatal,ignoreBOM:pending.ignoreBOM});
          decoders.set(pending.id, decoder);
        }
        response.value = decoder.decodeToString(new Uint8Array(pending.data), {stream:pending.stream});
      } catch (error) { response.error = error instanceof Error ? error.message : '字符解码失败'; }
      responses[envelope.key] = response;
    }
    throw new Error('字符解码超过执行预算');
  }
  private static async evaluateStep(script: string, sourceUrl: string,
    responses: Record<string, LightDecodeValue>, deadline: number, timingId: number, replay: number): Promise<LightDecodeEnvelope> {
    const buildStartedAt = Date.now();
    const request = new LocalRuleQuickJsRequest();
    request.script = '(function(){var __lightNextDecoderId=0,__lightDecodeCall=0,' +
      '__lightDecodeResults=' + JSON.stringify(responses) + ';' +
      'function codec(req){var key=String(++__lightDecodeCall);' +
      'if(Object.prototype.hasOwnProperty.call(__lightDecodeResults,key)){' +
      'var v=__lightDecodeResults[key];if(v.error)throw Error(v.error);return v.value;}' +
      'if(!globalThis.__lightDecodePendingEnvelope)globalThis.__lightDecodePendingEnvelope={key:key,request:req};' +
      'var p=globalThis.__lightDecodePendingEnvelope;throw {__lightDecodePending:true,key:p.key,request:p.request};}' +
      'globalThis.__lightHtmlBridge=function(kind,text){if(text.length>4194304)throw Error("HTML 输入超过限制");' +
      'return codec({kind:"html-"+kind,text:String(text),data:[]});};' +
      'globalThis.__lightNextDecoderId=0;globalThis.__lightDecodeBridge=function(id,charset,data,opts,read){' +
      'var bytes=data===undefined?[]:Array.from(data instanceof ArrayBuffer?new Uint8Array(data):' +
      '(ArrayBuffer.isView(data)?new Uint8Array(data.buffer,data.byteOffset,data.byteLength):data));' +
      'if(bytes.length>4194304)throw Error("字符解码输入超过限制");' +
      'var req={id:id,charset:String(charset),data:bytes,fatal:!!opts.fatal,ignoreBOM:!!opts.ignoreBOM,stream:!!read.stream};' +
      'return codec(req);};' +
      'try{var value=(0,eval)(' + JSON.stringify(script) + ');' +
      'if(globalThis.__lightDecodePendingEnvelope)return JSON.stringify(globalThis.__lightDecodePendingEnvelope);' +
      'return JSON.stringify({value:String(value??"")});}' +
      'catch(e){if(e&&e.__lightDecodePending)return JSON.stringify({key:e.key,request:e.request});throw e;}})()';
    request.sourceUrl = sourceUrl;
    request.timeoutMs = Math.max(1,Math.min(5000,deadline-Date.now()));
    request.memoryLimitBytes = 64 * 1024 * 1024;
    request.stackLimitBytes = 1024 * 1024;
    LightSourceTiming.end(timingId, 'sandbox-envelope', buildStartedAt, `decodeReplay=${replay}`);
    const executionStartedAt = Date.now();
    const result = await LocalRuleQuickJsRuntime.execute(request);
    LightSourceTiming.end(timingId, 'quickjs-roundtrip', executionStartedAt,
      `nativeMs=${result.elapsedMs} success=${result.success} decodeReplay=${replay}`);
    if (!result.success) throw new Error(result.errorMessage || '书源脚本执行失败');
    const envelope: LightDecodeEnvelope = JSON.parse(result.value);
    return envelope;
  }
}
