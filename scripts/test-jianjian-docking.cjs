const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const file=path.join(__dirname,'../entry/src/main/ets/components/JianjianCompanionComponent.ets');
const source=fs.readFileSync(file,'utf8').split('\n  build() {')[0]
  .replace(/^import .*;\r?\n/gm,'').replace('@ComponentV2','').replace('export struct ','export class ')
  .replace(/@(?:Param|Local)\s+/g,'').replace(/\s*@Monitor\([^\n]*\)\r?\n/g,'\n')+'\n}';
const timers=new Map(); let nextId=0,now=1000;
const output={};
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{
  exports:output,Math,Number,Curve:{EaseOut:'ease-out'},Date:{now:()=>now},$r:id=>({id}),
  WindowUtils:{getStatusBarHeightVp:()=>24,getBottomSafeVp:()=>16,getFloatingTabBottomVp:()=>80},
  setTimeout:callback=>{timers.set(++nextId,callback);return nextId;},clearTimeout:id=>timers.delete(id)
});
const c=new output.JianjianCompanionComponent();
c.getUIContext=()=>({animateTo:(_options,update)=>update()});
c.inViewport=true;
c.resize({width:400,height:800});
function dragTo(x) {
  c.beginDrag(); c.moveDrag({offsetX:x-c.dragStartX,offsetY:0}); c.finishDrag();
}
dragTo(10);
assert.equal(c.dockSide,-1);assert.equal(c.characterX,-52);
assert.equal(c.peeking,true);
c.interact(); assert.equal(c.delighted,false,'release must not trigger a click');
now+=301;c.interact();assert.equal(c.characterX,8);assert.equal(c.delighted,true);
assert.equal(c.peeking,false,'interaction unfolds the peeking pose');
const close=timers.get(c.resetTimer);timers.delete(c.resetTimer);close();
assert.equal(c.characterX,-52,'interaction returns to the same edge');
assert.equal(c.peeking,true);
dragTo(150);assert.equal(c.dockSide,0);assert.equal(c.characterX,150);
dragTo(280);assert.equal(c.dockSide,1);assert.equal(c.characterX,348);
c.resize({width:700,height:500});assert.equal(c.characterX,648,'right dock follows window resize');
assert.ok(c.characterY<=352,'height is clamped after resize');
now+=301;c.interact();assert.equal(c.characterX,588);
c.beginDrag();assert.equal(c.dragStartX,588,'expanded drag starts without jumping to the edge');
assert.equal(timers.size,0,'drag cancels auto-collapse');
c.moveDrag({offsetX:-200,offsetY:0});c.finishDrag();assert.equal(c.dockSide,0);
dragTo(-1000);assert.equal(c.characterX,-52,'left visible hit area is retained');
now+=301;c.interact();c.active=false;c.onActiveChanged();
assert.equal(c.characterX,-52);assert.equal(timers.size,0,'background collapses and clears timers');
c.resize({width:300,height:500});assert.equal(c.characterX,-52);
c.aboutToDisappear();assert.equal(timers.size,0);
console.log('PASS: left/right peeking dock, expand/return, drag-out, click suppression, resize and background cleanup');
