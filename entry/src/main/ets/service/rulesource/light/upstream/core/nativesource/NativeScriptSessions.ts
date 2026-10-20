
import type { NativeScriptEngine } from './NativeScriptHost';
export class NativeScriptSessions {
  static forCode(_code: string): NativeScriptEngine {
    throw new Error('Native script requires the isolated host');
  }
}
