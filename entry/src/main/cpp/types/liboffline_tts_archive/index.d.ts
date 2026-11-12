/** Extracts only the selected model's pinned assets into an empty private staging directory. */
export const extract: (fd: number, stagingDirectory: string, modelId: string) => Promise<number>;
export const cancel: () => void;
/** Number of pinned asset bytes written by the latest task. */
export const progress: () => number;
