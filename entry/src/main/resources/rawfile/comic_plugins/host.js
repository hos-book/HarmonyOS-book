'use strict';

let task;

async function processTask(current, ids) {
  try {
    const response = await fetch('input', { cache: 'no-store' });
    if (!response.ok) throw new Error('input image');
    const bitmap = await createImageBitmap(await response.blob());
    const canvas = document.createElement('canvas');
    canvas.width = bitmap.width; canvas.height = bitmap.height;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(bitmap, 0, 0); bitmap.close();
    const image = context.getImageData(0, 0, canvas.width, canvas.height);
    const plugins = [];
    for (const id of ids) {
      const [wasm, parameters] = await Promise.all([
        fetch(`${id}/processor.wasm`, { cache: 'no-store' }), fetch(`${id}/parameters.json`, { cache: 'no-store' })
      ]);
      if (!wasm.ok || !parameters.ok) throw new Error('plugin resource');
      plugins.push({ wasm: await wasm.arrayBuffer(), parameters: await parameters.json() });
    }
    if (task !== current) return;
    const worker = new Worker('worker.js');
    current.worker = worker;
    const output = await new Promise((resolve, reject) => {
      worker.onmessage = ({ data }) => data.error ? reject(new Error(data.error)) : resolve(data);
      worker.onerror = () => reject(new Error('plugin worker'));
      worker.postMessage({ width: image.width, height: image.height, pixels: image.data.buffer, plugins },
        [image.data.buffer, ...plugins.map(plugin => plugin.wasm)]);
    });
    worker.terminate(); current.worker = null;
    if (task !== current) return;
    if (!output.changed) { current.status = 'original'; return; }
    canvas.width = output.width; canvas.height = output.height;
    context.putImageData(new ImageData(new Uint8ClampedArray(output.pixels), output.width, output.height), 0, 0);
    current.output = canvas.toDataURL('image/png').split(',')[1];
    current.status = 'ready';
  } catch (_error) {
    if (task === current) { current.worker?.terminate(); current.worker = null; current.status = 'error'; }
  }
}

window.comicPlugins = {
  start(id, ids) {
    task?.worker?.terminate();
    task = { id, status: 'pending', output: '', worker: null };
    processTask(task, ids);
    return true;
  },
  status(id) { return task?.id === id ? task.status : 'cancelled'; },
  take(id, offset, length) { return task?.id === id ? task.output.slice(offset, offset + length) : ''; },
  cancel(id) {
    if (task?.id === id) { task.worker?.terminate(); task = null; }
    return true;
  }
};
