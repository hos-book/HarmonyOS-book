import { image } from '@kit.ImageKit';

/** Pixel dimensions returned by the native preparation worker. */
export declare class ShatterScene {
  handle: number;
  width: number;
  height: number;
  surfaceWidth: number;
  surfaceHeight: number;
  top: number;
}

/** Keep the source alive until this promise settles; only then call PixelMap.release(). */
export const shatterPrepare: (snapshot: image.PixelMap, density: number, budget: number) => Promise<ShatterScene | null>;
/** Events: 0 = first frame submitted, 1 = completed, -1 = renderer failure. */
export const shatterAttach: (handle: number, surfaceId: string, callback: (event: number) => void) => boolean;
export const shatterBegin: (handle: number, durationMs: number) => void;
export const shatterClose: (handle: number) => void;
