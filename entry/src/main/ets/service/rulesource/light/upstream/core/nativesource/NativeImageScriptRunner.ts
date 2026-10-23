import { SourceEngineHost } from '../host/SourceEngineHost';

export interface NativeImageScriptContext {
  url: string;
  index: number;
  params: Object;
}

/** Image-only session: no stage host, cookies, network, storage or login APIs. */
export class NativeImageScriptRunner {
  static readonly MAX_BYTES: number = 20 * 1024 * 1024;
  private static readonly QUEUE_TIMEOUT_MS: number = 60000;
  private static sequence: number = 0;
  private static queue: number[] = [];
  private static active: boolean = false;

  static program(js: string, fn: string, context: NativeImageScriptContext): string {
    if (!/^[A-Za-z_$][\w$]*$/.test(fn)) throw new Error('content.imageDecode.script 必须是 JS 函数名');
    const json = JSON.stringify(context);
    if (json.length > 32768) throw new Error('content.imageDecode 脚本上下文过大');
    if (!js || js.length > 256 * 1024) throw new Error('content.imageDecode.script 需要 js 函数库（最多 256K 字符）');
    // Capture bridge and input before evaluating the untrusted function library.
    return `(function(input,ctx,host){
      "use strict";
      const invoke=(op,data,algorithm,keyHex,ivHex)=>new Uint8Array(host(op,data,
        JSON.stringify({algorithm:algorithm,keyHex:keyHex||"",ivHex:ivHex||""})));
      const image=Object.freeze({
        decrypt:(algorithm,data,keyHex,ivHex)=>invoke("decrypt",data,algorithm,keyHex,ivHex),
        encrypt:(algorithm,data,keyHex,ivHex)=>invoke("encrypt",data,algorithm,keyHex,ivHex),
        hash:(algorithm,data)=>invoke("hash",data,algorithm),
        hmac:(algorithm,data,keyHex)=>invoke("hmac",data,algorithm,keyHex),
        reorderStrips:(data,options)=>new Uint8Array(host("reorderStrips",data,JSON.stringify(options)))
      });
      ${js}
      if(typeof ${fn}!=="function") throw new Error("content.imageDecode.script: function missing");
      return ${fn}(input,ctx);
    })(new Uint8Array(__imageInput),${json},__imageHost)`;
  }

  static async run(js: string, fn: string, input: Uint8Array, context: NativeImageScriptContext,
    cancelled: () => boolean = (): boolean => false): Promise<Uint8Array> {
    const code = this.program(js, fn, context);
    if (!input.length || input.length > this.MAX_BYTES) throw new Error('图片脚本输入须为 1 字节至 20 MiB');
    if (cancelled()) throw new Error('书源请求已取消');
    const executor = SourceEngineHost.imageScripts();
    if (!executor) throw new Error('Image script requires the isolated host');
    const bytes = await executor.run(code, input, cancelled);
    if (cancelled()) throw new Error('书源请求已取消');
    if (!bytes.length || bytes.length > this.MAX_BYTES) throw new Error('图片脚本输出超过限制');
    return bytes;
  }
}
