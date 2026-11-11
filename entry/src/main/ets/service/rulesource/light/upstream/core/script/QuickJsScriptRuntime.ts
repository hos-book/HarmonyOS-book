import { JSBoundedExecutionResult, JSContext, JSRuntimeOptions } from '@devzeng/quickjs';
import { SourceEngineHost } from '../host/SourceEngineHost';

export class QuickJsExpressionResult {
  success: boolean = false;
  value: string = '';
  error: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
}

/**
 * Sandboxed evaluator for the plain JavaScript a compatible rule leaves behind after JsRuntime's
 * textual shims have resolved the known host calls.
 *
 * It deliberately exposes no network, Cookie, filesystem or platform bridge; anything that needs
 * them stays on JsRuntime or the ArkWeb stage runtime.
 */
export class QuickJsScriptRuntime {
  private static readonly MAX_SCRIPT_LENGTH: number = 4096;
  private static readonly MAX_BINDING_COUNT: number = 64;
  private static readonly MAX_BINDING_BYTES: number = 128 * 1024;

  /**
   * Evaluate the residue a textual rule shim left behind (literal values plus plain JavaScript
   * operators/methods such as `String(x).replace(/…/,'')`). Screen only shapes the sandbox cannot
   * honor; unbindable host identifiers simply fail evaluation and the caller falls
   * back to its legacy behavior.
   */
  static evaluateResidualExpression(expression: string,
    variables: Record<string, Object>, timeoutMs: number = 150): QuickJsExpressionResult {
    const output = new QuickJsExpressionResult();
    const code = QuickJsScriptRuntime.normalizeExpression(expression);
    if (!code || code.length > QuickJsScriptRuntime.MAX_SCRIPT_LENGTH) {
      output.error = 'not-residual';
      return output;
    }
    if (/[;{}]/.test(code) ||
      /\b(?:java|cookie|cache|chapter)\s*\.\s*[A-Za-z_$]|\b(?:eval|Function|import|while|for|return|await|yield|throw|new)\b/.test(code)) {
      output.error = 'not-residual';
      return output;
    }
    return QuickJsScriptRuntime.evaluateBoundExpression(code, variables, timeoutMs, output);
  }

  private static evaluateBoundExpression(code: string, variables: Record<string, Object>,
    timeoutMs: number, output: QuickJsExpressionResult): QuickJsExpressionResult {
    const keys = Object.keys(variables);
    if (keys.length > QuickJsScriptRuntime.MAX_BINDING_COUNT) {
      output.error = 'too-many-bindings';
      return output;
    }
    let bindingBytes = 0;
    const declarations: string[] = [];
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      let serialized = '';
      try { serialized = JSON.stringify(variables[key]); } catch (_) { serialized = String(variables[key]); }
      bindingBytes += key.length + serialized.length;
      if (QuickJsScriptRuntime.isSafeIdentifier(key)) {
        declarations.push(`const ${key}=__bindings[${JSON.stringify(key)}]`);
      }
    }
    if (bindingBytes > QuickJsScriptRuntime.MAX_BINDING_BYTES) {
      output.error = 'bindings-too-large';
      return output;
    }

    return QuickJsScriptRuntime.evaluateInContext(code, variables, declarations, timeoutMs, output,
      'book-source-pure-expression.js');
  }

  private static evaluateInContext(code: string, variables: Record<string, Object>,
    declarations: string[], timeoutMs: number, output: QuickJsExpressionResult,
    scriptName: string): QuickJsExpressionResult {
    if (SourceEngineHost.scriptExecutor()?.allowSynchronousQuickJs === false) {
      output.error = 'synchronous QuickJS disabled by host; use the asynchronous stage runtime';
      return output;
    }
    const options = new JSRuntimeOptions();
    options.memoryLimitBytes = 16 * 1024 * 1024;
    options.stackLimitBytes = 512 * 1024;
    const context = new JSContext(options);
    try {
      context.setObject(variables, '__legadoBindings');
      const wrapped = `(function(){const __bindings=globalThis.__legadoBindings;` +
        `${declarations.join(';')};return (${code});})()`;
      const result = context.evaluateBounded(wrapped, scriptName,
        Math.max(10, Math.min(250, timeoutMs)), 8);
      QuickJsScriptRuntime.copyResult(result, output);
    } catch (error) {
      output.error = QuickJsScriptRuntime.errorMessage(error);
    } finally {
      context.release();
    }
    return output;
  }

  private static normalizeExpression(expression: string): string {
    return (expression || '').trim().replace(/^return\s+/, '').replace(/;\s*$/, '').trim();
  }

  private static isSafeIdentifier(key: string): boolean {
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key)) return false;
    return !/^(?:break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|await|enum|implements|interface|package|private|protected|public|static)$/.test(key);
  }

  private static copyResult(source: JSBoundedExecutionResult, target: QuickJsExpressionResult): void {
    target.success = source.success;
    target.value = source.value;
    target.error = source.error;
    target.timedOut = source.timedOut;
    target.elapsedMs = source.elapsedMs;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}
