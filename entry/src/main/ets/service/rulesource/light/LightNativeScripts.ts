import { BookSource } from './upstream/model/data/Book';
import { NativeExpr } from './upstream/core/nativesource/NativeExpr';
import type { NativeValue } from './upstream/core/nativesource/NativeExpr';
import type { NativeRunnerHost } from './upstream/core/nativesource/NativeSourceRunner';
import type { NativeScriptCallHandler, NativeScriptEngine, NativeScriptRunOptions } from './upstream/core/nativesource/NativeScriptHost';
import { NativeJsPrelude } from './upstream/core/nativesource/NativeJsPrelude';
import { nativeExprProgram } from './upstream/NativeExprProgram';
import { SourceEngineHost } from './upstream/core/host/SourceEngineHost';
import { LightSourceRuntime } from './LightSourceRuntime';

interface NativeEnvelope { value?: string; error?: string; }

/** Native JS uses the same isolated taskpool facade as compatible sources.
 * One bounded task keeps its execution stack while awaiting controlled host operations.
 * No context/global is shared between sources, accounts or executions.
 */
export class LightNativeScripts {
  /** Pure conversions run inside the bounded VM, using the same upstream implementation.
   * Scope-dependent functions and all host capabilities use the bounded JSON mailbox.
   */
  private static readonly LOCAL_BUILTINS: string[] = ['str', 'num', 'int', 'bool', 'typeOf', 'len',
    'trim', 'lower', 'upper', 'u32', 'imul', 'pow', 'abs', 'round', 'floor', 'ceil',
    'bytes', 'fromBytes', 'hexBytes', 'bytesHex', 'base64Bytes', 'bytesBase64'];

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
    const evaluate = LightSourceRuntime.host.evaluateNativeHost;
    if (!evaluate) throw new Error('原生 JS 沙箱未安装');
    const started = Date.now();
    let browserStarted = 0;
    const check = (): void => {
      if (options.cancelled() || SourceEngineHost.isCancelled(source)) throw new Error('已取消');
      const activePause = browserStarted ? Date.now() - browserStarted : 0;
      if (Date.now() - started - (options.pausedMs?.() || 0) - activePause > options.wallMs) throw new Error('脚本超过总时长限制');
    };
    check();
    try {
      const raw = await evaluate(this.program(code, invocation, bootstrap), source.bookSourceUrl,
        Math.max(1, Math.min(2000, options.cpuMs)), async (name, payload) => {
        check();
        const args = JSON.parse(payload);
        if (!Array.isArray(args)) throw new Error('脚本宿主参数格式错误');
        if (name === '@browserVerify') browserStarted = Date.now();
        try {
          const value = await handler(name, args);
          check();
          return JSON.stringify(value ?? null);
        } finally { browserStarted = 0; }
      }, check);
      check();
      const envelope = JSON.parse(raw) as NativeEnvelope;
      if (envelope.error) throw new Error(envelope.error);
      return NativeJsPrelude.parseResult(envelope.value || 'null');
    } finally {
      if (browserStarted) LightSourceRuntime.host.cancelBrowser?.(source.bookSourceUrl);
    }
  }

  private static program(code: string, invocation: string, bootstrap: string): string {
    const stageBuiltins = `var exports={};\n${nativeExprProgram}\n` +
      `var localExpr=new exports.NativeExpr({}),localScope=new exports.NativeScope(),` +
      `localNames=${JSON.stringify(this.LOCAL_BUILTINS)};` +
      `globalThis.__host=function(n,p){if(loading)throw Error('js 顶层不能调用宿主');` +
      `if(localNames.indexOf(n)>=0)return stringify(localExpr.callBuiltin(n,parse(p),localScope)??null);` +
      `return bridge(n,p);};`;
    return `(function(){var loading=true,transport=globalThis.__boundedHost;delete globalThis.__boundedHost;` +
      `var globalEval=(0,eval),stringify=JSON.stringify,parse=JSON.parse;` +
      `function bridge(name,payload){if(loading)throw Error('js 顶层不能调用宿主');` +
      `var r=parse(transport(name,payload));if(r.error)throw Error(r.error);return r.value;}` +
      `function finish(v,e){` +
      `return stringify(e?{error:String(e.message||e)}:{value:String(v??'null')});}` +
      `try{globalThis.__host=bridge;${bootstrap || stageBuiltins}` +
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
