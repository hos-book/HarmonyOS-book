export class RoleModelInfo {
  path: string = '';
  name: string = '';
  fingerprint: string = '';
  architecture: string = '';
  bytes: number = 0;
}

@ObservedV2
export class RoleModelState {
  @Trace model: RoleModelInfo | null = null;
  @Trace enabled: boolean = false;
  @Trace busy: boolean = false;
  @Trace progress: number = 0;
  @Trace verifying: boolean = false;
  @Trace error: ResourceStr = '';
}

export class RoleSpeaker {
  id: string = '';
  name: string = '';
  voiceId: string = '';
}

export class RoleBookSettings {
  bookId: string = '';
  narratorVoiceId: string = '';
  dialogueVoiceId: string = '';
  speakers: RoleSpeaker[] = [];
}

@ObservedV2
export class RoleSpeechState {
  @Trace bookId: string = '';
  @Trace bookTitle: string = '';
  @Trace narratorVoiceId: string = '';
  @Trace dialogueVoiceId: string = '';
  @Trace speakers: RoleSpeaker[] = [];
  @Trace analysing: boolean = false;
  @Trace error: ResourceStr = '';
}

export class RoleDialogue {
  start: number = 0;
  end: number = 0;
  speaker: string = '?';
  complete: boolean = false;
}

export class RoleAnalysisWindow {
  indices: number[] = [];
  complete: boolean = false;
}

export class RoleModelAnswer {
  id: number = -1;
  speaker: string = '?';
}

export class RoleChapterCache {
  version: number = 1;
  dialogues: RoleDialogue[] = [];
}

export class RoleSpeechSample {
  text: string = '';
  voiceId: string = '';
  constructor(text: string, voiceId: string = '') {
    this.text = text;
    this.voiceId = voiceId;
  }
}
