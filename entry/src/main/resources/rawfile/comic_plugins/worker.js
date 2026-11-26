'use strict';

self.onmessage = async ({ data }) => {
  try {
    let input = new Uint8ClampedArray(data.pixels);
    let width = data.width;
    let height = data.height;
    let changed = false;
    for (const plugin of data.plugins) {
      const config = new TextEncoder().encode(JSON.stringify({
        parameters: plugin.parameters, settings: {}, context: { application: 'auto' }
      }));
      let memory;
      let output;
      let outputWidth = 0;
      let outputHeight = 0;
      let writtenRows = 0;
      const region = (x, y, w, h) => Number.isInteger(x) && Number.isInteger(y) &&
        Number.isInteger(w) && Number.isInteger(h) && x >= 0 && y >= 0 && w > 0 && h > 0;
      const guest = (ptr, length) => {
        if (ptr < 0 || length < 0 || ptr + length > memory.buffer.byteLength) throw new Error('guest region');
        return new Uint8Array(memory.buffer, ptr, length);
      };
      const instance = await WebAssembly.instantiate(plugin.wasm, {
        koma_image: {
          width: () => width,
          height: () => height,
          config_len: () => config.length,
          config_read: (ptr, capacity) => {
            if (capacity < config.length) return -1;
            guest(ptr, config.length).set(config);
            return config.length;
          },
          read_region: (x, y, w, h, ptr, capacity) => {
            const length = w * h * 4;
            if (!region(x, y, w, h) || x + w > width || y + h > height || capacity < length) return -1;
            const destination = guest(ptr, length);
            for (let row = 0; row < h; row++) {
              const at = ((y + row) * width + x) * 4;
              destination.set(input.subarray(at, at + w * 4), row * w * 4);
            }
            return length;
          },
          output_create: (w, h) => {
            if (output || !region(0, 0, w, h)) return -1;
            outputWidth = w; outputHeight = h;
            output = new Uint8ClampedArray(w * h * 4);
            return 0;
          },
          output_write: (x, y, w, h, ptr, length) => {
            if (!output || !region(x, y, w, h) || x !== 0 || y !== writtenRows || w !== outputWidth ||
              y + h > outputHeight || length !== w * h * 4) return -1;
            output.set(guest(ptr, length), y * w * 4);
            writtenRows += h;
            return length;
          },
          check_cancel: () => 0
        }
      });
      const exports = instance.instance.exports;
      memory = exports.memory;
      if (exports.koma_image_processor_abi() !== 1) throw new Error('plugin ABI');
      const status = exports.koma_image_process();
      if (status === 1 && output && writtenRows === outputHeight) {
        input = output; width = outputWidth; height = outputHeight; changed = true;
      } else if (status !== 0) throw new Error('plugin output');
    }
    self.postMessage({ changed, width, height, pixels: input.buffer }, [input.buffer]);
  } catch (error) {
    self.postMessage({ error: String(error) });
  }
};
