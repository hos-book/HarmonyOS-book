import { CustomTtsConfig } from './CustomTtsConfig';
import { SpeechSynthesisSettings } from './SpeechSynthesisSettings';

@ObservedV2
export class TextToSpeechState {
  @Trace active: boolean = false;
  @Trace bookId: string = '';
  @Trace bookTitle: string = '';
  @Trace cover: string = '';
  @Trace highlightOffset: number = -1;
  @Trace highlightEnd: number = -1;
  @Trace chapterIndex: number = 0;
  @Trace chapterTitle: string = '';
  @Trace chapterCount: number = 0;
  @Trace charOffset: number = 0;
  // 听书页段内跟随坐标，不驱动正文逐字翻页或频繁保存阅读进度。
  @Trace playbackOffset: number = 0;
  @Trace contentLength: number = 0;
  @Trace sentence: string = '';
  @Trace playing: boolean = false;
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace speed: number = 1;
  @Trace person: number = 13;
  @Trace language: string = 'zh-CN';
  @Trace voices: SpeechVoice[] = [];
  @Trace downloadingVoice: string = '';
  @Trace customTtsId: string = '';
  @Trace customTtsConfigs: CustomTtsConfig[] = [];
  @Trace follow: boolean = true;
  @Trace synthesis: SpeechSynthesisSettings = new SpeechSynthesisSettings();
  @Trace stopAtChapterEnd: boolean = false;
  @Trace remainingSeconds: number = 0;

  isVoiceSelected(voice: SpeechVoice): boolean {
    const language = this.language.replace('_', '-').toLowerCase();
    const voiceLanguage = voice.language.replace('_', '-').toLowerCase();
    if (language !== voiceLanguage) return false;
    if (language === 'zh-cn' && (this.person === 0 || this.person === 13)) {
      return voice.person === 0 || voice.person === 13;
    }
    return this.person === voice.person;
  }
}

@ObservedV2
export class SpeechVoice {
  id: string = '';
  person: number = 13;
  language: string = 'zh-CN';
  style: string = 'interaction-broadcast';
  @Trace label: string = '';
  @Trace installed: boolean = false;
}

export class SpeechPosition {
  sourceUrl: string = '';
  bookUrl: string = '';
  chapterUrl: string = '';
  chapterIndex: number = 0;
  charOffset: number = 0;
}
