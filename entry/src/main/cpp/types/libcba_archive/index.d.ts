/** Taskpool only. Extracts validated ACE entries to generated image paths in natural page order. */
export const extract: (fd: number, directory: string, progress: (completed: number, total: number) => void) => string[];
