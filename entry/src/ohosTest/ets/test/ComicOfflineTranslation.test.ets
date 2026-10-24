import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ComponentContent, window, LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { ComicTranslationService } from '../../../main/ets/service/ComicTranslationService';
import { ComicOfflineTranslationHost } from '../../../main/ets/components/ComicOfflineTranslationHost';
import { ComicOfflineTranslationService } from '../../../main/ets/service/ComicOfflineTranslationService';
import { ComicTranslationText } from '../../../main/ets/model/ComicTranslation';
import { ComicTranslationModelService } from '../../../main/ets/service/ComicTranslationModelService';

class OfflineTestArgs {}

@Builder
function offlineTestHost(_args: OfflineTestArgs) {
  Column() { ComicOfflineTranslationHost() }.width(10).height(10)
}

export default function comicOfflineTranslationTest() {
  describe('ComicOfflineTranslationDevice', () => {
    it('downloads_verified_language_resources_then_translates_locally', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.huan.listenbook', abilityName: 'EntryAbility' });
      const ability = await delegator.getCurrentTopAbility();
      const missing = await ComicTranslationModelService.missingBytes(ability.context, 'zh-en', (): boolean => true);
      console.info(`[ComicOfflineDevice] missingBytes=${missing}`);
      await ComicTranslationModelService.ensure(ability.context, 'zh-en', (): boolean => true, (_percent: number): void => {});
      expect(await ComicTranslationModelService.missingBytes(ability.context, 'zh-en', (): boolean => true)).assertEqual(0);
      console.info('[ComicOfflineDevice] downloadVerified');
      const win = await window.getLastWindow(ability.context);
      const ui = win.getUIContext();
      const content = new ComponentContent(ui, wrapBuilder(offlineTestHost), new OfflineTestArgs());
      await ui.getPromptAction().openCustomDialog(content, { autoCancel: false });
      try {
        const cold = Date.now();
        const first = await ComicOfflineTranslationService.translate([new ComicTranslationText(0, '你好，世界！')], 'zh-en', (): boolean => true);
        console.info(`[ComicOfflineDevice] coldMs=${Date.now() - cold} result=${first[0].text}`);
        expect(first[0].text.toLowerCase().includes('hello')).assertTrue();
        expect(first[0].text.toLowerCase().includes('world')).assertTrue();
        const warm = Date.now();
        const second = await ComicOfflineTranslationService.translate([
          new ComicTranslationText(0, '我们明天早上在学校门口见。'),
          new ComicTranslationText(1, '小心！有人在你后面！')
        ], 'zh-en', (): boolean => true);
        console.info(`[ComicOfflineDevice] warmMs=${Date.now() - warm} result=${JSON.stringify(second)}`);
        expect(second.length).assertEqual(2);
        expect(second[0].text.toLowerCase().includes('school')).assertTrue();
        expect(second[1].text.toLowerCase().includes('behind')).assertTrue();
        const canvas = new OffscreenCanvas(800, 400, LengthMetricsUnit.PX);
        const ctx = canvas.getContext('2d', new RenderingContextSettings(true));
        ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, 800, 400);
        ctx.fillStyle = '#000000'; ctx.font = '60px sans-serif'; ctx.textBaseline = 'top';
        ctx.fillText('你好，世界！', 100, 120);
        const pixels = ctx.getPixelMap(0, 0, 800, 400);
        try {
          const bytes = await ComicTranslationService.translatePixels(pixels, 800, 400, 'zh-en', (): boolean => true);
          const source = image.createImageSource(bytes.buffer);
          const output = await source.createPixelMap();
          try {
            expect(await textRecognition.init()).assertTrue();
            const recognized = await textRecognition.recognizeText({ pixelMap: output });
            console.info(`[ComicOfflineDevice] rendered=${recognized.value}`);
            expect(recognized.value.toLowerCase().includes('hello')).assertTrue();
            expect(recognized.value.includes('你好')).assertFalse();
          } finally {
            await textRecognition.release(); await output.release(); await source.release();
          }
        } finally { await pixels.release(); canvas.width = 0; canvas.height = 0; }
      } finally {
        await ui.getPromptAction().closeCustomDialog(content);
        content.dispose();
      }
    });
  });
}
