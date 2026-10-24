'use strict';
// No platform bridge: the native owner submits JSON and polls a bounded result.
let worker = null;
let idleTimer = null;
let state = { id: 0, status: 'idle', translations: [] };
window.comicOffline = {
  start(id, items, direction) {
    if (state.status === 'running') return false;
    clearTimeout(idleTimer);
    state = { id, status: 'running', translations: [] };
    if (!worker) {
      worker = new Worker('engine.js', { type: 'module' });
      worker.onmessage = event => {
        if (event.data.id === state.id) {
          state = event.data;
          idleTimer = setTimeout(() => { worker?.terminate(); worker = null; }, 60000);
        }
      };
      worker.onerror = () => { state = { id: state.id, status: 'error', translations: [] }; };
    }
    worker.postMessage({ id, items, direction });
    return true;
  },
  snapshot() { return JSON.stringify(state); },
  cancel(id) {
    if (state.id !== id) return;
    clearTimeout(idleTimer);
    if (worker) worker.terminate();
    worker = null;
    state = { id, status: 'cancelled', translations: [] };
  }
};
