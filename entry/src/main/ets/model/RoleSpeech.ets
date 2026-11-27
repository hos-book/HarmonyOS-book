@ObservedV2
export class RoleAiState {
  @Trace configured: boolean = false;
  @Trace model: string = '';
  @Trace enabled: boolean = false;
}

export class RoleSpeaker {
  id: string = '';
  name: string = '';
  voiceId: string = '';
  profile: string = '';
  gender: string = 'pending';
  genderSource: string = 'ai';
  age: string = 'pending';
  ageSource: string = 'ai';
  voiceSource: string = 'manual';
}

export class RoleBookSettings {
  bookId: string = '';
  narratorVoiceId: string = '';
  dialogueVoiceId: string = '';
  speakers: RoleSpeaker[] = [];
  chapters: RoleChapterAnalysis[] = [];
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

export class RoleChapterAnalysis {
  chapter: string = '';
  dialogues: RoleDialogue[] = [];
}

export class RoleAnalysisWindow {
  indices: number[] = [];
  complete: boolean = false;
}

export class RoleVoiceMatch {
  profile: string = '';
  gender: string = 'pending';
  age: string = 'pending';
  voiceId: string = '';
}

export class RoleVoiceOption {
  id: string = '';
  description: string = '';
  gender: string = 'pending';
  ages: string[] = [];
  preferred: boolean = false;
}

export class RoleVoiceRequest {
  speaker: RoleSpeaker = new RoleSpeaker();
  context: string = '';
  known: RoleSpeaker[] = [];
  voices: RoleVoiceOption[] = [];
}

export class RoleModelAnswer extends RoleVoiceMatch {
  id: number = -1;
  speaker: string = '?';
}

export class RoleInferenceLine {
  id: number = 0;
  start: number = 0;
  end: number = 0;
  text: string = '';
}

export class RoleInferenceRequest {
  context: string = '';
  lines: RoleInferenceLine[] = [];
}

export class RoleSpeechSample {
  text: string = '';
  voiceId: string = '';
  constructor(text: string, voiceId: string = '') {
    this.text = text;
    this.voiceId = voiceId;
  }
}
