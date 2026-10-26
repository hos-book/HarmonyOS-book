const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
let resources = 0, ocrReleases = 0, chats = 0, supported = true, cancelled = false, longText = false, decodes = 0, encodes = 0;
const drawn = [], erased = [], canvasSizes = [];
let member = true;
const pixel = () => { resources++; return { release: async () => { resources--; } }; };
const line = (value,x,y,w,h) => ({ value, cornerPoints:[{x,y},{x:x+w,y},{x:x+w,y:y+h},{x,y:y+h}],words:[] });
let result = { blocks:[{lines:[line('Hello',100,100,180,32),line('world',100,138,160,32),line('Goodbye',500,400,150,32)]}] };
const image = {
  PixelMapFormat:{RGBA_8888:1},
  createImageSource: () => { resources++; decodes++; return { getImageInfo:async()=>({size:{width:800,height:600}}),
    createPixelMap:async()=>pixel(),release:async()=>{resources--;} }; },
  createImagePacker: () => { resources++; encodes++; return {packToData:async()=>new Uint8Array([255,216,255]).buffer,
    release:async()=>{resources--;} }; }
};
class Canvas {
  constructor(w,h,unit) { assert.equal(unit,1);this.width=w;this.height=h;canvasSizes.push(this); }
  getContext() { return { font:'',drawImage(){},getImageData:()=>({width:800,height:600,data:new Uint8ClampedArray(800*600*4).fill(255)}),
    measureText(text) { const font=Number.parseFloat(this.font);return {width:Array.from(text).length*font*0.7}; },
    save(){},restore(){},beginPath(){},rect(){},clip(){},
    fillRect(...args){erased.push(args);},fillText(...args){drawn.push(args);},getPixelMap:()=>pixel() }; }
}
function load(file,require) {
  const exports={};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,file),'utf8').replace(/import lazy /g,'import '),{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}
  }).outputText,{exports,require,Error,setTimeout,canIUse:()=>supported,OffscreenCanvas:Canvas,
    LengthMetricsUnit:{PX:1},RenderingContextSettings:class{},console});
  return exports;
}
const model=load('model/ComicTranslation.ets',()=>({}));
const {ComicTranslationService:service}=load('service/ComicTranslationService.ets',name=>{
  if(name.endsWith('MembershipState'))return {MembershipState:{current:{get hasAccess(){return member;}}}};
  if(name.endsWith('ComicTranslation'))return model;
  if(name.endsWith('ComicOfflineTranslationService')) return {ComicOfflineTranslationService:{translate:async(items,direction,active)=>{
    assert.equal(direction,'en-zh');assert.equal(active(),true);chats++;
    return items.map(item=>new model.ComicTranslationText(item.id,longText?'很'.repeat(2000):'你好世界'));
  }}};
  if(name==='@kit.ImageKit')return {image};
  if(name.includes('arkui') || name==='@kit.ArkUI')return {LengthMetricsUnit:{PX:1}};
  if(name==='@kit.CoreVisionKit')return {textRecognition:{init:async()=>true,recognizeText:async()=>result,
    release:async()=>{ocrReleases++;}}};
  if(name.endsWith('ComicAiConfigService')) throw Error('translation must not import the API service');
  return {};
});
(async()=>{
  const input=new Uint8Array([1,2,3]).buffer;
  member = false;
  await assert.rejects(service.translate(input,'en-zh',()=>true), /cancelled/);
  assert.equal(decodes,0,'non-member cannot start OCR or decode through the byte entry');
  await assert.rejects(service.translatePixels({},800,600,'en-zh',()=>true), /cancelled/);
  assert.equal(chats,0,'non-member cannot use the pixel entry');
  member = true;
  const regions=service.regions(result,800,600);
  assert.equal(regions.length,2,'nearby lines merge while distant balloons stay separate');
  assert.equal(regions[0].source,'Hello\nworld');
  assert.deepEqual(Array.from(service.wrap('hello world',5,x=>x.length)),['hello','world']);
  assert.deepEqual(Array.from(service.wrap('你好世界',2,x=>x.length)),['你好','世界']);
  await service.translate(input,'en-zh',()=>!cancelled);
  assert.equal(chats,1);assert.equal(erased.length,3,'only OCR line rectangles are erased');
  assert.equal(drawn.length,2);assert.equal(drawn[0][0],'你好世界');
  assert.deepEqual(Array.from(new Uint8Array(input)),[1,2,3]);
  assert.equal(resources,0);assert.equal(ocrReleases,1);
  assert.ok(canvasSizes.every(c=>c.width===0&&c.height===0),'canvas backing stores released');
  cancelled=true;
  await assert.rejects(service.translate(input,'en-zh',()=>!cancelled),/cancelled/);
  assert.equal(chats,1);cancelled=false;
  supported=false;
  await assert.rejects(service.translate(input,'en-zh',()=>true),/ocr_unsupported/);
  supported=true;
  longText=true;
  await assert.rejects(service.translate(input,'en-zh',()=>true),/layout_failed/);
  assert.equal(resources,0);
  result={blocks:[]};
  const before=chats;
  const blank=await service.translate(input,'en-zh',()=>true);
  assert.deepEqual(Array.from(blank),[1,2,3]);assert.equal(chats,before,'blank pages never call the model');
  assert.equal(resources,0);
  longText=false;
  result={blocks:[{lines:[line('Hello',100,100,180,32)]}]};
  const borrowed=pixel();
  const beforeDecodes=decodes,beforeEncodes=encodes;
  await service.translatePixels(borrowed,800,600,'en-zh',()=>true);
  assert.equal(decodes,beforeDecodes,'direct pixel entry does not decode again');
  assert.equal(encodes,beforeEncodes+1,'only the finished image is encoded');
  assert.equal(resources,1,'caller retains ownership of its pixel map');
  result={blocks:[]};
  const beforeBlank=chats;
  await service.translatePixels(borrowed,800,600,'en-zh',()=>true);
  assert.equal(chats,beforeBlank,'direct pixel blank page never requests translation');
  await assert.rejects(service.translatePixels(borrowed,800,600,'en-zh',()=>false),/cancelled/);
  await borrowed.release();
  assert.equal(resources,0);
  console.log('comic translation: local OCR, offline-only inference, region grouping, wrapping, rendering bounds, no-text skip and cleanup passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
