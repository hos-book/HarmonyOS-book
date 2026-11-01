const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/JianjianRig.ets'), 'utf8');
const out = {};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS
} }).outputText, { exports: out, Math });
const Rig = out.JianjianRig;
const rig = new Rig();
const vertex = (row, col) => (row*(Rig.COLUMNS+1)+col)*2;
const area = (v, a, b, c) => (v[b]-v[a])*(v[c+1]-v[a+1])-(v[b+1]-v[a+1])*(v[c]-v[a]);
let minimum = Infinity;
for (let t=0; t<12; t+=0.1) {
  for (const expression of [-1, 0, 6]) {
    rig.update(t, expression<0 ? -1 : t%2.4, expression);
    const v = rig.vertices;
    assert.equal(v.length, (Rig.COLUMNS+1)*(Rig.ROWS+1)*2);
    assert.ok(v.every(Number.isFinite));
    for (let row=0; row<Rig.ROWS; row++) for(let col=0;col<Rig.COLUMNS;col++) {
      const a=vertex(row,col), b=vertex(row,col+1), c=vertex(row+1,col), d=vertex(row+1,col+1);
      const first=area(v,a,b,c), second=area(v,b,d,c);
      assert.ok(first>0 && second>0, `mesh must not fold: t=${t}, expression=${expression}, row=${row}, col=${col}`);
      minimum=Math.min(minimum,first,second);
    }
    for(let col=0;col<=Rig.COLUMNS;col++) {
      const foot=vertex(Rig.ROWS,col);
      assert.ok(Math.abs(v[foot]-col/Rig.COLUMNS*Rig.WIDTH)<0.01);
      assert.ok(Math.abs(v[foot+1]-Rig.HEIGHT)<0.01, 'feet remain anchored');
    }
  }
}
rig.update(1, -1, -1);
const sample=[...rig.vertices];
rig.update(3, -1, -1);
assert.ok(Math.abs(sample[vertex(8,12)]-rig.vertices[vertex(8,12)])>2, 'head moves visibly');
assert.ok(Math.abs(sample[vertex(25,2)]-rig.vertices[vertex(25,2)])>2, 'hair has local motion');
console.log(`PASS: independent head/hair motion, anchored feet, no folded triangles; minimum area ${minimum.toFixed(2)}`);
if(process.argv[2]) {
  const frames=[];
  for(let i=0;i<72;i++) {
    rig.update(i/12, i>=36 ? (i-36)/12 : -1, 6);
    frames.push([...rig.vertices]);
  }
  fs.writeFileSync(process.argv[2],JSON.stringify({width:Rig.WIDTH,height:Rig.HEIGHT,columns:Rig.COLUMNS,rows:Rig.ROWS,frames}));
}
