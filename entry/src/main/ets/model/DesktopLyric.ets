import { SubtitleCue, SubtitleTimeline } from './AudioSubtitle';

@ObservedV2
export class DesktopLyricState {
  @Trace supported: boolean = false;
  @Trace checked: boolean = false;
  @Trace visible: boolean = false;
  @Trace busy: boolean = false;
  @Trace locked: boolean = false;
}

/** 系统歌词只接受 LRC；字幕使用音频时间，朗读使用实际播放回调更新的当前正文。 */
export class DesktopLyricText {
  static clean(text: string): string {
    return Array.from(text.replace(/[\r\n\t]+/g, ' ').replace(/\[/g, '［').replace(/\]/g, '］').trim())
      .slice(0, 160).join('');
  }

  static stamp(ms: number): string {
    const value = Math.floor(Math.max(0, Number.isFinite(ms) ? ms : 0) / 10);
    return `[${Math.floor(value / 6000).toString().padStart(2, '0')}:${
      Math.floor(value / 100) % 60 < 10 ? '0' : ''}${Math.floor(value / 100) % 60}.${
      (value % 100).toString().padStart(2, '0')}]`;
  }

  static audio(cues: SubtitleCue[], positionMs: number): string {
    let index = SubtitleTimeline.activeIndex(cues, positionMs);
    if (index < 0) {
      let low = 0;
      let high = cues.length;
      while (low < high) {
        const middle = Math.floor((low + high) / 2);
        if (cues[middle].startMs <= positionMs) low = middle + 1;
        else high = middle;
      }
      index = Math.max(0, low - 1);
    }
    const start = Math.max(0, index - 2);
    const end = Math.min(cues.length, index + 48);
    const lines: string[] = [];
    for (let i = start; i < end; i++) {
      const cue = cues[i];
      const text = DesktopLyricText.clean(cue.text);
      if (!text || !Number.isFinite(cue.startMs) || !Number.isFinite(cue.endMs) || cue.endMs <= cue.startMs) continue;
      lines.push(DesktopLyricText.stamp(cue.startMs) + text);
      if (i + 1 >= cues.length || cues[i + 1].startMs - cue.endMs >= 100) {
        lines.push(DesktopLyricText.stamp(cue.endMs) + ' ');
      }
    }
    return lines.join('\n');
  }

  static speech(content: string, offset: number): string {
    if (!content) return '';
    const position = Math.max(0, Math.min(content.length - 1, Math.floor(offset)));
    let start = position;
    let end = position;
    while (start > 0 && !/[。！？；\n]/.test(content.charAt(start - 1))) start--;
    start += Math.floor((position - start) / 56) * 56;
    end = start;
    while (end < content.length && end - start < 56) {
      const character = content.charAt(end++);
      if (/[。！？；\n]/.test(character)) break;
    }
    return DesktopLyricText.clean(content.substring(start, end));
  }
}
