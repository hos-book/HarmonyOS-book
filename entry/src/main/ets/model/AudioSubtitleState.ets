import { SubtitleCue } from './AudioSubtitle';

/** 仅 UI 线程可加载；Worker 共用的 AudioSubtitle 必须保持无 ArkUI 装饰器。 */
@ObservedV2
export class AudioSubtitleState {
  @Trace phase: string = 'idle';
  @Trace percent: number = 0;
  @Trace error: string = '';
  @Trace cues: SubtitleCue[] = [];
  @Trace revision: number = 0;
}
