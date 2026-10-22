/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the legado-harmony project in 2026 for QuickJS runtime integration.
 */

import { JSValue } from './JSValue';
import qjs from './NativeQuickJs';

export class JSRuntimeOptions {
  memoryLimitBytes: number = 64 * 1024 * 1024;
  stackLimitBytes: number = 256 * 1024;
}

export class JSBoundedExecutionResult {
  bytes: Uint8Array = new Uint8Array();
  success: boolean = false;
  value: string = '';
  error: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
  pendingJobs: number = 0;
}

export class JSContext {
  private static readonly MAX_BINDING_DEPTH: number = 32;
  private static readonly MAX_BINDING_NODES: number = 20000;
  private _engineHandle: bigint = 0n;
  private nameValue: string = '';

  get engineHandle(): bigint {
    return this._engineHandle;
  }

  constructor(options?: JSRuntimeOptions) {
    const runtimeOptions = options || new JSRuntimeOptions();
    this._engineHandle = qjs.createEngineWithOptions(
      runtimeOptions.memoryLimitBytes, runtimeOptions.stackLimitBytes);
  }

  get globalObject(): JSValue {
    const handle = qjs.getGlobal(this._engineHandle);
    return new JSValue(this, handle);
  }

  get exception(): JSValue | null {
    const handle = qjs.getException(this._engineHandle);
    if (handle === 0n) {
      return null;
    }
    return new JSValue(this, handle);
  }

  set exception(value: JSValue | null) {
    if (value !== null) {
      qjs.throwException(this._engineHandle, value.valueHandle);
    }
  }

  exceptionHandler?: (context: JSContext, exception: JSValue) => void;

  evaluateScript(script: string, sourceURL?: string): JSValue {
    const url = sourceURL ?? 'evaluate';
    const handle = qjs.evaluateScript(this.engineHandle, script, url);
    const value = new JSValue(this, handle);
    if (value.isException && this.exceptionHandler) {
      const exc = this.exception;
      if (exc) {
        this.exceptionHandler(this, exc);
      }
    }
    return value;
  }

  evaluateBounded(script: string, sourceURL: string = 'evaluate', timeoutMs: number = 100,
    maxPendingJobs: number = 8, input?: Uint8Array,
    imageHost?: (name: string, data: Uint8Array, options: string) => Uint8Array,
    cancelSignal?: Int32Array, scriptHost?: (name: string, payload: string) => string): JSBoundedExecutionResult {
    const nativeResult = qjs.evaluateBounded(this.engineHandle, script, sourceURL,
      Math.max(1, timeoutMs), Math.max(0, maxPendingJobs), input, imageHost, cancelSignal, scriptHost);
    const result = new JSBoundedExecutionResult();
    result.success = nativeResult.success;
    result.value = nativeResult.value;
    result.error = nativeResult.error;
    result.timedOut = nativeResult.timedOut;
    result.elapsedMs = nativeResult.elapsedMs;
    result.pendingJobs = nativeResult.pendingJobs;
    result.bytes = nativeResult.bytes;
    return result;
  }

  setObject(object: Record<string, Object> | JSValue, name: string): void {
    if (object instanceof JSValue) {
      const globalObj = this.globalObject;
      qjs.setProperty(this.engineHandle, globalObj.valueHandle, name, object.valueHandle);
      globalObj.release();
    } else {
      const budget: number[] = [0];
      const objHandle = this.createStructuredValue(object, 0, budget);
      const globalObj = this.globalObject;
      qjs.setProperty(this.engineHandle, globalObj.valueHandle, name, objHandle);
      globalObj.release();
      qjs.release(objHandle);
    }
  }

  /** Converts JSON-safe ArkTS values into real QuickJS objects instead of stringifying them. */
  private createStructuredValue(value: Object | null | undefined, depth: number, budget: number[]): bigint {
    budget[0] = (budget[0] || 0) + 1;
    if (budget[0] > JSContext.MAX_BINDING_NODES || depth > JSContext.MAX_BINDING_DEPTH) {
      return qjs.createNull(this.engineHandle);
    }
    if (value === undefined) return qjs.createUndefined(this.engineHandle);
    if (value === null) return qjs.createNull(this.engineHandle);
    if (typeof value === 'number') return qjs.createNumber(this.engineHandle, value);
    if (typeof value === 'string') return qjs.createString(this.engineHandle, value);
    if (typeof value === 'boolean') return qjs.createBoolean(this.engineHandle, value);
    if (Array.isArray(value)) {
      const array = value as Object[];
      const arrayHandle = qjs.createArray(this.engineHandle, array.length);
      for (let index = 0; index < array.length && budget[0] <= JSContext.MAX_BINDING_NODES; index++) {
        const childHandle = this.createStructuredValue(array[index], depth + 1, budget);
        qjs.setElement(this.engineHandle, arrayHandle, index, childHandle);
        qjs.release(childHandle);
      }
      return arrayHandle;
    }
    if (typeof value === 'object') {
      const objectHandle = qjs.createObject(this.engineHandle);
      const record = value as Record<string, Object>;
      const keys = Object.keys(record);
      for (let index = 0; index < keys.length && budget[0] <= JSContext.MAX_BINDING_NODES; index++) {
        const key = keys[index];
        const childHandle = this.createStructuredValue(record[key], depth + 1, budget);
        qjs.setProperty(this.engineHandle, objectHandle, key, childHandle);
        qjs.release(childHandle);
      }
      return objectHandle;
    }
    return qjs.createString(this.engineHandle, String(value));
  }

  getGlobalProperty(name: string): JSValue {
    return this.globalObject.getProperty(name);
  }

  get name(): string {
    return this.nameValue;
  }

  set name(value: string) {
    this.nameValue = value;
  }

  release(): void {
    if (this.engineHandle !== 0n) {
      qjs.releaseEngine(this.engineHandle);
      this._engineHandle = 0n;
    }
  }
}
