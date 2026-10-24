import { describe, expect, it } from '@ohos/hypium';
import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { textRecognition } from '@kit.CoreVisionKit';
import { ComicTranslationService } from '../../../main/ets/service/ComicTranslationService';
import { ComicTranslationRegion, ComicTextBox, ComicTranslationText } from '../../../main/ets/model/ComicTranslation';

export default function comicTranslationTest() {
  describe('ComicTranslationDevice', () => {
    it('recognizes_text_and_renders_chinese_locally_without_network', 0, async () => {
      expect(ComicTranslationService.supported()).assertTrue();
      const canvas = new OffscreenCanvas(600, 400, LengthMetricsUnit.PX);
      const ctx = canvas.getContext('2d', new RenderingContextSettings(true));
      ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, 600, 400);
      ctx.fillStyle = '#000000'; ctx.font = '60px sans-serif'; ctx.textBaseline = 'top';
      ctx.fillText('HELLO', 100, 120);
      const input = ctx.getPixelMap(0, 0, 600, 400);
      let output: image.PixelMap | null = null;
      let source: image.ImageSource | null = null;
      try {
        expect(await textRecognition.init()).assertTrue();
        const recognized = await textRecognition.recognizeText({ pixelMap: input });
        expect(recognized.value.toUpperCase().includes('HELLO')).assertTrue();
        expect(ComicTranslationService.regions(recognized, 600, 400).length > 0).assertTrue();
        const box = new ComicTextBox();
        box.x = 90; box.y = 110; box.width = 400; box.height = 100;
        const region = new ComicTranslationRegion();
        region.x = box.x; region.y = box.y; region.width = box.width; region.height = box.height;
        region.source = 'HELLO'; region.masks = [box];
        const bytes = await ComicTranslationService.render(input, 600, 400, [region],
          [new ComicTranslationText(0, '你好世界')], (): boolean => true);
        source = image.createImageSource(bytes.buffer);
        const info = await source.getImageInfo();
        expect(info.size.width).assertEqual(600); expect(info.size.height).assertEqual(400);
        output = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
        const translated = await textRecognition.recognizeText({ pixelMap: output });
        expect(translated.value.includes('你好世界')).assertTrue();
        expect(translated.value.toUpperCase().includes('HELLO')).assertFalse();
      } finally {
        try { await textRecognition.release(); } finally {
          if (output !== null) await output.release();
          if (source !== null) await source.release();
          await input.release(); canvas.width = 0; canvas.height = 0;
        }
      }
    });
  });
}
