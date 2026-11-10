/** Bounded local Qwen GGUF inference. Runs in native async work, never on the UI thread. */
export const run: (operation: string, path: string, prompt: string) => Promise<string>;
export const cancel: () => void;
