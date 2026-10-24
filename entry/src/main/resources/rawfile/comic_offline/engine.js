import { env, pipeline } from './transformers.min.js';

env.allowRemoteModels = false;
env.allowLocalModels = true;
env.localModelPath = new URL('./models/', import.meta.url).href;
env.useBrowserCache = false;
env.backends.onnx.wasm.wasmPaths = new URL('./', import.meta.url).href;
env.backends.onnx.wasm.numThreads = 1;
env.backends.onnx.wasm.proxy = false;
// At most two pipelines, released with the worker on cancellation or idle timeout.
const models = new Map();
const routes = { 'ja-zh': ['ja-en', 'en-zh'], 'ko-zh': ['ko-en', 'en-zh'], 'en-zh': ['en-zh'], 'zh-en': ['zh-en'] };

async function modelFor(id) {
  if (models.has(id)) {
    const model = models.get(id); models.delete(id); models.set(id, model); return model;
  }
  while (models.size >= 2) {
    const oldest = models.keys().next().value;
    await models.get(oldest).dispose(); models.delete(oldest);
  }
  const model = await pipeline('translation', id, { quantized: true, local_files_only: true });
  models.set(id, model);
  return model;
}

async function translateLeg(modelId, items) {
  const translator = await modelFor(modelId);
  const translations = [];
  let total = 0;
  for (const item of items) {
    const parts = item.text.match(/[^。！？!?\n]{1,100}[。！？!?\n]?|[。！？!?\n]/gu) || [];
    const output = [];
    for (const part of parts) {
      const hasSource = modelId === 'zh-en' ? /[\u3400-\u9fff]/u.test(part) : modelId === 'ja-en' ?
        /[\u3040-\u30ff\u3400-\u9fff]/u.test(part) : modelId === 'ko-en' ? /[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]/u.test(part) : /[A-Za-z]/.test(part);
      if (!hasSource) { output.push(part.trim()); continue; }
      const result = await translator(part, { max_new_tokens: 256, num_beams: 1, do_sample: false });
      const text = result[0]?.translation_text?.trim();
      if (!text || text.length > 2000) throw Error('output');
      output.push(text);
    }
    const text = output.join(' ').trim();
    total += text.length;
    if (!text || text.length > 2000 || total > 32000) throw Error('output');
    translations.push({ id: item.id, text });
  }
  return translations;
}

self.onmessage = async event => {
  const { id, items, direction } = event.data;
  try {
    if (!Object.hasOwn(routes, direction) || !Array.isArray(items) || items.length > 128 ||
      items.some(item => !Number.isInteger(item.id) || typeof item.text !== 'string' || item.text.length > 2000) ||
      items.reduce((n, item) => n + item.text.length, 0) > 16000) throw Error('bounds');
    let translations = items;
    for (const model of routes[direction]) translations = await translateLeg(model, translations);
    self.postMessage({ id, status: 'done', translations });
  } catch (_) {
    self.postMessage({ id, status: 'error', translations: [] });
  }
};
