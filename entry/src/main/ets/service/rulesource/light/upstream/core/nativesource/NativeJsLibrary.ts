
import type { NativeScriptLibrary } from './NativeExpr';
export class NativeJsLibrary {
  static check(_code: string, _names: string[], _functions: string[] = []): string { return ''; }
  static forCode(_code: string): NativeScriptLibrary {
    return { has: () => true, call: () => { throw new Error('Native JS requires the isolated host'); } };
  }
}
