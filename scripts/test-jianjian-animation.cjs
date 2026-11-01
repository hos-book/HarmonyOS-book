// Exercise the real avatar lifecycle methods with a deterministic scheduler.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const file = path.join(__dirname, '../entry/src/main/ets/components/JianjianAvatarComponent.ets');
const source = fs.readFileSync(file, 'utf8').split('\n  build() {')[0]
  .replace('@ComponentV2', '').replace('export struct ', 'export class ')
  .replace(/@(?:Param|Local)\s+/g, '').replace(/\s*@Monitor\([^\n]*\)\n/g, '\n') + '\n}';
const pending = new Map();
let id = 0;
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsObject, Math,
  require: name => {
    assert.equal(name, '../service/JianjianRenderController');
    return { JianjianRenderController: class { update() {} setEyes() {} release() {} } };
  },
  setTimeout: (callback, delay) => { pending.set(++id, { callback, delay }); return id; },
  clearTimeout: key => pending.delete(key) });
const avatar = new exportsObject.JianjianAvatarComponent();
function next() {
  assert.equal(pending.size, 1, 'exactly one next transition is scheduled');
  const [key, timer] = pending.entries().next().value;
  pending.delete(key); timer.callback();
}
avatar.mounted = true;
avatar.restart();
assert.equal(pending.size, 0, 'inactive component schedules nothing');
avatar.running = true;
avatar.onAnimationChanged();
next();
assert.equal(avatar.leftClosed && avatar.rightClosed, true);
next();
assert.equal(avatar.leftClosed || avatar.rightClosed, false);
const stale = pending.values().next().value.callback;
avatar.running = false;
avatar.onAnimationChanged();
assert.equal(pending.size, 0, 'background/drag cancels timers');
avatar.running = true;
avatar.onAnimationChanged();
stale();
assert.equal(pending.size, 1, 'stale callback cannot start an extra loop');
assert.equal(avatar.leftClosed, false);
avatar.reacting = true;
avatar.reactionIndex = 6;
avatar.onAnimationChanged();
assert.equal(avatar.leftClosed, true);
assert.equal(avatar.rightClosed, false);
next();
assert.equal(avatar.leftClosed, false);
avatar.reactionIndex = 3;
avatar.onAnimationChanged();
assert.equal(avatar.leftClosed && avatar.rightClosed, true);
assert.equal(pending.size, 0, 'sleepy expression has no idle blink loop');
avatar.reacting = false;
avatar.onAnimationChanged();
assert.equal(avatar.leftClosed || avatar.rightClosed, false);
const beforeRemoval = pending.values().next().value.callback;
avatar.aboutToDisappear();
beforeRemoval();
assert.equal(pending.size, 0, 'unmount prevents delayed restart');
console.log('PASS: blink/reopen, wink, sleepy reset, inactive/drag, stale callbacks and disposal');
