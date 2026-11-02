export class SubtitlePcm {
  samples: Float32Array;
  sampleRate: number;
  endMs: number;
}
/** Worker only. Decodes at most 16 seconds from a local, readable audio file. */
export const decodeSubtitleAudio: (path: string, startMs: number, durationMs: number) => SubtitlePcm;
