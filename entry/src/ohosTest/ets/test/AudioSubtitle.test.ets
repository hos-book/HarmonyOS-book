import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { worker, MessageEvents } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { application } from '@kit.AbilityKit';
import { decodeSubtitleAudio } from 'libsubtitle_audio.so';
import { SubtitleFiles } from '../../../main/ets/service/subtitle/SubtitleFiles';
import { SubtitleModelService } from '../../../main/ets/service/subtitle/SubtitleModelService';
import { SubtitleWorkerRequest, SubtitleWorkerResponse } from '../../../main/ets/model/AudioSubtitle';

/** Explicit suite only: downloads the pinned model; does not alter the user's library. */
export default function audioSubtitleTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  const mp3 = (args['-s class'] ?? args.class) === 'AudioSubtitleMp3Device';
  describe(mp3 ? 'AudioSubtitleMp3Device' : 'AudioSubtitleDevice', () => {
    it('downloads_verifies_decodes_and_recognizes_chinese_audio', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.huan.listenbook', abilityName: 'EntryAbility' });
      // Model verification can now finish immediately; wait for the main HAP to be loaded.
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      const context = ability.context;
      const fixture = `${context.cacheDir}/subtitle-device-fixture.wav`;
      let host: worker.ThreadWorker | null = null;
      try {
        if (mp3) {
          const testContext = await application.createModuleContext(context.getApplicationContext(), 'entry_test');
          const bytes = await testContext.resourceManager.getRawFileContent('audio-subtitle-fixture.mp3');
          const file = fileIo.openSync(fixture, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try { fileIo.writeSync(file.fd, bytes.buffer); } finally { fileIo.closeSync(file); }
        } else {
          await SubtitleFiles.download('https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03/resolve/ec0ba42ddef79fe0bd20c3563f14368f48e69a2c/test_wavs/0.wav',
            {}, fixture, 1024 * 1024, (): boolean => true, (_bytes: number): void => {});
        }
        console.info('[AudioSubtitleDevice] fixture downloaded');
        const decoded = decodeSubtitleAudio(fixture, 0, 12000);
        console.info(`[AudioSubtitleDevice] PCM samples=${decoded.samples.length} endMs=${decoded.endMs}`);
        expect(decoded.samples.length > 16000).assertTrue();
        if (mp3) {
          const seeked = decodeSubtitleAudio(fixture, 12000, 12000);
          expect(seeked.samples.length > 16000).assertTrue();
          expect(seeked.endMs > 12000).assertTrue();
          console.info(`[AudioSubtitleDevice] MP3 seek PCM samples=${seeked.samples.length} endMs=${seeked.endMs}`);
        }
        let lastPercent = -1;
        await SubtitleModelService.ensure(context, (): boolean => true,
          (percent: number): void => {
            if (percent !== lastPercent && percent % 10 === 0) console.info(`[AudioSubtitleDevice] model ${percent}%`);
            lastPercent = percent;
          });
        expect(await SubtitleModelService.ready(context, (): boolean => true)).assertTrue();
        await SubtitleModelService.preparePunctuation(context, (): boolean => true);
        console.info('[AudioSubtitleDevice] model verified');
        host = new worker.ThreadWorker('entry/ets/workers/AudioSubtitleWorker.ets');
        const request = new SubtitleWorkerRequest();
        request.requestId = 1; request.audioPath = fixture; request.modelDir = SubtitleModelService.directory(context);
        const running = host;
        for (const preview of [true, false]) {
        request.preview = preview; request.requestId++;
        const start = Date.now();
        const response = await new Promise<SubtitleWorkerResponse>((resolve, reject): void => {
          const timeout = setTimeout((): void => reject(new Error('subtitle_device_timeout')), 90000);
          running.onmessage = (event: MessageEvents): void => { clearTimeout(timeout); resolve(event.data); };
          running.onerror = (): void => { clearTimeout(timeout); reject(new Error('subtitle_worker_failed')); };
          running.postMessage(request);
        });
        console.info(`[AudioSubtitleDevice] preview=${preview} elapsedMs=${Date.now() - start} cues=${JSON.stringify(response.chunk.cues)}`);
        expect(response.error).assertEqual('');
        expect(response.preview).assertEqual(preview);
        expect(response.chunk.endMs <= (preview ? 4000 : 12000)).assertTrue();
        expect(response.chunk.cues.length > 0).assertTrue();
        expect(response.chunk.cues[0].text.length > 0).assertTrue();
        expect(response.chunk.cues[0].endMs > response.chunk.cues[0].startMs).assertTrue();
        }
      } finally {
        host?.terminate();
        SubtitleFiles.remove(fixture);
      }
    });
  });
}
