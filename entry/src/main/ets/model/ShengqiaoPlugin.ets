export const SHENGQIAO_PROVIDER: string = 'shengqiao';

export class ShengqiaoVoice {
  key: string = '';
  name: string = '';
  channel: string = 'huawei';
  sid: string = '';
  sampleRate: number = 16000;
  style: string = '';
  vip: boolean = false;
}

export class ShengqiaoPackage {
  format: number = 1;
  id: string = 'shengqiao';
  abi: string = 'shengqiao-tts-v1';
  version: string = '';
  secrets: string[] = [];
  voices: ShengqiaoVoice[] = [];
}

@ObservedV2
export class ShengqiaoState {
  @Trace ready: boolean = false;
  @Trace installed: boolean = false;
  @Trace active: boolean = false;
  @Trace loggedIn: boolean = false;
  @Trace busy: boolean = false;
  @Trace testing: boolean = false;
  @Trace version: string = '';
  @Trace voiceCount: number = 0;
  @Trace result: ResourceStr = '';
  @Trace elapsedMs: number = 0;
  @Trace audioBytes: number = 0;
  @Trace voiceName: string = '';
}
