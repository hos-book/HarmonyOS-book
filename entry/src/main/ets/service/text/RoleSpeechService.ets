import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { RoleAnalysisWindow, RoleBookSettings, RoleChapterCache, RoleDialogue,
  RoleSpeaker, RoleSpeechState, RoleSpeechSample } from '../../model/RoleSpeech';
import { SubtitleFiles } from '../subtitle/SubtitleFiles';
import { RoleModelService } from './RoleModelService';
import { RoleSpeechPlanner } from './RoleSpeechPlanner';

/** 每书音色绑定与有界分角缓存。预识别一个小窗口，暂停/换书后旧结果不再写入。 */
export class RoleSpeechService {
  private static instance: RoleSpeechService | null = null;
  readonly state: RoleSpeechState = new RoleSpeechState();
  private book: RoleBookSettings = new RoleBookSettings();
  private bookPath: string = '';
  private cachePath: string = '';
  private content: string = '';
  private dialogues: RoleDialogue[] = [];
  private windows: RoleAnalysisWindow[] = [];
  private pending: Map<number, Promise<void>> = new Map<number, Promise<void>>();
  private epoch: number = 0;
  private failed: boolean = false;
  private saveChain: Promise<void> = Promise.resolve();

  static getInstance(): RoleSpeechService {
    if (RoleSpeechService.instance === null) RoleSpeechService.instance = new RoleSpeechService();
    return RoleSpeechService.instance;
  }

  get enabled(): boolean {
    const model = RoleModelService.getInstance().state;
    return model.enabled && model.model !== null && !model.busy;
  }

  boundaries(): number[] {
    const result: number[] = this.enabled ? [0, this.content.length] : [];
    if (this.enabled) for (const dialogue of this.dialogues) result.push(dialogue.start, dialogue.end);
    return result;
  }

  private async read(path: string): Promise<string> {
    if (!await fileIo.access(path)) return '';
    if ((await fileIo.stat(path)).size > 1024 * 1024) return '';
    return fileIo.readText(path);
  }

