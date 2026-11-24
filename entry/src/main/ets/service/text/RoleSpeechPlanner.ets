import {
  RoleAnalysisWindow, RoleDialogue, RoleInferenceLine, RoleInferenceRequest, RoleModelAnswer
} from '../../model/RoleSpeech';
import { ReaderDialogueHighlighter } from './ReaderDialogueHighlighter';

/** 应用保存原文及 UTF-16 偏移，模型提供对白编号和说话人。 */
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
      if (window === null || window.indices.length >= 3 ||
        dialogues[index].end - dialogues[window.indices[0]].start > 420) {
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
    const start = Math.max(0, first.start - 768);
    const end = Math.min(content.length, last.end + 768);
    request.context = content.substring(start, end);
    for (let id = 0; id < window.indices.length; id++) {
      const dialogue = dialogues[window.indices[id]];
      const line = new RoleInferenceLine();
      line.id = id; line.start = dialogue.start - start; line.end = dialogue.end - start;
      request.lines.push(line);
    }
    return request;
  }

  static isSpeaker(name: string): boolean {
    return name.length > 0 && name.length <= 24 &&
      !['?', '未知', '未知角色', '旁白', '他', '她', '它', '我', '你', '他们', '她们'].includes(name) &&
      !new RegExp('[\\r\\n\\t<>"\\\\]').test(name);
  }

  static answers(answers: RoleModelAnswer[], count: number, context: string, known: string[]): string[] {
    if (answers.length !== count) throw new Error('role_inference');
    const result: string[] = [];
    for (let id = 0; id < count; id++) result.push('?');
    const seen: Set<number> = new Set<number>();
    for (const answer of answers) {
      if (!Number.isInteger(answer.id) || answer.id < 0 || answer.id >= count || seen.has(answer.id)) {
        throw new Error('role_inference');
      }
      seen.add(answer.id);
      const name = answer.speaker.trim();
      if (RoleSpeechPlanner.isSpeaker(name) && (known.includes(name) || context.includes(name))) {
        result[answer.id] = name;
      }
    }
    return result;
  }
}
