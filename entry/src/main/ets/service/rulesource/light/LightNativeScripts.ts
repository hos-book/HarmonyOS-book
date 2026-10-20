import { BookSource } from './upstream/model/data/Book';
import { NativeExpr } from './upstream/core/nativesource/NativeExpr';
import type { NativeValue } from './upstream/core/nativesource/NativeExpr';
import type { NativeRunnerHost } from './upstream/core/nativesource/NativeSourceRunner';
import type { NativeScriptCallHandler, NativeScriptEngine, NativeScriptRunOptions } from './upstream/core/nativesource/NativeScriptHost';
import { NativeJsPrelude } from './upstream/core/nativesource/NativeJsPrelude';
import { nativeExprProgram } from './upstream/NativeExprProgram';
import { SourceEngineHost } from './upstream/core/host/SourceEngineHost';
import { LightSourceRuntime } from './LightSourceRuntime';

interface ReplayReply { name: string; payload: string; value: string; error: string; }
interface ReplayRequest { name: string; payload: string; }
interface ReplayEnvelope { value?: string; pending?: ReplayRequest; error?: string; }

/** Native JS uses the same isolated taskpool facade as compatible sources.
 * Each replay recreates the context; completed host operations are journaled and never repeated.
 * No context/global is shared between sources, accounts or executions.
 */
export class LightNativeScripts {
  static create(source: BookSource, host: NativeRunnerHost): Pick<NativeRunnerHost, 'scriptEngine' | 'evaluateExpression'> {
    return {
      scriptEngine: (code: string): NativeScriptEngine => ({
        run: (fn, ctx, handler, options) => {
          if (!NativeJsPrelude.isIdentifier(fn)) throw new Error('脚本函数名无效');
          return this.execute(source, code, NativeJsPrelude.stageSource(fn, ctx), '', handler, options);
        }
      }),
      evaluateExpression: async (code, lib, expression, scope, template, cancelled) => {
        const bootstrap = `var exports = {};\n${nativeExprProgram}\n` +
          `var E=exports.NativeExpr,S=exports.NativeScope;` +
          `var remote=function(n,a){return JSON.parse(bridge(n,JSON.stringify(a)));};` +
          `var h={jsonPath:(r,p)=>exports.JsonPathEvaluator.evaluate(r,p),select:(c,r,b,l)=>remote('select',[c,r,b,l]),` +
          `digest:(a,t)=>remote('digest',[a,t]),crypto:(n,a)=>remote('crypto',[n,a]),cookie:(u,n)=>remote('cookie',[u,n])};` +
          `var scope=new S();var values=${JSON.stringify(scope)};Object.keys(values).forEach(k=>scope.set(k,values[k]));` +
          `var expr=new E(h).loadLibrary(${JSON.stringify(lib)});` +
          `globalThis.__host=function(n,p){if(loading)throw Error('js 顶层不能调用 native');` +
          `return JSON.stringify(expr.callBuiltin(n,JSON.parse(p),scope)??null);};`;
        const call = `expr.loadScript(user);` +
          `JSON.stringify(expr.${template ? 'render' : 'evaluate'}(${JSON.stringify(expression)},scope)??null)`;
        return this.execute(source, code, call, bootstrap, async (name, args) => {
          switch (name) {
            case 'select': return host.select(String(args[0]),String(args[1]),String(args[2]),args[3] === true);
            case 'digest': return host.digest(String(args[0]),String(args[1]));
            case 'crypto': if (host.crypto) return host.crypto(String(args[0]),args[1]); break;
            case 'cookie': return host.cookie ? host.cookie(String(args[0]),String(args[1])) : '';
          }
          throw new Error('表达式宿主接口不可用');
        }, {cpuMs:2000,wallMs:10000,cancelled});
      }
    };
  }

