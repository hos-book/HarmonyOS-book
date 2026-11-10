import { RoleAnalysisWindow, RoleDialogue, RoleModelAnswer } from '../../model/RoleSpeech';
import { ReaderDialogueHighlighter } from './ReaderDialogueHighlighter';

class RolePromptLine {
  id: number = 0;
  text: string = '';
}
class RolePrompt {
  known: string[] = [];
  context: string = '';
  lines: RolePromptLine[] = [];
}

/** 模型只决定程序已确定的对白编号；正文及 UTF-16 偏移从不取自模型。 */
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

  static prompt(content: string, dialogues: RoleDialogue[], window: RoleAnalysisWindow, known: string[]): string {
    const request = new RolePrompt();
    request.known = known.slice(-16);
    const first = dialogues[window.indices[0]];
    const last = dialogues[window.indices[window.indices.length - 1]];
    const start = Math.max(0, first.start - 160);
    const end = Math.min(content.length, last.end + 160);
    const excerpt = content.substring(start, end);
    request.context = excerpt.length <= 1000 ? excerpt : excerpt.substring(0, 600) + '\n…\n' + excerpt.slice(-400);
    for (let id = 0; id < window.indices.length; id++) {
      const dialogue = dialogues[window.indices[id]];
      const line = new RolePromptLine();
      line.id = id; line.text = content.substring(dialogue.start, dialogue.end).substring(0, 160);
      request.lines.push(line);
    }
    return JSON.stringify(request);
  }

  static answers(raw: string, count: number, context: string, known: string[]): string[] {
    if (raw.length > 4096) throw new Error('role_output_limit');
    const parsed: RoleModelAnswer[] = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length > count) throw new Error('role_inference');
    const result: string[] = [];
    for (let id = 0; id < count; id++) result.push('?');
    const seen: Set<number> = new Set<number>();
    for (const answer of parsed) {
      if (answer === null || !Number.isInteger(answer.id) || answer.id < 0 || answer.id >= count ||
        seen.has(answer.id) || typeof answer.speaker !== 'string') throw new Error('role_inference');
      seen.add(answer.id);
      const name = answer.speaker.trim();
      // 不凭空创建角色，也不把人称代词当成跨章稳定姓名。
      if (name.length > 0 && name.length <= 24 &&
        !['?', '未知', '未知角色', '旁白', '他', '她', '它', '我', '你', '他们', '她们'].includes(name) &&
        !new RegExp('[\\r\\n\\t<>"\\\\]').test(name) && (known.includes(name) || context.includes(name))) {
        result[answer.id] = name;
      }
    }
    return result;
  }

  static evidence(prompt: string): string {
    const request: RolePrompt = JSON.parse(prompt);
    return request.context + request.lines.map((line: RolePromptLine): string => line.text).join('\n');
  }
}
