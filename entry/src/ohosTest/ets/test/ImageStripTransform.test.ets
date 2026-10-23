import { describe, expect, it } from '@ohos/hypium';
import { image } from '@kit.ImageKit';
import { NativeImageScriptRunner, NativeImageScriptContext } from '../../../main/ets/service/rulesource/light/upstream/core/nativesource/NativeImageScriptRunner';
import { LightSourceSandbox } from '../../../main/ets/service/rulesource/light/LightSourceSandbox';

async function fixture(): Promise<Uint8Array> {
  const rgba = new Uint8Array(3 * 11 * 4);
  for (let row = 0; row < 11; row++) {
    for (let column = 0; column < 3; column++) {
      const offset = (row * 3 + column) * 4;
      rgba[offset] = row * 20;
      rgba[offset + 1] = 40;
      rgba[offset + 2] = 80;
      rgba[offset + 3] = 255;
    }
  }
  const pixels = await image.createPixelMap(rgba.buffer, {
    size: { width: 3, height: 11 }, pixelFormat: image.PixelMapFormat.RGBA_8888,
    srcPixelFormat: image.PixelMapFormat.RGBA_8888
  });
  const packer = image.createImagePacker();
  try { return new Uint8Array(await packer.packToData(pixels, { format: 'image/png', quality: 100 })); }
  finally { try { await packer.release(); } finally { await pixels.release(); } }
}

async function verifyRows(options: string, expected: number[]): Promise<void> {
  const context: NativeImageScriptContext = { url: 'https://fixture.test/image.png', index: 0, params: {} };
  const program = NativeImageScriptRunner.program(
    `function restore(bytes){return image.reorderStrips(bytes,${options});}`, 'restore', context);
  const result = await LightSourceSandbox.evaluateImage(program, await fixture(), (): boolean => false);
  const source = image.createImageSource(result.buffer);
  let pixels: image.PixelMap | null = null;
  try {
    const info = await source.getImageInfo();
    expect(info.size.width).assertEqual(3);
    expect(info.size.height).assertEqual(11);
    pixels = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const buffer = new ArrayBuffer(pixels.getBytesNumberPerRow() * 11);
    await pixels.readPixelsToBuffer(buffer);
    const output = new Uint8Array(buffer);
    for (let row = 0; row < expected.length; row++) {
      for (let column = 0; column < 3; column++) {
        const offset = row * pixels.getBytesNumberPerRow() + column * 4;
        expect(output[offset]).assertEqual(expected[row] * 20);
        expect(output[offset + 1]).assertEqual(40);
        expect(output[offset + 2]).assertEqual(80);
        expect(output[offset + 3]).assertEqual(255);
      }
    }
  } finally { try { if (pixels !== null) await pixels.release(); } finally { await source.release(); } }
}

export default function imageStripTransformTest() {
  describe('ImageStripTransform', () => {
    it('restores_native_strips_with_remainder_and_custom_order', 0, async () => {
      await verifyRows('{count:3}', [6, 7, 8, 9, 10, 3, 4, 5, 0, 1, 2]);
      await verifyRows('{count:3,remainder:"first",order:[2,0,1]}', [8, 9, 10, 0, 1, 2, 3, 4, 5, 6, 7]);
    });
  });
}