  private static async execute(source: BookSource, code: string, invocation: string, bootstrap: string,
    handler: NativeScriptCallHandler, options: NativeScriptRunOptions): Promise<NativeValue> {
    if (code.length > NativeJsPrelude.MAX_CODE_LENGTH) throw new Error('js 超过执行输入限制');
    const evaluate = LightSourceRuntime.host.evaluateNative;
    if (!evaluate) throw new Error('原生 JS 沙箱未安装');
    const replies: ReplayReply[] = [];
    const started = Date.now();
    const seed = Math.floor(Math.random() * 0x7fffffff) || 1;
    let cpu = 0;
    let bytes = 0;
    let browserStarted = 0;
    const check = (): void => {
      if (options.cancelled() || SourceEngineHost.isCancelled(source)) throw new Error('已取消');
      const activePause = browserStarted ? Date.now() - browserStarted : 0;
      if (Date.now() - started - (options.pausedMs?.() || 0) - activePause > options.wallMs) throw new Error('脚本超过总时长限制');
      if (cpu >= options.cpuMs) throw new Error('脚本超过计算时间限制');
    };
    for (let step = 0; step <= 256; step++) {
      check();
      const script = this.envelope(code, invocation, bootstrap, replies, started, seed);
      const raw = await evaluate(script, source.bookSourceUrl, Math.max(1, options.cpuMs - cpu));
      const result = JSON.parse(raw) as {value: string; elapsedMs: number};
      cpu += Math.max(1, Number(result.elapsedMs) || 0);
      check();
      const envelope = JSON.parse(result.value) as ReplayEnvelope;
      if (!envelope.pending) {
        if (envelope.error) throw new Error(envelope.error);
        return NativeJsPrelude.parseResult(envelope.value || 'null');
      }
      if (step === 256) throw new Error('脚本宿主调用超过 256 次');
      const pending = envelope.pending;
      if (pending.payload.length > 4 * 1024 * 1024) throw new Error('脚本宿主输入超过限制');
      const reply: ReplayReply = {name:pending.name,payload:pending.payload,value:'null',error:''};
      try {
        const args = JSON.parse(pending.payload);
        if (!Array.isArray(args)) throw new Error('脚本宿主参数格式错误');
        if (pending.name === '@browserVerify') browserStarted = Date.now();
        reply.value = JSON.stringify((await this.waitHost(handler, pending, args, check)) ?? null);
      } catch (error) {
        if (pending.name === '@browserVerify') LightSourceRuntime.host.cancelBrowser?.(source.bookSourceUrl);
        reply.error = error instanceof Error ? error.message : String(error);
      } finally { browserStarted = 0; }
      check();
      bytes += reply.payload.length + reply.value.length + reply.error.length;
      if (bytes > 16 * 1024 * 1024) throw new Error('脚本宿主交换数据超过限制');
      replies.push(reply);
    }
    throw new Error('脚本执行超过预算');
  }

  private static async waitHost(handler: NativeScriptCallHandler, pending: ReplayRequest,
    args: NativeValue[], check: () => void): Promise<NativeValue> {
    let timer = -1;
    try {
      return await new Promise<NativeValue>((resolve, reject) => {
        timer = setInterval(() => {
          try { check(); } catch (error) { reject(error); }
        }, 50);
        Promise.resolve().then(() => handler(pending.name,args)).then(resolve,reject);
      });
    } finally { if (timer !== -1) clearInterval(timer); }
  }

  private static envelope(code: string, invocation: string, bootstrap: string, replies: ReplayReply[],
    epoch: number, seed: number): string {
    return `(function(){var replies=${JSON.stringify(replies)},index=0,pending=null,loading=true;` +
      `var globalEval=(0,eval),stringify=JSON.stringify,parse=JSON.parse;` +
      // Keep time/random stable across replays, including uuid and user-defined request signatures.
      `var OriginalDate=Date;globalThis.Date=class extends OriginalDate{constructor(...a){super(...(a.length?a:[${epoch}]));}` +
      `static now(){return ${epoch};}};var randomSeed=${seed};Math.random=function(){randomSeed=(Math.imul(randomSeed,1664525)+1013904223)|0;return(randomSeed>>>0)/4294967296;};` +
      `function bridge(name,payload){if(loading)throw Error('js 顶层不能调用宿主');` +
      `if(pending)throw Error('宿主调用等待中');var r=replies[index++];` +
      `if(r){if(r.name!==name||r.payload!==payload)throw Error('脚本回放调用不一致');` +
      `if(r.error)throw Error(r.error);return r.value;}` +
      `pending={name:name,payload:payload};throw Error('宿主调用等待中');}` +
      `function finish(v,e){if(pending)return stringify({pending:pending});` +
      `return stringify(e?{error:String(e.message||e)}:{value:String(v??'null')});}` +
      `try{globalThis.__host=bridge;${bootstrap}` +
      `globalEval(${JSON.stringify(NativeJsPrelude.source(NativeExpr.scriptBuiltinNames(), !bootstrap))});` +
      `var user=globalEval(${JSON.stringify('(function(){' + code + '\n;return ' + (bootstrap ?
        `{has:function(n){return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(n)&&eval('typeof '+n+" === 'function'");},` +
        `call:function(n,a){return JSON.parse(__nativeReturn(eval(n).apply(null,a)));}}` :
        `function(){return ${invocation};}`) + ';})()')});loading=false;` +
      (bootstrap ? `var value=eval(${JSON.stringify(invocation)});` : `var value=user();`) +
      `return value&&typeof value.then==='function'?value.then(v=>finish(v),e=>finish(null,e)):finish(value);` +
      `}catch(e){return finish(null,e);}})()`;
  }
}
