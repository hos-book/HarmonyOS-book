// Run against the temporary, patched upstream checkout before packaging the HAR.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const project = process.argv[2];
if (!project) throw Error('Pass the external engine checkout path');
const root = path.join(project, 'aiengine/src/main/ets/core/reader');
const load = (ctx, file) => vm.runInContext(stripTypeScriptTypes(fs.readFileSync(path.join(root, file), 'utf8')
  .replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '')), ctx);
let member = true, active = true, now = 1000000, thread, tick, expiry, created = 0;
class FakeWorker {
  constructor() { created++; thread = this; this.messages = []; this.terminated = false; }
  postMessage(job) { this.messages.push(job); }
  terminate() { this.terminated = true; }
  reply(data) { this.onmessage({ data }); }
}
const ctx = vm.createContext({ Promise, Map, Error, ArrayBuffer, Uint8Array, Number, Array,
  console: { info() {}, warn() {} }, Date: { now: () => now },
  AiRuntime: { isAllowed: () => member, current: () => ({ createColorWorker: () => new FakeWorker() }) },
  setInterval(fn) { tick = fn; return 1; }, clearInterval() { tick = null; },
  setTimeout(fn, ms) { assert.equal(ms, 120000); expiry = fn; return 2; }, clearTimeout() { expiry = null; }
});
for (const file of ['ComicColorTypes.ts', 'ComicColorProfilePolicy.ts', 'ReaderComicComputeQueue.ts', 'ComicColorizer.ets']) load(ctx, file);
const Colorizer = vm.runInContext('ComicColorizer', ctx);
const Job = vm.runInContext('ComicColorJob', ctx);
const Queue = vm.runInContext('ReaderComicComputeQueue', ctx);
const start = () => Colorizer.execute(new Job(), () => active, () => {});
const warm = start(); thread.reply({ jpeg: new ArrayBuffer(8) }); await warm;
const retained = thread;
for (const reply of [{ error: Colorizer.CANCELLED }, { jpeg: new ArrayBuffer(8) }]) {
  const task = start(); let settled = false; task.then(() => { settled = true; }, () => { settled = true; });
  active = false; tick();
  assert.equal(thread.messages.at(-1).cancel, true);
  await Promise.resolve();
  assert.equal(settled, false, 'native queue remains occupied until safe acknowledgement');
  assert.equal(thread.terminated, false, 'never tear down an active native callback');
  thread.reply(reply); await assert.rejects(task, /已取消着色/);
  assert.equal(thread.terminated, false, 'viewport cancellation keeps worker');
  active = true;
  const next = start(); thread.reply({ jpeg: new ArrayBuffer(8) }); await next;
  assert.equal(thread, retained, 'next page uses the same worker');
}
assert.equal(created, 1);
expiry(); assert.equal(retained.terminated, true, 'idle retention is bounded');
for (const action of ['release', 'background', 'pressure', 'member', 'error', 'error-after-cancel', 'timeout', 'worker-error']) {
  Colorizer.setAppForeground(true); member = true; active = true; now += 60001;
  const task = start(); const current = thread;
  if (action === 'release') { active = false; Colorizer.releaseIdleWorker(); }
  if (action === 'background') Colorizer.setAppForeground(false);
  if (action === 'pressure') { active = false; Colorizer.onMemoryPressure(); }
  if (action === 'member') member = false;
  if (action === 'error-after-cancel') active = false;
  if (action === 'timeout') now += 180001;
  tick(); assert.equal(current.terminated, false, action);
  if (action === 'worker-error') current.onerror();
  else if (action.startsWith('error')) current.reply({ error: 'native failed' });
  else current.reply({ error: Colorizer.CANCELLED });
  await assert.rejects(task);
  assert.equal(current.terminated, true, `${action} must evict`);
}
Colorizer.setAppForeground(true); member = true; active = true; now += 60001;
const task = start(); thread.reply({ jpeg: new ArrayBuffer(8) }); await task;
await Queue.run(async () => assert.equal(thread.terminated, true), () => 0, 'sr');
console.log('AI package: viewport cancellation reuses; release/background/pressure/expiry/error/revocation evict safely.');

// Exercise the real wrapper and inference, with platform inference substituted at its boundary.
let loads = 0, cancelOnLoad = false, cancelled = false, outputLayout = 'nchw';
const width = 32, height = 32;
const runtime = {
  DataType: { NUMBER_TYPE_FLOAT32: 43 },
  async loadModelFromFile() {
    loads++;
    if (cancelOnLoad) cancelled = true;
    const input = { shape: [1, height, width, 5], dtype: 43, setData() {} };
    return { getInputs: () => [input], async predict() {
      const values = new Float32Array(width * height * 3);
      values.fill(0.25);
      return [{ dtype: 43, shape: outputLayout === 'nchw' ? [1, 3, height, width] : [1, height, width, 3],
        getData: () => values.buffer }];
    } };
  }
};
const numeric = vm.createContext({ mindSporeLite: runtime, Float32Array, Uint8Array, ArrayBuffer, Error, Number, Math, Date,
  pixelNative: { input() { throw Error('native unavailable'); }, output() { throw Error('native unavailable'); } },
  console: { info() {}, warn() {} } });
for (const file of ['ComicColorPixels.ts', 'ComicColorComposite.ets', 'ComicColorTypes.ts', 'ComicColorInference.ets']) load(numeric, file);
const Inference = vm.runInContext('ComicColorInference', numeric);
const Composite = vm.runInContext('ComicColorComposite', numeric);
const Pixels = vm.runInContext('ComicColorPixels', numeric);
const check = () => { if (cancelled) throw Error('cancelled'); };
const tensor = new Float32Array(width * height * 5);
cancelOnLoad = true;
await assert.rejects(Inference.execute('portrait.ms', tensor, width, height, { target: ['nnrt'] }, check), /cancelled/);
cancelOnLoad = false; cancelled = false;
await Inference.execute('portrait.ms', tensor, width, height, { target: ['nnrt'] }, check);
assert.equal(loads, 1, 'a completed load survives a cancelled page');
outputLayout = 'nhwc';
await Inference.execute('portrait.ms', tensor, width, height, { target: ['nnrt'] }, check);
await Inference.execute('landscape.ms', tensor, width, height, { target: ['nnrt'] }, check);
assert.equal(loads, 2, 'a different model path must reload');
const rgba = new Uint8Array([0,0,0,255,255,128,64,128,9,9,9,9,128,128,128,0,64,32,16,255,9,9,9,9]);
assert.deepEqual(Composite.input(rgba, 2, 2, 12, 32, 32), Pixels.input(rgba, 2, 2, 12, 32, 32));
const values = new Float32Array([1,0.5,0,-0.5,-1,0.25]);
assert.deepEqual(Composite.output(values, 2, 1, true), Pixels.interleave(values, 2, 1));
const owned = Composite.output(values, 2, 1, false);
values[0] = -0.9; assert.equal(owned[0], 1, 'output owns its buffer');
for (const bad of [NaN, Infinity, -Infinity, 1.02, -1.02]) {
  values[0] = bad;
  for (const planar of [true, false]) assert.throws(() => Composite.output(values, 2, 1, planar));
}
console.log('AI package: load cancellation reuse, model-path isolation, layout handling and validated ArkTS fallback passed.');
