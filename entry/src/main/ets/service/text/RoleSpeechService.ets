import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { JianjianAiError, JianjianAiErrorCode } from '../../model/JianjianAi';
import { RoleAnalysisWindow, RoleBookSettings, RoleDialogue, RoleSpeaker, RoleSpeechState,
  RoleSpeechSample, RoleVoiceOption } from '../../model/RoleSpeech';
import { JianjianAiService } from '../JianjianAiService';
import { RoleAiService } from './RoleAiService';
import { RoleSpeechPlanner } from './RoleSpeechPlanner';

/** 保存每书音色，按阅读位置使用 AI 识别当前与后续对白。 */
export class RoleSpeechService {
  private static instance: RoleSpeechService | null = null;
  readonly state: RoleSpeechState = new RoleSpeechState();
  private book: RoleBookSettings = new RoleBookSettings();
  private bookPath: string = '';
  private content: string = '';
  private dialogues: RoleDialogue[] = [];
  private windows: RoleAnalysisWindow[] = [];
  private pending: Map<number, Promise<void>> = new Map<number, Promise<void>>();
  private epoch: number = 0;
  private failed: boolean = false;
  private voices: RoleVoiceOption[] = [];
  private saveChain: Promise<void> = Promise.resolve();

  static getInstance(): RoleSpeechService {
    if (RoleSpeechService.instance === null) RoleSpeechService.instance = new RoleSpeechService();
    return RoleSpeechService.instance;
  }

  get enabled(): boolean { return RoleAiService.instance.state.enabled; }

  setVoices(configs: CustomTtsConfig[], selected: string): void {
    this.voices = RoleAiService.voiceOptions(configs, selected);
  }

  boundaries(): number[] {
    const result: number[] = this.enabled ? [0, this.content.length] : [];
    if (this.enabled) for (const dialogue of this.dialogues) result.push(dialogue.start, dialogue.end);
    return result;
  }