  private save(path: string, content: string): Promise<void> {
    const task = this.saveChain.catch((): void => {}).then(async (): Promise<void> => {
      const temporary = path + '.partial';
      const file = await fileIo.open(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, content); await fileIo.fsync(file.fd); }
      finally { await fileIo.close(file); }
      try { await fileIo.rename(temporary, path); }
      finally { await fileIo.unlink(temporary).catch((): void => {}); }
    });
    this.saveChain = task;
    return task;
  }

  async selectBook(context: common.Context, id: string, title: string): Promise<void> {
    if (this.state.bookId === id && this.bookPath) { this.state.bookTitle = title; return; }
    const ticket = this.epoch;
    const directory = `${context.filesDir}/role_speech`;
    if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
    const path = `${directory}/book-${await SubtitleFiles.key(id)}.json`;
    const settings = new RoleBookSettings(); settings.bookId = id;
    try {
      const text = await this.read(path);
      if (text) {
        const saved: RoleBookSettings = JSON.parse(text);
        if (saved !== null && saved.bookId === id) {
          settings.narratorVoiceId = typeof saved.narratorVoiceId === 'string' ? saved.narratorVoiceId : '';
          settings.dialogueVoiceId = typeof saved.dialogueVoiceId === 'string' ? saved.dialogueVoiceId : '';
          if (Array.isArray(saved.speakers)) for (const speaker of saved.speakers.slice(0, 128)) {
            if (speaker === null || typeof speaker.id !== 'string' || typeof speaker.name !== 'string' ||
              typeof speaker.voiceId !== 'string' || speaker.name.length > 24 || !speaker.name ||
              settings.speakers.some((item: RoleSpeaker): boolean => item.id === speaker.id)) continue;
            const item = new RoleSpeaker();
            item.id = speaker.id; item.name = speaker.name; item.voiceId = speaker.voiceId;
            settings.speakers.push(item);
          }
        }
      }
    } catch (_error) { /* 损坏的本地记录回退默认音色。 */ }
    if (ticket !== this.epoch) return;
    this.book = settings; this.bookPath = path;
    this.state.bookId = id; this.state.bookTitle = title; this.publish();
  }

  private publish(): void {
    this.state.narratorVoiceId = this.book.narratorVoiceId;
    this.state.dialogueVoiceId = this.book.dialogueVoiceId;
    this.state.speakers = this.book.speakers.slice();
  }

  async setVoice(roleId: string, voiceId: string): Promise<void> {
    if (!this.bookPath) return;
    const current = this.book;
    const path = this.bookPath;
    const previous: RoleBookSettings = JSON.parse(JSON.stringify(this.book));
    if (roleId === '@narrator') this.book.narratorVoiceId = voiceId;
    else if (roleId === '@dialogue') this.book.dialogueVoiceId = voiceId;
    else {
      const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.id === roleId);
      if (!speaker) return;
      speaker.voiceId = voiceId;
    }
    try {
      await this.save(path, JSON.stringify(current));
      if (this.book === current) this.publish();
    } catch (_error) {
      if (this.book === current) { this.book = previous; this.publish(); }
      throw new Error('role_save');
    }
  }

  /** 从已经识别的正文取短句；配置界面不启动新的模型识别。 */
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

  preview(offset: number): RoleSpeechSample[] {
    const samples: RoleSpeechSample[] = [];
    if (!this.content) return samples;
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

  async prepare(context: common.Context, bookId: string, title: string, chapter: string,
    content: string, quotes: string): Promise<void> {
    this.cancel();
    const ticket = this.epoch;
    this.content = ''; this.dialogues = []; this.windows = []; this.cachePath = '';
    this.failed = false; this.state.error = '';
    await RoleModelService.getInstance().initialize(context);
    await this.selectBook(context, bookId, title);
    if (ticket !== this.epoch || !this.enabled) return;
    this.content = content;
    this.dialogues = RoleSpeechPlanner.dialogues(content, quotes);
    this.windows = RoleSpeechPlanner.windows(this.dialogues);
    const fingerprint = RoleModelService.getInstance().state.model?.fingerprint ?? '';
    const key = await SubtitleFiles.key(JSON.stringify([1, bookId, chapter, fingerprint, quotes, content]));
    if (ticket !== this.epoch) return;
    this.cachePath = `${context.filesDir}/role_speech/cache-${key}.json`;
    try {
      const text = await this.read(this.cachePath);
      if (ticket !== this.epoch) return;
      const saved: RoleChapterCache = text ? JSON.parse(text) : new RoleChapterCache();
      if (saved?.version === 1 && Array.isArray(saved.dialogues) && saved.dialogues.length <= this.dialogues.length) {
        const byStart: Map<number, RoleDialogue> = new Map<number, RoleDialogue>();
        for (const item of saved.dialogues) if (item !== null) byStart.set(item.start, item);
        for (const dialogue of this.dialogues) {
          const item = byStart.get(dialogue.start);
          if (item?.end === dialogue.end && item.complete === true && typeof item.speaker === 'string' &&
            (item.speaker === '?' || this.book.speakers.some((speaker: RoleSpeaker): boolean => speaker.name === item.speaker))) {
            dialogue.speaker = item.speaker; dialogue.complete = true;
          }
        }
        for (const window of this.windows) window.complete = window.indices.every((id: number): boolean => this.dialogues[id].complete);
      }
    } catch (_error) { /* 缓存仅是加速数据，损坏时重新分析。 */ }
  }

  cancel(): void {
    this.epoch++; this.pending.clear(); this.state.analysing = false;
    RoleModelService.getInstance().cancelAnalysis();
  }

  private dialogueAt(offset: number): RoleDialogue | undefined {
    // 二分避免长章节的逐片段全量扫描。
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

  voiceAt(offset: number): string {
    if (!this.enabled) return '';
    const dialogue = this.dialogueAt(offset);
    if (!dialogue) return this.book.narratorVoiceId;
    const speaker = this.book.speakers.find((item: RoleSpeaker): boolean => item.name === dialogue.speaker);
    return speaker !== undefined ? speaker.voiceId : this.book.dialogueVoiceId;
  }

  async ensureAt(offset: number, voices: CustomTtsConfig[], defaultVoice: string): Promise<void> {
    if (this.readyAt(offset)) return;
    const dialogue = this.dialogueAt(offset);
    if (!dialogue) return;
    const index = this.windows.findIndex((window: RoleAnalysisWindow): boolean =>
      window.indices.some((id: number): boolean => this.dialogues[id] === dialogue));
    if (index >= 0) await this.analyse(index, voices, defaultVoice);
  }

  prefetch(offset: number, voices: CustomTtsConfig[], defaultVoice: string): Promise<void> {
    if (!this.enabled || this.failed || this.pending.size > 0) return Promise.resolve();
    const index = this.windows.findIndex((window: RoleAnalysisWindow): boolean => !window.complete &&
      this.dialogues[window.indices[window.indices.length - 1]].end > offset);
    return index < 0 ? Promise.resolve() : this.analyse(index, voices, defaultVoice);
  }

  private analyse(index: number, voices: CustomTtsConfig[], defaultVoice: string): Promise<void> {
    const existing = this.pending.get(index);
    if (existing !== undefined) return existing;
    const ticket = this.epoch;
    const window = this.windows[index];
    const task = (async (): Promise<void> => {
      try {
        this.state.analysing = true;
        const known = this.book.speakers.map((item: RoleSpeaker): string => item.name);
        const prompt = RoleSpeechPlanner.prompt(this.content, this.dialogues, window, known);
        const result = await RoleModelService.getInstance().infer(prompt);
        if (ticket !== this.epoch || !this.enabled) return;
        const names = RoleSpeechPlanner.answers(result, window.indices.length, RoleSpeechPlanner.evidence(prompt), known);
        const available = voices.filter((item: CustomTtsConfig): boolean => item.enabled && item.id !== defaultVoice);
        for (let position = 0; position < window.indices.length; position++) {
          const dialogue = this.dialogues[window.indices[position]];
          let name = names[position];
          if (name !== '?' && !this.book.speakers.some((item: RoleSpeaker): boolean => item.name === name)) {
            if (this.book.speakers.length >= 128) name = '?';
            else {
              const speaker = new RoleSpeaker(); speaker.name = name; speaker.id = name;
              speaker.voiceId = available.length > 0 ? available[this.book.speakers.length % available.length].id : '';
              this.book.speakers.push(speaker);
            }
          }
          dialogue.speaker = name; dialogue.complete = true;
        }
        window.complete = true; this.publish();
        const cache = new RoleChapterCache();
        cache.dialogues = this.dialogues.filter((item: RoleDialogue): boolean => item.complete);
        await this.save(this.bookPath, JSON.stringify(this.book));
        if (ticket !== this.epoch) return;
        await this.save(this.cachePath, JSON.stringify(cache));
        await this.trimCache();
      } catch (error) {
        if (ticket !== this.epoch) return;
        const message = error instanceof Error ? error.message : String(error);
        if (!message.includes('role_cancelled')) {
          this.failed = true;
          this.state.error = RoleModelService.errorMessage(message);
        }
      } finally {
        if (ticket === this.epoch) { this.pending.delete(index); this.state.analysing = this.pending.size > 0; }
      }
    })();
    this.pending.set(index, task);
    return task;
  }

  private async trimCache(): Promise<void> {
    const directory = this.cachePath.substring(0, this.cachePath.lastIndexOf('/'));
    const names = (await fileIo.listFile(directory)).filter((name: string): boolean =>
      new RegExp('^cache-[a-f0-9]{64}\\.json$').test(name));
    if (names.length <= 64) return;
    const age: Map<string, number> = new Map<string, number>();
    for (const name of names) age.set(name, (await fileIo.stat(`${directory}/${name}`)).mtime);
    names.sort((left: string, right: string): number => (age.get(left) ?? 0) - (age.get(right) ?? 0));
    for (const name of names.slice(0, names.length - 64)) {
      if (`${directory}/${name}` !== this.cachePath) await fileIo.unlink(`${directory}/${name}`).catch((): void => {});
    }
  }

  async retryChapter(): Promise<void> {
    this.cancel(); await this.saveChain.catch((): void => {});
    if (this.cachePath) await fileIo.unlink(this.cachePath).catch((): void => {});
    for (const dialogue of this.dialogues) { dialogue.complete = false; dialogue.speaker = '?'; }
    for (const window of this.windows) window.complete = false;
    this.failed = false; this.state.error = '';
  }
}
