// Copyright (c) 2026 legado-harmony contributors
// SPDX-License-Identifier: MIT

export interface BoundedExecutionResult {
  bytes: Uint8Array;
  success: boolean;
  value: string;
  error: string;
  timedOut: boolean;
  elapsedMs: number;
  pendingJobs: number;
}

/**
 * Type surface of the object exported by libquickjs.so.
 *
 * Keep the native exports behind an interface instead of declaring dozens of top-level function-valued constants.
 * DevEco's native implementation inspection cannot follow this module's napi_define_properties registration table
 * and otherwise reports every valid export as "has no native implementation". Runtime loading is isolated in
 * NativeQuickJs.ts, so this type-only declaration does not change the N-API ABI.
 */
export interface QuickJsNativeApi {
  // Engine/Context Lifecycle
  createEngine(): bigint;
  createEngineWithOptions(memoryLimitBytes: number, stackLimitBytes: number): bigint;
  releaseEngine(engineHandle: bigint): void;
  getGlobal(engineHandle: bigint): bigint;

  // Value Factory
  createUndefined(engineHandle: bigint): bigint;
  createNull(engineHandle: bigint): bigint;
  createBoolean(engineHandle: bigint, value: boolean): bigint;
  createNumber(engineHandle: bigint, value: number): bigint;
  createString(engineHandle: bigint, value: string): bigint;
  createObject(engineHandle: bigint): bigint;
  createArray(engineHandle: bigint, length?: number): bigint;
  createError(engineHandle: bigint, code: string, message: string): bigint;
  createDate(engineHandle: bigint, timeMs: number): bigint;

  // Value Type Checks
  isUndefined(valueHandle: bigint): boolean;
  isNull(valueHandle: bigint): boolean;
  isBoolean(valueHandle: bigint): boolean;
  isNumber(valueHandle: bigint): boolean;
  isString(valueHandle: bigint): boolean;
  isObject(valueHandle: bigint): boolean;
  isArray(valueHandle: bigint): boolean;
  isDate(valueHandle: bigint): boolean;
  isCallable(valueHandle: bigint): boolean;
  isError(valueHandle: bigint): boolean;
  isException(valueHandle: bigint): boolean;

  // Value Conversion
  toBooleanValue(valueHandle: bigint): boolean;
  toNumberValue(valueHandle: bigint): number;
  toStringValue(valueHandle: bigint): string;

  // Property Access
  getProperty(engineHandle: bigint, objHandle: bigint, key: string): bigint;
  setProperty(engineHandle: bigint, objHandle: bigint, key: string, valueHandle: bigint): boolean;
  hasProperty(engineHandle: bigint, objHandle: bigint, key: string): boolean;
  deleteProperty(engineHandle: bigint, objHandle: bigint, key: string): boolean;
  getPropertyNames(engineHandle: bigint, objHandle: bigint): bigint;
  getElement(engineHandle: bigint, arrayHandle: bigint, index: number): bigint;
  setElement(engineHandle: bigint, arrayHandle: bigint, index: number, valueHandle: bigint): boolean;
  getArrayLength(engineHandle: bigint, arrayHandle: bigint): number;

  // Function Call
  callFunction(engineHandle: bigint, thisHandle: bigint, funcHandle: bigint, args: bigint[]): bigint;
  construct(engineHandle: bigint, constructorHandle: bigint, args: bigint[]): bigint;

  // Comparison
  strictEquals(valueHandle1: bigint, valueHandle2: bigint): boolean;
  looseEquals(valueHandle1: bigint, valueHandle2: bigint): boolean;
  instanceOf(valueHandle: bigint, constructorHandle: bigint): boolean;

  // Value Lifecycle
  addRef(valueHandle: bigint): void;
  release(valueHandle: bigint): void;

  // Script Evaluation
  evaluateScript(engineHandle: bigint, script: string, sourceURL?: string): bigint;
  evaluateBounded(engineHandle: bigint, script: string, sourceURL: string,
    timeoutMs: number, maxPendingJobs: number, input?: Uint8Array,
    imageHost?: (name: string, data: Uint8Array, options: string) => Uint8Array,
    cancelSignal?: Int32Array, scriptHost?: (name: string, payload: string) => string): BoundedExecutionResult;

  // Error / Exception
  getException(engineHandle: bigint): bigint;
  throwException(engineHandle: bigint, valueHandle: bigint): bigint;
}