  private save(): Promise<void> {
    const path = this.bookPath;
    const content = JSON.stringify(this.book);
    const task = this.saveChain.catch((): void => {}).then(async (): Promise<void> => {
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, content); }
      finally { await fileIo.close(file); }
    });
    this.saveChain = task;
    return task;
  }

  async selectBook(context: common.Context, id: string, title: string): Promise<void> {
    if (this.state.bookId === id && this.bookPath) { this.state.bookTitle = title; return; }
    const ticket = this.epoch;
    const directory = `${context.filesDir}/role_speech`;
    if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
    let settings = new RoleBookSettings();
    settings.bookId = id;
    let path = `${directory}/book-${Date.now()}.json`;
    for (const name of await fileIo.listFile(directory)) {
      if (!name.startsWith('book-') || !name.endsWith('.json')) continue;
      try {
        const saved: RoleBookSettings = JSON.parse(await fileIo.readText(`${directory}/${name}`));
        if (saved.bookId === id) { settings = saved; path = `${directory}/${name}`; break; }
      } catch (_error) { /* 继续查找本书设置。 */ }
    }
    if (ticket !== this.epoch) return;
    this.book = settings; this.bookPath = path;
    this.state.bookId = id; this.state.bookTitle = title; this.publish();
  }

  private publish(): void {
    this.state.narratorVoiceId = this.book.narratorVoiceId;
    this.state.dialogueVoiceId = this.book.dialogueVoiceId;
    this.state.speakers = this.book.speakers.slice();
  }

  async setVoice(roleId: string, voiceId: string, source: string = 'manual', profile: string = ''): Promise<void> {
    if (!this.bookPath) return;
    if (roleId === '@narrator') this.book.narratorVoiceId = voiceId;
    else if (roleId === '@dialogue') this.book.dialogueVoiceId = voiceId;
    else {
      const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.id === roleId);
      if (!speaker) return;
      speaker.voiceId = voiceId;
      speaker.voiceSource = source;
      if (profile) speaker.profile = profile;
    }
    await this.save();
    this.publish();
  }

  sample(roleId: string): string {
    if (roleId === '@narrator') {
      let start = 0;
      for (const dialogue of this.dialogues) {
        const text = this.content.substring(start, dialogue.start).trim();
        if (text) return text.slice(0, 120);
        start = dialogue.end;
      }
      return this.content.substring(start).trim().slice(0, 120);
    }
    const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.id === roleId);
    const dialogue = this.dialogues.find((item: RoleDialogue): boolean =>
      roleId === '@dialogue' ? item.speaker === '?' : speaker !== undefined && item.speaker === speaker.name);
    return dialogue ? this.content.substring(dialogue.start, dialogue.end).trim().slice(0, 120) : '';
  }

  voiceContext(roleId: string): string {
    const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.id === roleId);
    if (!speaker) return '';
    const dialogue = this.dialogues.find((item: RoleDialogue): boolean => item.speaker === speaker.name);
    const start = dialogue?.start ?? this.content.indexOf(speaker.name);
    if (start < 0) return '';
    return this.content.substring(Math.max(0, start - 1200), Math.min(this.content.length, (dialogue?.end ?? start) + 1200));
  }

  preview(offset: number): RoleSpeechSample[] {
    const samples: RoleSpeechSample[] = [];
    let start = Math.max(0, Math.min(offset, this.content.length));
    const limit = Math.min(this.content.length, start + 300);
    while (start < limit && samples.length < 6) {
      const dialogue = this.dialogueAt(start);
      const next = dialogue?.end ?? this.dialogues.find((item: RoleDialogue): boolean => item.start > start)?.start ?? limit;
      const end = Math.min(limit, next);
      if (end <= start) break;
      const text = this.content.substring(start, end).trim();
      if (text) samples.push(new RoleSpeechSample(text, this.voiceAt(start)));
      start = end;
    }
    return samples;
  }

  async prepare(context: common.Context, bookId: string, title: string, _chapter: string,
    content: string, quotes: string): Promise<void> {
    this.cancel();
    const ticket = this.epoch;
    this.content = ''; this.dialogues = []; this.windows = [];
    this.failed = false; this.state.error = '';
    await RoleAiService.instance.initialize(context);
    await this.selectBook(context, bookId, title);
    if (ticket !== this.epoch || !this.enabled) return;
    this.content = content;
    this.dialogues = RoleSpeechPlanner.dialogues(content, quotes);
    this.windows = RoleSpeechPlanner.windows(this.dialogues);
  }

  cancel(): void {
    this.epoch++; this.pending.clear(); this.state.analysing = false;
    RoleAiService.instance.cancel();
  }

  private dialogueAt(offset: number): RoleDialogue | undefined {
    let low = 0; let high = this.dialogues.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.dialogues[middle].end <= offset) low = middle + 1;
      else high = middle;
    }
    const item = this.dialogues[low];
    return item && item.start <= offset ? item : undefined;
  }

  readyAt(offset: number): boolean {
    return !this.enabled || this.failed || (this.dialogueAt(offset)?.complete ?? true);
  }

  async ensureAt(offset: number): Promise<void> {
    if (this.readyAt(offset)) return;
    const ticket = this.epoch;
    for (const task of this.pending.values()) await task;
    if (ticket !== this.epoch || this.readyAt(offset)) return;
    const index = this.windows.findIndex((window: RoleAnalysisWindow): boolean => window.indices.some((id: number): boolean =>
      this.dialogues[id].start <= offset && this.dialogues[id].end > offset));
    if (index >= 0) await this.analyse(index);
  }

  voiceAt(offset: number): string {
    if (!this.enabled) return '';
    const dialogue = this.dialogueAt(offset);
    if (!dialogue) return this.book.narratorVoiceId;
    const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.name === dialogue.speaker);
    return speaker !== undefined && speaker.voiceId.length > 0 ? speaker.voiceId : this.book.dialogueVoiceId;
  }

  prefetch(offset: number): Promise<void> {
    if (!this.enabled || this.failed || this.pending.size > 0) return Promise.resolve();
    const index = this.windows.findIndex((window: RoleAnalysisWindow): boolean => !window.complete &&
      this.dialogues[window.indices[window.indices.length - 1]].end > offset);
    return index < 0 ? Promise.resolve() : this.analyse(index);
  }

  private analyse(index: number): Promise<void> {
    const existing = this.pending.get(index);
    if (existing !== undefined) return existing;
    const ticket = this.epoch;
    const window = this.windows[index];
    const task = (async (): Promise<void> => {
      try {
        this.state.analysing = true;
        const known = this.book.speakers.map((item: RoleSpeaker): string => item.name);
        const request = RoleSpeechPlanner.request(this.content, this.dialogues, window);
        const result = await RoleAiService.instance.infer(request, this.book.speakers, this.voices);
        if (ticket !== this.epoch || !this.enabled) return;
        const answers = RoleSpeechPlanner.answers(result, window.indices.length, request.context, known, this.voices);
        for (let position = 0; position < window.indices.length; position++) {
          const dialogue = this.dialogues[window.indices[position]];
          const answer = answers[position];
          const name = answer.speaker;
          if (name !== '?') {
            let speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.name === name);
            if (!speaker) {
              speaker = new RoleSpeaker(); speaker.name = name; speaker.id = name;
              speaker.voiceId = answer.voiceId; speaker.voiceSource = 'ai';
              this.book.speakers.push(speaker);
            }
            if (answer.profile) speaker.profile = answer.profile;
          }
          dialogue.speaker = name; dialogue.complete = true;
        }
        window.complete = true; this.publish();
        await this.save();
      } catch (error) {
        if (ticket !== this.epoch) return;
        if (!(error instanceof JianjianAiError && error.code === JianjianAiErrorCode.CANCELLED)) {
          this.failed = true;
          this.state.error = JianjianAiService.errorText(error instanceof Error ? error : new Error(String(error)));
        }
      } finally {
        if (ticket === this.epoch) { this.pending.delete(index); this.state.analysing = this.pending.size > 0; }
      }
    })();
    this.pending.set(index, task);
    return task;
  }

  async retryChapter(): Promise<void> {
    this.cancel();
    for (const dialogue of this.dialogues) { dialogue.complete = false; dialogue.speaker = '?'; }
    for (const window of this.windows) window.complete = false;
    this.failed = false; this.state.error = '';
  }
}
