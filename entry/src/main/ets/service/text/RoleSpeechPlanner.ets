import {
  RoleAnalysisWindow, RoleDialogue, RoleInferenceLine, RoleInferenceRequest, RoleModelAnswer, RoleSpeaker, RoleVoiceOption
} from '../../model/RoleSpeech';
import { RoleAiService } from './RoleAiService';
import { RoleVoiceMetadata } from './RoleVoiceMetadata';
import { RoleVoiceMatcher } from './RoleVoiceMatcher';
import { ReaderDialogueHighlighter } from './ReaderDialogueHighlighter';

/** 应用保存原文及 UTF-16 偏移，模型提供说话人、人物特征与音色建议。 */
export class RoleSpeechPlanner {
  static dialogues(content: string, quotes: string): RoleDialogue[] {
    return ReaderDialogueHighlighter.ranges(content, quotes).map((range): RoleDialogue => {
      const item = new RoleDialogue();
      item.start = range.start; item.end = range.end;
      return item;
    });
  }

  static windows(dialogues: RoleDialogue[]): RoleAnalysisWindow[] {
    const result: RoleAnalysisWindow[] = [];
    for (let index = 0; index < dialogues.length; index++) {
      let window = result.length > 0 ? result[result.length - 1] : null;
      if (window === null || window.indices.length >= 12 ||
        dialogues[index].end - dialogues[window.indices[0]].start > 6000) {
        window = new RoleAnalysisWindow(); result.push(window);
      }
      window.indices.push(index);
    }
    return result;
  }

  static request(content: string, dialogues: RoleDialogue[], window: RoleAnalysisWindow): RoleInferenceRequest {
    const request = new RoleInferenceRequest();
    const first = dialogues[window.indices[0]];
    const last = dialogues[window.indices[window.indices.length - 1]];
    const start = Math.max(0, first.start - 1200);
    const end = Math.min(content.length, last.end + 1200);
    request.context = content.substring(start, end);
    for (let id = 0; id < window.indices.length; id++) {
      const dialogue = dialogues[window.indices[id]];
      const line = new RoleInferenceLine();
      line.id = id; line.start = dialogue.start - start; line.end = dialogue.end - start;
      line.text = content.substring(dialogue.start, dialogue.end);
      request.lines.push(line);
    }
    return request;
  }

  static isSpeaker(name: string): boolean {
    return name.length > 0 && name.length <= 24 &&
      !['?', '未知', '未知角色', '旁白', '他', '她', '它', '我', '你', '他们', '她们'].includes(name) &&
      !new RegExp('[\\r\\n\\t<>"\\\\]').test(name);
  }

  static answers(answers: RoleModelAnswer[], count: number, context: string, known: RoleSpeaker[],
    voices: RoleVoiceOption[]): RoleModelAnswer[] {
    if (answers.length !== count) throw new Error('role_inference');
    const result: RoleModelAnswer[] = [];
    for (let id = 0; id < count; id++) {
      const item = new RoleModelAnswer(); item.id = id; result.push(item);
    }
    const seen: Set<number> = new Set<number>();
    const matches = new Map<string, RoleModelAnswer>();
    const assigned = known.slice();
    for (const answer of answers) {
      if (answer === null || typeof answer.speaker !== 'string' ||
        !Number.isInteger(answer.id) || answer.id < 0 || answer.id >= count || seen.has(answer.id)) {
        throw new Error('role_inference');
      }
      seen.add(answer.id);
      const name = answer.speaker.trim();
      const speaker = known.find((item: RoleSpeaker): boolean => item.name === name);
      if (RoleSpeechPlanner.isSpeaker(name) && (speaker !== undefined || context.includes(name))) {
        const item = result[answer.id];
        item.speaker = name;
        const existing = matches.get(name);
        if (existing !== undefined) {
          item.gender = existing.gender; item.age = existing.age;
          item.profile = existing.profile; item.voiceId = existing.voiceId;
          continue;
        }
        const match = RoleAiService.voiceMatch(answer, voices);
        item.gender = speaker !== undefined && (speaker.genderSource === 'manual' || match.gender === 'pending') ?
          RoleAiService.gender(speaker.gender) : match.gender;
        item.age = speaker !== undefined && (speaker.ageSource === 'manual' || match.age === 'pending') ?
          RoleVoiceMetadata.age(speaker.age) : match.age;
        item.profile = match.profile || speaker?.profile || '';
        const current = speaker?.voiceId ?? '';
        const valid = voices.some((voice: RoleVoiceOption): boolean => voice.id === current);
        const manual = speaker?.voiceSource === 'manual';
        const candidates = RoleVoiceMatcher.candidates(voices, item.gender, item.age);
        if (speaker !== undefined && ((manual && (!current || valid)) ||
          (valid && candidates.some((voice: RoleVoiceOption): boolean => voice.id === current)))) {
          item.voiceId = current;
        } else {
          item.voiceId = RoleVoiceMatcher.choose(match.voiceId || current, voices, item.gender, item.age, assigned, name);
        }
        matches.set(name, item);
        const allocation = new RoleSpeaker();
        allocation.id = name; allocation.voiceId = item.voiceId;
        const previous = assigned.findIndex((knownSpeaker: RoleSpeaker): boolean => knownSpeaker.id === name);
        if (previous >= 0) assigned.splice(previous, 1, allocation); else assigned.push(allocation);
      }
    }
    return result;
  }
}
